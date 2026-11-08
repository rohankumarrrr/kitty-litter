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
        let title = CatWords.notification(alert)
        let id = alert.id
        let thread = alert.threadID
        center.requestAuthorization(options: [.alert, .sound]) { allowed, _ in
            guard allowed else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.userInfo = ["thread": thread]
            content.sound = .default
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
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
