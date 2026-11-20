import Foundation
import UIKit
import Combine
import UserNotifications

final class ReminderRouter: ObservableObject {
    static let shared = ReminderRouter()
    @Published var tripID: UUID?
    static func tripID(from info: [AnyHashable: Any]) -> UUID? {
        guard info["kind"] as? String == "trip-inactivity", let value = info["tripID"] as? String else { return nil }
        return UUID(uuidString: value)
    }
}
final class TravelAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           let id = ReminderRouter.tripID(from: response.notification.request.content.userInfo) {
            DispatchQueue.main.async { ReminderRouter.shared.tripID = id }
        }
        completionHandler()
    }
}
protocol TripNotificationCenter {
    func permission(_ completion: @escaping (Bool) -> Void)
    func requestPermission(_ completion: @escaping (Bool, Error?) -> Void)
    func add(_ request: UNNotificationRequest, completion: @escaping (Error?) -> Void)
    func removePending(_ ids: [String])
    func removeDelivered(_ ids: [String])
}
private final class SystemTripNotificationCenter: TripNotificationCenter {
    private let center = UNUserNotificationCenter.current()
    func permission(_ completion: @escaping (Bool) -> Void) {
        center.getNotificationSettings { completion($0.authorizationStatus == .authorized || $0.authorizationStatus == .provisional) }
    }
    func requestPermission(_ completion: @escaping (Bool, Error?) -> Void) { center.requestAuthorization(options: [.alert, .sound], completionHandler: completion) }
    func add(_ request: UNNotificationRequest, completion: @escaping (Error?) -> Void) { center.add(request, withCompletionHandler: completion) }
    func removePending(_ ids: [String]) { center.removePendingNotificationRequests(withIdentifiers: ids) }
    func removeDelivered(_ ids: [String]) { center.removeDeliveredNotifications(withIdentifiers: ids) }
}
final class TripReminderService {
    private let center: TripNotificationCenter
    private let defaults: UserDefaults
    private let key = "tripInactivityStateV1"
    private let requestIdentifier = "travel.trip.inactivity"
    private var state: InactivityReminderState?
    private var generation = UUID()
    private var scheduledDue: Date?
    var onMessage: ((String) -> Void)?
    init(defaults: UserDefaults = .standard, center: TripNotificationCenter? = nil) {
        self.defaults = defaults; self.center = center ?? SystemTripNotificationCenter()
        if let data = defaults.data(forKey: key) { state = try? JSONDecoder().decode(InactivityReminderState.self, from: data) }
        if let stamp = defaults.object(forKey: key + ".scheduled") as? Date { scheduledDue = stamp }
    }
    func reconcile(_ trip: Trip?, now: Date) {
        guard let trip = trip, trip.status != .ended else { cancel(); return }
        // A paused/interrupted trip has no position stream; its message says so.
        let paused = trip.status != .recording
        if state?.tripID != trip.id || state?.paused != paused {
            state = InactivityReminderState(tripID: trip.id, since: now, paused: paused)
            scheduledDue = nil
            center.removePending( [requestIdentifier])
        }
        persist()
        if paused || state?.anchor != nil { schedule(now: now) }
    }
    func observe(_ samples: [LocationSample], trip: Trip, now: Date) {
        reconcile(trip, now: now)
        guard var value = state else { return }
        var moved = false
        for sample in samples { if value.observe(sample, now: now) { moved = true } }
        state = value; persist()
        if moved {
            scheduledDue = nil
            center.removePending( [requestIdentifier])
            center.removeDelivered( [requestIdentifier])
            schedule(now: now)
        }
    }
    func requestPermission() {
        center.requestPermission { [weak self] allowed, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if allowed { self.scheduledDue = nil; self.schedule(now: Date()) }
                else { self.onMessage?(L("未允许通知，两小时未移动提醒无法显示，可在系统设置中开启。")) }
                if let error = error { self.onMessage?(error.localizedDescription) }
            }
        }
    }
    func snooze(_ trip: Trip?, now: Date) {
        guard let trip = trip, state?.tripID == trip.id else { return }
        state?.since = now; scheduledDue = nil; persist()
        center.removeDelivered( [requestIdentifier])
        schedule(now: now)
    }
    private func persist() {
        if let state = state, let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: key) }
        else { defaults.removeObject(forKey: key) }
    }
    private func schedule(now: Date) {
        guard let value = state, value.paused || value.anchor != nil, scheduledDue != value.due else { return }
        let token = UUID(); generation = token
        center.permission { [weak self] allowed in
            DispatchQueue.main.async {
                guard let self = self, self.generation == token, self.state?.tripID == value.tripID,
                      self.state?.due == value.due else { return }
                guard allowed else { return }
                let content = Self.content(for: value)
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, value.due.timeIntervalSince(Date())), repeats: false)
                let request = UNNotificationRequest(identifier: self.requestIdentifier, content: content, trigger: trigger)
                // add/remove are issued in main-queue order; stale async permission callbacks are rejected.
                self.center.add(request) { [weak self] error in
                    DispatchQueue.main.async {
                        guard let self = self, self.generation == token else { return }
                        if let error = error { self.onMessage?(error.localizedDescription) }
                        else { self.scheduledDue = value.due; self.defaults.set(value.due, forKey: self.key + ".scheduled") }
                    }
                }
            }
        }
    }
    static func content(for value: InactivityReminderState) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = L("是否结束这段旅程？")
        content.body = value.paused ? L("旅程已暂停或中断约两小时，尚未结束。点击进入 App 确认。") : L("约两小时未记录到明显移动，旅程尚未结束。点击进入 App 确认。")
        content.sound = .default
        content.userInfo = ["kind": "trip-inactivity", "tripID": value.tripID.uuidString]
        return content
    }
    func cancel() {
        generation = UUID(); state = nil; scheduledDue = nil
        defaults.removeObject(forKey: key); defaults.removeObject(forKey: key + ".scheduled")
        center.removePending( [requestIdentifier])
        center.removeDelivered( [requestIdentifier])
    }
}
