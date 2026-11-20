import Foundation

/// A reminder about no *recorded* movement, not proof the device is stationary.
struct InactivityReminderState: Codable, Equatable {
    static let interval: TimeInterval = 2 * 60 * 60
    var tripID: UUID
    var anchor: Coordinate?
    var anchorAccuracy: Double = 0
    var lastSampleAt: Date?
    var since: Date
    var paused: Bool
    var due: Date { since.addingTimeInterval(Self.interval) }
    mutating func observe(_ sample: LocationSample, now: Date) -> Bool {
        guard !paused, sample.coordinate.isValid, sample.accuracy.isFinite, (0...50).contains(sample.accuracy),
              sample.timestamp >= since, sample.timestamp <= now.addingTimeInterval(10),
              now.timeIntervalSince(sample.timestamp) <= 120,
              lastSampleAt.map({ sample.timestamp > $0 }) ?? true else { return false }
        let moved = anchor.map { $0.distance(to: sample.coordinate) >= max(50, anchorAccuracy + sample.accuracy) } ?? true
        lastSampleAt = sample.timestamp
        if moved { anchor = sample.coordinate; anchorAccuracy = sample.accuracy; since = sample.timestamp }
        return moved
    }
}
