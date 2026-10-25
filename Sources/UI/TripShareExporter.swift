import UIKit
import MapKit
import AVFoundation
import ImageIO
import Combine

private final class ShareJob {
    private let lock = NSLock()
    private var stopped = false
    private var resolved = false
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
    func claimSnapshot() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if resolved || stopped { return false }; resolved = true; return true
    }
}

final class TripShareExporter: ObservableObject {
    @Published private(set) var busy = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var message = ""
    @Published private(set) var output: URL?
    @Published private(set) var preview: UIImage?
    private let queue = DispatchQueue(label: "travel.share.render", qos: .utility)
    private var job: ShareJob?
    private var snapshotter: MKMapSnapshotter?
    deinit { job?.cancel(); snapshotter?.cancel() }
    func invalidate() { cancel(); output = nil; preview = nil; message = "" }
    func cancel(message: String = "已取消生成") {
        job?.cancel(); job = nil; snapshotter?.cancel(); snapshotter = nil
        if busy { busy = false; self.message = message }
    }
    func generate(snapshot: TripShareSnapshot, photos: [PhotoAttachment], text: String, video: Bool, useMap: Bool = false, cacheRoot: URL? = nil) {
        invalidate()
        let job = ShareJob(); self.job = job
        busy = true; progress = 0; message = "正在准备路线…"
        let drawing = ShareDrawing(snapshot: snapshot, photos: photos, text: text)
        func render(_ map: MKMapSnapshotter.Snapshot?) {
            guard job.claimSnapshot() else { return }
            self.queue.async { [weak self] in
                guard let self = self else { return }
                var folder: URL?
                do {
                    if job.cancelled { return }
                    drawing.prepare(map: map)
                    if drawing.missingPhotos > 0 { throw TripError.storage("有选中的照片暂时无法读取，请返回检查照片后重试") }
                    let root = try cacheRoot ?? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("TripShares", isDirectory: true)
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                    for old in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey])) ?? [] {
                        if let created = try? old.resourceValues(forKeys: [.creationDateKey]).creationDate, Date().timeIntervalSince(created) > 86400 { try? FileManager.default.removeItem(at: old) }
                    }
                    let dir = root.appendingPathComponent(UUID().uuidString, isDirectory: true); folder = dir
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    let url = dir.appendingPathComponent(video ? "旅途重现.mp4" : "旅程图片.jpg")
                    if video {
                        try self.writeVideo(drawing, to: url, job: job)
                    } else {
                        let image = drawing.image(videoTime: nil, scale: 1.5)
                        guard let cg = image.cgImage else { throw TripError.storage("图片生成失败") }
                        let bytes = NSMutableData()
                        guard let destination = CGImageDestinationCreateWithData(bytes, "public.jpeg" as CFString, 1, nil) else { throw TripError.storage("图片编码失败") }
                        CGImageDestinationAddImage(destination, cg, [kCGImageDestinationLossyCompressionQuality: 0.92, kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFSoftware: "TravelRecorder Share"]] as CFDictionary)
                        guard CGImageDestinationFinalize(destination) else { throw TripError.storage("图片编码失败") }
                        try (bytes as Data).write(to: url, options: .atomic)
                    }
                    if job.cancelled { try? FileManager.default.removeItem(at: dir); return }
                    let poster = video ? nil : drawing.image(videoTime: nil, scale: 0.5)
                    DispatchQueue.main.async {
                        guard self.job === job, !job.cancelled else { return }
                        self.busy = false; self.progress = 1; self.output = url; self.preview = poster
                        self.message = "已生成路线作品，请预览后分享。"
                    }
                } catch {
                    if let folder = folder { try? FileManager.default.removeItem(at: folder) }
                    DispatchQueue.main.async {
                        guard self.job === job, !job.cancelled else { return }
                        self.busy = false; self.message = "生成失败：\(error.localizedDescription)，可以重试。"
                    }
                }
            }
        }
        guard useMap, !drawing.path.points.isEmpty else { render(nil); return }
        let options = MKMapSnapshotter.Options()
        options.size = CGSize(width: 672, height: 620); options.scale = 1
        options.mapRect = drawing.mapRect; options.mapType = .standard
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)
        let snapshotter = MKMapSnapshotter(options: options); self.snapshotter = snapshotter
        snapshotter.start(with: queue) { map, _ in render(map) }
        DispatchQueue.main.asyncAfter(deadline: .now()+15) { [weak self, weak snapshotter] in
            guard self?.job === job, !job.cancelled else { return }
            render(nil); snapshotter?.cancel()
        }
    }
    private func writeVideo(_ drawing: ShareDrawing, to url: URL, job: ShareJob) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 720, AVVideoHeightKey: 1280, AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 4_000_000]])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 720, kCVPixelBufferHeightKey as String: 1280, kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true])
        guard writer.canAdd(input) else { throw TripError.storage("设备不支持视频编码") }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? TripError.storage("无法开始编码") }
        writer.startSession(atSourceTime: .zero)
        let frames = Int(ceil(drawing.videoDuration*30))
        for index in 0..<frames {
            if job.cancelled { writer.cancelWriting(); throw TripError.storage("已取消") }
            while !input.isReadyForMoreMediaData {
                if job.cancelled { writer.cancelWriting(); throw TripError.storage("已取消") }
                if writer.status != .writing { throw writer.error ?? TripError.storage("编码中断") }
                Thread.sleep(forTimeInterval: 0.005)
            }
            try autoreleasepool {
                var buffer: CVPixelBuffer?
                guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let pixel = buffer else { throw TripError.storage("视频内存不足") }
                CVPixelBufferLockBaseAddress(pixel, [])
                defer { CVPixelBufferUnlockBaseAddress(pixel, []) }
                guard let context = CGContext(data: CVPixelBufferGetBaseAddress(pixel), width: 720, height: 1280, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixel), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue), let cg = drawing.image(videoTime: Double(index)/30, scale: 1).cgImage else { throw TripError.storage("视频帧绘制失败") }
                context.draw(cg, in: CGRect(x: 0, y: 0, width: 720, height: 1280))
                guard adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(index), timescale: 30)) else { throw writer.error ?? TripError.storage("视频写入失败") }
            }
            if index % 15 == 0 {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, self.job === job, !job.cancelled else { return }
                    self.progress = Double(index)/Double(frames); self.message = "正在生成视频 \(Int(self.progress*100))%"
                }
            }
        }
        input.markAsFinished()
        let completion = DispatchSemaphore(value: 0)
        writer.finishWriting { completion.signal() }
        completion.wait()
        guard writer.status == .completed else { throw writer.error ?? TripError.storage("视频未能保存") }
    }
}

/// Shared CoreGraphics rendering for the poster and every video frame.
final class ShareDrawing {
    let snapshot: TripShareSnapshot
    let photos: [PhotoAttachment]
    let text: String
    let path: RouteReplayPath
    let mapRect: MKMapRect
    private let coordinates: [CLLocationCoordinate2D]
    private var points: [CGPoint] = []
    private var images: [UUID: UIImage] = [:]
    private var photoPoints: [UUID: CGPoint] = [:]
    var missingPhotos: Int { photos.count-images.count }
    private var map: UIImage?
    private(set) var timeline: RouteReplayTimeline
    private var events: [(Double, PhotoAttachment)] = []
    var videoDuration: Double { min(60, max(20, timeline.duration+3, Double(photos.count)*2+3)) }
    init(snapshot: TripShareSnapshot, photos: [PhotoAttachment], text: String) {
        self.snapshot = snapshot; self.photos = photos; self.text = text
        path = RouteReplayPath(points: snapshot.points)
        coordinates = path.points.map {
            let c = MapCoordinates.display($0.coordinate, mode: snapshot.alignment)
            return CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude)
        }
        var rect = MKMapRect.null
        let anchor = coordinates.first.map { MKMapPoint($0).x } ?? 0
        for c in coordinates {
            let p = MKMapPoint(c)
            let x = anchor+ReplayGeometry.shortestDelta(p.x-anchor, worldWidth: MKMapRect.world.width)
            rect = rect.union(MKMapRect(x: x, y: p.y, width: 1, height: 1))
        }
        if rect.isNull { rect = MKMapRect(x: MKMapRect.world.midX, y: MKMapRect.world.midY, width: 2000, height: 2000) }
        let width = max(2000, rect.width*1.3, rect.height*1.3*672/620)
        mapRect = MKMapRect(x: rect.midX-width/2, y: rect.midY-width*620/672/2, width: width, height: width*620/672)
        timeline = RouteReplayTimeline(path: path, screenDistances: Array(repeating: 0, count: max(0, path.points.count-1)))
    }
    func prepare(map snapshot: MKMapSnapshotter.Snapshot?) {
        map = snapshot?.image
        points = coordinates.map { c in
            if let snapshot = snapshot { return snapshot.point(for: c) }
            let p = MKMapPoint(c)
            let x = mapRect.midX+ReplayGeometry.shortestDelta(p.x-mapRect.midX, worldWidth: MKMapRect.world.width)
            return CGPoint(x: (x-mapRect.minX)/mapRect.width*672, y: (p.y-mapRect.minY)/mapRect.height*620)
        }
        let distances = points.dropFirst().enumerated().map { index, point in Double(hypot(point.x-points[index].x, point.y-points[index].y)) }
        timeline = RouteReplayTimeline(path: path, screenDistances: distances)
        for photo in photos {
            if let raw = photo.mapCoordinate {
                let coordinate = MapCoordinates.display(raw, mode: self.snapshot.alignment)
                let c = CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
                if let snapshot = snapshot { photoPoints[photo.id] = snapshot.point(for: c) }
                else {
                    let p = MKMapPoint(c)
                    let x = mapRect.midX+ReplayGeometry.shortestDelta(p.x-mapRect.midX, worldWidth: MKMapRect.world.width)
                    photoPoints[photo.id] = CGPoint(x: (x-mapRect.minX)/mapRect.width*672, y: (p.y-mapRect.minY)/mapRect.height*620)
                }
            }
            let url = self.snapshot.photoDirectory.appendingPathComponent(photo.imageFile)
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil), let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1024] as CFDictionary) {
                images[photo.id] = UIImage(cgImage: cg)
            }
        }
        let sorted = photos.sorted {
            let a = ShareSelection.frame(for: $0, in: path) != nil, b = ShareSelection.frame(for: $1, in: path) != nil
            return a == b ? $0.capturedAt < $1.capturedAt : a
        }
        var next: Double = 1
        for (index, photo) in sorted.enumerated() {
            let target = ShareSelection.frame(for: photo, in: path).map { 1+timeline.time(for: $0)/max(1, timeline.duration)*(videoDuration-3) } ?? (videoDuration-2*Double(sorted.count-index))
            let latest = videoDuration-2*Double(sorted.count-index)
            let start = min(latest, max(next, target))
            events.append((max(1, start), photo)); next = max(1, start)+2
        }
    }
    private func location(at time: Double) -> (CGPoint, Int)? {
        guard let frame = timeline.frame(at: time), frame.visible, points.indices.contains(frame.from), points.indices.contains(frame.to) else { return nil }
        let a = points[frame.from], b = points[frame.to]
        let p = CGPoint(x: a.x+(b.x-a.x)*CGFloat(frame.fraction), y: a.y+(b.y-a.y)*CGFloat(frame.fraction))
        let section = path.connectsToPrevious.prefix(frame.to+1).filter { !$0 }.count
        return (p, section)
    }
    func image(videoTime: Double?, scale: CGFloat) -> UIImage {
        // Additional writing expands the poster; the video reserves an explicit excerpt.
        let posterExtra = videoTime == nil ? min(9000, max(0, ceil(textHeight(text, width: 672))-150)) : 0
        let size = CGSize(width: 720, height: 1280+posterExtra)
        let format = UIGraphicsImageRendererFormat(); format.scale = scale; format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let cg = renderer.cgContext
            UIColor(red: 0.97, green: 0.97, blue: 0.94, alpha: 1).setFill(); cg.fill(CGRect(origin: .zero, size: size))
            drawText(snapshot.endpoints, rect: CGRect(x: 24, y: 25, width: 672, height: 66), size: 26, bold: true)
            drawText(snapshot.trip.startedAt.formattedShareTime + " · " + TravelFormat.distance(snapshot.trip.distance) + " · " + TravelFormat.duration(snapshot.trip.duration(at: snapshot.capturedAt)), rect: CGRect(x: 24, y: 99, width: 672, height: 45), size: 17)
            let mapFrame = CGRect(x: 24, y: 155, width: 672, height: 620)
            cg.saveGState(); cg.translateBy(x: mapFrame.minX, y: mapFrame.minY)
            cg.clip(to: CGRect(origin: .zero, size: mapFrame.size))
            if let map = map { map.draw(in: CGRect(origin: .zero, size: mapFrame.size)) }
            else { UIColor(white: 0.92, alpha: 1).setFill(); cg.fill(CGRect(origin: .zero, size: mapFrame.size)) }
            cg.setStrokeColor(UIColor.systemBlue.cgColor); cg.setLineWidth(4); cg.setLineCap(.round); cg.setLineJoin(.round)
            for i in points.indices {
                if i == 0 || !path.connectsToPrevious[i] { cg.move(to: points[i]) }
                else { cg.addLine(to: points[i]) }
            }
            cg.strokePath()
            for (index, p) in points.enumerated() where index == 0 || index == points.count-1 {
                cg.setFillColor(index == 0 ? UIColor.systemGreen.cgColor : UIColor.systemBlue.cgColor)
                cg.fillEllipse(in: CGRect(x: p.x-6, y: p.y-6, width: 12, height: 12))
            }
            for photo in photos {
                if let point = photoPoints[photo.id], let image = images[photo.id] {
                    let rect = CGRect(x: point.x-17, y: point.y-40, width: 34, height: 34)
                    UIColor.white.setFill(); cg.fill(rect.insetBy(dx: -2, dy: -2)); drawPhoto(image, rect: rect)
                }
            }
            if let videoTime = videoTime {
                let t = min(timeline.duration, max(0, (videoTime-1)/max(1, videoDuration-3)*timeline.duration))
                if let head = location(at: t)?.0 {
                    let sparks = ReplaySparks.frame(at: max(0, videoTime-1), emissionEnd: videoDuration-3) { clock in
                        self.location(at: min(self.timeline.duration, clock/max(1, self.videoDuration-3)*self.timeline.duration))
                    }
                    ReplaySparkPainter.draw(in: cg, head: head, sparks: sparks)
                }
            }
            cg.restoreGState()
            if let time = videoTime {
                let routeTime = min(timeline.duration, max(0, (time-1)/max(1, videoDuration-3)*timeline.duration))
                let date = timeline.recordedTime(at: routeTime, path: path)
                drawText(date.map { "当时 " + $0.formattedShareTime } ?? "暂无路线点", rect: CGRect(x: 24, y: 790, width: 672, height: 35), size: 18)
                if let event = events.last(where: { time >= $0.0 }), let image = images[event.1.id] {
                    drawPhoto(image, rect: CGRect(x: 24, y: 840, width: 672, height: 260), fill: false)
                    drawText("拍摄于 " + event.1.capturedAt.formattedShareTime, rect: CGRect(x: 24, y: 1110, width: 672, height: 30), size: 15)
                }
                drawText(text, rect: CGRect(x: 24, y: 1150, width: 672, height: 70), size: 19)
            } else {
                let selected = Array(photos.prefix(3))
                for (index, photo) in selected.enumerated() {
                    let width = (672-CGFloat(max(0, selected.count-1))*8)/CGFloat(max(1, selected.count))
                    if let image = images[photo.id] { drawPhoto(image, rect: CGRect(x: 24+CGFloat(index)*(width+8), y: 810, width: width, height: 220)) }
                }
                drawText(text, rect: CGRect(x: 24, y: 1060, width: 672, height: 150+posterExtra), size: 20)
            }
            drawText(snapshot.trip.status == .ended ? "旅迹 · 把走过的路留成回忆" : "旅迹 · 截至 " + snapshot.capturedAt.formattedShareTime, rect: CGRect(x: 24, y: size.height-40, width: 672, height: 30), size: 15)
        }
    }
    private func textHeight(_ text: String, width: CGFloat) -> CGFloat {
        (text as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: UIFont.systemFont(ofSize: 20)], context: nil).height
    }
    private func drawText(_ text: String, rect: CGRect, size: CGFloat, bold: Bool = false) {
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size), .foregroundColor: UIColor.darkText, .paragraphStyle: paragraph], context: nil)
    }
    private func drawPhoto(_ image: UIImage, rect: CGRect, fill: Bool = true) {
        guard let context = UIGraphicsGetCurrentContext(), image.size.width > 0, image.size.height > 0 else { return }
        context.saveGState(); context.clip(to: rect)
        let scale = fill ? max(rect.width/image.size.width, rect.height/image.size.height) : min(rect.width/image.size.width, rect.height/image.size.height)
        let size = CGSize(width: image.size.width*scale, height: image.size.height*scale)
        image.draw(in: CGRect(x: rect.midX-size.width/2, y: rect.midY-size.height/2, width: size.width, height: size.height))
        context.restoreGState()
    }
}
