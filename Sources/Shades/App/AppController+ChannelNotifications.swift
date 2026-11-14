import Foundation
import ShadesCore

/// Each channel in Messages says what it tells you, on the Mac and on your phone: everything, only what needs you, or
/// nothing, or it's muted. `mayPopUp` asks it before Do Not Disturb, so nothing pops up around it.
extension AppController {
    /// Something from no channel, such as the cat's own line or a thread Messages doesn't show, is only Do Not
    /// Disturb's to hold.
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

    /// The listed thread it's about, as Activity lists it, since a subagent's own thread lives nowhere in Messages.
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
    /// What Settings calls it.
    var settingsKey: String {
        switch self {
        case .shades: "shades"
        case .kitten(let id): "kitten:\(id)"
        }
    }
}
