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
    private var pathSubscription: AnyCancellable?
    private var cameraEngaged = false
    private let camera = SmoothMapCamera()
    private var particleClock: Double = 0
    private var history: [(time: Double, point: MKMapPoint, section: Int)] = []
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
                self?.history = []; self?.particleClock = 0
                self?.rememberHead()
                self?.followIfNeeded(force: true)
                self?.render()
            }
            pathSubscription = controller?.pathChanged.sink { [weak self] in self?.refreshPath(); self?.render() }
        } else if reproject && runID != nil {
            history = []; particleClock = 0
            mapPoints = path.points.map { MKMapPoint(transform($0.coordinate)) }
            render()
        }
    }

    private func apply(_ state: RouteReplayController.State) {
        guard let controller = controller, let map = map, transform != nil else { return }
        if state == .idle { detachPlayback(); return }
        if runID != controller.runID {
            runID = controller.runID; path = controller.path
            particleClock = 0; history = []; cameraEngaged = false; camera.stop()
            refreshPath()
            map.layoutIfNeeded()
            overlay.frame = map.bounds
            map.addSubview(overlay)
        }
        playing = state == .playing || state == .live
        lastTimestamp = nil
        if playing {
            if link == nil {
                let displayLink = CADisplayLink(target: target, selector: #selector(LinkTarget.tick(_:)))
                displayLink.preferredFramesPerSecond = 60
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
            let delta = min(0.1, max(0, link.timestamp-previous))
            particleClock += delta
            controller?.advance(by: delta)
        }
        lastTimestamp = link.timestamp
        rememberHead()
        followIfNeeded()
        render()
    }

    private func refreshPath() {
        guard let controller = controller, let transform = transform else { return }
        path = controller.path
        var section = 0
        sectionIDs = path.connectsToPrevious.map { connected in
            if !connected { section += 1 }; return section
        }
        mapPoints = path.points.map { MKMapPoint(transform($0.coordinate)) }
    }
    func stopCamera() { camera.stop(); cameraEngaged = false }
    func followLocation(_ coordinate: CLLocationCoordinate2D, on map: MKMapView) {
        camera.follow(coordinate, on: map)
    }
    private func followIfNeeded(force: Bool = false) {
        guard let map = map, let controller = controller, controller.followsHead else { stopCamera(); return }
        guard let position = worldPoint(at: elapsed)?.0 else { camera.stop(); return }
        if !cameraEngaged {
            if mapPoints.allSatisfy({ map.bounds.insetBy(dx: 20, dy: 20).contains(map.convert($0.coordinate, toPointTo: map)) }) { return }
            let safe = map.bounds.insetBy(dx: map.bounds.width*0.22, dy: map.bounds.height*0.22)
            guard !safe.contains(map.convert(position.coordinate, toPointTo: map)) else { return }
            cameraEngaged = true
        }
        camera.follow(position.coordinate, on: map)
    }

    private func worldPoint(at time: Double) -> (MKMapPoint, Int)? {
        guard let frame = controller?.timeline.frame(at: time), frame.visible,
              mapPoints.indices.contains(frame.from), mapPoints.indices.contains(frame.to) else { return nil }
        let start = mapPoints[frame.from], end = mapPoints[frame.to]
        let world = MKMapRect.world.width
        var x = start.x + ReplayGeometry.shortestDelta(end.x-start.x, worldWidth: world)*frame.fraction
        x = x.truncatingRemainder(dividingBy: world); if x < 0 { x += world }
        let position = MKMapPoint(x: x, y: start.y+(end.y-start.y)*frame.fraction)
        return (position, sectionIDs[frame.to])
    }

    private func point(at time: Double) -> (CGPoint, Int)? {
        guard let map = map, let world = worldPoint(at: time) else { return nil }
        return (map.convert(world.0.coordinate, toPointTo: map), world.1)
    }
    private func rememberHead() {
        if let head = worldPoint(at: elapsed) { history.append((particleClock, head.0, head.1)) }
        history.removeAll { $0.time < particleClock-1.2 }
    }
    private func historicalPoint(at time: Double) -> (CGPoint, Int)? {
        guard let map = map, let current = worldPoint(at: elapsed),
              let sample = history.last(where: { $0.time <= time }), sample.section == current.1 else { return nil }
        return (map.convert(sample.point.coordinate, toPointTo: map), sample.section)
    }

    func render() {
        guard runID != nil, let map = map, let controller = controller else { return }
        overlay.frame = map.bounds
        overlay.alpha = playing && !controller.isScrubbing ? CGFloat(controller.timeline.frame(at: elapsed)?.opacity ?? 0) : 1
        let current = point(at: elapsed)
        overlay.head = current?.0
        overlay.sparks = ReplaySparks.frame(at: particleClock,
                                           emissionEnd: controller.state == .finished ? particleClock-1.1 : .infinity,
                                           reducedMotion: UIAccessibility.isReduceMotionEnabled) { time in
            self.historicalPoint(at: time)
        }
        overlay.setNeedsDisplay()
    }

    private func detachPlayback() {
        stopCamera()
        link?.invalidate(); link = nil; playing = false; lastTimestamp = nil
        runID = nil; mapPoints = []; sectionIDs = []; path = RouteReplayPath(points: [])
        particleClock = 0; history = []
        overlay.head = nil; overlay.sparks = []
        overlay.removeFromSuperview()
    }
    func dismantle() {
        subscription = nil; seekSubscription = nil; pathSubscription = nil
        detachPlayback()
        controller = nil; map = nil; transform = nil; fitRoute = nil
    }
}
