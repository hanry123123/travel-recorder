import Foundation

/// A frozen, chronological route. Never modifies the live recorder or its points.
struct RouteReplayPath {
    let points: [TrackPoint]
    let connectsToPrevious: [Bool]

    init(points input: [TrackPoint]) {
        let invalidTime = input.contains { !$0.timestamp.timeIntervalSinceReferenceDate.isFinite }
        let ordered = input.enumerated().filter { $0.element.timestamp.timeIntervalSinceReferenceDate.isFinite }.sorted {
            if $0.element.timestamp == $1.element.timestamp { return $0.offset < $1.offset }
            return $0.element.timestamp < $1.element.timestamp
        }
        var points: [TrackPoint] = [], connections: [Bool] = []
        var previous: TrackPoint?
        for item in ordered {
            let point = item.element
            guard point.coordinate.isValid else { previous = nil; continue }
            let joins = previous.map {
                !invalidTime && $0.tripID == point.tripID && $0.segmentID == point.segmentID &&
                    point.timestamp.timeIntervalSince($0.timestamp) <= 120
            } ?? false
            points.append(point); connections.append(joins)
            previous = point
        }
        self.points = points
        connectsToPrevious = connections
    }
}

struct RouteReplayFrame {
    let from: Int
    let to: Int
    let fraction: Double
    let visible: Bool
    let opacity: Double
}

struct RouteReplayTimeline {
    private struct Step {
        let start: Double, end: Double
        let from: Int, to: Int
        let visible: Bool
    }
    private var steps: [Step] = []
    private(set) var duration: Double = 0

    /// Distances are measured in screen points at the initial route overview.
    /// A long winding route takes longer instead of accelerating arbitrarily.
    init(path: RouteReplayPath, screenDistances: [Double], pointsPerSecond: Double = 36) {
        guard !path.points.isEmpty else { return }
        precondition(screenDistances.count == max(0, path.points.count - 1))
        let speed = pointsPerSecond.isFinite ? min(60, max(12, pointsPerSecond)) : 36
        let distances = screenDistances.enumerated().map { index, distance in
            path.connectsToPrevious[index+1] && distance.isFinite ? max(0, distance) : 0
        }
        let total = distances.reduce(0, +)
        let movingDuration = max(12, total / speed)
        func append(_ from: Int, _ to: Int, _ seconds: Double, _ visible: Bool = true) {
            let start = duration
            duration += seconds
            steps.append(Step(start: start, end: duration, from: from, to: to, visible: visible))
        }
        append(0, 0, 0.8)
        for index in 1..<path.points.count {
            if !path.connectsToPrevious[index] {
                // Disappear at a recording gap; do not animate across unrecorded ground.
                append(index-1, index-1, 0.65, false)
                append(index, index, 0.5)
            } else if total > 0 && distances[index-1] > 0 {
                append(index-1, index, distances[index-1] / total * movingDuration)
            }
        }
        append(path.points.count-1, path.points.count-1, 1.2)
    }

    func frame(at elapsed: Double) -> RouteReplayFrame? {
        guard !steps.isEmpty else { return nil }
        let time = elapsed.isNaN ? 0 : min(duration, max(0, elapsed))
        var low = 0, high = steps.count - 1
        while low < high {
            let mid = (low + high) / 2
            if time >= steps[mid].end { low = mid + 1 } else { high = mid }
        }
        let step = steps[low]
        let fraction = min(1, max(0, (time-step.start)/(step.end-step.start)))
        var opacity: Double = step.visible ? 1 : 0
        if low == 0 || !steps[low-1].visible { opacity = min(opacity, max(0, (time-step.start)/0.18)) }
        if low+1 < steps.count && !steps[low+1].visible { opacity = min(opacity, max(0, (step.end-time)/0.18)) }
        return RouteReplayFrame(from: step.from, to: step.to, fraction: fraction, visible: step.visible, opacity: opacity)
    }

    /// A scrub always lands on recorded ground, never inside a recording gap.
    func scrubTime(fraction: Double) -> Double {
        let value = fraction.isFinite ? min(1, max(0, fraction)) : 0
        let time = value*duration
        guard let gap = steps.first(where: { !$0.visible && time >= $0.start && time < $0.end }) else { return time }
        return time-gap.start < gap.end-time ? max(0, gap.start-0.000001) : gap.end
    }

    func recordedTime(at elapsed: Double, path: RouteReplayPath) -> Date? {
        guard let frame = frame(at: elapsed), path.points.indices.contains(frame.from),
              path.points.indices.contains(frame.to) else { return nil }
        let start = path.points[frame.from].timestamp
        return start.addingTimeInterval(path.points[frame.to].timestamp.timeIntervalSince(start)*frame.fraction)
    }
}

/// Keep all animations and map bounds on the short side of the date line.
enum ReplayGeometry {
    static func shortestDelta(_ delta: Double, worldWidth: Double) -> Double {
        guard worldWidth > 0, delta.isFinite else { return 0 }
        var value = delta.truncatingRemainder(dividingBy: worldWidth)
        if value > worldWidth/2 { value -= worldWidth }
        if value < -worldWidth/2 { value += worldWidth }
        return value
    }
}
