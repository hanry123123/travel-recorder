import Foundation

/// A manual gesture wins over GPS updates until an explicit recenter request.
struct MapFollowState {
    private(set) var manuallyMoved = false
    private var recenterToken = 0
    mutating func userMoved() { manuallyMoved = true }
    mutating func consumeRecenter(_ token: Int) -> Bool {
        guard token != recenterToken else { return false }
        recenterToken = token; manuallyMoved = false
        return true
    }
    func shouldFollow(enabled: Bool, replaying: Bool) -> Bool {
        enabled && !manuallyMoved && !replaying
    }
}

enum MemoryPresentation {
    static func coverPhotos(_ photos: [PhotoAttachment]) -> [PhotoAttachment] {
        Array(photos.enumerated().sorted {
            $0.element.capturedAt == $1.element.capturedAt ? $0.offset < $1.offset : $0.element.capturedAt < $1.element.capturedAt
        }.prefix(3).map { $0.element })
    }
    static func placeKey(_ coordinate: Coordinate) -> String {
        String(format: "%.4f,%.4f", locale: Locale(identifier: "en_US_POSIX"), coordinate.latitude, coordinate.longitude)
    }
    static func fallbackPlace(_ coordinate: Coordinate?) -> String {
        guard let coordinate = coordinate, coordinate.isValid else { return "待记录" }
        return String(format: "%.3f, %.3f", locale: Locale(identifier: "en_US_POSIX"), coordinate.latitude, coordinate.longitude)
    }
    static func placeLabel(locality: String?, district: String?, name: String?, region: String?) -> String? {
        let parts = [locality ?? region, name ?? district].compactMap { value -> String? in
            guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return text
        }
        let unique = parts.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return unique.isEmpty ? nil : unique.joined(separator: "·")
    }
}
