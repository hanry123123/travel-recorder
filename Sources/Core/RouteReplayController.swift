import Foundation
import Combine

/// Only the small progress control observes clock updates; the recording page does not.
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
    enum State { case idle, playing, paused, finished }
    @Published private(set) var state: State = .idle
    private(set) var path = RouteReplayPath(points: [])
    private(set) var runID = UUID()
    let progress = RouteReplayProgress()
    let seekRequested = PassthroughSubject<Void, Never>()
    private(set) var elapsed: Double = 0
    private(set) var timeline = RouteReplayTimeline(path: RouteReplayPath(points: []), screenDistances: [])
    private var lastProgressTime: Double = -.infinity
    private var resumeAfterScrubbing = false
    private(set) var isScrubbing = false
    var isPresenting: Bool { state != .idle }
    func start(_ points: [TrackPoint]) {
        let snapshot = RouteReplayPath(points: points)
        guard !snapshot.points.isEmpty else { return }
        path = snapshot; runID = UUID(); elapsed = 0; isScrubbing = false; resumeAfterScrubbing = false
        timeline = RouteReplayTimeline(path: snapshot, screenDistances: Array(repeating: 0, count: max(0, snapshot.points.count-1)))
        publishProgress(); state = .playing
    }
    func configure(screenDistances: [Double]) {
        timeline = RouteReplayTimeline(path: path, screenDistances: screenDistances)
        publishProgress()
    }
    func pause() {
        resumeAfterScrubbing = false
        if state == .playing { publishProgress(); state = .paused }
    }
    func resume() { if state == .paused { state = .playing } }
    func stop() {
        state = .idle; path = RouteReplayPath(points: []); elapsed = 0
        isScrubbing = false; resumeAfterScrubbing = false
        timeline = RouteReplayTimeline(path: path, screenDistances: [])
        publishProgress()
    }
    func finish() {
        if state == .playing { elapsed = timeline.duration; publishProgress(); state = .finished }
    }
    func advance(by seconds: Double) {
        guard state == .playing, !isScrubbing, seconds.isFinite else { return }
        elapsed = min(timeline.duration, elapsed+min(0.1, max(0, seconds)))
        if elapsed-lastProgressTime >= 0.1 || elapsed >= timeline.duration { publishProgress() }
    }
    func beginScrubbing() {
        guard isPresenting, !isScrubbing else { return }
        let wasPlaying = state == .playing
        pause(); resumeAfterScrubbing = wasPlaying; isScrubbing = true
    }
    func seek(to fraction: Double) {
        guard isPresenting else { return }
        elapsed = timeline.scrubTime(fraction: fraction)
        if state == .finished { state = .paused }
        publishProgress(); seekRequested.send()
    }
    func endScrubbing() {
        guard isScrubbing else { return }
        isScrubbing = false
        let shouldResume = resumeAfterScrubbing; resumeAfterScrubbing = false
        if elapsed >= timeline.duration { state = .finished }
        else if shouldResume { state = .playing }
    }
    private func publishProgress() {
        lastProgressTime = elapsed
        progress.update(fraction: timeline.duration > 0 ? elapsed/timeline.duration : 0,
                        recordedAt: timeline.recordedTime(at: elapsed, path: path),
                        inGap: timeline.frame(at: elapsed)?.visible == false)
    }
}
