import Foundation
import UserNotifications

/// Puts what needs you in Notification Center. That only works for a bundled app, so a plain `swift run` posts nothing.
@MainActor
final class NeedsYouNotifications: NSObject, UNUserNotificationCenterDelegate {
    var onClick: (() -> Void)?
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
        center.requestAuthorization(options: [.alert, .sound]) { allowed, _ in
            guard allowed else { return }
            let content = UNMutableNotificationContent()
            content.title = title
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
        DispatchQueue.main.async { MainActor.assumeIsolated { self.onClick?() } }
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
