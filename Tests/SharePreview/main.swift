import Foundation
import UIKit
import Photos
import UserNotifications
import CoreGraphics
import MapKit
import SwiftUI
import CoreImage

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var checks = 0
func require(_ condition: Bool, _ name: String) {
    checks += 1
    if !condition { fputs("FAIL: \(name)\n", stderr); exit(1) }
    print("PASS: \(name)")
}
// Language choice is the only first-run gate; no tutorial completion is required.
require(AppLanguage.needsWelcome(language: "", completed: false), "fresh install requires language selection")
require(AppLanguage.needsWelcome(language: "", completed: true), "missing language cannot bypass welcome")
require(!AppLanguage.needsWelcome(language: "en", completed: false) && !AppLanguage.needsWelcome(language: "zh-Hans", completed: false), "selected language enters real app without tutorial completion")
require(!AppLanguage.needsWelcome(language: "en", completed: true) && !AppLanguage.needsWelcome(language: "zh-Hans", completed: true), "completed welcome does not repeat in either language")
let priorLanguage = UserDefaults.standard.object(forKey: AppLanguage.key)
UserDefaults.standard.set("en", forKey: AppLanguage.key)
require(L("开始记录") == "Start recording" && L("回忆") == "Memories", "English choice translates main actions")
require(L("My own diary 中文") == "My own diary 中文", "localization preserves user-authored content")
UserDefaults.standard.set("zh-Hans", forKey: AppLanguage.key)
require(L("开始记录") == "开始记录", "Chinese choice keeps original text")
if let priorLanguage = priorLanguage { UserDefaults.standard.set(priorLanguage, forKey: AppLanguage.key) }
else { UserDefaults.standard.removeObject(forKey: AppLanguage.key) }
// Verify the native header's hit regions and latest closures after a render update.
let header = ShareHeaderView()
var nextActions = 0, doneActions = 0, backActions = 0
header.configure(showingPreview: false, canShare: false, onLeft: { doneActions += 1 }, onRight: { nextActions += 1 })
for width in [320, 414, 896] {
    header.frame = CGRect(x: 0, y: 0, width: width, height: 52)
    header.setNeedsLayout(); header.layoutIfNeeded()
    for button in [header.doneButton, header.nextButton] {
        let hit = header.hitTest(button.center, with: nil)
        require(hit === button || hit?.isDescendant(of: button) == true, "native share action is hittable at width \(width)")
    }
    require(header.doneButton.frame.maxX < header.nextButton.frame.minX, "Done and Next do not overlap")
}
// UIApplication event dispatch is not available in this CLI renderer.
// Invoke the registered selector here; actual button events are tested in a window.
header.perform(NSSelectorFromString(header.nextButton.actions(forTarget: header, forControlEvent: .touchUpInside)!.first!))
require(nextActions == 1 && doneActions == 0, "registered Next target invokes exactly one generation action")
var shares = 0
header.configure(showingPreview: true, canShare: false, onLeft: { backActions += 1 }, onRight: { shares += 1 })
require(header.doneButton.currentTitle == L("返回编辑") && header.doneButton.isEnabled && !header.nextButton.isEnabled, "can return to editing while preview is generating or unavailable")
header.configure(showingPreview: true, canShare: true, onLeft: { backActions += 1 }, onRight: { shares += 1 })
require(header.nextButton.currentImage != nil && header.nextButton.isEnabled && header.nextButton.accessibilityLabel == L("分享旅程"), "ready preview has an accessible share icon on the right")
header.perform(NSSelectorFromString(header.nextButton.actions(forTarget: header, forControlEvent: .touchUpInside)!.first!))
header.perform(NSSelectorFromString(header.doneButton.actions(forTarget: header, forControlEvent: .touchUpInside)!.first!))
require(backActions == 1 && nextActions == 1 && doneActions == 0 && shares == 1, "preview shares on right and returns on left without dismissing editor")
header.configure(showingPreview: false, canShare: false, onLeft: { doneActions += 1 }, onRight: { nextActions += 1 })
require(header.doneButton.currentTitle == L("完成") && header.nextButton.currentTitle == L("下一步") && header.nextButton.currentImage == nil && header.nextButton.isEnabled, "returning restores editor controls after preview")
// Render the production asynchronous photo component with mixed source aspect ratios.
// UIKit can draw in this CLI, but some Catalyst versions do not attach SwiftUI's
// display list without UIApplicationMain. Such a runtime is reported as unavailable,
// never counted as a passing layout test.
var photoLayoutStatus = "not attempted"
let thumbnailProbeDirectory = output.appendingPathComponent("thumbnail-layout", isDirectory: true)
try FileManager.default.createDirectory(at: thumbnailProbeDirectory, withIntermediateDirectories: true)
let probeSizes = [CGSize(width: 320, height: 180), CGSize(width: 240, height: 180), CGSize(width: 180, height: 240)]
let probeColors = [UIColor(red: 0.9, green: 0.08, blue: 0.08, alpha: 1),
                   UIColor(red: 0.05, green: 0.8, blue: 0.1, alpha: 1),
                   UIColor(red: 0.08, green: 0.15, blue: 0.9, alpha: 1)]
var probeFiles: [URL] = []
for index in 0..<3 {
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let image = UIGraphicsImageRenderer(size: probeSizes[index], format: format).image { context in
        probeColors[index].setFill(); context.fill(CGRect(origin: .zero, size: probeSizes[index]))
        UIColor.black.setStroke()
        let edge = UIBezierPath(rect: CGRect(origin: .zero, size: probeSizes[index]).insetBy(dx: 4, dy: 4))
        edge.lineWidth = 8; edge.stroke()
    }
    let file = thumbnailProbeDirectory.appendingPathComponent("aspect-\(index).png")
    try image.pngData()!.write(to: file); probeFiles.append(file)
}
struct ThumbnailLayoutProbe: View {
    let files: [URL]
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 10), count: 3), spacing: 10) {
            ForEach(files.indices, id: \.self) { index in
                PhotoThumbnail(file: files[index], height: 110, cornerRadius: 0)
            }
        }.padding(12).background(Color(red: 0.9, green: 0.03, blue: 0.9))
    }
}
func rgbaPixels(_ image: UIImage) -> (bytes: [UInt8], width: Int, height: Int)? {
    guard let cg = image.cgImage else { return nil }
    let width = cg.width, height = cg.height
    var bytes = [UInt8](repeating: 0, count: width*height*4)
    let rendered = bytes.withUnsafeMutableBytes { memory -> Bool in
        guard let context = CGContext(data: memory.baseAddress, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width*4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    return rendered ? (bytes, width, height) : nil
}
func classifyPixel(_ pixels: (bytes: [UInt8], width: Int, height: Int), x: Int, y: Int) -> Int {
    guard x >= 0, y >= 0, x < pixels.width, y < pixels.height else { return -1 }
    let offset = (y*pixels.width+x)*4
    let r = Int(pixels.bytes[offset]), g = Int(pixels.bytes[offset+1]), b = Int(pixels.bytes[offset+2])
    if r > 150 && b > 150 && g < 80 { return 3 } // exposed grid/background gap
    if r > 150 && r > g*2 && r > b*2 { return 0 }
    if g > 150 && g > r*2 && g > b*2 { return 1 }
    if b > 150 && b > r*2 && b > g*2 { return 2 }
    return -1
}
var successfulPhotoLayouts = 0
for width in [CGFloat(320), CGFloat(414)] {
    let controller = UIHostingController(rootView: ThumbnailLayoutProbe(files: probeFiles))
    let parent = UIViewController()
    parent.loadViewIfNeeded(); parent.view.frame = CGRect(x: 0, y: 0, width: width, height: 134)
    parent.addChild(controller); parent.view.addSubview(controller.view); controller.didMove(toParent: parent)
    controller.view.frame = parent.view.bounds
    controller.overrideUserInterfaceStyle = .light; controller.view.backgroundColor = .clear
    parent.beginAppearanceTransition(true, animated: false); parent.endAppearanceTransition()
    let slot = (width-24-20)/3
    let centers = (0..<3).map { Int(12+slot/2+CGFloat($0)*(slot+10)) }
    let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
    var rendered: UIImage?
    var colors: [Int] = []
    let deadline = Date().addingTimeInterval(2)
    repeat {
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        parent.view.setNeedsLayout(); parent.view.layoutIfNeeded(); controller.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: parent.view.bounds.size, format: format).image { context in
            parent.view.layer.render(in: context.cgContext)
        }
        rendered = image
        if let pixels = rgbaPixels(image) { colors = centers.map { classifyPixel(pixels, x: $0, y: 67) } }
    } while colors != [0, 1, 2] && Date() < deadline
    if let image = rendered { try image.pngData()!.write(to: thumbnailProbeDirectory.appendingPathComponent("mixed-grid-\(Int(width)).png")) }
    if colors == [0, 1, 2], let image = rendered, let pixels = rgbaPixels(image) {
        // Distinct decoded center colors establish that all three async images loaded.
        require(colors == [0, 1, 2], "mixed 16:9 4:3 and portrait photo centers render in assigned slots at \(Int(width))pt")
        let gaps = [6, Int(12+slot+5), Int(12+slot*2+15), Int(width)-6]
        require(gaps.allSatisfy { classifyPixel(pixels, x: $0, y: 67) == 3 },
                "loaded photos do not paint into gutters or outside grid at \(Int(width))pt")
        successfulPhotoLayouts += 1
    } else {
        // A painted SwiftUI background proves the display list is available;
        // failure to load the images or put them in the right slots must then fail.
        let hostPainted = rendered.flatMap(rgbaPixels).map { classifyPixel($0, x: 6, y: 67) == 3 } ?? false
        if hostPainted || colors.contains(where: { $0 >= 0 && $0 < 3 }) {
            require(false, "mixed photo layout did not load and paint all images into their expected slots at \(Int(width))pt")
        }
        print("UNAVAILABLE: SwiftUI thumbnail display list did not render in this CLI at \(Int(width))pt; native window/device validation remains required")
    }
    parent.beginAppearanceTransition(false, animated: false); parent.endAppearanceTransition()
    controller.willMove(toParent: nil); controller.view.removeFromSuperview(); controller.removeFromParent()
}
photoLayoutStatus = successfulPhotoLayouts == 2 ? "PASS: mixed-photo production grid rendered at 320 and 414pt" : "UNAVAILABLE: Catalyst CLI did not render all SwiftUI thumbnail grids; device validation required"
let qrDetector = CIDetector(ofType: CIDetectorTypeQRCode, context: CIContext(),
                            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])!
func decodedInvitations(_ image: UIImage) -> [String] {
    guard let cg = image.cgImage else { return [] }
    return qrDetector.features(in: CIImage(cgImage: cg)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
}

// Force a slow real SQLite open. UI queue must keep servicing taps/timers.
final class RepositoryProbe: TripRepository {
    let underlying: TripRepository
    var mainMetadataLoads = 0
    var failWrites = false
    init(_ underlying: TripRepository) { self.underlying = underlying }
    func load<T: StoredModel>(_ type: T.Type, tripID: UUID?) throws -> [T] {
        if Thread.isMainThread && (T.kind == PhotoAttachment.kind || T.kind == DiaryEntry.kind) { mainMetadataLoads += 1 }
        return try underlying.load(type, tripID: tripID)
    }
    func commit(_ records: [StoredRecord], deleting: [String]) throws {
        if failWrites { throw TripError.storage("Fixture failed write") }
        try underlying.commit(records, deleting: deleting)
    }
    func deleteTrip(_ id: UUID) throws { try underlying.deleteTrip(id) }
}
var startupTrip = Trip(now: Date()); startupTrip.status = .ended; startupTrip.endedAt = Date()
var startupPhoto = PhotoAttachment(tripID: startupTrip.id, capturedAt: Date(), importedAt: Date(), imageFile: "", thumbnailFile: "")
startupPhoto.libraryLinked = true
var startupDiary = DiaryEntry(tripID: startupTrip.id, photoID: startupPhoto.id, text: "before", createdAt: Date(), updatedAt: Date())
var startupRepository: RepositoryProbe?
let startupBegin = Date()
var openedOnMain = true
let startup = TravelStore(storageRoot: output.appendingPathComponent("startup"), openRepository: { url in
    openedOnMain = Thread.isMainThread
    Thread.sleep(forTimeInterval: 0.4)
    let repository = try CoreDataRepository(url: url)
    try repository.commit([StoredRecord(startupTrip), StoredRecord(startupPhoto), StoredRecord(startupDiary)], deleting: [])
    let probe = RepositoryProbe(repository); startupRepository = probe
    return probe
}, remindersEnabled: false)
require(Date().timeIntervalSince(startupBegin) < 0.25 && !startup.ready, "cold store returns before slow SQLite open")
var heartbeat = false
DispatchQueue.main.async { heartbeat = true }
let heartbeatDeadline = Date().addingTimeInterval(0.2)
while !heartbeat && Date() < heartbeatDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
require(heartbeat && !startup.ready, "UI queue responds while store opens")
let startupDeadline = Date().addingTimeInterval(5)
while !startup.ready && startup.errorMessage == nil && Date() < startupDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
require(startup.ready && !openedOnMain, "asynchronous startup publishes ready after real SQLite load")
for _ in 0..<100 { _ = startup.attachments(startupTrip.id); _ = startup.diaries(startupTrip.id) }
require(startup.attachments(startupTrip.id).count == 1 && startup.diaries(startupTrip.id).count == 1 && startupRepository?.mainMetadataLoads == 0, "UI photo and diary reads use bootstrap snapshots without synchronous database loads")
startupDiary.text = "after"
require(startup.saveDiary(startupDiary) && startup.diaries(startupTrip.id).first?.text == "after", "diary save updates the read snapshot after commit")
startupRepository?.failWrites = true
startupDiary.text = "must not appear"
require(!startup.saveDiary(startupDiary) && startup.diaries(startupTrip.id).first?.text == "after", "failed database write cannot change cached writing")
startupRepository?.failWrites = false
let placedAt = Coordinate(latitude: 30, longitude: 120)
try startup.placeExistingPhoto(startupPhoto, at: placedAt)
require( startup.attachments(startupTrip.id).first?.manuallyPlaced == true && startup.diaries(startupTrip.id).first?.coordinate == placedAt, "manual photo placement updates photo and diary snapshots together")
let cachedPhoto = startup.attachments(startupTrip.id).first!
require(startup.removePhoto(cachedPhoto) && startup.attachments(startupTrip.id).isEmpty && startup.diaries(startupTrip.id).first?.photoID == nil, "removing a photo preserves writing in the current read snapshot")
do {
    try startup.placeExistingPhoto(cachedPhoto, at: placedAt)
    require(false, "removed photo must not be resurrected by an open placement sheet")
} catch {
    require(startup.attachments(startupTrip.id).isEmpty && startup.diaries(startupTrip.id).first?.photoID == nil,
            "stale placement fails without restoring removed photo or relinking its diary")
}
require(startup.deleteDiary(startupDiary) && startup.diaries(startupTrip.id).isEmpty, "diary deletion immediately updates its read snapshot")
require(startup.deleteTrip(startupTrip.id) && startup.attachments(startupTrip.id).isEmpty && startup.diaries(startupTrip.id).isEmpty, "trip deletion clears cached photo and diary records")
// Exercise real store transactions with an injected Photos catalog, not the host's library.
final class CatalogFixture: PhotoLibraryService {
    private let lock = NSLock()
    private var status: PHAuthorizationStatus = .denied
    var catalog: [String: LibraryPhotoMetadata] = [:]
    var beforeReturn: (() -> Void)?
    private(set) var completed = 0
    override var authorization: PHAuthorizationStatus { lock.lock(); defer { lock.unlock() }; return status }
    func setAuthorization(_ value: PHAuthorizationStatus) { lock.lock(); status = value; lock.unlock() }
    override func observe() {}
    override func candidates(for trip: Trip, now: Date) -> [PHAsset] { [] }
    override func snapshot(identifiers: [String]) -> LibraryPhotoSnapshot {
        let auth = authorization
        let result = LibraryPhotoSnapshot(authorization: auth, authorizationUnchanged: true, assets: catalog)
        let action = beforeReturn; beforeReturn = nil; action?()
        DispatchQueue.main.asyncAfter(deadline: .now()+0.05) { self.completed += 1 }
        return result
    }
}
let catalog = CatalogFixture()
var cleanupTrip = Trip(now: Date()); cleanupTrip.status = .ended; cleanupTrip.endedAt = Date()
func catalogPhoto(_ asset: String?) -> PhotoAttachment {
    var p = PhotoAttachment(tripID: cleanupTrip.id, assetID: asset, capturedAt: Date(), importedAt: Date(), imageFile: "", thumbnailFile: "")
    p.libraryLinked = true; return p
}
let missingNoDiary = catalogPhoto("removed-empty")
let missingWithDiary = catalogPhoto("removed-diary")
var existingPhoto = catalogPhoto("existing-hidden-or-cloud")
existingPhoto.manuallyPlaced = true; existingPhoto.coordinate = Coordinate(latitude: 30, longitude: 120)
let unknownLegacyPhoto = catalogPhoto(nil)
let preservedDiary = DiaryEntry(tripID: cleanupTrip.id, photoID: missingWithDiary.id, text: "不能丢失的日记", createdAt: Date(), updatedAt: Date())
var cleanupRepository: RepositoryProbe?
let cleanupStore = TravelStore(photos: catalog, storageRoot: output.appendingPathComponent("cleanup"), openRepository: { url in
    let repository = try CoreDataRepository(url: url)
    try repository.commit([StoredRecord(cleanupTrip), StoredRecord(preservedDiary)] + [missingNoDiary, missingWithDiary, existingPhoto, unknownLegacyPhoto].map { try StoredRecord($0) }, deleting: [])
    let probe = RepositoryProbe(repository); cleanupRepository = probe; return probe
}, remindersEnabled: false)
func awaitCatalog(_ additional: Int = 1, action: () -> Void) {
    let target = catalog.completed+additional
    action()
    let deadline = Date().addingTimeInterval(5)
    while catalog.completed < target && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    require(catalog.completed >= target, "library reconciliation completes")
}
let cleanupDeadline = Date().addingTimeInterval(5)
while (!cleanupStore.ready || catalog.completed == 0) && Date() < cleanupDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
require(cleanupStore.ready && cleanupStore.attachments(cleanupTrip.id).count == 4, "denied Photos access never deletes stored associations")
catalog.setAuthorization(.limited)
awaitCatalog { cleanupStore.synchronizeLibrary() }
require(cleanupStore.attachments(cleanupTrip.id).count == 4, "limited library visibility cannot be mistaken for deletion")
catalog.setAuthorization(.authorized)
catalog.catalog = ["existing-hidden-or-cloud": LibraryPhotoMetadata(createdAt: Date(), modifiedAt: nil, coordinate: Coordinate(latitude: 31, longitude: 121))]
cleanupRepository?.failWrites = true
awaitCatalog { cleanupStore.synchronizeLibrary() }
require(cleanupStore.attachments(cleanupTrip.id).count == 4 && cleanupStore.errorMessage != nil, "failed cleanup transaction preserves the entire visible snapshot")
cleanupRepository?.failWrites = false
awaitCatalog { cleanupStore.synchronizeLibrary() }
let survivors = cleanupStore.attachments(cleanupTrip.id)
require(!survivors.contains { $0.id == missingNoDiary.id } && survivors.count == 3, "full-library missing photo without diary is removed")
require(survivors.contains { $0.id == missingWithDiary.id && $0.libraryAvailable == false } && cleanupStore.diaries(cleanupTrip.id).first?.text == preservedDiary.text, "deleted original with diary keeps its association and writing")
require(survivors.contains { $0.id == existingPhoto.id && $0.libraryAvailable == true && $0.coordinate == existingPhoto.coordinate }, "available hidden or cloud asset keeps association and manual placement")
require(survivors.contains { $0.id == unknownLegacyPhoto.id }, "unknown legacy identity is not guessed to be deleted")
require(!(try cleanupRepository!.load(PhotoAttachment.self, tripID: cleanupTrip.id)).contains { $0.id == missingNoDiary.id }, "removal is persisted, not just hidden until restart")
catalog.setAuthorization(.limited)
awaitCatalog { _ = cleanupStore.deleteDiary(preservedDiary) }
require(cleanupStore.attachments(cleanupTrip.id).contains { $0.id == missingWithDiary.id }, "last diary removal cannot prune without full Photos access")
// Authorization revoked during a full lookup forces a fresh limited lookup.
catalog.setAuthorization(.authorized)
catalog.beforeReturn = { catalog.setAuthorization(.limited) }
awaitCatalog(2) { cleanupStore.synchronizeLibrary() }
require(cleanupStore.attachments(cleanupTrip.id).contains { $0.id == missingWithDiary.id }, "permission change while fetching rejects a destructive old full-access result")
catalog.setAuthorization(.authorized)
awaitCatalog { cleanupStore.synchronizeLibrary() }
require(!cleanupStore.attachments(cleanupTrip.id).contains { $0.id == missingWithDiary.id }, "missing photo is removed once its last diary is deleted and full access returns")
// A new diary created during the worker lookup must win over the older photo snapshot.
let concurrentDiary = DiaryEntry(tripID: cleanupTrip.id, photoID: existingPhoto.id, text: "查询时刚写的日记", createdAt: Date(), updatedAt: Date())
catalog.catalog = [:]
catalog.beforeReturn = { DispatchQueue.main.sync { _ = cleanupStore.saveDiary(concurrentDiary) } }
awaitCatalog { cleanupStore.synchronizeLibrary() }
require(cleanupStore.attachments(cleanupTrip.id).contains { $0.id == existingPhoto.id } && cleanupStore.diaries(cleanupTrip.id).contains { $0.id == concurrentDiary.id }, "concurrent diary save prevents stale-snapshot photo deletion")
// Actual MKMapView camera uses intermediate positions, then converges; cancellation holds.
let cameraMap = MKMapView(frame: CGRect(x: 0, y: 0, width: 400, height: 500))
cameraMap.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 30, longitude: 120), span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)), animated: false)
let smoothCamera = SmoothMapCamera()
let cameraStart = cameraMap.centerCoordinate.longitude
let cameraWidth = cameraMap.visibleMapRect.width
smoothCamera.follow(CLLocationCoordinate2D(latitude: 30, longitude: 120.02), on: cameraMap)
require(abs(cameraMap.centerCoordinate.longitude-cameraStart) < 0.000001, "camera target does not teleport")
smoothCamera.step(1.0/60)
require(cameraMap.centerCoordinate.longitude > cameraStart && cameraMap.centerCoordinate.longitude < 120.019, "camera first frame is intermediate")
for _ in 0..<360 { smoothCamera.step(1.0/60) }
require(abs(cameraMap.centerCoordinate.longitude-120.02) < 0.00001, "camera converges continuously")
require(abs(cameraMap.visibleMapRect.width-cameraWidth) / cameraWidth < 0.001, "smooth follow preserves the current map zoom")
smoothCamera.follow(CLLocationCoordinate2D(latitude: 31, longitude: 121), on: cameraMap)
smoothCamera.stop()
let stoppedCenter = cameraMap.centerCoordinate.longitude
smoothCamera.step(0.1)
require(cameraMap.centerCoordinate.longitude == stoppedCenter, "manual camera stop cancels motion")
// Visual evidence for the production native map controls; phone compositor still needs testing.
for scale in [CGFloat(2), CGFloat(3)] {
    for dark in [false, true] {
        let panel = UIView(frame: CGRect(x: 0, y: 0, width: 150, height: 80))
        panel.overrideUserInterfaceStyle = dark ? .dark : .light
        panel.backgroundColor = dark ? UIColor(white: 0.2, alpha: 1) : UIColor(red: 0.7, green: 0.85, blue: 0.7, alpha: 1)
        for (index, symbol) in ["location.fill", "arrow.up.left.and.arrow.down.right"].enumerated() {
            let button = MapControlButton(frame: .zero)
            button.frame = CGRect(x: 18+index*58, y: 18, width: 44, height: 44)
            button.overrideUserInterfaceStyle = dark ? .dark : .light
            button.contentScaleFactor = scale; button.isOpaque = false; button.backgroundColor = .clear
            button.symbol = symbol; button.darkAppearance = dark
            panel.addSubview(button)
        }
        panel.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let format = UIGraphicsImageRendererFormat(); format.scale = scale
        let preview = UIGraphicsImageRenderer(size: panel.bounds.size, format: format).image { ctx in panel.layer.render(in: ctx.cgContext) }
        try preview.pngData()!.write(to: output.appendingPathComponent("map-controls-\(dark ? "dark" : "light")-\(Int(scale))x.png"))
    }
}
// Exercise production map/control ownership, touches, callback replacement and resize.
let host = TravelMapHost(frame: CGRect(x: 0, y: 0, width: 414, height: 460))
var recenterCalls = 0
var fitCalls = 0
host.configure(follow: true, onRecenter: { recenterCalls += 1 }, onFitRoute: { fitCalls += 1 })
host.layoutIfNeeded()
require([host.recenterButton, host.routeButton].allSatisfy { !($0.gestureRecognizers ?? []).contains { $0 is UILongPressGestureRecognizer } }, "map controls contain no tutorial long-press recognizers")
require([host.recenterButton, host.routeButton].allSatisfy { ($0.accessibilityCustomActions ?? []).isEmpty }, "map controls expose no removed tutorial actions")

// This CLI has no UIApplicationMain event dispatcher. Invoke each action registered
// for touchUpInside through Objective-C; actual touch dispatch remains a phone check.
func invokeRegisteredActions(_ control: UIControl) {
    for target in control.allTargets {
        guard let object = target.base as? NSObject else { continue }
        for action in control.actions(forTarget: object, forControlEvent: .touchUpInside) ?? [] {
            object.perform(NSSelectorFromString(action), with: control)
        }
    }
}
func hitCenter(_ view: UIView) -> UIView? {
    host.hitTest(CGPoint(x: view.frame.midX, y: view.frame.midY), with: nil)
}
require(hitCenter(host.recenterButton) === host.recenterButton && hitCenter(host.routeButton) === host.routeButton, "native controls receive touches above live map")
let gapHit = host.hitTest(CGPoint(x: (host.recenterButton.frame.maxX + host.routeButton.frame.minX)/2, y: host.routeButton.frame.midY), with: nil)
require(gapHit === host.map || gapHit?.isDescendant(of: host.map) == true, "space between controls passes gestures to map")
invokeRegisteredActions(host.recenterButton)
invokeRegisteredActions(host.routeButton)
require(recenterCalls == 1 && fitCalls == 1, "each native control registers its own action exactly once")
host.configure(follow: false, onRecenter: { recenterCalls += 10 }, onFitRoute: { fitCalls += 10 })
invokeRegisteredActions(host.recenterButton)
require(recenterCalls == 11 && fitCalls == 1 && host.recenterButton.symbol == "location", "state update replaces action without accumulating targets")
host.frame.size = CGSize(width: 320, height: 340)
host.layoutIfNeeded()
require(host.map.frame == host.bounds && host.bounds.contains(host.recenterButton.frame) && host.bounds.contains(host.routeButton.frame), "resized map fills host and controls remain inside")
let replayLayer = UIView(frame: host.map.bounds); replayLayer.isUserInteractionEnabled = false
host.map.addSubview(replayLayer)
require(hitCenter(host.routeButton) === host.routeButton && host.subviews.first === host.map, "map overlay stays below native controls")
replayLayer.removeFromSuperview()
// Native appearance propagation requires an attached application window; verify on phone.
host.configure(follow: false, onRecenter: nil, onFitRoute: { fitCalls += 1 })
host.layoutIfNeeded()
require(host.recenterButton.isHidden && !host.routeButton.isHidden && hitCenter(host.routeButton) === host.routeButton, "detail map exposes only route control")
host.configure(follow: false, onRecenter: nil, onFitRoute: nil)
host.layoutIfNeeded()
require(host.recenterButton.isHidden && host.routeButton.isHidden, "photo placement map exposes no navigation controls")
require(host.subviews.count == 3, "map host contains only map and two circular controls, without backing or replay follow button")
host.configure(follow: true, onRecenter: {}, onFitRoute: {})
host.layoutIfNeeded()
require(host.subviews[1] === host.recenterButton && host.subviews[2] === host.routeButton, "both circular controls sit directly over the map without a rectangular backing")
final class FixtureNotificationCenter: TripNotificationCenter {
    var allowed = true
    var delayPermission = false
    var waiting: [(Bool) -> Void] = []
    var pending: [String: UNNotificationRequest] = [:]
    var adds = 0
    func permission(_ completion: @escaping (Bool) -> Void) { if delayPermission { waiting.append(completion) } else { completion(allowed) } }
    func requestPermission(_ completion: @escaping (Bool, Error?) -> Void) { completion(allowed, nil) }
    func add(_ request: UNNotificationRequest, completion: @escaping (Error?) -> Void) { adds += 1; pending[request.identifier] = request; completion(nil) }
    func removePending(_ ids: [String]) { ids.forEach { pending.removeValue(forKey: $0) } }
    func removeDelivered(_ ids: [String]) {}
}
func drainReminderCallbacks() { RunLoop.main.run(until: Date().addingTimeInterval(0.04)) }
let reminderDefaultsName = "travel.fixture.reminder." + UUID().uuidString
let reminderDefaults = UserDefaults(suiteName: reminderDefaultsName)!
let notificationFixture = FixtureNotificationCenter()
let reminders = TripReminderService(defaults: reminderDefaults, center: notificationFixture)
let reminderNow = Date()
var reminderTrip = Trip(now: reminderNow)
reminders.reconcile(reminderTrip, now: reminderNow); drainReminderCallbacks()
require(notificationFixture.pending.isEmpty, "no stationary claim before first location")
let reminderSample = LocationSample(coordinate: Coordinate(latitude: 30, longitude: 120), timestamp: reminderNow, accuracy: 8)
reminders.observe([reminderSample], trip: reminderTrip, now: reminderNow); drainReminderCallbacks()
let idleRequest = notificationFixture.pending.values.first!
require((idleRequest.trigger as? UNTimeIntervalNotificationTrigger).map { $0.timeInterval > 7198 && $0.timeInterval <= 7200 } == true && idleRequest.trigger?.repeats == false, "notification requests a single two-hour delay")
require(ReminderRouter.tripID(from: idleRequest.content.userInfo) == reminderTrip.id, "notification routes to the matching trip identity")
require(ReminderRouter.tripID(from: ["tripID": reminderTrip.id.uuidString]) == nil, "unrelated notification cannot open trip confirmation")
let previousAdds = notificationFixture.adds
reminders.observe([LocationSample(coordinate: reminderSample.coordinate, timestamp: reminderNow.addingTimeInterval(60), accuracy: 8)], trip: reminderTrip, now: reminderNow.addingTimeInterval(60)); drainReminderCallbacks()
require(notificationFixture.adds == previousAdds, "stationary fixes do not repeatedly replace the deadline")
reminders.cancel(); drainReminderCallbacks()
require(notificationFixture.pending.isEmpty, "finishing trip cancels pending reminder")
notificationFixture.delayPermission = true
reminders.observe([reminderSample], trip: reminderTrip, now: reminderNow)
reminders.cancel()
notificationFixture.waiting.forEach { $0(true) }; notificationFixture.waiting = []; drainReminderCallbacks()
require(notificationFixture.pending.isEmpty, "late permission lookup cannot revive a finished trip notification")
notificationFixture.delayPermission = false; notificationFixture.allowed = false
reminders.observe([reminderSample], trip: reminderTrip, now: reminderNow); drainReminderCallbacks()
require(notificationFixture.pending.isEmpty, "denied notification permission never schedules a reminder")
reminders.cancel(); notificationFixture.allowed = true
reminderTrip.status = .paused
reminders.reconcile(reminderTrip, now: reminderNow); drainReminderCallbacks()
require(notificationFixture.pending.count == 1 && notificationFixture.pending.values.first!.content.body != idleRequest.content.body, "paused trip uses a pause message without claiming observed location")
reminders.cancel(); reminderDefaults.removePersistentDomain(forName: reminderDefaultsName)

var libraryPhoto = PhotoAttachment(tripID: reminderTrip.id, assetID: "asset/with+symbols=L0/001", capturedAt: reminderNow, importedAt: reminderNow, imageFile: "", thumbnailFile: "")
libraryPhoto.libraryLinked = true
require(PhotoImageLoader.assetID(libraryPhoto.sourceURL(in: output)) == libraryPhoto.assetID, "image reader resolves escaped library identifiers")
libraryPhoto.libraryAvailable = false
require(PhotoImageLoader.assetID(libraryPhoto.sourceURL(in: output)) == nil, "unavailable library reference cannot resolve to a stale image")
require(PhotoImageLoader.assetID(output.appendingPathComponent("legacy.jpg")) == nil, "legacy file path is never mistaken for a Photos identifier")

let base = Date(timeIntervalSince1970: 1_800_000_000)
var trip = Trip(now: base)
trip.title = "西湖漫步"; trip.features = "沿湖散步，记录一路的风景。"; trip.endedAt = base.addingTimeInterval(900); trip.status = .ended
let segment = UUID()
let points = (0..<40).map { index -> TrackPoint in
    let angle = Double(index)/39*Double.pi*1.7
    return TrackPoint(tripID: trip.id, segmentID: segment, coordinate: Coordinate(latitude: 30.24+sin(angle)*0.008, longitude: 120.14+cos(angle)*0.009), timestamp: base.addingTimeInterval(Double(index)*20), accuracy: 5)
}
trip.distance = zip(points, points.dropFirst()).reduce(0) { $0+$1.0.coordinate.distance(to: $1.1.coordinate) }
var photos: [PhotoAttachment] = []
for index in 0..<3 {
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 500, height: 400), format: format).image { context in
        [UIColor.systemGreen, .systemOrange, .systemBlue][index].setFill(); context.fill(CGRect(x: 0, y: 0, width: 500, height: 400))
        ("旅途照片 \(index+1)" as NSString).draw(at: CGPoint(x: 50, y: 150), withAttributes: [.font: UIFont.systemFont(ofSize: 38), .foregroundColor: UIColor.white])
    }
    let name = "photo\(index).jpg"; try image.jpegData(compressionQuality: 0.9)!.write(to: output.appendingPathComponent(name))
    let point = points[6+index*12]
    photos.append(PhotoAttachment(tripID: trip.id, capturedAt: point.timestamp, importedAt: base, coordinate: point.coordinate, originalCoordinate: point.coordinate, imageFile: name, thumbnailFile: name))
}
let snapshot = TripShareSnapshot(trip: trip, points: points, photos: photos, diaries: [], photoDirectory: output, endpoints: "西湖 to 湖滨", capturedAt: base.addingTimeInterval(900), alignment: .automatic)
let drawing = ShareDrawing(snapshot: snapshot, photos: photos, text: trip.features)
drawing.prepare(map: nil)
let poster = drawing.image(scale: 1.5)
require(poster.cgImage?.width == 1080 && poster.cgImage?.height == 2160, "production poster dimensions")
try poster.jpegData(compressionQuality: 0.9)!.write(to: output.appendingPathComponent("share-preview.jpg"))
require(decodedInvitations(poster).contains(ShareBranding.invitationURL), "production poster QR decodes to the configured TestFlight invitation")
let compressedFormat = UIGraphicsImageRendererFormat(); compressedFormat.scale = 1; compressedFormat.opaque = true
let compressedSize = CGSize(width: 720, height: poster.size.height/poster.size.width*720)
let reduced = UIGraphicsImageRenderer(size: compressedSize, format: compressedFormat).image { _ in
    poster.draw(in: CGRect(origin: .zero, size: compressedSize))
}
let compressedData = reduced.jpegData(compressionQuality: 0.45)!
try compressedData.write(to: output.appendingPathComponent("share-compressed-720.jpg"))
require(decodedInvitations(UIImage(data: compressedData)!).contains(ShareBranding.invitationURL), "QR survives 720px downscale and JPEG compression")
let longDrawing = ShareDrawing(snapshot: snapshot, photos: photos,
                               text: String(repeating: "这段旅程的文字会一直保留，二维码不覆盖日记。\n", count: 40))
longDrawing.prepare(map: nil)
let longPoster = longDrawing.image(scale: 1)
try longPoster.jpegData(compressionQuality: 0.9)!.write(to: output.appendingPathComponent("share-long-journal.jpg"))
require(longPoster.size.height == 1440 && longDrawing.text.count <= SharePosterLayout.bodyLimit, "long writing is bounded and poster size stays fixed")
require(decodedInvitations(longPoster).contains(ShareBranding.invitationURL), "long journal poster retains a decodable footer invitation")
// Content limits are measured with the exact drawing attributes, including newlines/emoji.
for input in [String(repeating: "沿湖散步看风景", count: 40), String(repeating: "W", count: 300),
              String(repeating: "👨‍👩‍👧‍👦🌈", count: 120), String(repeating: "一行\n", count: 30),
              String(repeating: "\n", count: 60)] {
    let bounded = SharePosterLayout.limited(input)
    require(bounded.count <= 120 && SharePosterLayout.height(bounded, title: false) <= 150, "body input fits both character and poster line limits")
    require(SharePosterLayout.limited(bounded) == bounded, "body limit is stable on repeated editor updates")
}
let boundedTitle = SharePosterLayout.limited(String(repeating: "自定义分享标题\n", count: 20), title: true)
require(boundedTitle.count <= 40 && !boundedTitle.contains("\n") && SharePosterLayout.height(boundedTitle, title: true) <= 66, "title fits two lines without breaking emoji or inserting paragraphs")
require(SharePosterLayout.bodyRect.maxY < SharePosterLayout.posterSize.height-208, "body ends before in-progress timestamp and branding footer")
// An extreme input cannot paint into the footer even if called outside the editor.
let emptyDrawing = ShareDrawing(snapshot: snapshot, photos: photos, text: "")
emptyDrawing.prepare(map: nil)
let emptyPoster = emptyDrawing.image(scale: 1)
let footerCrop = CGRect(x: 0, y: 1230, width: 720, height: 210)
let emptyFooter = UIImage(cgImage: emptyPoster.cgImage!.cropping(to: footerCrop)!).pngData()
let longFooter = UIImage(cgImage: longPoster.cgImage!.cropping(to: footerCrop)!).pngData()
require(emptyFooter == longFooter, "overlong writing cannot alter the reserved logo and QR pixels")
// Real annotation image loading: same URL stays visible, replacement wins reuse.
let marker = PhotoMapMarker(annotation: nil, reuseIdentifier: "fixture")
marker.load(output.appendingPathComponent("photo0.jpg"))
let firstImageDeadline = Date().addingTimeInterval(3)
let imageView = marker.subviews.compactMap { $0 as? UIImageView }.first!
while imageView.contentMode != .scaleAspectFill && Date() < firstImageDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
require(imageView.contentMode == .scaleAspectFill, "annotation loads real thumbnail")
let loadedImage = imageView.image
marker.load(output.appendingPathComponent("photo0.jpg"))
require(imageView.image === loadedImage, "same thumbnail refresh never clears image")
marker.prepareForReuse(); marker.load(output.appendingPathComponent("photo1.jpg")); marker.load(output.appendingPathComponent("photo2.jpg"))
let reusedDeadline = Date().addingTimeInterval(0.5)
while Date() < reusedDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
let expected = UIImage(contentsOfFile: output.appendingPathComponent("photo2.jpg").path)!
require(imageView.image?.pngData() == expected.pngData(), "reused marker rejects older asynchronous photo result")
require(marker.displayPriority == .required && marker.bounds.size == CGSize(width: 48, height: 54), "photo marker has stable size and required visibility")
let exporter = TripShareExporter()
let longPoints = (0..<20000).map { index in
    TrackPoint(tripID: trip.id, segmentID: segment, coordinate: Coordinate(latitude: 30.24 + Double(index) * 0.000001, longitude: 120.14), timestamp: base.addingTimeInterval(Double(index)), accuracy: 5)
}
let longSnapshot = TripShareSnapshot(trip: trip, points: longPoints, photos: [], diaries: [], photoDirectory: output, endpoints: "Long trip", capturedAt: base, alignment: .automatic)
let longExporter = TripShareExporter()
let longStart = Date()
longExporter.generate(snapshot: longSnapshot, photos: [], text: "", useMap: false, cacheRoot: output.appendingPathComponent("long-cancel-cache"))
require(longExporter.busy && Date().timeIntervalSince(longStart) < 0.25, "next publishes loading immediately before preparing a large route")
longExporter.cancel()
require(!longExporter.busy && longExporter.output == nil, "cancel during background route preparation cannot publish a preview")
exporter.generate(snapshot: snapshot, photos: photos, text: trip.features, useMap: false, cacheRoot: output.appendingPathComponent("poster-cache"))
let posterDeadline = Date().addingTimeInterval(15)
while exporter.busy && Date() < posterDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
require(exporter.output != nil && !exporter.busy, "production JPEG export completes")
require(PhotoFileStore.isShareImage(try Data(contentsOf: exporter.output!)), "exported image can be excluded from automatic photo reimport")
let exportedJPEG = UIImage(contentsOfFile: exporter.output!.path)!
require(decodedInvitations(exportedJPEG).contains(ShareBranding.invitationURL), "actual exported JPEG preserves the TestFlight QR")
exporter.generate(snapshot: snapshot, photos: photos, text: trip.features, useMap: false, cacheRoot: output.appendingPathComponent("cancel-cache"))
exporter.cancel()
require(!exporter.busy && exporter.output == nil, "cancel clears pending share without a false success")
let mapExporter = TripShareExporter()
mapExporter.generate(snapshot: snapshot, photos: [], text: "地图背景与加大文字", useMap: true, cacheRoot: output.appendingPathComponent("map-cache"))
let mapDeadline = Date().addingTimeInterval(30)
while mapExporter.busy && Date() < mapDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
require(!mapExporter.busy, "map-backed export completes or reports a bounded map-loading failure")
var mapExportStatus: String
if let file = mapExporter.output {
    try FileManager.default.copyItem(at: file, to: output.appendingPathComponent("share-map-preview.jpg"))
    require(mapExporter.preview != nil, "map-backed export returns an actual preview")
    mapExportStatus = "PASS: production MapKit snapshot and JPEG export completed; inspect share-map-preview.jpg"
} else {
    require(mapExporter.preview == nil && !mapExporter.message.isEmpty, "map failure exposes retry state without exporting a shape-only fallback")
    mapExportStatus = "UNAVAILABLE: " + mapExporter.message
}
let data = try JSONSerialization.data(withJSONObject: ["status":"PASS", "checks":checks, "runtime":"Mac Catalyst production poster renderer; not iPhone", "photo_layout":photoLayoutStatus, "map_export":mapExportStatus, "testflight_url":ShareBranding.invitationURL], options: [.prettyPrinted,.sortedKeys])
try data.write(to: output.appendingPathComponent("share-fixture-report.json"))
print("SHARE FIXTURES PASS: \(checks)")
