import Foundation
import ShadesCore

struct NeedsYouAlert: Equatable {
    enum Kind: Equatable {
        case approval, question, decision, finished
    }

    var id: String
    var kind: Kind
    var who: String?
    var threadID: String

    var missed: Missed {
        switch kind {
        case .approval: .approval(id)
        case .question: .question(id)
        case .decision, .finished: .thread(threadID)
        }
    }
}

extension AppController {
    func notifyNeedsYou() {
        showNeedsYouCount()
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
        let fresh = current.filter { ($0.at ?? launchedAt) >= launchedAt && !notified.contains($0.id) }
        guard !fresh.isEmpty else { return }
        let kittens = loadKittens()
        for item in fresh {
            notified.insert(item.id)
            let thread = latestThreads.first { $0.id == item.threadID }
            let owner = waiting.owners[item.id] ?? thread.flatMap { KittenBoard.owner(of: $0, among: kittens) }?.id
            if tell(NeedsYouAlert(id: item.id, kind: item.kind, who: kittens.first { $0.id == owner }?.name, threadID: item.threadID)) {
                showing.insert(item.id)
            }
        }
    }

    func notifyFinished(_ thread: AgentThread, by kitten: Kitten?) {
        guard settings.notifyFinished, !thread.isLiveTest else { return }
        tell(NeedsYouAlert(id: thread.id, kind: .finished, who: kitten?.name, threadID: thread.id))
    }

    @discardableResult
    private func tell(_ alert: NeedsYouAlert) -> Bool {
        let onMac = mayPopUp(alert.missed)
        let toPhone = mayPopUp(alert.missed, on: .phone)
        if onMac { notify(alert) }
        if toPhone {
            let home = messagesHome(ofThread: alert.threadID).flatMap { $0 == .shades && onPhone[alert.threadID] == nil ? nil : $0 }
            let opens = home.map { ChannelSelection.thread(alert.threadID, in: .channel($0)) } ?? .activity
            phone?.pushes.push(alert, opening: PhonePlace.key(opens), now: now())
        }
        return onMac
    }
}
