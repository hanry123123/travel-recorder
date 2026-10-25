import UIKit
import MapKit

/// One continuous camera motion; a new GPS target does not restart an animation.
final class SmoothMapCamera: NSObject {
    private final class Target: NSObject {
        weak var owner: SmoothMapCamera?
        @objc func tick(_ link: CADisplayLink) { owner?.tick(link) }
    }
    private weak var map: MKMapView?
    private var destination: MKMapPoint?
    private let target = Target()
    private var link: CADisplayLink?
    private var previous: CFTimeInterval?
    override init() { super.init(); target.owner = self }
    deinit { link?.invalidate() }
    func follow(_ coordinate: CLLocationCoordinate2D, on map: MKMapView) {
        self.map = map; destination = MKMapPoint(coordinate)
        if link == nil {
            let display = CADisplayLink(target: target, selector: #selector(Target.tick(_:)))
            display.preferredFramesPerSecond = 60
            display.add(to: .main, forMode: .common); link = display
        }
    }
    func stop() { link?.invalidate(); link = nil; previous = nil; destination = nil }
    private func tick(_ link: CADisplayLink) {
        guard map?.window != nil else { previous = nil; return }
        let delta = previous.map { min(0.05, max(0, link.timestamp-$0)) } ?? 1.0/60
        previous = link.timestamp
        step(delta)
    }
    // Kept separate so the production interpolation can be checked deterministically.
    func step(_ delta: Double) {
        guard let map = map, let end = destination else { return }
        let start = MKMapPoint(map.centerCoordinate), world = MKMapRect.world.width
        let fraction = 1-exp(-max(0, delta)/0.42)
        var x = start.x + ReplayGeometry.shortestDelta(end.x-start.x, worldWidth: world)*fraction
        x = x.truncatingRemainder(dividingBy: world); if x < 0 { x += world }
        let next = MKMapPoint(x: x, y: start.y+(end.y-start.y)*fraction)
        map.setCenter(next.coordinate, animated: false)
        let dx = ReplayGeometry.shortestDelta(end.x-next.x, worldWidth: world)
        let pixels = hypot(dx, end.y-next.y)*Double(map.bounds.width)/max(1, map.visibleMapRect.width)
        if pixels < 0.05 { stop() }
    }
}
