import Foundation
import UserNotifications

/// 把 PingPlanner 挑好的时间变成 iPad 的本地通知。不需要服务器，也不用联网。
@MainActor
final class PingScheduler {
    static let shared = PingScheduler()

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private let planner = PingPlanner()

    private static let notificationID = "kai.ping"
    private static let enabledKey = "ping_enabled"
    private static let pendingKey = "ping_pending_date"

    /// 设置里「让他偶尔主动找你」的开关，默认打开。
    var isEnabled: Bool {
        get { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: Self.enabledKey)
            if !newValue { cancelPending() }
        }
    }

    private var pendingDate: Date? {
        get { defaults.object(forKey: Self.pendingKey) as? Date }
        set { defaults.set(newValue, forKey: Self.pendingKey) }
    }

    /// 第一次打开时问一次通知权限（系统弹窗，点「允许」就行）。
    func requestPermissionIfNeeded() async {
        guard isEnabled else { return }
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    /// 她打开 app：没响的通知取消；已经响过的，把「?」记进聊天记录。
    func appBecameActive(store: ChatStore) {
        if let date = pendingDate, date <= Date() {
            store.receivePing(at: date)
        }
        cancelPending()
        center.removeAllDeliveredNotifications()
    }

    /// 她离开 app：安排下一条。
    func appWentToBackground(store: ChatStore) {
        guard isEnabled, store.hasKey else { return }
        let date = planner.nextPingDate(after: Date())
        let content = UNMutableNotificationContent()
        content.title = "@/"
        content.body = PingPlanner.pingText
        content.sound = .default
        let interval = max(60, date.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: trigger)
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        center.add(request)
        pendingDate = date
    }

    private func cancelPending() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        pendingDate = nil
    }
}
