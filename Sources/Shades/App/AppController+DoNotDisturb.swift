import Foundation
import ShadesCore

/// Do Not Disturb. While it's on nothing pops up by itself: no bubble, no notification and no push to your phone. What
/// would have popped up waits as IDs, read again from T3 or the inbox, for one catch-up once it's off. Anything you
/// start yourself, such as asking the cat, still answers as usual, since you're there.
extension AppController {
    /// The one place everything that comes in by itself asks before it pops up, on the Mac or, for a notification, on
    /// your phone. Its channel can say no for good, which isn't kept. Do Not Disturb keeps what it holds for the catch-up.
    func mayPopUp(_ missed: Missed, on device: NotifyDevice = .mac) -> Bool {
        guard channelAllows(missed, on: device) else { return false }
        guard settings.doNotDisturb else { return true }
        keepForLater(missed)
        return false
    }

    /// What a bubble that came by itself was about.
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
            catchingUp = !awayNow.isEmpty
        }
        channels.refresh()
        renderBubble()
    }

    /// What came in while you were away that's still there to see. An approval or question answered meanwhile isn't.
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

    /// What came by itself and is up or waiting to be read when it's turned on goes too, so nothing pops up after.
    /// Approvals wait in Messages, as if you'd pressed Esc, and clicking the cat still brings them up.
    private func putAway() {
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
