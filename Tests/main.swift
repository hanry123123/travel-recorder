import Foundation
import CoreData
import ImageIO
import CoreGraphics

var checks = 0
func check(_ condition: Bool, _ description: String) {
    checks += 1
    guard condition else { fputs("FAIL: \(description)\n", stderr); exit(1) }
    print("PASS: \(description)")
}
func mustThrow(_ description: String, _ operation: () throws -> Void) {
    do { try operation(); check(false, description) } catch { check(true, description) }
}
let base = Date(timeIntervalSince1970: 1_800_000_000)
func sample(_ seconds: Double, _ lat: Double = 31, _ lon: Double = 121, accuracy: Double = 8) -> LocationSample {
    LocationSample(coordinate: Coordinate(latitude: lat, longitude: lon), timestamp: base.addingTimeInterval(seconds), accuracy: accuracy)
}
var trip = Trip(now: base)
let first = RecorderLogic.accept(sample(1), trip: trip, previous: nil, now: base.addingTimeInterval(1))!
trip = first.0
check(trip.distance == 0, "first point does not invent distance")
check(RecorderLogic.accept(sample(1), trip: trip, previous: first.1, now: base.addingTimeInterval(2)) == nil, "duplicate timestamp rejected")
check(RecorderLogic.accept(sample(-1), trip: trip, previous: first.1, now: base) == nil, "pre-session location rejected")
check(RecorderLogic.accept(sample(2, 91), trip: trip, previous: first.1, now: base.addingTimeInterval(2)) == nil, "invalid latitude rejected")
check(RecorderLogic.accept(sample(2, 31, .nan), trip: trip, previous: first.1, now: base.addingTimeInterval(2)) == nil, "non-finite longitude rejected")
check(RecorderLogic.accept(sample(2, accuracy: -1), trip: trip, previous: first.1, now: base.addingTimeInterval(2)) == nil, "invalid accuracy rejected")
check(RecorderLogic.accept(sample(2, accuracy: 101), trip: trip, previous: first.1, now: base.addingTimeInterval(2)) == nil, "inaccurate fix rejected")
check(RecorderLogic.accept(sample(500), trip: trip, previous: first.1, now: base) == nil, "future fix rejected")
check(RecorderLogic.accept(sample(2), trip: trip, previous: first.1, now: base.addingTimeInterval(500)) == nil, "stale fix rejected")
check(RecorderLogic.accept(sample(3), trip: trip, previous: first.1, now: base.addingTimeInterval(3)) == nil, "stationary jitter does not add distance")
let second = RecorderLogic.accept(sample(21, 31.0002), trip: trip, previous: first.1, now: base.addingTimeInterval(21))!
trip = second.0
check(trip.distance > 20 && trip.distance < 25, "actual movement contributes geodesic distance")
check(second.1.segmentID == first.1.segmentID, "continuous movement stays in segment")
check(RecorderLogic.accept(sample(22, 35), trip: trip, previous: second.1, now: base.addingTimeInterval(22)) == nil, "impossible GPS jump rejected")
let paused = try RecorderLogic.pause(trip, at: base.addingTimeInterval(30))
check(paused.status == .paused && paused.currentSegment == nil, "pause closes active recording")
check(paused.duration(at: base.addingTimeInterval(600)) == 30, "paused time excluded from duration")
check(RecorderLogic.accept(sample(40, 31.01), trip: paused, previous: second.1, now: base.addingTimeInterval(40)) == nil, "no samples accepted while paused")
mustThrow("double pause rejected") { _ = try RecorderLogic.pause(paused, at: base) }
let resumed = try RecorderLogic.resume(paused, at: base.addingTimeInterval(100))
check(resumed.currentSegment != trip.currentSegment, "resume creates separate segment")
check(RecorderLogic.accept(sample(90, 32), trip: resumed, previous: second.1, now: base.addingTimeInterval(101)) == nil, "queued pre-resume location rejected")
let afterPause = RecorderLogic.accept(sample(101, 32), trip: resumed, previous: second.1, now: base.addingTimeInterval(101))!
check(afterPause.0.distance == trip.distance, "travel during pause does not count or connect")
let gap = RecorderLogic.accept(sample(300, 33), trip: afterPause.0, previous: afterPause.1, now: base.addingTimeInterval(300))!
check(gap.1.segmentID != afterPause.1.segmentID, "signal loss creates a route gap")
check(gap.0.distance == afterPause.0.distance, "unobserved gap excluded from mileage")
let recovered = try RecorderLogic.recover(gap.0)
check(recovered.status == .interrupted, "process restart marks interrupted")
check(recovered.intervals.last?.end == base.addingTimeInterval(300), "recovery ends at last saved position")
let noFix = try RecorderLogic.recover(Trip(now: base))
check(noFix.duration(at: base.addingTimeInterval(10000)) == 0, "restart without first fix invents no elapsed recording")
let ended = try RecorderLogic.finish(recovered, at: base.addingTimeInterval(400))
check(ended.status == .ended && ended.endedAt != nil, "finish saves terminal state")
mustThrow("ended trip cannot resume") { _ = try RecorderLogic.resume(ended, at: base) }
mustThrow("ended trip cannot finish twice") { _ = try RecorderLogic.finish(ended, at: base) }
check(PhotoMatching.belongs(capturedAt: base.addingTimeInterval(50), to: ended, now: base), "photos during pause still belong to journey")
check(!PhotoMatching.belongs(capturedAt: base.addingTimeInterval(-1), to: ended, now: base), "older photos excluded from automatic scan")
check(!PhotoMatching.belongs(capturedAt: base.addingTimeInterval(401), to: ended, now: base), "photos after finish excluded")
check(!PhotoMatching.shouldImport(assetID: "a", capturedAt: base, trip: ended, now: base, existing: ["a"], excluded: []), "existing photo not imported twice")
check(!PhotoMatching.shouldImport(assetID: "a", capturedAt: base, trip: ended, now: base, existing: [], excluded: ["a"]), "removed automatic photo stays excluded")
check(Coordinate(latitude: 0, longitude: 179.999).distance(to: Coordinate(latitude: 0, longitude: -179.999)) < 225, "dateline distance takes short path")
check(Coordinate(latitude: -33.86, longitude: 151.21).isValid, "southern hemisphere coordinate supported")

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let database = root.appendingPathComponent("fixture.sqlite")
var repo: CoreDataRepository? = try CoreDataRepository(url: database)
try repo!.commit([StoredRecord(ended), StoredRecord(first.1), StoredRecord(second.1)], deleting: [])
var entry = DiaryEntry(tripID: trip.id, coordinate: first.1.coordinate, title: "湖边", text: "风很轻。", createdAt: base, updatedAt: base)
try repo!.save(entry)
entry.text = "再次补写：下次还来。"
try repo!.save(entry)
check(try repo!.load(DiaryEntry.self).count == 1, "editing diary updates instead of duplicating")
repo = nil
repo = try CoreDataRepository(url: database)
check(try repo!.load(Trip.self).first!.status == .ended, "trip survives reopening SQLite store")
check(try repo!.load(TrackPoint.self).count == 2, "incremental track points survive reopen")
check(try repo!.load(DiaryEntry.self).first!.text == entry.text, "Unicode diary edits persist")
let other = try RecorderLogic.finish(Trip(now: base.addingTimeInterval(1000)), at: base.addingTimeInterval(1100))
try repo!.save(other)
check(try repo!.load(TrackPoint.self, tripID: other.id).isEmpty, "journeys do not share track points")
var changed = ended; changed.title = "跨天的旅程"; changed.reflection = "值得纪念"
try repo!.save(changed)
check(try repo!.load(TrackPoint.self, tripID: trip.id).count == 2, "editing trip preserves its recorded route")
var invalid = first.1; invalid.coordinate.latitude = .nan
mustThrow("invalid encoded value cannot enter a transaction") { try repo!.commit([StoredRecord(changed), StoredRecord(invalid)], deleting: []) }
check(try repo!.load(TrackPoint.self, tripID: trip.id).count == 2, "failed encoding does not corrupt saved points")

let files = try PhotoFileStore(directory: root.appendingPathComponent("photos"))
let color = CGColorSpaceCreateDeviceRGB()
let context = CGContext(data: nil, width: 100, height: 80, bitsPerComponent: 8, bytesPerRow: 400, space: color, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(red: 0.1, green: 0.5, blue: 0.9, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: 100, height: 80))
let original = NSMutableData()
let destination = CGImageDestinationCreateWithData(original, "public.jpeg" as CFString, 1, nil)!
let gps: [String: Any] = [kCGImagePropertyGPSLatitude as String: 33.86, kCGImagePropertyGPSLatitudeRef as String: "S", kCGImagePropertyGPSLongitude as String: 151.21, kCGImagePropertyGPSLongitudeRef as String: "E"]
CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImagePropertyGPSDictionary: gps, kCGImagePropertyOrientation: 6] as CFDictionary)
check(CGImageDestinationFinalize(destination), "photo fixture contains actual JPEG and EXIF")
let originalURL = root.appendingPathComponent("source.jpg")
try (original as Data).write(to: originalURL)
let imported = try files.prepare(data: Data(contentsOf: originalURL))
check(imported.coordinate?.latitude == -33.86 && imported.coordinate?.longitude == 151.21, "GPS hemisphere extracted before image conversion")
check(FileManager.default.fileExists(atPath: files.url(imported.imageFile).path), "independent viewing image saved")
check(FileManager.default.fileExists(atPath: files.url(imported.thumbnailFile).path), "independent thumbnail saved")
try FileManager.default.removeItem(at: originalURL)
check(CGImageSourceCreateWithURL(files.url(imported.imageFile) as CFURL, nil) != nil, "photo remains readable after original deletion")
let source = CGImageSourceCreateWithURL(files.url(imported.imageFile) as CFURL, nil)!
let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
check((props[kCGImagePropertyPixelWidth] as? Int) == 80 && (props[kCGImagePropertyPixelHeight] as? Int) == 100, "EXIF image orientation is preserved visually")
check(PhotoFileStore.coordinate(in: [:]) == nil, "missing GPS stays unknown rather than zero zero")
check(PhotoFileStore.coordinate(in: [kCGImagePropertyGPSDictionary as String: [kCGImagePropertyGPSLatitude as String: 10, kCGImagePropertyGPSLongitude as String: 10]]) == nil, "GPS without hemisphere is not guessed")
let before = try FileManager.default.contentsOfDirectory(atPath: files.directory.path).count
mustThrow("corrupt photo fails import") { _ = try files.prepare(data: Data("broken image".utf8)) }
check(try FileManager.default.contentsOfDirectory(atPath: files.directory.path).count == before, "failed photo import leaves no partial files")
let attachment = PhotoAttachment(tripID: trip.id, assetID: "camera-1", capturedAt: base, importedAt: base, coordinate: imported.coordinate, originalCoordinate: imported.coordinate, imageFile: imported.imageFile, thumbnailFile: imported.thumbnailFile)
try repo!.save(attachment)
check(try repo!.load(PhotoAttachment.self).first!.imageFile == imported.imageFile, "photo-to-trip link persists")
let photoDiary = DiaryEntry(tripID: trip.id, photoID: attachment.id, coordinate: attachment.coordinate, title: "照片的故事", text: "拍摄当天", createdAt: base, updatedAt: base)
let newLocation = Coordinate(latitude: 39.9, longitude: 116.4)
let placed = PhotoEditing.place(attachment, at: newLocation, diaries: [photoDiary, entry])!
check(placed.0.coordinate == newLocation && placed.0.manuallyPlaced, "manual photo placement saves chosen location")
check(placed.0.originalCoordinate == imported.coordinate, "manual placement preserves original GPS metadata")
check(placed.1.count == 1 && placed.1[0].id == photoDiary.id && placed.1[0].coordinate == newLocation, "moving a photo moves only its own attached diary")
check(placed.1[0].text == photoDiary.text, "moving a photo preserves diary text")
check(PhotoEditing.place(attachment, at: Coordinate(latitude: .nan, longitude: 0), diaries: [photoDiary]) == nil, "invalid manual placement rejected")
try repo!.commit([StoredRecord(placed.0), StoredRecord(placed.1[0])], deleting: [])
check(try repo!.load(DiaryEntry.self, tripID: trip.id).first(where: { $0.id == photoDiary.id })?.coordinate == newLocation, "photo and journal relocation persist together")
try repo!.deleteTrip(trip.id)
check(try repo!.load(TrackPoint.self, tripID: trip.id).isEmpty, "deleting journey removes its points")
check(try repo!.load(DiaryEntry.self, tripID: trip.id).isEmpty, "deleting journey removes its diary")
check(try repo!.load(PhotoAttachment.self, tripID: trip.id).isEmpty, "deleting journey removes its photo records")
check(try repo!.load(Trip.self).count == 1, "deleting one journey preserves another")
// Map datum regression: known control, overseas non-conversion, old manual pins.
let beijing = Coordinate(latitude: 39.908823, longitude: 116.397470)
let beijingMap = MapCoordinates.display(beijing, mode: .automatic)
let expectedMap = Coordinate(latitude: 39.91022649807321, longitude: 116.4037135824225)
check(beijingMap.distance(to: expectedMap) < 0.05, "Beijing WGS84 projects to independent GCJ control")
check(beijing.distance(to: beijingMap) > 400, "regression reproduces hundreds-of-meters raw GPS/map mismatch")
check(MapCoordinates.display(beijing, mode: .original) == beijing, "original mode preserves coordinates exactly")
let mainlandCities: [(String, Coordinate)] = [
    ("Shanghai", Coordinate(latitude: 31.2304, longitude: 121.4737)),
    ("Shenzhen", Coordinate(latitude: 22.5431, longitude: 114.0579)),
    ("Chengdu", Coordinate(latitude: 30.5728, longitude: 104.0668)),
    ("Sanya", Coordinate(latitude: 18.2528, longitude: 109.5119)),
    ("Urumqi", Coordinate(latitude: 43.8256, longitude: 87.6168))]
for (name, coordinate) in mainlandCities {
    let display = MapCoordinates.display(coordinate, mode: .automatic)
    check(display.distance(to: coordinate) > 100, "mainland map conversion: \(name)")
    let saved = MapCoordinates.storedSelection(display, mode: .automatic)
    check(saved.datum == .wgs84 && saved.distance(to: coordinate) < 0.02, "tap inverse round trip: \(name)")
    check(MapCoordinates.display(saved, mode: .automatic).distance(to: display) < 0.02, "saved selection redraw stays under tap: \(name)")
}
let outside: [(String, Coordinate)] = [
    ("Hong Kong", Coordinate(latitude: 22.3193, longitude: 114.1694)),
    ("Macao", Coordinate(latitude: 22.1987, longitude: 113.5439)),
    ("Taipei", Coordinate(latitude: 25.0330, longitude: 121.5654)),
    ("Seoul", Coordinate(latitude: 37.5665, longitude: 126.978)),
    ("Tokyo", Coordinate(latitude: 35.6762, longitude: 139.6503)),
    ("Hanoi", Coordinate(latitude: 21.0285, longitude: 105.8542)),
    ("Bangkok", Coordinate(latitude: 13.7563, longitude: 100.5018)),
    ("Ulaanbaatar", Coordinate(latitude: 47.9184, longitude: 106.9177)),
    ("Kathmandu", Coordinate(latitude: 27.7172, longitude: 85.3240)),
    ("Sydney", Coordinate(latitude: -33.8688, longitude: 151.2093)),
    ("London", Coordinate(latitude: 51.5074, longitude: -0.1278)),
    ("New York", Coordinate(latitude: 40.7128, longitude: -74.006)),
    ("Dateline", Coordinate(latitude: 0, longitude: -179.999))]
for (name, coordinate) in outside {
    check(MapCoordinates.display(coordinate, mode: .automatic) == coordinate, "outside mainland remains unchanged: \(name)")
    check(MapCoordinates.storedSelection(coordinate, mode: .automatic).distance(to: coordinate) < 0.001, "outside map selection unchanged: \(name)")
}
let oldCoordinateData = Data("{\"latitude\":39.908823,\"longitude\":116.397470}".utf8)
let decodedOldCoordinate = try JSONDecoder().decode(Coordinate.self, from: oldCoordinateData)
check(decodedOldCoordinate.datum == nil && decodedOldCoordinate == beijing, "legacy coordinate JSON decodes without migration")
var oldManual = attachment
oldManual.coordinate = beijingMap; oldManual.manuallyPlaced = true
check(MapCoordinates.display(oldManual.mapCoordinate!, mode: .automatic).distance(to: beijingMap) < 0.001, "legacy manually placed photo is not shifted twice")
var oldDiary = entry; oldDiary.coordinate = beijingMap; oldDiary.photoID = nil
check(MapCoordinates.display(oldDiary.mapCoordinate!, mode: .automatic).distance(to: beijingMap) < 0.001, "legacy tapped diary stays in place")
var newManual = oldManual
newManual.coordinate = MapCoordinates.storedSelection(beijingMap, mode: .automatic)
let newManualDecoded = try JSONDecoder().decode(PhotoAttachment.self, from: JSONEncoder().encode(newManual))
check(newManualDecoded.coordinate?.datum == .wgs84, "new manual photo datum survives Codable persistence")
check(MapCoordinates.display(newManualDecoded.mapCoordinate!, mode: .automatic).distance(to: beijingMap) < 0.02, "new manual photo restores in the right place")
let mainlandOverride = MapCoordinates.display(beijing, mode: .mainland)
check(mainlandOverride.distance(to: beijingMap) < 0.001, "manual mainland setting agrees with auto inland")
check(first.1.coordinate == Coordinate(latitude: 31, longitude: 121), "display conversion never rewrites stored GPS points")
// Chronological replay, gaps and lifecycle. Synthetic pixel distances control pacing.
let replayTrip = UUID(), segmentA = UUID(), segmentB = UUID()
func replayPoint(_ time: Double, _ longitude: Double, _ segment: UUID) -> TrackPoint {
    TrackPoint(tripID: replayTrip, segmentID: segment, coordinate: Coordinate(latitude: 31, longitude: longitude), timestamp: base.addingTimeInterval(time), accuracy: 5)
}
let r0 = replayPoint(0, 121, segmentA), r1 = replayPoint(10, 121.001, segmentA)
let r2 = replayPoint(20, 121, segmentA), r3 = replayPoint(40, 121.1, segmentB)
let r4 = replayPoint(50, 121.101, segmentB)
let replayPath = RouteReplayPath(points: [r4, r1, r0, r3, r2])
check(replayPath.points.map { $0.id } == [r0, r1, r2, r3, r4].map { $0.id }, "replay follows timestamps, including revisiting the same place")
check(replayPath.connectsToPrevious == [false, true, true, false, true], "replay preserves the pause segment break")
let replayTimeline = RouteReplayTimeline(path: replayPath, screenDistances: [180, 180, 100000, 180])
check(abs(replayTimeline.duration-18.15) < 0.001, "moderate 36-point/sec speed excludes the unrecorded gap distance")
check(replayTimeline.frame(at: 0)?.from == 0, "replay starts at the first recorded point")
let outbound = replayTimeline.frame(at: 3.3)!
check(outbound.from == 0 && outbound.to == 1 && abs(outbound.fraction-0.5) < 0.001, "outbound leg advances smoothly to its midpoint")
let inbound = replayTimeline.frame(at: 8.3)!
check(inbound.from == 1 && inbound.to == 2 && abs(inbound.fraction-0.5) < 0.001, "return leg retains its original travel order")
check(replayTimeline.frame(at: 11.0)?.visible == false, "light disappears at a pause instead of flying over the gap")
check(replayTimeline.frame(at: 11.6)?.from == 3, "next segment restarts at its own first recorded position")
let finalFrame = replayTimeline.frame(at: replayTimeline.duration+100)!
check(finalFrame.from == 4 && finalFrame.to == 4, "playback clamps to the actual last point")
check(replayTimeline.frame(at: -10)?.from == 0, "negative replay time is safely clamped")
check(replayTimeline.frame(at: .nan)?.from == 0, "invalid replay clock is safely clamped")
check(replayTimeline.frame(at: 0)?.opacity == 0 && replayTimeline.frame(at: 0.3)?.opacity == 1, "light fades in gently rather than flashing")
let emptyTimeline = RouteReplayTimeline(path: RouteReplayPath(points: []), screenDistances: [])
check(emptyTimeline.duration == 0 && emptyTimeline.frame(at: 0) == nil, "empty journey creates no light or timer timeline")
let singleTimeline = RouteReplayTimeline(path: RouteReplayPath(points: [r0]), screenDistances: [])
check(singleTimeline.duration == 2 && singleTimeline.frame(at: 1)?.from == 0, "one point is shown briefly without inventing motion")
let shortTimeline = RouteReplayTimeline(path: RouteReplayPath(points: [r0,r1]), screenDistances: [3])
check(shortTimeline.duration == 14, "very short journeys are not replayed in a blink")
let longTimeline = RouteReplayTimeline(path: RouteReplayPath(points: [r0,r1]), screenDistances: [7200])
check(longTimeline.duration == 202, "long winding journeys take longer instead of becoming too fast")
var badReplayPoint = r1; badReplayPoint.coordinate.latitude = .nan
let invalidPath = RouteReplayPath(points: [r0, badReplayPoint, r2])
check(invalidPath.points.count == 2 && !invalidPath.connectsToPrevious[1], "invalid intermediate GPS point cannot create a replay bridge")
let late = replayPoint(200, 121.02, segmentA)
check(!RouteReplayPath(points: [r0, late]).connectsToPrevious[1], "long signal loss cannot be bridged even with a reused segment ID")
var foreignTrip = r1; foreignTrip.tripID = UUID()
check(!RouteReplayPath(points: [r0, foreignTrip]).connectsToPrevious[1], "different journeys cannot be connected in replay")
let sameTime = replayPoint(0, 121.002, segmentA)
check(RouteReplayPath(points: [sameTime,r0]).points.first?.id == sameTime.id, "equal timestamps retain input order")
check(abs(ReplayGeometry.shortestDelta(-359.8, worldWidth: 360)-0.2) < 1e-8, "eastward dateline replay takes the short path")
check(abs(ReplayGeometry.shortestDelta(359.8, worldWidth: 360)+0.2) < 1e-8, "westward dateline replay takes the short path")
let replayController = RouteReplayController()
replayController.start([])
check(replayController.state == .idle, "empty replay request stays idle")
var livePoints = [r0,r1]
replayController.start(livePoints)
let firstRunID = replayController.runID
livePoints.append(r2)
check(replayController.path.points.count == 2 && replayController.state == .playing, "new GPS points do not move the frozen replay endpoint")
replayController.pause()
check(replayController.state == .paused && replayController.runID == firstRunID, "pause retains the current replay run")
replayController.resume()
check(replayController.state == .playing && replayController.runID == firstRunID, "resume continues rather than creating a new run")
replayController.finish()
check(replayController.state == .finished && replayController.isPresenting, "replay finishes once and can leave a final marker")
replayController.start(livePoints)
check(replayController.runID != firstRunID && replayController.path.points.count == 3, "replay again takes a fresh ordered snapshot")
replayController.stop()
check(replayController.state == .idle && replayController.path.points.isEmpty, "leaving or stopping clears playback state")
replayController.resume()
check(replayController.state == .idle, "a stopped playback cannot silently resume")
check(livePoints.map { $0.id } == [r0,r1,r2].map { $0.id }, "replay never changes the recorder's point collection")
// Visible sparks use independent flight, lifetime and replay-time anchoring.
func sparkLocation(_ time: Double) -> (point: CGPoint, section: Int)? {
    (CGPoint(x: 80+time*36, y: 90), 0)
}
let sparkFrame = ReplaySparks.frame(at: 2, locate: sparkLocation)
check(sparkFrame.count >= 12 && sparkFrame.count <= 51, "visible sparks have bounded particle count")
check(sparkFrame.contains { abs($0.tip.y-90) > 10 }, "sparks fly off the route rather than forming a dotted halo")
check(sparkFrame.allSatisfy { hypot($0.tip.x-$0.tail.x, $0.tip.y-$0.tail.y).isFinite && $0.heat >= 0 && $0.heat <= 1 }, "physical spark trails and cooling values stay finite")
check(sparkFrame == ReplaySparks.frame(at: 2, locate: sparkLocation), "pause and redraw freeze every particle exactly")
check(sparkFrame != ReplaySparks.frame(at: 2.1, locate: sparkLocation), "advancing the clock moves sparks")
let shifted = ReplaySparks.frame(at: 2) { time -> (point: CGPoint, section: Int)? in
    let location = sparkLocation(time)!
    return (CGPoint(x: location.point.x+50, y: location.point.y-30), location.section)
}
check(zip(sparkFrame, shifted).allSatisfy { abs($1.tip.x-$0.tip.x-50)<0.001 && abs($1.tip.y-$0.tip.y+30)<0.001 }, "panning reprojects all particle origins together")
check(ReplaySparks.frame(at: 2) { _ in nil }.isEmpty, "recording gaps show no sparks")
let afterBreak = ReplaySparks.frame(at: 2) { time -> (point: CGPoint, section: Int)? in
    (CGPoint(x: 0, y: 0), time < 1.99 ? 0 : 1)
}
check(afterBreak.allSatisfy { $0.opacity == 0 }, "new section cannot retain sparks from a previous section")
check(ReplaySparks.frame(at: 3.2, emissionEnd: 2, locate: sparkLocation).isEmpty, "sparks fully extinguish before finished playback freezes")
let fadingEarly = ReplaySparks.frame(at: 0.15, emissionEnd: 0, locate: sparkLocation)
let fadingLate = ReplaySparks.frame(at: 0.4, emissionEnd: 0, locate: sparkLocation)
check(fadingEarly.count == 1 && fadingLate.count == 1 && fadingEarly[0].opacity > fadingLate[0].opacity, "individual sparks dim as they age")
check(abs(fadingLate[0].tip.x-80) > abs(fadingEarly[0].tip.x-80), "an individual spark travels outward during its life")
let reducedSparks = ReplaySparks.frame(at: 2, reducedMotion: true, locate: sparkLocation)
check(!reducedSparks.isEmpty && reducedSparks.count <= 7, "reduce motion retains sparse short-lived sparks")
check(ReplaySparks.frame(at: .nan, locate: sparkLocation).isEmpty, "invalid particle clock is safely rejected")
check(ReplaySparks.frame(at: -1, locate: sparkLocation).isEmpty, "restart cannot display particles from negative time")
check(ReplaySparks.frame(at: 100000, locate: sparkLocation).count <= 51, "long playback does not accumulate particles")
// Scrubbing uses the same replay frame for the displayed capture time and map position.
check(abs(replayTimeline.recordedTime(at: 3.3, path: replayPath)!.timeIntervalSince(base)-5) < 0.001, "outbound map midpoint displays the corresponding capture time")
check(abs(replayTimeline.recordedTime(at: 8.3, path: replayPath)!.timeIntervalSince(base)-15) < 0.001, "revisited coordinates retain their later capture time")
let gapSeekTime = replayTimeline.scrubTime(fraction: 11.0/replayTimeline.duration)
check(replayTimeline.frame(at: gapSeekTime)!.visible, "scrubbing into a recording gap snaps to a visible recorded position")
check(replayTimeline.scrubTime(fraction: -1) == 0 && replayTimeline.scrubTime(fraction: 2) == replayTimeline.duration, "scrub endpoints clamp safely")
check(replayTimeline.scrubTime(fraction: .nan) == 0, "invalid scrub value is safe")
replayController.start(replayPath.points)
replayController.configure(screenDistances: [180,180,100000,180])
replayController.beginScrubbing()
check(replayController.state == .paused && replayController.isScrubbing, "touching progress pauses playback")
replayController.seek(to: 3.3/replayTimeline.duration)
check(abs(replayController.elapsed-3.3) < 0.001 && abs(replayController.progress.position.recordedAt!.timeIntervalSince(base)-5) < 0.001, "seek updates map clock and progress time together")
let scrubbedTime = replayController.elapsed
replayController.advance(by: 0.1)
check(replayController.elapsed == scrubbedTime, "display ticks cannot fight a held slider")
replayController.endScrubbing()
check(replayController.state == .playing, "releasing a playing scrub resumes from its new position")
replayController.pause(); replayController.beginScrubbing(); replayController.seek(to: 0.7); replayController.endScrubbing()
check(replayController.state == .paused, "dragging while paused preserves pause")
replayController.beginScrubbing(); replayController.seek(to: 0.2); replayController.endScrubbing()
check(abs(replayController.progress.position.fraction-0.2) < 0.001, "backward scrubbing updates progress")
replayController.beginScrubbing(); replayController.seek(to: 1); replayController.endScrubbing()
check(replayController.state == .finished && replayController.progress.position.recordedAt == r4.timestamp, "dragging to end shows actual final capture time")
replayController.beginScrubbing(); replayController.seek(to: 0.4); replayController.endScrubbing()
check(replayController.state == .paused && replayController.progress.position.fraction == 0.4, "finished replay can scrub back without resetting to start")
replayController.resume(); replayController.beginScrubbing(); replayController.pause(); replayController.endScrubbing()
check(replayController.state == .paused, "background interruption during drag cannot auto-resume")
replayController.start([r0,r1]); replayController.configure(screenDistances: [180])
check(replayController.elapsed == 0 && replayController.progress.position.fraction == 0, "new replay resets progress and capture time")
replayController.advance(by: 0.033); replayController.pause()
check(abs(replayController.progress.position.fraction-replayController.elapsed/replayController.timeline.duration) < 0.000001, "pausing flushes throttled progress to the exact map position")
replayController.stop()
check(replayController.progress.position.recordedAt == nil && replayController.progress.position.fraction == 0, "stop clears progress and timestamp")
check(singleTimeline.recordedTime(at: 1, path: RouteReplayPath(points: [r0])) == r0.timestamp, "single-point route scrubs without inventing time or travel")
// Manual map exploration is sticky across location and unrelated UI updates.
var mapFollow = MapFollowState()
check(mapFollow.shouldFollow(enabled: true, replaying: false), "initial recording map can follow")
mapFollow.userMoved()
check(!mapFollow.shouldFollow(enabled: true, replaying: false), "gesture immediately overrides a stale SwiftUI follow flag")
for _ in 0..<100 { _ = mapFollow.consumeRecenter(0) }
check(!mapFollow.shouldFollow(enabled: true, replaying: false), "GPS callbacks and body refreshes cannot reenable follow")
check(mapFollow.consumeRecenter(1) && mapFollow.shouldFollow(enabled: true, replaying: false), "explicit location button reenables follow")
mapFollow.userMoved()
check(!mapFollow.consumeRecenter(1) && mapFollow.manuallyMoved, "old location requests cannot undo a new gesture")
check(mapFollow.consumeRecenter(2), "repeated location button works without waiting for another GPS sample")
check(!mapFollow.shouldFollow(enabled: true, replaying: true), "replay prevents GPS recentering")
check(!mapFollow.shouldFollow(enabled: false, replaying: false), "whole-route overview remains unfollowed")
var coverA = attachment, coverB = attachment, coverC = attachment, coverD = attachment
coverA.id = UUID(); coverB.id = UUID(); coverC.id = UUID(); coverD.id = UUID()
coverA.capturedAt = base; coverB.capturedAt = base.addingTimeInterval(10)
coverC.capturedAt = base.addingTimeInterval(20); coverD.capturedAt = base.addingTimeInterval(30)
check(MemoryPresentation.coverPhotos([coverD,coverC,coverB,coverA]).map { $0.id } == [coverA.id,coverB.id,coverC.id], "memory card displays at most three photos in capture order")
check(MemoryPresentation.coverPhotos([]).isEmpty, "empty photo card uses its empty state")
check(MemoryPresentation.coverPhotos([coverA]).count == 1 && MemoryPresentation.coverPhotos([coverA,coverB]).count == 2, "one and two photo layouts do not invent duplicates")
coverB.capturedAt = coverA.capturedAt
check(MemoryPresentation.coverPhotos([coverB,coverA]).map { $0.id } == [coverB.id,coverA.id], "photos with equal times keep input order")
check(MemoryPresentation.placeLabel(locality: "上海", district: "黄浦区", name: "外滩", region: nil) == "上海·外滩", "endpoint label combines city and actual place")
check(MemoryPresentation.placeLabel(locality: "上海", district: nil, name: "上海", region: nil) == "上海", "endpoint label removes duplicate names")
check(MemoryPresentation.placeLabel(locality: nil, district: nil, name: nil, region: nil) == nil, "failed geocoding cannot invent a place name")
check(MemoryPresentation.fallbackPlace(nil) == "待记录", "empty journey shows pending endpoints")
check(MemoryPresentation.fallbackPlace(Coordinate(latitude: 31.234, longitude: 121.456)) == "31.234, 121.456", "offline endpoint fallback is an actual coordinate")
check(MemoryPresentation.placeKey(Coordinate(latitude: 31.23456, longitude: 121.45678)) == "31.2346,121.4568", "place cache keys are stable and locale independent")
// Real SQLite delete regression: reopening must not resurrect deleted memories.
repo = nil; repo = try CoreDataRepository(url: database)
check(try repo!.load(Trip.self).map { $0.id } == [other.id], "deleted memory stays deleted after repository reopen")
check(try repo!.load(PhotoAttachment.self, tripID: trip.id).isEmpty && repo!.load(DiaryEntry.self, tripID: trip.id).isEmpty, "deleted memory photo and diary records remain removed")
check(FileManager.default.fileExists(atPath: files.url(imported.imageFile).path), "repository deletion does not operate on arbitrary image files")
let report: [String: Any] = ["status":"PASS", "checks":checks, "tested":"production core logic, SQLite persistence, ImageIO import", "ios14_device_tested":false]
try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys]).write(to: root.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("report.json"))
print("FIXTURES PASS: \(checks) checks; device behavior still pending")
