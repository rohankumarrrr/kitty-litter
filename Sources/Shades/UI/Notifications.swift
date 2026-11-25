import Foundation
import UserNotifications

@MainActor
final class NeedsYouNotifications: NSObject, UNUserNotificationCenterDelegate {
    var onClick: ((String) -> Void)?
    private let center: UNUserNotificationCenter?

    override init() {
        // Outside the repo: UNUserNotificationCenter.current() stops an app that isn't in a bundle.
        center = Bundle.main.bundleURL.pathExtension == "app" ? .current() : nil
        super.init()
        center?.delegate = self
    }

    func post(_ alert: NeedsYouAlert) {
        guard let center else { return }
        let content = Self.content(alert)
        let id = alert.id
        center.requestAuthorization(options: [.alert, .sound]) { allowed, _ in
            guard allowed else { return }
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
    }

    static func content(_ alert: NeedsYouAlert) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        if let who = alert.who {
            let what = CatWords.notificationWhat(alert.kind)
            content.title = who
            content.body = what.prefix(1).uppercased() + what.dropFirst()
        } else {
            content.body = CatWords.notification(alert)
        }
        content.threadIdentifier = alert.threadID
        content.userInfo = ["thread": alert.threadID]
        content.sound = .default
        return content
    }

    func withdraw(_ ids: [String]) {
        center?.removeDeliveredNotifications(withIdentifiers: ids)
    }

    func clear() {
        center?.removeAllDeliveredNotifications()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let thread = response.notification.request.content.userInfo["thread"] as? String {
            DispatchQueue.main.async { MainActor.assumeIsolated { self.onClick?(thread) } }
        }
        completionHandler()
    }

    // Outside the repo: macOS shows an active app's notification only if willPresent asks for it.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
