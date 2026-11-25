import Foundation
import ShadesCore

extension AppController {
    func channelAllows(_ missed: Missed, on device: NotifyDevice) -> Bool {
        guard let thread = listedThread(of: missed), let home = messagesHome(ofThread: thread) else { return true }
        return settings.notifications(for: home.settingsKey).allows(needsYou: needsYou(missed), on: device)
    }

    func setNotifications(_ notifications: ChannelNotifications, for channel: ChannelID) {
        var updated = settings
        updated.setNotifications(notifications, for: channel.settingsKey)
        apply(updated)
        channels.refresh()
    }

    func listedThread(of missed: Missed) -> String? {
        switch missed {
        case .thread(let id):
            id
        case .approval(let id):
            latestThreads.first { $0.pendingApprovals.contains { $0.id == id } }?.id ?? approvals.pending.first { $0.id == id }?.threadID
        case .question(let id):
            latestThreads.first { $0.pendingQuestion?.id == id }?.id
        case .line:
            nil
        }
    }

    private func needsYou(_ missed: Missed) -> Bool {
        switch missed {
        case .approval, .question:
            true
        case .thread(let id):
            inbox.entries.contains { $0.threadID == id && $0.needsYou } || latestThreads.first { $0.id == id }?.status == .failed
        case .line:
            false
        }
    }
}

extension ChannelID {
    var settingsKey: String {
        switch self {
        case .shades: "shades"
        case .kitten(let id): "kitten:\(id)"
        }
    }
}
