import Foundation
import ShadesCore

extension AppController {
    func mayPopUp(_ missed: Missed, on device: NotifyDevice = .mac) -> Bool {
        guard channelAllows(missed, on: device) else { return false }
        guard settings.doNotDisturb || lockdownHolds(missed) else { return true }
        keepForLater(missed)
        return false
    }

    func missed(question: String? = nil, thread: String?, text: String) -> Missed {
        question.map(Missed.question) ?? thread.map(Missed.thread) ?? .line(text)
    }

    func doNotDisturbPressed() {
        setDoNotDisturb(!settings.doNotDisturb)
    }

    func setDoNotDisturb(_ on: Bool) {
        var updated = settings
        updated.doNotDisturb = on
        apply(updated)
    }

    func doNotDisturbChanged() {
        stage.catDoNotDisturb(settings.doNotDisturb)
        if settings.doNotDisturb {
            putAway()
            catchingUp = false
        } else {
            catchingUp = settings.lockdown == nil && !awayNow.isEmpty
        }
        channels.refresh()
        renderBubble()
    }

    var awayNow: [Missed] {
        let asked = Set(waiting.questions.map(\.id))
        return away.filter { missed in
            switch missed {
            case .approval(let id): approvals.pending.contains { $0.id == id }
            case .question(let id): asked.contains(id)
            case .thread, .line: true
            }
        }
    }

    func putAway() {
        for notice in notices { keepForLater(missed(question: notice.questionID, thread: notice.threadID, text: notice.text)) }
        notices = []
        if let line, line.unasked {
            keepForLater(missed(thread: line.threadID, text: line.text))
            self.line = nil
        }
        inboxNudge = false
        nudgeOnClose = false
        if !approvals.isEmpty { approvalsHidden = true }
    }

    private func keepForLater(_ missed: Missed) {
        if !away.contains(missed) { away.append(missed) }
    }
}
