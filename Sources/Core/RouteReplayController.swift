import Foundation
import Combine

final class RouteReplayProgress: ObservableObject {
    struct Position {
        let fraction: Double
        let recordedAt: Date?
        let inGap: Bool
    }
    @Published private(set) var position = Position(fraction: 0, recordedAt: nil, inGap: false)
    func update(fraction: Double, recordedAt: Date?, inGap: Bool) {
        position = Position(fraction: fraction, recordedAt: recordedAt, inGap: inGap)
    }
}

final class RouteReplayController: ObservableObject {
    enum State { case idle, playing, live, paused, finished }
    @Published private(set) var state: State = .idle
    @Published private(set) var followsHead = true
    private(set) var path = RouteReplayPath(points: [])
    private(set) var runID = UUID()
    let progress = RouteReplayProgress()
    let seekRequested = PassthroughSubject<Void, Never>()
    let pathChanged = PassthroughSubject<Void, Never>()
    private(set) var elapsed: Double = 0
    private(set) var timeline = RouteReplayTimeline(path: RouteReplayPath(points: []), screenDistances: [])
    private var lastProgressTime: Double = -.infinity
    private var resumeAfterScrubbing = false
    private var receivesUpdates = false
    private var pendingUpdate: ([TrackPoint], Bool)?
    private var remainingBudget: Double = 20
    private var liveRemaining: Double = 0
    private(set) var isScrubbing = false
    var isPresenting: Bool { state != .idle }
    var isRunning: Bool { state == .playing || state == .live }

    private func makeTimeline(_ path: RouteReplayPath) -> RouteReplayTimeline {
        let distances = path.points.dropFirst().enumerated().map { index, point in
            path.points[index].coordinate.distance(to: point.coordinate) / 5
        }
        return RouteReplayTimeline(path: path, screenDistances: distances)
    }
    func start(_ points: [TrackPoint], live: Bool = false) {
        let snapshot = RouteReplayPath(points: points)
        guard !snapshot.points.isEmpty else { return }
        path = snapshot; runID = UUID(); elapsed = 0; isScrubbing = false; resumeAfterScrubbing = false
        receivesUpdates = live; pendingUpdate = nil; followsHead = true
        timeline = makeTimeline(snapshot); remainingBudget = timeline.duration; liveRemaining = 0
        publishProgress(); state = .playing
    }
    func configure(screenDistances: [Double]) {
        let cursor = timeline.frame(at: elapsed)
        timeline = RouteReplayTimeline(path: path, screenDistances: screenDistances)
        elapsed = cursor.map { timeline.time(for: $0) } ?? 0
        remainingBudget = max(0, timeline.duration-elapsed)
        publishProgress()
    }
    func update(_ points: [TrackPoint], live: Bool) {
        guard isPresenting else { return }
        if isScrubbing { pendingUpdate = (points, live); return }
        receivesUpdates = live
        let updated = RouteReplayPath(points: points)
        if updated.points.count > path.points.count,
           Array(updated.points.prefix(path.points.count).map { $0.id }) == path.points.map({ $0.id }) {
            let cursor = timeline.frame(at: elapsed)
            // At an old endpoint continue from that endpoint, not from the new end.
            let oldEnd = path.points.count-1
            path = updated; timeline = makeTimeline(updated)
            if let cursor = cursor {
                if cursor.from == oldEnd && cursor.to == oldEnd {
                    let anchor = RouteReplayFrame(from: oldEnd, to: oldEnd+1, fraction: 0, visible: true, opacity: 1)
                    elapsed = timeline.time(for: anchor)
                    if !path.connectsToPrevious[oldEnd+1] {
                        elapsed = timeline.time(for: RouteReplayFrame(from: oldEnd, to: oldEnd, fraction: 0, visible: false, opacity: 0))
                    }
                } else { elapsed = timeline.time(for: cursor) }
            }
            if state == .live { liveRemaining = 1 }
            pathChanged.send(); publishProgress()
        }
        if !live && state == .live { state = .playing; remainingBudget = max(1, liveRemaining) }
    }
    func userMovedMap() { if followsHead { followsHead = false } }
    func followHead() { followsHead = true; seekRequested.send() }
    func pause() {
        resumeAfterScrubbing = false
        if isRunning { publishProgress(); state = .paused }
    }
    func resume() {
        guard state == .paused else { return }
        if elapsed >= timeline.duration { finishAtEnd() }
        else { state = .playing }
    }
    func stop() {
        state = .idle; path = RouteReplayPath(points: []); elapsed = 0
        isScrubbing = false; resumeAfterScrubbing = false; pendingUpdate = nil; receivesUpdates = false
        timeline = makeTimeline(path); publishProgress()
    }
    private func finishAtEnd() {
        elapsed = timeline.duration; publishProgress()
        state = receivesUpdates ? .live : .finished
    }
    func finish() { if state == .playing { finishAtEnd() } }
    func advance(by seconds: Double) {
        guard isRunning, !isScrubbing, seconds.isFinite else { return }
        let delta = min(0.1, max(0, seconds))
        if state == .live {
            if liveRemaining > 0 {
                elapsed += (timeline.duration-elapsed) * min(1, delta/liveRemaining)
                liveRemaining = max(0, liveRemaining-delta)
            } else { elapsed = timeline.duration }
        } else {
            elapsed += (timeline.duration-elapsed) * min(1, delta/max(0.000001, remainingBudget))
            remainingBudget = max(0, remainingBudget-delta)
            if remainingBudget <= 0.000001 { finishAtEnd() }
        }
        if abs(elapsed-lastProgressTime) >= 0.1 || elapsed >= timeline.duration { publishProgress() }
    }
    func beginScrubbing() {
        guard isPresenting, !isScrubbing else { return }
        let wasRunning = isRunning
        pause(); resumeAfterScrubbing = wasRunning; isScrubbing = true
    }
    func seek(to fraction: Double) {
        guard isPresenting else { return }
        elapsed = timeline.scrubTime(fraction: fraction)
        remainingBudget = min(60, max(1, timeline.duration-elapsed))
        if state == .finished { state = .paused }
        publishProgress(); seekRequested.send()
    }
    func endScrubbing() {
        guard isScrubbing else { return }
        let atEnd = elapsed >= timeline.duration
        isScrubbing = false
        if let update = pendingUpdate { pendingUpdate = nil; self.update(update.0, live: update.1) }
        let shouldResume = resumeAfterScrubbing; resumeAfterScrubbing = false
        if atEnd { finishAtEnd() }
        else if shouldResume { resume() }
    }
    private func publishProgress() {
        lastProgressTime = elapsed
        progress.update(fraction: timeline.duration > 0 ? elapsed/timeline.duration : 0,
                        recordedAt: timeline.recordedTime(at: elapsed, path: path),
                        inGap: timeline.frame(at: elapsed)?.visible == false)
    }
}
