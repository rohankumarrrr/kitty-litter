import Foundation
import UserNotifications

/// Puts what needs you, and if you asked, what finished, in Notification Center. That only works for a bundled app, so a plain `swift run` posts nothing.
@MainActor
final class NeedsYouNotifications: NSObject, UNUserNotificationCenterDelegate {
    /// Given the thread a notification is about.
    var onClick: ((String) -> Void)?
    private let center: UNUserNotificationCenter?

    override init() {
        // Outside a bundle, asking for the center stops the app.
        center = Bundle.main.bundleURL.pathExtension == "app" ? .current() : nil
        super.init()
        center?.delegate = self
    }

    /// macOS asks you once, the first time there's something to say.
    func post(_ alert: NeedsYouAlert) {
        guard let center else { return }
        let content = Self.content(alert)
        let id = alert.id
        center.requestAuthorization(options: [.alert, .sound]) { allowed, _ in
            guard allowed else { return }
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
    }

    /// Who in its title and what in its body, as Messages and Slack write theirs, and grouped by thread in
    /// Notification Center. Work no kitten owns has no one to name, so macOS titles it with the app's name.
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
        // Starting takes back every notification from before, so each one there is says which thread.
        if let thread = response.notification.request.content.userInfo["thread"] as? String {
            DispatchQueue.main.async { MainActor.assumeIsolated { self.onClick?(thread) } }
        }
        completionHandler()
    }

    /// Shades is hardly ever the active app, but it can be just after you click one, and the next still shows.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
