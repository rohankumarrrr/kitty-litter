import Foundation
import ShadesCore

/// A macOS notification about a thread: something it needs from you, or if you asked for them, that it finished. It
/// says who and what kind, and nothing anyone said, since Notification Center keeps its own copy, out of reach of what
/// keeps a kitten's words to itself, and can show it on the lock screen.
struct NeedsYouAlert: Equatable {
    enum Kind: Equatable {
        case approval, question, decision, finished
    }

    /// The approval's, question's or report's own ID, or for a session that reports in the bubble, its thread's.
    var id: String
    var kind: Kind
    /// A kitten's name, or `nil` for work no kitten owns.
    var who: String?
    /// The listed thread it's about, which clicking it opens.
    var threadID: String
}

/// One notification for each new thing waiting on you, so Messages doesn't have to be open to know. Clicking one
/// opens its thread.
extension AppController {
    func notifyNeedsYou() {
        let waiting = waiting
        // Replying stops a report asking, and means you've seen it.
        let reports = waiting.reports.filter { $0.repliedAt == nil && ($0.kind == .decision || settings.notifyFinished) }
        let items: [(kind: NeedsYouAlert.Kind, id: String, threadID: String, title: String, at: Date?)] =
            waiting.approvals.map { (.approval, $0.id, waiting.listed[$0.id] ?? $0.threadID, $0.threadTitle, $0.createdAt) }
            + waiting.questions.map { (.question, $0.id, waiting.listed[$0.id] ?? $0.threadID, $0.threadTitle, $0.askedAt) }
            + reports.map { ($0.kind == .decision ? .decision : .finished, $0.id, $0.threadID, $0.threadTitle, $0.at) }
        let current = items.filter { item in
            !AgentThread.isLiveTest(title: item.title) && latestThreads.first { $0.id == item.threadID }?.isLiveTest != true
        }
        let ids = Set(current.map(\.id))
        let gone = showing.subtracting(ids)
        if !gone.isEmpty { withdrawNotifications(gone.sorted()) }
        showing.formIntersection(ids)
        // What was already waiting when the app started is the cat's to say. T3 can take a moment to list it, so
        // it's told apart by when it was asked, not by when it showed up.
        let fresh = current.filter { ($0.at ?? launchedAt) >= launchedAt && !notified.contains($0.id) }
        guard !fresh.isEmpty else { return }
        let kittens = loadKittens()
        // One report can file a row of each kind at once, and a decision already says it's done.
        var told: Set<String> = []
        for item in fresh.filter({ $0.kind != .finished }) + fresh.filter({ $0.kind == .finished }) {
            notified.insert(item.id)
            guard told.insert(item.threadID).inserted || item.kind != .finished else { continue }
            let thread = latestThreads.first { $0.id == item.threadID }
            let owner = waiting.owners[item.id] ?? thread.flatMap { KittenBoard.owner(of: $0, among: kittens) }?.id
            tell(NeedsYouAlert(id: item.id, kind: item.kind, who: kittens.first { $0.id == owner }?.name, threadID: item.threadID))
            showing.insert(item.id)
        }
    }

    /// A session that reports in the bubble, rather than the inbox, finished.
    func notifyFinished(_ thread: AgentThread, by kitten: Kitten?) {
        guard settings.notifyFinished, !thread.isLiveTest else { return }
        tell(NeedsYouAlert(id: thread.id, kind: .finished, who: kitten?.name, threadID: thread.id))
    }

    /// On the Mac, and on each phone, where a tap opens the thread's own page. A phone can't show a thread Messages
    /// doesn't, or one in the cat's DM, so those open Activity there.
    private func tell(_ alert: NeedsYouAlert) {
        notify(alert)
        let home = messagesHome(ofThread: alert.threadID).flatMap { $0 == .shades ? nil : $0 }
        let opens = home.map { ChannelSelection.thread(alert.threadID, in: .channel($0)) } ?? .activity
        phone?.pushes.push(alert, opening: PhonePlace.key(opens), now: now())
    }

    /// Clicking one is looking at what came in, so closing Messages has nothing new to say.
    func notificationClicked(_ threadID: String) {
        nudgeOnClose = false
        showInMessages(threadID)
    }
}
