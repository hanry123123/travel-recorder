import Foundation
import UIKit
import AVFoundation
import CoreGraphics
import MapKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var checks = 0
func require(_ condition: Bool, _ name: String) {
    checks += 1
    if !condition { fputs("FAIL: \(name)\n", stderr); exit(1) }
    print("PASS: \(name)")
}
// Force a slow real SQLite open. UI queue must keep servicing taps/timers.
let startupBegin = Date()
var openedOnMain = true
let startup = TravelStore(storageRoot: output.appendingPathComponent("startup"), openRepository: { url in
    openedOnMain = Thread.isMainThread
    Thread.sleep(forTimeInterval: 0.4)
    return try CoreDataRepository(url: url)
})
require(Date().timeIntervalSince(startupBegin) < 0.25 && !startup.ready, "cold store returns before slow SQLite open")
var heartbeat = false
DispatchQueue.main.async { heartbeat = true }
let heartbeatDeadline = Date().addingTimeInterval(0.2)
while !heartbeat && Date() < heartbeatDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
require(heartbeat && !startup.ready, "UI queue responds while store opens")
let startupDeadline = Date().addingTimeInterval(5)
while !startup.ready && startup.errorMessage == nil && Date() < startupDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
require(startup.ready && !openedOnMain, "asynchronous startup publishes ready after real SQLite load")
// Actual MKMapView camera uses intermediate positions, then converges; cancellation holds.
let cameraMap = MKMapView(frame: CGRect(x: 0, y: 0, width: 400, height: 500))
cameraMap.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 30, longitude: 120), span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)), animated: false)
let smoothCamera = SmoothMapCamera()
let cameraStart = cameraMap.centerCoordinate.longitude
smoothCamera.follow(CLLocationCoordinate2D(latitude: 30, longitude: 120.02), on: cameraMap)
require(abs(cameraMap.centerCoordinate.longitude-cameraStart) < 0.000001, "camera target does not teleport")
smoothCamera.step(1.0/60)
require(cameraMap.centerCoordinate.longitude > cameraStart && cameraMap.centerCoordinate.longitude < 120.019, "camera first frame is intermediate")
for _ in 0..<360 { smoothCamera.step(1.0/60) }
require(abs(cameraMap.centerCoordinate.longitude-120.02) < 0.00001, "camera converges continuously")
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
let poster = drawing.image(videoTime: nil, scale: 1.5)
require(poster.cgImage?.width == 1080 && poster.cgImage?.height == 1920, "production poster dimensions")
try poster.jpegData(compressionQuality: 0.9)!.write(to: output.appendingPathComponent("share-preview.jpg"))
let frame = drawing.image(videoTime: drawing.videoDuration*0.5, scale: 1)
try frame.pngData()!.write(to: output.appendingPathComponent("video-frame.png"))
require(frame.cgImage?.width == 720 && frame.cgImage?.height == 1280, "production video frame dimensions")
require(drawing.videoDuration >= 20 && drawing.videoDuration <= 60, "video duration is bounded")
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
exporter.generate(snapshot: snapshot, photos: photos, text: trip.features, video: true, useMap: false, cacheRoot: output.appendingPathComponent("cache"))
let deadline = Date().addingTimeInterval(180)
while exporter.busy && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
require(!exporter.busy && exporter.output != nil, "production video encoder completes")
let movie = exporter.output!
let asset = AVURLAsset(url: movie)
let track = asset.tracks(withMediaType: .video).first
require(track?.naturalSize == CGSize(width: 720, height: 1280), "encoded movie size")
require(abs(CMTimeGetSeconds(asset.duration)-drawing.videoDuration) < 0.1, "encoded movie duration matches timeline")
require(abs((track?.nominalFrameRate ?? 0)-30) < 0.1, "encoded movie is 30fps")
require(asset.tracks(withMediaType: .audio).isEmpty, "movie has no unsolicited audio")
let generator = AVAssetImageGenerator(asset: asset); generator.appliesPreferredTrackTransform = true
let decoded = try generator.copyCGImage(at: CMTime(seconds: drawing.videoDuration*0.5, preferredTimescale: 600), actualTime: nil)
try UIImage(cgImage: decoded).pngData()!.write(to: output.appendingPathComponent("decoded-video-frame.png"))
require(decoded.width == 720 && decoded.height == 1280, "encoded frame decodes")
try FileManager.default.copyItem(at: movie, to: output.appendingPathComponent("share-preview.mp4"))
exporter.generate(snapshot: snapshot, photos: photos, text: trip.features, video: false, useMap: false, cacheRoot: output.appendingPathComponent("poster-cache"))
let posterDeadline = Date().addingTimeInterval(15)
while exporter.busy && Date() < posterDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
require(exporter.output != nil && !exporter.busy, "production JPEG export completes")
require(PhotoFileStore.isShareImage(try Data(contentsOf: exporter.output!)), "exported image can be excluded from automatic photo reimport")
exporter.generate(snapshot: snapshot, photos: photos, text: trip.features, video: true, useMap: false, cacheRoot: output.appendingPathComponent("cancel-cache"))
exporter.cancel()
require(!exporter.busy && exporter.output == nil, "cancel clears pending share without a false success")
let data = try JSONSerialization.data(withJSONObject: ["status":"PASS", "checks":checks, "runtime":"Mac Catalyst production renderer and encoder; not iPhone", "duration":CMTimeGetSeconds(asset.duration)], options: [.prettyPrinted,.sortedKeys])
try data.write(to: output.appendingPathComponent("share-fixture-report.json"))
print("SHARE FIXTURES PASS: \(checks)")
