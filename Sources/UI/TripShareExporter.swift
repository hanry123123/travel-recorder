import UIKit
import MapKit
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
    func cancel(message: String = L("已取消生成")) {
        job?.cancel(); job = nil; snapshotter?.cancel(); snapshotter = nil
        if busy { busy = false; self.message = message }
    }
    func generate(snapshot: TripShareSnapshot, photos: [PhotoAttachment], text: String, useMap: Bool = false, cacheRoot: URL? = nil) {
        invalidate()
        let job = ShareJob(); self.job = job
        busy = true; progress = 0; message = L("正在准备路线…")
        // Route sorting/projection can be substantial for long trips. Publish busy
        // first and return to the run loop before doing that work.
        queue.async { [weak self] in
            guard let self = self, !job.cancelled else { return }
            let drawing = ShareDrawing(snapshot: snapshot, photos: photos, text: text)
            DispatchQueue.main.async {
                guard self.job === job, !job.cancelled else { return }
                self.prepareExport(drawing, job: job, useMap: useMap, cacheRoot: cacheRoot)
            }
        }
    }
    private func prepareExport(_ drawing: ShareDrawing, job: ShareJob, useMap: Bool, cacheRoot: URL?) {
        func render(_ map: MKMapSnapshotter.Snapshot?, error: Error? = nil) {
            guard job.claimSnapshot() else { return }
            self.queue.async { [weak self] in
                guard let self = self else { return }
                var folder: URL?
                do {
                    if job.cancelled { return }
                    if useMap && map == nil { throw error ?? TripError.storage(L("地图暂时无法加载，请联网后重试")) }
                    drawing.prepare(map: map)
                    if drawing.missingPhotos > 0 { throw TripError.storage(L("有选中的照片暂时无法读取，请返回检查照片后重试")) }
                    if ShareBranding.qrImage == nil {
                        throw TripError.storage(AppLanguage.english ? "Could not generate the invitation code" : "无法生成邀请二维码")
                    }
                    let root = try cacheRoot ?? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("TripShares", isDirectory: true)
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                    for old in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey])) ?? [] {
                        if let created = try? old.resourceValues(forKeys: [.creationDateKey]).creationDate, Date().timeIntervalSince(created) > 86400 { try? FileManager.default.removeItem(at: old) }
                    }
                    let dir = root.appendingPathComponent(UUID().uuidString, isDirectory: true); folder = dir
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    let url = dir.appendingPathComponent("旅程图片.jpg")
                    let image = drawing.image(scale: SharePosterLayout.exportScale)
                    guard let cg = image.cgImage else { throw TripError.storage(L("图片生成失败")) }
                    let bytes = NSMutableData()
                    guard let destination = CGImageDestinationCreateWithData(bytes, "public.jpeg" as CFString, 1, nil) else { throw TripError.storage(L("图片编码失败")) }
                    CGImageDestinationAddImage(destination, cg, [kCGImageDestinationLossyCompressionQuality: 0.92, kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFSoftware: "TravelRecorder Share"]] as CFDictionary)
                    guard CGImageDestinationFinalize(destination) else { throw TripError.storage(L("图片编码失败")) }
                    try (bytes as Data).write(to: url, options: .atomic)
                    if job.cancelled { try? FileManager.default.removeItem(at: dir); return }
                    let poster = drawing.image(scale: 0.5)
                    DispatchQueue.main.async {
                        guard self.job === job, !job.cancelled else { return }
                        self.busy = false; self.progress = 1; self.output = url; self.preview = poster
                        self.message = L("已生成路线作品，请预览后分享。")
                    }
                } catch {
                    if let folder = folder { try? FileManager.default.removeItem(at: folder) }
                    DispatchQueue.main.async {
                        guard self.job === job, !job.cancelled else { return }
                        self.busy = false; self.message = (AppLanguage.english ? "Generation failed: \(error.localizedDescription). Please retry." : "生成失败：\(error.localizedDescription)，可以重试。")
                    }
                }
            }
        }
        guard useMap else { render(nil); return }
        message = L("正在加载地图…")
        let options = MKMapSnapshotter.Options()
        options.size = CGSize(width: 672, height: 620); options.scale = 1
        options.mapRect = drawing.mapRect; options.mapType = .standard
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)
        let snapshotter = MKMapSnapshotter(options: options); self.snapshotter = snapshotter
        snapshotter.start(with: queue) { map, error in render(map, error: error) }
        DispatchQueue.main.asyncAfter(deadline: .now()+15) { [weak self, weak snapshotter] in
            guard self?.job === job, !job.cancelled else { return }
            render(nil, error: TripError.storage(L("地图加载超时，请联网后重试"))); snapshotter?.cancel()
        }
    }

}

/// Fixed-size still-image renderer. Text stays above the reserved branding area.
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
    init(snapshot: TripShareSnapshot, photos: [PhotoAttachment], text: String) {
        self.snapshot = snapshot; self.photos = photos; self.text = SharePosterLayout.limited(text)
        path = RouteReplayPath(points: snapshot.points)
        coordinates = path.points.map {
            let c = MapCoordinates.display($0.coordinate, mode: snapshot.alignment)
            return CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude)
        }
        var rect = MKMapRect.null
        let framingCoordinates = coordinates.isEmpty ? photos.compactMap { $0.mapCoordinate }.map { value -> CLLocationCoordinate2D in
            let coordinate = MapCoordinates.display(value, mode: snapshot.alignment)
            return CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
        } : coordinates
        let anchor = framingCoordinates.first.map { MKMapPoint($0).x } ?? 0
        for c in framingCoordinates {
            let p = MKMapPoint(c)
            let x = anchor+ReplayGeometry.shortestDelta(p.x-anchor, worldWidth: MKMapRect.world.width)
            rect = rect.union(MKMapRect(x: x, y: p.y, width: 1, height: 1))
        }
        if rect.isNull { rect = MKMapRect.world }
        let width = max(2000, rect.width*1.3, rect.height*1.3*672/620)
        mapRect = MKMapRect(x: rect.midX-width/2, y: rect.midY-width*620/672/2, width: width, height: width*620/672)
    }
    func prepare(map snapshot: MKMapSnapshotter.Snapshot?) {
        map = snapshot?.image
        points = coordinates.map { c in
            if let snapshot = snapshot { return snapshot.point(for: c) }
            let p = MKMapPoint(c)
            let x = mapRect.midX+ReplayGeometry.shortestDelta(p.x-mapRect.midX, worldWidth: MKMapRect.world.width)
            return CGPoint(x: (x-mapRect.minX)/mapRect.width*672, y: (p.y-mapRect.minY)/mapRect.height*620)
        }
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
            let url = photo.sourceURL(in: self.snapshot.photoDirectory, thumbnail: false)
            if let image = PhotoImageLoader.shareImage(url) { images[photo.id] = image }
        }
    }
    func image(scale: CGFloat) -> UIImage {
        let size = SharePosterLayout.posterSize
        let format = UIGraphicsImageRendererFormat(); format.scale = scale; format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let cg = renderer.cgContext
            UIColor(red: 0.97, green: 0.97, blue: 0.94, alpha: 1).setFill(); cg.fill(CGRect(origin: .zero, size: size))
            SharePosterLayout.draw(snapshot.endpoints, title: true, in: cg)
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
            cg.restoreGState()
            let selected = Array(photos.prefix(3))
            for (index, photo) in selected.enumerated() {
                let width = (672-CGFloat(max(0, selected.count-1))*8)/CGFloat(max(1, selected.count))
                if let image = images[photo.id] { drawPhoto(image, rect: CGRect(x: 24+CGFloat(index)*(width+8), y: 810, width: width, height: 220)) }
            }
            SharePosterLayout.draw(text, title: false, in: cg)
            if snapshot.trip.status != .ended {
                drawText(L("本次内容截至 ") + snapshot.capturedAt.formattedShareTime,
                         rect: CGRect(x: 24, y: size.height-208, width: 672, height: 24), size: 15)
            }
            ShareBranding.draw(in: CGRect(x: 24, y: size.height-24-ShareBranding.footerHeight,
                                          width: 672, height: ShareBranding.footerHeight), context: cg)
        }
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
