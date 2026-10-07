import SwiftUI
import MapKit

struct MapSelection: Identifiable {
    let id = UUID()
    let coordinate: Coordinate
}
final class TravelAnnotation: NSObject, MKAnnotation {
    let identifier: UUID
    let kind: String
    dynamic var coordinate: CLLocationCoordinate2D
    var title: String?
    var thumbnailURL: URL?
    init(id: UUID, kind: String, coordinate: CLLocationCoordinate2D, title: String) {
        identifier = id; self.kind = kind
        self.coordinate = coordinate
        self.title = title
    }
}
struct TravelMap: UIViewRepresentable {
    @AppStorage("mapAlignment") private var alignmentRaw = MapAlignment.automatic.rawValue
    private var alignment: MapAlignment { MapAlignment(rawValue: alignmentRaw) ?? .automatic }
    fileprivate func displayed(_ coordinate: Coordinate) -> CLLocationCoordinate2D {
        let value = MapCoordinates.display(coordinate, mode: alignment)
        return CLLocationCoordinate2D(latitude: value.latitude, longitude: value.longitude)
    }
    var points: [TrackPoint]
    var photos: [PhotoAttachment] = []
    var photoDirectory: URL?
    var diaries: [DiaryEntry] = []
    var selection: Coordinate?
    var fallback: Coordinate?
    var fitToken: Int = 0
    var recenterToken: Int = 0
    var follow = false
    var isInteractive = true
    var replay: RouteReplayController? = nil
    var onCoordinate: (Coordinate) -> Void = { _ in }
    var onPhoto: (UUID) -> Void = { _ in }
    var onDiary: (UUID) -> Void = { _ in }
    var onUserInteraction: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    static func dismantleUIView(_ map: MKMapView, coordinator: Coordinator) {
        coordinator.replayAnimator.dismantle()
        map.delegate = nil
    }
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.mapType = .standard
        map.showsCompass = true
        map.showsScale = true
        map.isRotateEnabled = false
        map.clipsToBounds = true
        map.isOpaque = true; map.backgroundColor = .systemBackground
        map.layer.borderWidth = 0; map.layer.shadowOpacity = 0
        map.pointOfInterestFilter = .includingAll
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.delegate = context.coordinator
        map.addGestureRecognizer(tap)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.manuallyMoved(_:)))
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.manuallyMoved(_:)))
        for gesture in [pan, pinch] as [UIGestureRecognizer] {
            gesture.delegate = context.coordinator
            gesture.cancelsTouchesInView = false
            map.addGestureRecognizer(gesture)
        }
        map.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 30, longitude: 105), span: MKCoordinateSpan(latitudeDelta: 40, longitudeDelta: 55)), animated: false)
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        map.isUserInteractionEnabled = isInteractive
        coordinator.replayAnimator.fitRoute = { [weak map, weak coordinator] coordinates in
            guard let map = map else { return }
            coordinator?.fit(map, coordinates: coordinates, animated: false)
        }
        coordinator.replayAnimator.connect(map: map, controller: replay, projectionKey: alignmentRaw, transform: displayed)
        if coordinator.alignmentRaw != alignmentRaw {
            coordinator.alignmentRaw = alignmentRaw
            coordinator.pathSignature = ""
            coordinator.pinSignature = ""
            coordinator.hasFitted = false
        }
        let recenter = coordinator.followState.consumeRecenter(recenterToken)
        let auth = coordinator.locationManager.authorizationStatus
        map.showsUserLocation = auth == .authorizedAlways || auth == .authorizedWhenInUse
        let signature = "\(points.count):\(points.last?.id.uuidString ?? ""):\(replay?.isPresenting == true)"
        if signature != coordinator.pathSignature {
            coordinator.pathSignature = signature
            map.removeOverlays(map.overlays)
            var groups: [[TrackPoint]] = []
            for point in points {
                if groups.last?.last?.segmentID == point.segmentID { groups[groups.count-1].append(point) }
                else { groups.append([point]) }
            }
            for group in groups where group.count > 1 {
                // During replay the line and light use the same complete geometry;
                // skipping a sharp corner here would make the light leave the line.
                let step = replay?.isPresenting == true ? 1 : max(1, Int(ceil(Double(group.count) / 5000)))
                var coordinates = stride(from: 0, to: group.count, by: step).map { displayed(group[$0].coordinate) }
                if (group.count-1) % step != 0, let last = group.last { coordinates.append(displayed(last.coordinate)) }
                map.addOverlay(MKPolyline(coordinates: coordinates, count: coordinates.count))
            }
            if coordinator.followState.shouldFollow(enabled: follow, replaying: replay?.isPresenting == true), let last = points.last {
                map.setRegion(MKCoordinateRegion(center: displayed(last.coordinate), latitudinalMeters: 1400, longitudinalMeters: 1400), animated: true)
            }
        }
        let photoSignature = (photoDirectory?.path ?? "") + photos.map { "\($0.id):\($0.thumbnailFile):\(String(describing: $0.coordinate))" }.joined(separator: "|")
        let diarySignature = diaries.map { "\($0.id):\($0.title):\(String(describing: $0.coordinate))" }.joined(separator: "|")
        let pinSignature = [photoSignature, diarySignature, String(describing: selection)].joined(separator: ":")
        if pinSignature != coordinator.pinSignature {
            coordinator.pinSignature = pinSignature
            map.removeAnnotations(map.annotations.filter {
                guard let pin = $0 as? TravelAnnotation else { return false }
                return pin.kind != "start" && pin.kind != "end"
            })
            var annotations: [TravelAnnotation] = []
            for photo in photos {
                if let coordinate = photo.mapCoordinate {
                    let pin = TravelAnnotation(id: photo.id, kind: "photo", coordinate: displayed(coordinate), title: "旅途照片")
                    pin.thumbnailURL = photoDirectory?.appendingPathComponent(URL(fileURLWithPath: photo.thumbnailFile).lastPathComponent)
                    annotations.append(pin)
                }
            }
            for diary in diaries where diary.photoID == nil {
                if let coordinate = diary.mapCoordinate { annotations.append(TravelAnnotation(id: diary.id, kind: "diary", coordinate: displayed(coordinate), title: diary.title.isEmpty ? "地点日记" : diary.title)) }
            }
            if let coordinate = selection { annotations.append(TravelAnnotation(id: UUID(), kind: "selection", coordinate: displayed(coordinate), title: "选中的位置")) }
            map.addAnnotations(annotations)
        }
        coordinator.updateEndpoint(on: map, point: points.first, kind: "start")
        coordinator.updateEndpoint(on: map, point: points.count > 1 ? points.last : nil, kind: "end")
        let hasContent = !points.isEmpty || photos.contains { $0.coordinate != nil } || diaries.contains { $0.coordinate != nil } || selection != nil || fallback != nil
        if hasContent && ((!coordinator.hasFitted && !coordinator.followState.manuallyMoved) || coordinator.lastFitToken != fitToken) {
            coordinator.hasFitted = true
            coordinator.lastFitToken = fitToken
            var coordinates = points.map { $0.coordinate } + photos.compactMap { $0.mapCoordinate } + diaries.filter { $0.photoID == nil }.compactMap { $0.mapCoordinate }
            if let selection = selection { coordinates.append(selection) }
            if coordinates.isEmpty, let fallback = fallback { coordinates.append(fallback) }
            coordinator.fit(map, coordinates: coordinates)
        }
        if recenter, let coordinate = fallback ?? points.last?.coordinate {
            coordinator.hasFitted = true
            map.setRegion(MKCoordinateRegion(center: displayed(coordinate), latitudinalMeters: 1400, longitudinalMeters: 1400), animated: true)
        }
    }
    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: TravelMap
        let replayAnimator = MapReplayAnimator()
        let locationManager = CLLocationManager()
        var followState = MapFollowState()
        var endpoints: [String: TravelAnnotation] = [:]
        var alignmentRaw = ""
        var pathSignature = ""
        var pinSignature = ""
        var hasFitted = false
        var lastFitToken = 0
        init(_ parent: TravelMap) { self.parent = parent }
        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) { replayAnimator.render() }
        @objc func manuallyMoved(_ gesture: UIGestureRecognizer) {
            guard gesture.state == .began else { return }
            followState.userMoved()
            parent.onUserInteraction()
        }
        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            // MapKit also supports double-tap zoom; it must count as manual exploration.
            func hasZoomTap(_ view: UIView) -> Bool {
                if (view.gestureRecognizers ?? []).contains(where: {
                    guard let tap = $0 as? UITapGestureRecognizer else { return false }
                    return tap.state == .ended && (tap.numberOfTapsRequired > 1 || tap.numberOfTouchesRequired > 1)
                }) { return true }
                return view.subviews.contains { hasZoomTap($0) }
            }
            if hasZoomTap(mapView) { followState.userMoved(); parent.onUserInteraction() }
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            gestureRecognizer is UIPanGestureRecognizer || gestureRecognizer is UIPinchGestureRecognizer
        }
        func updateEndpoint(on map: MKMapView, point: TrackPoint?, kind: String) {
            guard let point = point else {
                if let pin = endpoints.removeValue(forKey: kind) { map.removeAnnotation(pin) }
                return
            }
            let coordinate = parent.displayed(point.coordinate)
            if let pin = endpoints[kind] {
                if pin.coordinate.latitude != coordinate.latitude || pin.coordinate.longitude != coordinate.longitude { pin.coordinate = coordinate }
            } else {
                let pin = TravelAnnotation(id: point.id, kind: kind, coordinate: coordinate, title: kind == "start" ? "起点" : "最近记录的位置")
                endpoints[kind] = pin; map.addAnnotation(pin)
            }
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UIControl || (current is MKAnnotationView && gestureRecognizer is UITapGestureRecognizer) { return false }
                view = current.superview
            }
            return true
        }
        @objc func tapped(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let map = recognizer.view as? MKMapView else { return }
            let point = map.convert(recognizer.location(in: map), toCoordinateFrom: map)
            let coordinate = Coordinate(latitude: point.latitude, longitude: point.longitude)
            if coordinate.isValid { parent.onCoordinate(MapCoordinates.storedSelection(coordinate, mode: parent.alignment)) }
        }
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.strokeColor = .systemBlue
            renderer.lineWidth = 5
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let pin = annotation as? TravelAnnotation else { return nil }
            if pin.kind == "photo" {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "photoThumbnail") as? PhotoMapMarker ?? PhotoMapMarker(annotation: pin, reuseIdentifier: "photoThumbnail")
                view.annotation = pin; view.load(pin.thumbnailURL)
                return view
            }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "marker") as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: pin, reuseIdentifier: "marker")
            view.annotation = pin
            view.canShowCallout = pin.kind == "start" || pin.kind == "end" || pin.kind == "selection"
            view.displayPriority = pin.kind == "selection" ? .required : .defaultHigh
            view.markerTintColor = pin.kind == "photo" ? .systemOrange : pin.kind == "diary" ? .systemPurple : pin.kind == "start" ? .systemGreen : .systemBlue
            let symbol = pin.kind == "photo" ? "photo" : pin.kind == "diary" ? "book.closed" : pin.kind == "start" ? "flag" : "mappin"
            view.glyphImage = UIImage(systemName: symbol)
            view.accessibilityLabel = pin.title
            return view
        }
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation as? TravelAnnotation else { return }
            if annotation.kind == "photo" { parent.onPhoto(annotation.identifier); mapView.deselectAnnotation(annotation, animated: false) }
            if annotation.kind == "diary" { parent.onDiary(annotation.identifier); mapView.deselectAnnotation(annotation, animated: false) }
        }
        func fit(_ map: MKMapView, coordinates: [Coordinate], animated: Bool = true) {
            guard let first = coordinates.first else { return }
            if coordinates.count == 1 {
                map.setRegion(MKCoordinateRegion(center: parent.displayed(first), latitudinalMeters: 1800, longitudinalMeters: 1800), animated: animated)
                return
            }
            let world = MKMapRect.world.width
            let origin = MKMapPoint(parent.displayed(first)).x
            var rect = MKMapRect.null
            for coordinate in coordinates {
                var p = MKMapPoint(parent.displayed(coordinate))
                if p.x-origin > world/2 { p.x -= world }
                if p.x-origin < -world/2 { p.x += world }
                rect = rect.union(MKMapRect(x: p.x, y: p.y, width: 1, height: 1))
            }
            if rect.width < 400 && rect.height < 400 { rect = rect.insetBy(dx: -400, dy: -400) }
            map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 65, left: 40, bottom: 65, right: 40), animated: animated)
        }
    }
}

struct RoutePreview: View {
    let points: [TrackPoint]
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(UIColor.secondarySystemGroupedBackground)
                if points.isEmpty { Image(systemName: "map").font(.largeTitle).foregroundColor(.blue.opacity(0.4)) }
                else {
                    Path { path in
                        let firstLon = points.first!.coordinate.longitude
                        let longitudes = points.map { point -> Double in
                            var lon = point.coordinate.longitude
                            if lon-firstLon > 180 { lon -= 360 }; if lon-firstLon < -180 { lon += 360 }
                            return lon
                        }
                        let latitudes = points.map { $0.coordinate.latitude }
                        let minX = longitudes.min()!, maxX = longitudes.max()!, minY = latitudes.min()!, maxY = latitudes.max()!
                        let scaleX = max(0.1, cos((minY+maxY)/2 * .pi/180))
                        let width = max(0.0001, (maxX-minX)*scaleX), height = max(0.0001, maxY-minY)
                        let scale = min((geometry.size.width-30)/width, (geometry.size.height-30)/height)
                        let step = max(1, points.count/1500)
                        var previous: UUID?
                        for index in stride(from: 0, to: points.count, by: step) {
                            let point = CGPoint(x: (longitudes[index]-(minX+maxX)/2)*scaleX*scale+geometry.size.width/2, y: -((latitudes[index]-(minY+maxY)/2)*scale)+geometry.size.height/2)
                            if previous == points[index].segmentID { path.addLine(to: point) } else { path.move(to: point) }
                            previous = points[index].segmentID
                        }
                    }.stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }
}
