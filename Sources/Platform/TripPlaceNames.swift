import Foundation
import Combine
import CoreLocation
import UIKit

/// Visible memory cards share a serial geocoder and a persistent local name cache.
final class TripPlaceNames: ObservableObject {
    @Published private(set) var names: [String: String] = [:]
    private let cacheURL: URL
    private let geocoder = CLGeocoder()
    private var wanted: [UUID: [Coordinate]] = [:]
    private var movingRefresh: [UUID: Date] = [:]
    private var attempted: [String: Date] = [:]
    private var busy = false
    private var nextRequest = Date.distantPast
    private var wake: DispatchWorkItem?
    private var activeObserver: NSObjectProtocol?
    init(cacheURL: URL) {
        self.cacheURL = cacheURL
        if let data = try? Data(contentsOf: cacheURL), let cache = try? JSONDecoder().decode([String: String].self, from: data) { names = cache }
        activeObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.pump() }
    }
    deinit {
        wake?.cancel(); geocoder.cancelGeocode()
        if let observer = activeObserver { NotificationCenter.default.removeObserver(observer) }
    }
    func name(for coordinate: Coordinate?) -> String {
        guard let coordinate = coordinate else { return MemoryPresentation.fallbackPlace(nil) }
        return names[MemoryPresentation.placeKey(coordinate)] ?? MemoryPresentation.fallbackPlace(coordinate)
    }
    func show(tripID: UUID, start: Coordinate?, end: Coordinate?, moving: Bool) {
        // A live journey must not turn every GPS callback into a network lookup.
        if moving, wanted[tripID] != nil, Date().timeIntervalSince(movingRefresh[tripID] ?? .distantPast) < 60 { return }
        movingRefresh[tripID] = Date()
        wanted[tripID] = [start, end].compactMap { $0 }.filter { $0.isValid }
        pump()
    }
    func hide(tripID: UUID) { wanted.removeValue(forKey: tripID); movingRefresh.removeValue(forKey: tripID) }
    private func pump() {
        guard !busy, UIApplication.shared.applicationState == .active else { return }
        let now = Date()
        let candidates = wanted.sorted { $0.key.uuidString < $1.key.uuidString }.flatMap { $0.value }
        guard let coordinate = candidates.first(where: {
            let key = MemoryPresentation.placeKey($0)
            return names[key] == nil && now.timeIntervalSince(attempted[key] ?? .distantPast) > 120
        }) else { return }
        let delay = nextRequest.timeIntervalSince(now)
        if delay > 0 {
            wake?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.pump() }; wake = work
            DispatchQueue.main.asyncAfter(deadline: .now()+delay, execute: work)
            return
        }
        busy = true
        let key = MemoryPresentation.placeKey(coordinate)
        attempted[key] = now
        nextRequest = now.addingTimeInterval(2)
        geocoder.reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), preferredLocale: Locale(identifier: "zh_CN")) { [weak self] placemarks, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.busy = false
                if let place = placemarks?.first,
                   let name = MemoryPresentation.placeLabel(locality: place.locality, district: place.subLocality, name: place.name, region: place.administrativeArea ?? place.country) {
                    self.names[key] = name
                    if let data = try? JSONEncoder().encode(self.names) {
                        try? data.write(to: self.cacheURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    }
                } else if error != nil { self.nextRequest = Date().addingTimeInterval(60) }
                self.pump()
            }
        }
    }
}
