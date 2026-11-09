import Foundation
import ShadesCore

/// A macOS notification about a thread: something it needs from you, or if you asked for them, that it finished. It
/// says who and what kind, and nothing anyone said, since Notification Center keeps its own copy, out of reach of what
/// keeps a kitten's words to itself, and can show it on the lock screen.
struct NeedsYouAlert: Equatable {
    enum Kind: Equatable {
        case approval, question, decision, finished
    }

    /// The approval's, question's or decision's own ID, or for a finished session, its thread's.
    var id: String
    var kind: Kind
    /// A kitten's name, or `nil` for work no kitten owns.
    var who: String?
    /// The listed thread it's about, which clicking it opens.
    var threadID: String

    /// What Do Not Disturb keeps of it for the catch-up.
    var missed: Missed {
        switch kind {
        case .approval: .approval(id)
        case .question: .question(id)
        case .decision, .finished: .thread(threadID)
        }
    }
}

/// One notification for each new thing waiting on you, so Messages doesn't have to be open to know. Clicking one
/// opens its thread, the same as the bubble's Open.
extension AppController {
    func notifyNeedsYou() {
        let waiting = waiting
        let items: [(kind: NeedsYouAlert.Kind, id: String, threadID: String, title: String, at: Date?)] =
            waiting.approvals.map { (.approval, $0.id, waiting.listed[$0.id] ?? $0.threadID, $0.threadTitle, $0.createdAt) }
            + waiting.questions.map { (.question, $0.id, waiting.listed[$0.id] ?? $0.threadID, $0.threadTitle, $0.askedAt) }
            + waiting.reports.filter(\.needsYou).map { (.decision, $0.id, $0.threadID, $0.threadTitle, $0.at) }
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
        for item in fresh {
            // One Do Not Disturb holds isn't sent late. The catch-up covers it.
            notified.insert(item.id)
            let thread = latestThreads.first { $0.id == item.threadID }
            let owner = waiting.owners[item.id] ?? thread.flatMap { KittenBoard.owner(of: $0, among: kittens) }?.id
            if tell(NeedsYouAlert(id: item.id, kind: item.kind, who: kittens.first { $0.id == owner }?.name, threadID: item.threadID)) {
                showing.insert(item.id)
            }
        }
    }

    /// A session's run finished, with a report that doesn't need a decision, since a decision has its own. There's
    /// nothing to answer, so it stays until it's clicked, and a later run's takes its place.
    func notifyFinished(_ thread: AgentThread, by kitten: Kitten?) {
        guard settings.notifyFinished, !thread.isLiveTest else { return }
        tell(NeedsYouAlert(id: thread.id, kind: .finished, who: kitten?.name, threadID: thread.id))
    }

    /// On the Mac, and on each phone, where a tap opens the thread's own page. A phone can't show a thread Messages
    /// doesn't, or one in the cat's DM, so those open Activity there. Each asks first, since its channel can say
    /// something different for the Mac and the phone. It says whether the Mac shows it, the only one taken back.
    @discardableResult
    private func tell(_ alert: NeedsYouAlert) -> Bool {
        let onMac = mayPopUp(alert.missed)
        let onPhone = mayPopUp(alert.missed, on: .phone)
        if onMac { notify(alert) }
        if onPhone {
            let home = messagesHome(ofThread: alert.threadID).flatMap { $0 == .shades ? nil : $0 }
            let opens = home.map { ChannelSelection.thread(alert.threadID, in: .channel($0)) } ?? .activity
            phone?.pushes.push(alert, opening: PhonePlace.key(opens), now: now())
        }
        return onMac
    }
}
