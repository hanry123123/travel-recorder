import Foundation
import Combine
import CoreLocation
import Photos
import PhotosUI
import UIKit

final class TravelStore: ObservableObject {
    @Published private(set) var trips: [Trip] = []
    @Published private(set) var revision = 0
    @Published var errorMessage: String?
    @Published var locationMessage = L("点击开始，记录新的旅程")
    @Published var photoMessage = ""
    @Published private(set) var importCount = 0
    @Published private(set) var currentCoordinate: Coordinate?
    @Published private(set) var ready = false
    let photos: PhotoLibraryService
    private var reminder: TripReminderService?
    @Published var reminderMessage = ""
    private(set) var files: PhotoFileStore!
    private(set) var placeNames: TripPlaceNames!
    private var repository: TripRepository!
    private let location: LocationSource
    private let now: () -> Date
    private var pendingStart = false
    private var latestPoint: TrackPoint?
    private var pointCache: [UUID: [TrackPoint]] = [:]
    private var photoCache: [UUID: [PhotoAttachment]] = [:]
    private var diaryCache: [UUID: [DiaryEntry]] = [:]
    private let photoQueue = DispatchQueue(label: "travel.photo.processing", qos: .utility)
    private var librarySyncGeneration = UUID()
    private var scanWork: DispatchWorkItem?
    private var scanGeneration = UUID()
    private var scanning = Set<UUID>()
    var activeTrip: Trip? { trips.first { $0.status != .ended } }
    var automaticPhotos: Bool { UserDefaults.standard.bool(forKey: "automaticPhotos") }
    var photoAccessDescription: String {
        switch photos.authorization {
        case .authorized: return automaticPhotos ? L("自动关联已开启") : L("自动关联已关闭")
        case .limited: return L("仅能自动关联已获授权的照片；其他照片可手动添加")
        case .denied, .restricted: return L("未获相册访问权限，请先允许访问要关联的照片")
        case .notDetermined: return L("开启相册权限后，自动关联旅途中拍摄的照片")
        @unknown default: return L("请检查相册权限")
        }
    }
    init(location: LocationSource = DeviceLocationSource(), photos: PhotoLibraryService = PhotoLibraryService(), now: @escaping () -> Date = Date.init, storageRoot: URL? = nil, openRepository: @escaping (URL) throws -> TripRepository = { try CoreDataRepository(url: $0) }, remindersEnabled: Bool = true) {
        self.location = location
        self.photos = photos
        self.now = now
        if remindersEnabled { self.reminder = TripReminderService() }
        // Publish an immediately usable tab shell; SQLite open/recovery/decoding must
        // never occupy the UI thread during cold launch.
        DispatchQueue(label: "travel.bootstrap", qos: .userInitiated).async {
            do {
                let root = try storageRoot ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("TravelRecorder", isDirectory: true)
                let files = try PhotoFileStore(directory: root.appendingPathComponent("Photos", isDirectory: true))
                let repository = try openRepository(root.appendingPathComponent("Travel.sqlite"))
                try files.migrateToLibraryReferences(repository: repository)
                for trip in try repository.load(Trip.self) where trip.status == .recording { try repository.save(RecorderLogic.recover(trip)) }
                let trips = try repository.load(Trip.self).sorted { $0.startedAt > $1.startedAt }
                let points = Dictionary(grouping: try repository.load(TrackPoint.self), by: { $0.tripID })
                let photos = Dictionary(grouping: try repository.load(PhotoAttachment.self), by: { $0.tripID })
                let diaries = Dictionary(grouping: try repository.load(DiaryEntry.self), by: { $0.tripID })
                DispatchQueue.main.async {
                    self.files = files; self.repository = repository
                    self.placeNames = TripPlaceNames(cacheURL: root.appendingPathComponent("PlaceNames.json"))
                    self.pointCache = points; self.photoCache = photos; self.diaryCache = diaries
                    self.trips = trips; self.ready = true; self.revision += 1
                    self.foreground()
                }
            } catch { DispatchQueue.main.async { self.errorMessage = (AppLanguage.english ? "Unable to open local data: \(error.localizedDescription)" : "无法打开本地数据：\(error.localizedDescription)") } }
        }
        reminder?.onMessage = { [weak self] in self?.reminderMessage = $0 }
        location.onSamples = { [weak self] samples in self?.receive(samples) }
        location.onAuthorization = { [weak self] in self?.authorizationChanged() }
        location.onFailure = { [weak self] message in self?.locationMessage = message }
        photos.onChange = { [weak self] in self?.synchronizeLibrary(); self?.schedulePhotoScan() }
    }
    private func cacheMetadata(photos: [PhotoAttachment], diaries: [DiaryEntry]) {
        for (tripID, values) in Dictionary(grouping: photos, by: { $0.tripID }) {
            let ids = Set(values.map { $0.id })
            photoCache[tripID] = (photoCache[tripID] ?? []).filter { !ids.contains($0.id) } + values
        }
        for (tripID, values) in Dictionary(grouping: diaries, by: { $0.tripID }) {
            let ids = Set(values.map { $0.id })
            diaryCache[tripID] = (diaryCache[tripID] ?? []).filter { !ids.contains($0.id) } + values
        }
    }
    private func commit(_ records: [StoredRecord], deleting keys: [String]) throws {
        let decoder = JSONDecoder()
        let photos = try records.filter { $0.kind == PhotoAttachment.kind }.map { try decoder.decode(PhotoAttachment.self, from: $0.data) }
        let diaries = try records.filter { $0.kind == DiaryEntry.kind }.map { try decoder.decode(DiaryEntry.self, from: $0.data) }
        try repository.commit(records, deleting: keys)
        if !keys.isEmpty {
            let deleted = Set(keys)
            for id in Array(photoCache.keys) { photoCache[id]?.removeAll { deleted.contains("photo:" + $0.id.uuidString) } }
            for id in Array(diaryCache.keys) { diaryCache[id]?.removeAll { deleted.contains("diary:" + $0.id.uuidString) } }
        }
        cacheMetadata(photos: photos, diaries: diaries)
    }
    private func save<T: StoredModel>(_ value: T) throws { try commit([StoredRecord(value)], deleting: []) }
    private func reload() throws {
        trips = try repository.load(Trip.self).sorted { $0.startedAt > $1.startedAt }
        revision += 1
    }
    func trip(_ id: UUID) -> Trip? { trips.first { $0.id == id } }
    func points(_ id: UUID) -> [TrackPoint] {
        if let cached = pointCache[id] { return cached }
        guard ready else { return [] }
        do { let points = try repository.load(TrackPoint.self, tripID: id); pointCache[id] = points; return points }
        catch { report(error); return [] }
    }
    func attachments(_ id: UUID) -> [PhotoAttachment] {
        savedAttachments(id).sorted { $0.capturedAt < $1.capturedAt }
    }
    private func savedAttachments(_ id: UUID) -> [PhotoAttachment] { photoCache[id] ?? [] }
    func diaries(_ id: UUID) -> [DiaryEntry] { (diaryCache[id] ?? []).sorted { $0.sortDate < $1.sortDate } }
    private func load<T: StoredModel>(_ type: T.Type, _ id: UUID) -> [T] {
        guard ready else { return [] }
        do { return try repository.load(type, tripID: id) } catch { report(error); return [] }
    }
    private func report(_ error: Error) { DispatchQueue.main.async { self.errorMessage = error.localizedDescription } }
    private func authorized() -> Bool {
        let status = location.authorization
        if status == .notDetermined { pendingStart = true; location.requestPermission(); return false }
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            errorMessage = L("请在系统设置中允许旅迹使用位置。已有旅程、照片和日记仍可查看。")
            return false
        }
        return true
    }
    func startOrResume() {
        guard ready, activeTrip?.status != .recording, authorized() else { return }
        do {
            let value = try activeTrip.map { try RecorderLogic.resume($0, at: now()) } ?? Trip(now: now())
            try save(value)
            latestPoint = nil
            try reload()
            locationMessage = L("正在获取位置…")
            location.start()
            reminder?.reconcile(activeTrip, now: now()); reminder?.requestPermission()
            if photos.authorization == .notDetermined { setAutomaticPhotos(true) }
            else { schedulePhotoScan() }
        } catch { report(error) }
    }
    func pause() {
        guard let trip = activeTrip, trip.status == .recording else { return }
        do {
            try save(RecorderLogic.pause(trip, at: now()))
            location.stop()
            latestPoint = nil
            try reload()
            reminder?.reconcile(activeTrip, now: now())
            locationMessage = L("已暂停，继续后记录新的路线段")
        } catch { report(error) }
    }
    func finish(expectedTripID: UUID? = nil) {
        guard let trip = activeTrip, expectedTripID == nil || expectedTripID == trip.id else { return }
        do {
            let ended = try RecorderLogic.finish(trip, at: now())
            try save(ended)
            location.stop()
            latestPoint = nil
            try reload()
            reminder?.cancel()
            locationMessage = L("旅程已保存在回忆中")
            scanPhotos(for: ended)
        } catch { report(error) }
    }
    private func receive(_ samples: [LocationSample]) {
        guard ready, var trip = activeTrip, trip.status == .recording else { return }
        reminder?.observe(samples, trip: trip, now: now())
        var accepted: [TrackPoint] = []
        var last = latestPoint
        for sample in samples {
            guard let (updated, point) = RecorderLogic.accept(sample, trip: trip, previous: last, now: now()) else { continue }
            trip = updated; last = point; accepted.append(point)
        }
        guard !accepted.isEmpty else {
            if let sample = samples.last, sample.accuracy > 100 { locationMessage = L("定位精度不足，等待更准确的位置") }
            return
        }
        do {
            // Trip state, distance and all points from this callback commit together.
            try commit([StoredRecord(trip)] + accepted.map { try StoredRecord($0) }, deleting: [])
            latestPoint = last
            if pointCache[trip.id] != nil { pointCache[trip.id]!.append(contentsOf: accepted) }
            currentCoordinate = accepted.last?.coordinate
            try reload()
            locationMessage = location.precise ? (AppLanguage.english ? "Recording · Accuracy about \(Int(accepted.last!.accuracy)) m" : "正在记录 · 定位精度约 \(Int(accepted.last!.accuracy)) 米") : L("当前为大致位置，请在设置中开启精确位置")
        } catch {
            location.stop()
            locationMessage = L("保存失败，已停止定位；请先处理错误再继续")
            if let old = activeTrip, let interrupted = try? RecorderLogic.pause(old, at: old.lastRecordedAt ?? now(), interrupted: true) {
                try? save(interrupted)
                if let index = trips.firstIndex(where: { $0.id == old.id }) { trips[index] = interrupted }
            }
            report(error)
        }
    }
    private func authorizationChanged() {
        guard ready else { return }
        let permitted = location.authorization == .authorizedWhenInUse || location.authorization == .authorizedAlways
        if pendingStart {
            pendingStart = false
            if permitted { startOrResume() }
        }
        if !permitted, let trip = activeTrip, trip.status == .recording {
            location.stop()
            do { try save(RecorderLogic.pause(trip, at: now(), interrupted: true)); try reload() } catch { report(error) }
            locationMessage = L("定位权限已关闭，记录已中断")
        }
        revision += 1
    }
    func foreground() {
        guard ready else { return }
        authorizationChanged(); photos.observe(); synchronizeLibrary()
        NotificationCenter.default.post(name: .travelPhotoLibraryChanged, object: nil)
        reminder?.reconcile(activeTrip, now: now())
        scanGeneration = UUID(); let generation = scanGeneration
        for delay in [0.0, 2.0, 5.0, 12.0] {
            DispatchQueue.main.asyncAfter(deadline: .now()+delay) { [weak self] in
                guard let self = self, self.scanGeneration == generation else { return }
                self.schedulePhotoScan()
            }
        }
    }
    func setAutomaticPhotos(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "automaticPhotos")
        if enabled, photos.authorization == .notDetermined { photos.request { self.revision += 1; self.synchronizeLibrary(); self.schedulePhotoScan() } }
        else { revision += 1; schedulePhotoScan() }
    }
    private func schedulePhotoScan() {
        guard scanWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.scanWork = nil
            for trip in self.trips where trip.status != .ended || self.now().timeIntervalSince(trip.endedAt ?? .distantPast) < 172800 { self.scanPhotos(for: trip) }
        }
        scanWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
    /// Query the current library on a worker; preserve writing, manual placements and IDs.
    func synchronizeLibrary() {
        guard ready else { return }
        let generation = UUID(); librarySyncGeneration = generation
        let saved = photoCache.values.flatMap { $0 }
        photoQueue.async {
            let ids = Array(Set(saved.compactMap { $0.assetID }))
            let snapshot = self.photos.snapshot(identifiers: ids)
            DispatchQueue.main.async {
                guard self.librarySyncGeneration == generation else { return }
                guard snapshot.authorizationUnchanged, self.photos.authorization == snapshot.authorization else {
                    self.synchronizeLibrary(); return
                }
                let assets = saved.map { ($0.id, $0.assetID, $0.assetID.flatMap { snapshot.assets[$0] }) }
                do {
                    var changes: [StoredRecord] = []
                    var deletions: [String] = []
                    let currentPhotos = Dictionary(uniqueKeysWithValues: self.photoCache.values.flatMap { $0 }.map { ($0.id, $0) })
                    var photoUpdates: [PhotoAttachment] = []
                    let currentDiaries = Dictionary(grouping: self.diaryCache.values.flatMap { $0 }.filter { $0.photoID != nil }, by: { $0.photoID! })
                    for (id, requestedAssetID, asset) in assets {
                        guard let current = currentPhotos[id], current.assetID == requestedAssetID else { continue }
                        // Decide using CURRENT diaries: the user may have written one while Photos was queried.
                        // No identifier, limited access, or revoked permission is not proof of deletion.
                        if asset == nil, requestedAssetID?.isEmpty == false, snapshot.canConfirmMissing,
                           (currentDiaries[id] ?? []).isEmpty {
                            deletions.append("photo:" + id.uuidString)
                            continue
                        }
                        var updated = current
                        updated.libraryLinked = true; updated.libraryAvailable = asset != nil
                        updated.libraryRevision = asset.map { String(($0.modifiedAt ?? $0.createdAt ?? .distantPast).timeIntervalSince1970) } ?? "unavailable"
                        if let asset = asset {
                            updated.capturedAt = asset.createdAt ?? current.capturedAt
                            updated.captureDateKnown = asset.createdAt != nil
                            let position = asset.coordinate
                            updated.originalCoordinate = position
                            if !current.manuallyPlaced { updated.coordinate = position }
                        }
                        let metadataChanged = updated.capturedAt != current.capturedAt || updated.captureDateKnown != current.captureDateKnown || updated.coordinate != current.coordinate || updated.originalCoordinate != current.originalCoordinate
                        if metadataChanged { changes.append(try StoredRecord(updated)) }
                        if metadataChanged || updated.libraryAvailable != current.libraryAvailable || updated.libraryRevision != current.libraryRevision { photoUpdates.append(updated) }
                        // Persist changed user-visible metadata; availability and image revisions are read snapshots.
                        for var diary in currentDiaries[id] ?? [] where diary.coordinate != updated.coordinate {
                            diary.coordinate = updated.coordinate
                            changes.append(try StoredRecord(diary))
                        }
                    }
                    if !changes.isEmpty || !deletions.isEmpty { try self.commit(changes, deleting: deletions) }
                    self.cacheMetadata(photos: photoUpdates, diaries: [])
                    if !photoUpdates.isEmpty || !changes.isEmpty || !deletions.isEmpty { self.revision += 1 }
                } catch { self.report(error) }
            }
        }
    }
    func scanPhotos(for trip: Trip, force: Bool = false) {
        guard ready, automaticPhotos || force,
              photos.authorization == .authorized || photos.authorization == .limited,
              scanning.insert(trip.id).inserted else { return }
        let capturedNow = now()
        photoQueue.async {
            let assets = self.photos.candidates(for: trip, now: capturedNow)
            DispatchQueue.main.async {
                self.scanning.remove(trip.id)
                guard let current = self.trip(trip.id), self.automaticPhotos || force else { return }
                let existing = Set(self.savedAttachments(trip.id).compactMap { $0.assetID })
                let excluded = Set(self.load(PhotoExclusion.self, trip.id).map { $0.assetID })
                for asset in assets {
                    guard let date = asset.creationDate,
                          PhotoMatching.shouldImport(assetID: asset.localIdentifier, capturedAt: date, trip: current, now: self.now(), existing: existing, excluded: excluded) else { continue }
                    self.link(asset, to: trip.id, automatic: true)
                }
                if !assets.isEmpty { self.synchronizeLibrary() }
            }
        }
    }
    private func link(_ asset: PHAsset, to tripID: UUID, automatic: Bool) {
        guard trip(tripID) != nil, !savedAttachments(tripID).contains(where: { $0.assetID == asset.localIdentifier }) else { return }
        let coordinate = asset.location.map { Coordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
        var photo = PhotoAttachment(tripID: tripID, assetID: asset.localIdentifier, capturedAt: asset.creationDate ?? now(), importedAt: now(), coordinate: coordinate, originalCoordinate: coordinate, captureDateKnown: asset.creationDate != nil, imageFile: "", thumbnailFile: "")
        photo.libraryLinked = true; photo.libraryAvailable = true
        photo.libraryRevision = UUID().uuidString; photo.autoLinked = automatic
        do { try save(photo); revision += 1; photoMessage = L("照片已关联到系统相册") }
        catch { report(error) }
    }
    func importPhotos(_ results: [PHPickerResult], into tripID: UUID) {
        guard !results.isEmpty, ready else { return }
        if photos.authorization == .notDetermined {
            photos.request { self.importPhotos(results, into: tripID) }; return
        }
        importCount += results.count
        photoQueue.async {
            let assets = results.map { $0.assetIdentifier.flatMap { self.photos.asset($0) } }
            DispatchQueue.main.async {
                var missing = 0
                for asset in assets {
                    guard let asset = asset else { missing += 1; continue }
                    do {
                        let exclusions = self.load(PhotoExclusion.self, tripID).filter { $0.assetID == asset.localIdentifier }
                        try self.commit([], deleting: exclusions.map { "exclusion:" + $0.id.uuidString })
                        self.link(asset, to: tripID, automatic: false)
                    } catch { self.report(error) }
                }
                self.synchronizeLibrary()
                self.importCount -= results.count
                if missing > 0 { self.photoMessage = L("部分照片未获相册访问权限，请在设置中允许访问这些原图后重新添加。") }
            }
        }
    }
    @discardableResult func update(_ trip: Trip) -> Bool {
        guard let current = self.trip(trip.id) else { return false }
        var merged = current
        merged.title = trip.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? current.title : trip.title
        merged.features = trip.features; merged.reflection = trip.reflection; merged.updatedAt = now()
        do { try save(merged); try reload(); return true } catch { report(error); return false }
    }
    @discardableResult func setFavorite(_ id: UUID, reason: String?, enabled: Bool) -> Bool {
        guard var value = trip(id) else { return false }
        value.favoritedAt = enabled ? (value.favoritedAt ?? now()) : nil
        value.favoriteReason = enabled ? reason?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        value.updatedAt = now()
        do { try save(value); try reload(); return true } catch { report(error); return false }
    }
    @discardableResult func saveDiary(_ diary: DiaryEntry) -> Bool {
        guard trip(diary.tripID) != nil else { return false }
        var value = diary
        if let photoID = diary.photoID, let photo = attachments(diary.tripID).first(where: { $0.id == photoID }) { value.coordinate = photo.coordinate }
        do { try save(value); revision += 1; return true } catch { report(error); return false }
    }
    @discardableResult func deleteDiary(_ diary: DiaryEntry) -> Bool {
        do { try commit([], deleting: ["diary:" + diary.id.uuidString]); revision += 1; if diary.photoID != nil { synchronizeLibrary() }; return true } catch { report(error); return false }
    }
    func placeExistingPhoto(_ reference: PhotoAttachment, at coordinate: Coordinate) throws {
        guard trip(reference.tripID) != nil,
              let current = savedAttachments(reference.tripID).first(where: { $0.id == reference.id }) else {
            throw TripError.storage(AppLanguage.english ? "This photo is no longer in the trip." : "这张照片已从旅程中移除。")
        }
        guard current.isPreview != true else { throw TripError.storage(L("完整照片仍在准备，请保存完成后放置。")) }
        guard let (updated, related) = PhotoEditing.place(current, at: coordinate, diaries: diaries(current.tripID)) else {
            throw TripError.storage(AppLanguage.english ? "Select a valid location on the map." : "请重新在地图上选择位置。")
        }
        try commit([StoredRecord(updated)] + related.map { try StoredRecord($0) }, deleting: [])
        revision += 1
    }
    @discardableResult func removePhoto(_ photo: PhotoAttachment) -> Bool {
        do {
            let related = diaries(photo.tripID).filter { $0.photoID == photo.id }
            // Preserve attached writing as a place/general diary when removing a photo.
            let preserved = related.map { value -> DiaryEntry in var copy = value; copy.photoID = nil; copy.coordinate = photo.mapCoordinate?.identified; return copy }
            var records = try preserved.map { try StoredRecord($0) }
            if let id = photo.assetID { records.append(try StoredRecord(PhotoExclusion(tripID: photo.tripID, assetID: id, sortDate: now()))) }
            try commit(records, deleting: ["photo:" + photo.id.uuidString])
            files.remove(photo.imageFile); files.remove(photo.thumbnailFile)
            revision += 1
            return true
        } catch { report(error); return false }
    }
    @discardableResult func deleteTrip(_ id: UUID) -> Bool {
        guard activeTrip?.id != id else { errorMessage = L("请先结束旅程，再删除。"); return false }
        let images = attachments(id)
        do {
            try repository.deleteTrip(id)
            for photo in images { files.remove(photo.imageFile); files.remove(photo.thumbnailFile) }
            pointCache.removeValue(forKey: id)
            photoCache.removeValue(forKey: id); diaryCache.removeValue(forKey: id)
            try reload()
            return true
        } catch { report(error); return false }
    }
    func snoozeReminder() { reminder?.snooze(activeTrip, now: now()) }
    func enableReminderNotifications() { reminder?.requestPermission() }
    func openSettings() { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
}
