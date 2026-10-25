import Foundation

struct TripShareSnapshot: Identifiable {
    let id = UUID()
    let trip: Trip
    let points: [TrackPoint]
    let photos: [PhotoAttachment]
    let diaries: [DiaryEntry]
    let photoDirectory: URL
    let endpoints: String
    let capturedAt: Date
    let alignment: MapAlignment
}

enum ShareSelection {
    static func representative(_ photos: [PhotoAttachment]) -> [UUID] {
        let sorted = photos.sorted { $0.capturedAt < $1.capturedAt }
        guard sorted.count > 3 else { return sorted.map { $0.id } }
        return [sorted[0].id, sorted[sorted.count/2].id, sorted[sorted.count-1].id]
    }
    static func frame(for photo: PhotoAttachment, in path: RouteReplayPath) -> RouteReplayFrame? {
        guard photo.captureDateKnown, let first = path.points.first, let last = path.points.last,
              photo.capturedAt >= first.timestamp, photo.capturedAt <= last.timestamp else { return nil }
        for i in path.points.indices {
            if photo.capturedAt == path.points[i].timestamp {
                if i+1 < path.points.count && path.connectsToPrevious[i+1] {
                    return RouteReplayFrame(from: i, to: i+1, fraction: 0, visible: true, opacity: 1)
                }
                if i > 0 && path.connectsToPrevious[i] {
                    return RouteReplayFrame(from: i-1, to: i, fraction: 1, visible: true, opacity: 1)
                }
                return RouteReplayFrame(from: i, to: i, fraction: 0, visible: true, opacity: 1)
            }
            if i > 0 && path.connectsToPrevious[i] && photo.capturedAt > path.points[i-1].timestamp && photo.capturedAt < path.points[i].timestamp {
                let fraction = photo.capturedAt.timeIntervalSince(path.points[i-1].timestamp)/path.points[i].timestamp.timeIntervalSince(path.points[i-1].timestamp)
                return RouteReplayFrame(from: i-1, to: i, fraction: fraction, visible: true, opacity: 1)
            }
        }
        return nil
    }
}
