import Foundation

protocol StoredModel: Codable {
    static var kind: String { get }
    var id: UUID { get }
    var tripID: UUID { get }
    var sortDate: Date { get }
}

enum CoordinateDatum: String, Codable { case wgs84, legacyMap }
struct Coordinate: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    // Absent on old GPS records. Old manually selected coordinates are handled
    // by their owning photo/diary, since 1.0.1 stored map coordinates directly.
    var datum: CoordinateDatum? = nil
    var identified: Coordinate {
        var value = self
        if value.datum == nil { value.datum = .wgs84 }
        return value
    }
    var isValid: Bool { latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude) }
    func distance(to other: Coordinate) -> Double {
        let p = Double.pi / 180
        let a = sin((other.latitude - latitude) * p / 2)
        let b = sin((other.longitude - longitude) * p / 2)
        let h = min(1, max(0, a*a + cos(latitude*p) * cos(other.latitude*p) * b*b))
        return 6_371_000 * 2 * atan2(sqrt(h), sqrt(1-h))
    }
}

enum TripStatus: String, Codable { case recording, paused, interrupted, ended }
struct RecordingInterval: Codable {
    var id = UUID()
    var start: Date
    var end: Date?
}
struct Trip: StoredModel, Identifiable {
    static let kind = "trip"
    var id = UUID()
    var tripID: UUID { id }
    var sortDate: Date { startedAt }
    var title: String
    var features = ""
    var reflection = ""
    var startedAt: Date
    var endedAt: Date?
    var status: TripStatus = .recording
    var intervals: [RecordingInterval]
    var distance: Double = 0
    var lastRecordedAt: Date?
    var currentSegment: UUID?
    var updatedAt: Date
    init(now: Date) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日的旅程"
        title = formatter.string(from: now)
        startedAt = now
        updatedAt = now
        let interval = RecordingInterval(start: now)
        intervals = [interval]
        currentSegment = interval.id
    }
    func duration(at now: Date) -> TimeInterval {
        intervals.reduce(0) { $0 + max(0, ($1.end ?? now).timeIntervalSince($1.start)) }
    }
}

struct LocationSample {
    var coordinate: Coordinate
    var timestamp: Date
    var accuracy: Double
}
struct TrackPoint: StoredModel, Identifiable {
    static let kind = "point"
    var id = UUID()
    var tripID: UUID
    var segmentID: UUID
    var coordinate: Coordinate
    var timestamp: Date
    var accuracy: Double
    var sortDate: Date { timestamp }
}

struct PhotoAttachment: StoredModel, Identifiable {
    static let kind = "photo"
    var id = UUID()
    var tripID: UUID
    var assetID: String?
    var capturedAt: Date
    var importedAt: Date
    var coordinate: Coordinate?
    var originalCoordinate: Coordinate?
    var manuallyPlaced = false
    var captureDateKnown = true
    var imageFile: String
    var thumbnailFile: String
    var sortDate: Date { capturedAt }
    var mapCoordinate: Coordinate? {
        guard var value = coordinate else { return nil }
        if manuallyPlaced && value.datum == nil { value.datum = .legacyMap }
        return value
    }
}
struct PhotoExclusion: StoredModel {
    static let kind = "exclusion"
    var id = UUID()
    var tripID: UUID
    var assetID: String
    var sortDate: Date
}
struct DiaryEntry: StoredModel, Identifiable {
    static let kind = "diary"
    var id = UUID()
    var tripID: UUID
    var photoID: UUID?
    var coordinate: Coordinate?
    var mapCoordinate: Coordinate? {
        guard var value = coordinate else { return nil }
        if photoID == nil && value.datum == nil { value.datum = .legacyMap }
        return value
    }
    var title = ""
    var text = ""
    var createdAt: Date
    var updatedAt: Date
    var sortDate: Date { createdAt }
}

enum TripError: LocalizedError {
    case invalidTransition, missingTrip, storage(String)
    var errorDescription: String? {
        switch self {
        case .invalidTransition: return "当前记录状态不支持这个操作。"
        case .missingTrip: return "这段旅程已不存在。"
        case .storage(let message): return "保存失败：\(message)"
        }
    }
}

enum RecorderLogic {
    static func pause(_ trip: Trip, at date: Date, interrupted: Bool = false) throws -> Trip {
        guard trip.status == .recording else { throw TripError.invalidTransition }
        var result = trip
        if !result.intervals.isEmpty { result.intervals[result.intervals.count-1].end = max(date, result.intervals.last!.start) }
        result.status = interrupted ? .interrupted : .paused
        result.currentSegment = nil
        result.updatedAt = date
        return result
    }
    static func resume(_ trip: Trip, at date: Date) throws -> Trip {
        guard trip.status == .paused || trip.status == .interrupted else { throw TripError.invalidTransition }
        var result = trip
        let interval = RecordingInterval(start: date)
        result.intervals.append(interval)
        result.currentSegment = interval.id
        result.status = .recording
        result.updatedAt = date
        return result
    }
    static func finish(_ trip: Trip, at date: Date) throws -> Trip {
        guard trip.status != .ended else { throw TripError.invalidTransition }
        var result = trip.status == .recording ? try pause(trip, at: date) : trip
        result.status = .ended
        result.endedAt = date
        result.updatedAt = date
        return result
    }
    static func recover(_ trip: Trip) throws -> Trip {
        guard trip.status == .recording else { return trip }
        return try pause(trip, at: trip.lastRecordedAt ?? trip.intervals.last!.start, interrupted: true)
    }
    static func accept(_ sample: LocationSample, trip: Trip, previous: TrackPoint?, now: Date) -> (Trip, TrackPoint)? {
        guard trip.status == .recording, let segment = trip.currentSegment, let start = trip.intervals.last?.start,
              sample.coordinate.isValid, sample.accuracy.isFinite, sample.accuracy >= 0, sample.accuracy <= 100,
              sample.timestamp >= start, sample.timestamp <= now.addingTimeInterval(10),
              now.timeIntervalSince(sample.timestamp) <= 120 else { return nil }
        if let lastTime = trip.lastRecordedAt, sample.timestamp <= lastTime { return nil }
        var result = trip
        var segmentID = segment
        var increment = 0.0
        if let last = previous, last.tripID == trip.id, last.segmentID == segment {
            let elapsed = sample.timestamp.timeIntervalSince(last.timestamp)
            let distance = last.coordinate.distance(to: sample.coordinate)
            if elapsed > 120 {
                segmentID = UUID()
            } else {
                guard distance >= max(5, min(20, (last.accuracy + sample.accuracy)/4)) else { return nil }
                guard distance <= elapsed * 450 + last.accuracy + sample.accuracy else { return nil }
                increment = distance
            }
        }
        result.currentSegment = segmentID
        result.distance += increment
        result.lastRecordedAt = sample.timestamp
        result.updatedAt = now
        let point = TrackPoint(tripID: trip.id, segmentID: segmentID, coordinate: sample.coordinate, timestamp: sample.timestamp, accuracy: sample.accuracy)
        return (result, point)
    }
}

enum PhotoMatching {
    static func belongs(capturedAt: Date, to trip: Trip, now: Date) -> Bool {
        capturedAt >= trip.startedAt && capturedAt <= (trip.endedAt ?? now)
    }
    static func shouldImport(assetID: String, capturedAt: Date, trip: Trip, now: Date, existing: Set<String>, excluded: Set<String>) -> Bool {
        belongs(capturedAt: capturedAt, to: trip, now: now) && !existing.contains(assetID) && !excluded.contains(assetID)
    }
}

enum PhotoEditing {
    static func place(_ photo: PhotoAttachment, at coordinate: Coordinate, diaries: [DiaryEntry]) -> (PhotoAttachment, [DiaryEntry])? {
        guard coordinate.isValid else { return nil }
        var updated = photo
        updated.coordinate = coordinate
        updated.manuallyPlaced = true
        let changed = diaries.filter { $0.tripID == photo.tripID && $0.photoID == photo.id }.map { entry -> DiaryEntry in
            var copy = entry
            copy.coordinate = coordinate
            return copy
        }
        return (updated, changed)
    }
}
