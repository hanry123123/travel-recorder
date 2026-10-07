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
    @Published var locationMessage = "点击开始，记录新的旅程"
    @Published var photoMessage = ""
    @Published private(set) var importCount = 0
    @Published private(set) var currentCoordinate: Coordinate?
    @Published private(set) var ready = false
    let photos = PhotoLibraryService()
    private(set) var files: PhotoFileStore!
    private(set) var placeNames: TripPlaceNames!
    private var repository: TripRepository!
    private let location: LocationSource
    private let now: () -> Date
    private var pendingStart = false
    private var latestPoint: TrackPoint?
    private var pointCache: [UUID: [TrackPoint]] = [:]
    private let photoQueue = DispatchQueue(label: "travel.photo.processing", qos: .utility)
    private var imports: [(UUID, String, (@escaping (Result<ImportedPhotoInput, Error>) -> Void) -> Void)] = []
    private var inFlight = Set<String>()
    private var runningImports = 0
    private var scanWork: DispatchWorkItem?
    var activeTrip: Trip? { trips.first { $0.status != .ended } }
    var automaticPhotos: Bool { UserDefaults.standard.bool(forKey: "automaticPhotos") }
    var photoAccessDescription: String {
        switch photos.authorization {
        case .authorized: return automaticPhotos ? "自动关联已开启" : "自动关联已关闭"
        case .limited: return "仅能自动关联已获授权的照片；其他照片可手动添加"
        case .denied, .restricted: return "未获相册访问权限，仍可手动选择照片"
        case .notDetermined: return "开启相册权限后，自动关联旅途中拍摄的照片"
        @unknown default: return "请检查相册权限"
        }
    }
    init(location: LocationSource = DeviceLocationSource(), now: @escaping () -> Date = Date.init) {
        self.location = location
        self.now = now
        do {
            let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("TravelRecorder", isDirectory: true)
            files = try PhotoFileStore(directory: root.appendingPathComponent("Photos", isDirectory: true))
            placeNames = TripPlaceNames(cacheURL: root.appendingPathComponent("PlaceNames.json"))
            repository = try CoreDataRepository(url: root.appendingPathComponent("Travel.sqlite"))
            for trip in try repository.load(Trip.self) where trip.status == .recording { try repository.save(RecorderLogic.recover(trip)) }
            try reload()
            ready = true
        } catch { errorMessage = "无法打开本地数据：\(error.localizedDescription)" }
        location.onSamples = { [weak self] samples in self?.receive(samples) }
        location.onAuthorization = { [weak self] in self?.authorizationChanged() }
        location.onFailure = { [weak self] message in self?.locationMessage = message }
        photos.onChange = { [weak self] in self?.schedulePhotoScan() }
        photos.observe()
    }
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
    func attachments(_ id: UUID) -> [PhotoAttachment] { load(PhotoAttachment.self, id) }
    func diaries(_ id: UUID) -> [DiaryEntry] { load(DiaryEntry.self, id) }
    private func load<T: StoredModel>(_ type: T.Type, _ id: UUID) -> [T] {
        guard ready else { return [] }
        do { return try repository.load(type, tripID: id) } catch { report(error); return [] }
    }
    private func report(_ error: Error) { DispatchQueue.main.async { self.errorMessage = error.localizedDescription } }
    private func authorized() -> Bool {
        let status = location.authorization
        if status == .notDetermined { pendingStart = true; location.requestPermission(); return false }
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            errorMessage = "请在系统设置中允许旅迹使用位置。已有旅程、照片和日记仍可查看。"
            return false
        }
        return true
    }
    func startOrResume() {
        guard ready, activeTrip?.status != .recording, authorized() else { return }
        do {
            let value = try activeTrip.map { try RecorderLogic.resume($0, at: now()) } ?? Trip(now: now())
            try repository.save(value)
            latestPoint = nil
            try reload()
            locationMessage = "正在获取位置…"
            location.start()
            if photos.authorization == .notDetermined { setAutomaticPhotos(true) }
            else { schedulePhotoScan() }
        } catch { report(error) }
    }
    func pause() {
        guard let trip = activeTrip, trip.status == .recording else { return }
        do {
            try repository.save(RecorderLogic.pause(trip, at: now()))
            location.stop()
            latestPoint = nil
            try reload()
            locationMessage = "已暂停，继续后记录新的路线段"
        } catch { report(error) }
    }
    func finish() {
        guard let trip = activeTrip else { return }
        do {
            let ended = try RecorderLogic.finish(trip, at: now())
            try repository.save(ended)
            location.stop()
            latestPoint = nil
            try reload()
            locationMessage = "旅程已保存在回忆中"
            scanPhotos(for: ended)
        } catch { report(error) }
    }
    private func receive(_ samples: [LocationSample]) {
        guard ready, var trip = activeTrip, trip.status == .recording else { return }
        var accepted: [TrackPoint] = []
        var last = latestPoint
        for sample in samples {
            guard let (updated, point) = RecorderLogic.accept(sample, trip: trip, previous: last, now: now()) else { continue }
            trip = updated; last = point; accepted.append(point)
        }
        guard !accepted.isEmpty else {
            if let sample = samples.last, sample.accuracy > 100 { locationMessage = "定位精度不足，等待更准确的位置" }
            return
        }
        do {
            // Trip state, distance and all points from this callback commit together.
            try repository.commit([StoredRecord(trip)] + accepted.map { try StoredRecord($0) }, deleting: [])
            latestPoint = last
            if pointCache[trip.id] != nil { pointCache[trip.id]!.append(contentsOf: accepted) }
            currentCoordinate = accepted.last?.coordinate
            try reload()
            locationMessage = location.precise ? "正在记录 · 定位精度约 \(Int(accepted.last!.accuracy)) 米" : "当前为大致位置，请在设置中开启精确位置"
        } catch {
            location.stop()
            locationMessage = "保存失败，已停止定位；请先处理错误再继续"
            if let old = activeTrip, let interrupted = try? RecorderLogic.pause(old, at: old.lastRecordedAt ?? now(), interrupted: true) {
                try? repository.save(interrupted)
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
            do { try repository.save(RecorderLogic.pause(trip, at: now(), interrupted: true)); try reload() } catch { report(error) }
            locationMessage = "定位权限已关闭，记录已中断"
        }
        revision += 1
    }
    func foreground() { authorizationChanged(); photos.observe(); schedulePhotoScan() }
    func setAutomaticPhotos(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "automaticPhotos")
        if enabled, photos.authorization == .notDetermined { photos.request { self.revision += 1; self.schedulePhotoScan() } }
        else { revision += 1; schedulePhotoScan() }
    }
    private func schedulePhotoScan() {
        scanWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            for trip in self.trips where trip.status != .ended || self.now().timeIntervalSince(trip.endedAt ?? .distantPast) < 172800 { self.scanPhotos(for: trip) }
        }
        scanWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }
    func scanPhotos(for trip: Trip, force: Bool = false) {
        guard ready, automaticPhotos || force else { return }
        guard photos.authorization == .authorized || photos.authorization == .limited else { revision += 1; return }
        let existing = Set(attachments(trip.id).compactMap { $0.assetID })
        let excluded = Set(load(PhotoExclusion.self, trip.id).map { $0.assetID })
        for asset in photos.candidates(for: trip, now: now()) {
            guard let date = asset.creationDate, PhotoMatching.shouldImport(assetID: asset.localIdentifier, capturedAt: date, trip: trip, now: now(), existing: existing, excluded: excluded) else { continue }
            enqueue(tripID: trip.id, key: asset.localIdentifier) { self.photos.read(asset, completion: $0) }
        }
    }
    func importPhotos(_ results: [PHPickerResult], into tripID: UUID) {
        for result in results {
            let key = result.assetIdentifier ?? UUID().uuidString
            guard !attachments(tripID).contains(where: { $0.assetID != nil && $0.assetID == result.assetIdentifier }) else { continue }
            enqueue(tripID: tripID, key: key) { self.photos.read(result, completion: $0) }
        }
    }
    private func enqueue(tripID: UUID, key: String, reader: @escaping (@escaping (Result<ImportedPhotoInput, Error>) -> Void) -> Void) {
        let token = tripID.uuidString + ":" + key
        guard !inFlight.contains(token), trip(tripID) != nil else { return }
        inFlight.insert(token)
        imports.append((tripID, token, reader))
        importCount += 1
        photoMessage = "正在导入照片…"
        pumpImports()
    }
    private func pumpImports() {
        guard runningImports < 2, !imports.isEmpty else { return }
        let (tripID, token, reader) = imports.removeFirst()
        runningImports += 1
        reader { result in
            self.photoQueue.async {
                switch result {
                case .failure(let error): DispatchQueue.main.async { self.completeImport(token: token, error: error) }
                case .success(let input):
                    do {
                        let prepared = try self.files.prepare(data: input.data)
                        DispatchQueue.main.async {
                            do {
                                guard self.trip(tripID) != nil else { throw TripError.missingTrip }
                                if let id = input.assetID, self.attachments(tripID).contains(where: { $0.assetID == id }) {
                                    self.files.remove(prepared.imageFile); self.files.remove(prepared.thumbnailFile)
                                    self.completeImport(token: token, error: nil); return
                                }
                                let coordinate = (input.coordinate ?? prepared.coordinate).flatMap { $0.isValid ? $0 : nil }
                                let photo = PhotoAttachment(tripID: tripID, assetID: input.assetID, capturedAt: input.date ?? prepared.capturedAt ?? self.now(), importedAt: self.now(), coordinate: coordinate, originalCoordinate: coordinate, captureDateKnown: input.date != nil || prepared.capturedAt != nil, imageFile: prepared.imageFile, thumbnailFile: prepared.thumbnailFile)
                                try self.repository.save(photo)
                                self.revision += 1
                                self.completeImport(token: token, error: nil)
                            } catch {
                                self.files.remove(prepared.imageFile); self.files.remove(prepared.thumbnailFile)
                                self.completeImport(token: token, error: error)
                            }
                        }
                    } catch { DispatchQueue.main.async { self.completeImport(token: token, error: error) } }
                }
            }
        }
        pumpImports()
    }
    private func completeImport(token: String, error: Error?) {
        inFlight.remove(token)
        runningImports -= 1
        importCount -= 1
        if let error = error { photoMessage = "有照片未能导入：\(error.localizedDescription) 可稍后重试。" }
        else if importCount == 0 && !photoMessage.contains("未能") { photoMessage = "照片已保存在本机" }
        pumpImports()
    }
    @discardableResult func update(_ trip: Trip) -> Bool {
        guard let current = self.trip(trip.id) else { return false }
        var merged = current
        merged.title = trip.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? current.title : trip.title
        merged.features = trip.features; merged.reflection = trip.reflection; merged.updatedAt = now()
        do { try repository.save(merged); try reload(); return true } catch { report(error); return false }
    }
    @discardableResult func saveDiary(_ diary: DiaryEntry) -> Bool {
        guard trip(diary.tripID) != nil else { return false }
        var value = diary
        if let photoID = diary.photoID, let photo = attachments(diary.tripID).first(where: { $0.id == photoID }) { value.coordinate = photo.coordinate }
        do { try repository.save(value); revision += 1; return true } catch { report(error); return false }
    }
    @discardableResult func deleteDiary(_ diary: DiaryEntry) -> Bool {
        do { try repository.commit([], deleting: ["diary:" + diary.id.uuidString]); revision += 1; return true } catch { report(error); return false }
    }
    @discardableResult func place(_ photo: PhotoAttachment, at coordinate: Coordinate) -> Bool {
        guard trip(photo.tripID) != nil, let (updated, related) = PhotoEditing.place(photo, at: coordinate, diaries: diaries(photo.tripID)) else { return false }
        do { try repository.commit([StoredRecord(updated)] + related.map { try StoredRecord($0) }, deleting: []); revision += 1; return true } catch { report(error); return false }
    }
    @discardableResult func removePhoto(_ photo: PhotoAttachment) -> Bool {
        do {
            let related = diaries(photo.tripID).filter { $0.photoID == photo.id }
            // Preserve attached writing as a place/general diary when removing a photo.
            let preserved = related.map { value -> DiaryEntry in var copy = value; copy.photoID = nil; copy.coordinate = photo.mapCoordinate?.identified; return copy }
            var records = try preserved.map { try StoredRecord($0) }
            if let id = photo.assetID { records.append(try StoredRecord(PhotoExclusion(tripID: photo.tripID, assetID: id, sortDate: now()))) }
            try repository.commit(records, deleting: ["photo:" + photo.id.uuidString])
            files.remove(photo.imageFile); files.remove(photo.thumbnailFile)
            revision += 1
            return true
        } catch { report(error); return false }
    }
    @discardableResult func deleteTrip(_ id: UUID) -> Bool {
        guard activeTrip?.id != id else { errorMessage = "请先结束旅程，再删除。"; return false }
        let images = attachments(id)
        do {
            try repository.deleteTrip(id)
            for photo in images { files.remove(photo.imageFile); files.remove(photo.thumbnailFile) }
            pointCache.removeValue(forKey: id)
            try reload()
            return true
        } catch { report(error); return false }
    }
    func openSettings() { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
}
