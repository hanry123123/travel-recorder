import UIKit
import MapKit
import Combine

private final class ReplayOverlayView: UIView {
    var head: CGPoint?
    var sparks: [ReplaySpark] = []
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false; backgroundColor = .clear; isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ rect: CGRect) {
        guard let head = head, let context = UIGraphicsGetCurrentContext() else { return }
        ReplaySparkPainter.draw(in: context, head: head, sparks: sparks)
    }
}

/// Map-local display link: does not publish per-frame changes into the recording UI.
final class MapReplayAnimator: NSObject {
    private final class LinkTarget: NSObject {
        weak var owner: MapReplayAnimator?
        @objc func tick(_ link: CADisplayLink) { owner?.tick(link) }
    }
    private weak var map: MKMapView?
    private weak var controller: RouteReplayController?
    private var subscription: AnyCancellable?
    private var seekSubscription: AnyCancellable?
    private var observers: [NSObjectProtocol] = []
    private let overlay = ReplayOverlayView(frame: .zero)
    private let target = LinkTarget()
    private var link: CADisplayLink?
    private var runID: UUID?
    private var projectionKey = ""
    private var mapPoints: [MKMapPoint] = []
    private var sectionIDs: [Int] = []
    private var path = RouteReplayPath(points: [])
    private var elapsed: Double { controller?.elapsed ?? 0 }
    private var lastTimestamp: CFTimeInterval?
    private var playing = false
    private var transform: ((Coordinate) -> CLLocationCoordinate2D)?
    var fitRoute: (([Coordinate]) -> Void)?

    override init() {
        super.init()
        target.owner = self
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.controller?.pause()
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.render() })
    }
    deinit {
        link?.invalidate()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func connect(map: MKMapView, controller: RouteReplayController?, projectionKey: String,
                 transform: @escaping (Coordinate) -> CLLocationCoordinate2D) {
        self.map = map; self.transform = transform
        let reproject = self.projectionKey != projectionKey
        self.projectionKey = projectionKey
        if self.controller !== controller {
            detachPlayback()
            self.controller = controller
            subscription = controller?.$state.sink { [weak self] state in self?.apply(state) }
            seekSubscription = controller?.seekRequested.sink { [weak self] in
                self?.lastTimestamp = nil
                self?.render()
            }
        } else if reproject && runID != nil {
            mapPoints = path.points.map { MKMapPoint(transform($0.coordinate)) }
            render()
        }
    }

    private func apply(_ state: RouteReplayController.State) {
        guard let controller = controller, let map = map, let transform = transform else { return }
        if state == .idle { detachPlayback(); return }
        if runID != controller.runID {
            runID = controller.runID; path = controller.path
            var section = 0
            sectionIDs = path.connectsToPrevious.map { connected in
                if !connected { section += 1 }
                return section
            }
            fitRoute?(path.points.map { $0.coordinate })
            map.layoutIfNeeded()
            mapPoints = path.points.map { MKMapPoint(transform($0.coordinate)) }
            let scale = Double(map.bounds.width) / max(1, map.visibleMapRect.width)
            let distances = mapPoints.dropFirst().enumerated().map { index, point -> Double in
                let previous = mapPoints[index]
                let dx = ReplayGeometry.shortestDelta(point.x-previous.x, worldWidth: MKMapRect.world.width)
                return hypot(dx, point.y-previous.y) * scale
            }
            controller.configure(screenDistances: distances)
            overlay.frame = map.bounds
            map.addSubview(overlay)
        }
        playing = state == .playing
        lastTimestamp = nil
        if playing {
            if link == nil {
                let displayLink = CADisplayLink(target: target, selector: #selector(LinkTarget.tick(_:)))
                displayLink.preferredFramesPerSecond = 30
                displayLink.add(to: .main, forMode: .common)
                link = displayLink
            }
        } else { link?.invalidate(); link = nil }
        render()
    }

    private func tick(_ link: CADisplayLink) {
        guard playing, map?.window != nil else { lastTimestamp = nil; return }
        if let previous = lastTimestamp {
            // Avoid a sudden leap after a stalled frame, interruption or window change.
            controller?.advance(by: link.timestamp-previous)
        }
        lastTimestamp = link.timestamp
        render()
        if let controller = controller, elapsed >= controller.timeline.duration { controller.finish() }
    }

    private func point(at time: Double) -> (CGPoint, Int)? {
        guard let map = map, let frame = controller?.timeline.frame(at: time), frame.visible,
              mapPoints.indices.contains(frame.from), mapPoints.indices.contains(frame.to) else { return nil }
        let start = mapPoints[frame.from], end = mapPoints[frame.to]
        let world = MKMapRect.world.width
        var x = start.x + ReplayGeometry.shortestDelta(end.x-start.x, worldWidth: world)*frame.fraction
        x = x.truncatingRemainder(dividingBy: world); if x < 0 { x += world }
        let position = MKMapPoint(x: x, y: start.y+(end.y-start.y)*frame.fraction)
        return (map.convert(position.coordinate, toPointTo: map), sectionIDs[frame.to])
    }

    func render() {
        guard runID != nil, let map = map, let controller = controller else { return }
        overlay.frame = map.bounds
        overlay.alpha = playing && !controller.isScrubbing ? CGFloat(controller.timeline.frame(at: elapsed)?.opacity ?? 0) : 1
        let current = point(at: elapsed)
        overlay.head = current?.0
        overlay.sparks = ReplaySparks.frame(at: elapsed, emissionEnd: controller.timeline.duration-1.1,
                                           reducedMotion: UIAccessibility.isReduceMotionEnabled) { time in
            self.point(at: time)
        }
        overlay.setNeedsDisplay()
    }

    private func detachPlayback() {
        link?.invalidate(); link = nil; playing = false; lastTimestamp = nil
        runID = nil; mapPoints = []; sectionIDs = []; path = RouteReplayPath(points: [])
        overlay.head = nil; overlay.sparks = []
        overlay.removeFromSuperview()
    }
    func dismantle() {
        subscription = nil; seekSubscription = nil
        detachPlayback()
        controller = nil; map = nil; transform = nil; fitRoute = nil
    }
}
