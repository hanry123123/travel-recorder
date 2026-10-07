import Foundation
import CoreLocation

protocol LocationSource: AnyObject {
    var onSamples: (([LocationSample]) -> Void)? { get set }
    var onAuthorization: (() -> Void)? { get set }
    var onFailure: ((String) -> Void)? { get set }
    var authorization: CLAuthorizationStatus { get }
    var precise: Bool { get }
    func requestPermission()
    func start()
    func stop()
}
final class DeviceLocationSource: NSObject, LocationSource, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onSamples: (([LocationSample]) -> Void)?
    var onAuthorization: (() -> Void)?
    var onFailure: ((String) -> Void)?
    var authorization: CLAuthorizationStatus { manager.authorizationStatus }
    var precise: Bool { manager.accuracyAuthorization == .fullAccuracy }
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10
        manager.activityType = .other
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
    }
    func requestPermission() { manager.requestWhenInUseAuthorization() }
    func start() {
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
        if !precise { manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "RecordTrip") }
    }
    func stop() { manager.stopUpdatingLocation(); manager.allowsBackgroundLocationUpdates = false }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { onAuthorization?() }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        onSamples?(locations.map { LocationSample(coordinate: Coordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude), timestamp: $0.timestamp, accuracy: $0.horizontalAccuracy) }.sorted { $0.timestamp < $1.timestamp })
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let error = error as? CLError, error.code == .locationUnknown { onFailure?("暂时无法定位，恢复信号后继续记录。") }
        else { onFailure?(error.localizedDescription) }
    }
}
