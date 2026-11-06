import Foundation
import ShadesCore

/// A macOS notification that something needs you. It says who and what kind, and nothing anyone said, since
/// Notification Center keeps its own copy, out of reach of what keeps a kitten's words to itself, and can show
/// it on the lock screen.
struct NeedsYouAlert: Equatable {
    enum Kind: Equatable {
        case approval, question, decision
    }

    /// The approval's, question's or report's own ID.
    var id: String
    var kind: Kind
    /// A kitten's name, or `nil` for work no kitten owns.
    var who: String?
}

/// One notification for each new thing in Needs you, so Messages doesn't have to be open to know. Clicking one
/// opens Needs you, where it is.
extension AppController {
    func notifyNeedsYou() {
        let waiting = waiting
        let items: [(kind: NeedsYouAlert.Kind, id: String, threadID: String, title: String, at: Date?)] =
            waiting.approvals.map { (.approval, $0.id, $0.threadID, $0.threadTitle, $0.createdAt) }
            + waiting.questions.map { (.question, $0.id, $0.threadID, $0.threadTitle, $0.askedAt) }
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
            let thread = latestThreads.first { $0.id == item.threadID }
            let owner = waiting.owners[item.id] ?? thread.flatMap { KittenBoard.owner(of: $0, among: kittens) }?.id
            let alert = NeedsYouAlert(id: item.id, kind: item.kind, who: kittens.first { $0.id == owner }?.name)
            notify(alert)
            phone?.pushes.push(alert, now: now())
            notified.insert(item.id)
            showing.insert(item.id)
        }
    }

    func notificationClicked() {
        channelsPressed(selecting: .needsYou)
    }
}
