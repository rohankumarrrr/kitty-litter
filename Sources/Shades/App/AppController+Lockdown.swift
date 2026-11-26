import Foundation
import ShadesCore

extension AppController {
    var lockedDownKitten: Kitten? {
        guard let id = settings.lockdown?.kitten else { return nil }
        return loadKittens().first { $0.id == id && !$0.planned }
    }

    var isHolding: Bool { settings.doNotDisturb || settings.lockdown != nil }

    func lockdownPicked(_ kitten: Kitten) {
        guard settings.lockdown?.kitten != kitten.id else { return lockdownOff() }
        var updated = settings
        updated.lockdown = Lockdown(kitten: kitten.id)
        apply(updated)
    }

    func lockdownOff() {
        var updated = settings
        updated.lockdown = nil
        apply(updated)
    }

    func lockdownNewThread() {
        guard settings.lockdown?.thread != nil else { return }
        var updated = settings
        updated.lockdown?.thread = nil
        apply(updated)
    }

    func lockdownChanged() {
        if settings.lockdown != nil {
            putAway()
            catchingUp = false
        } else {
            catchingUp = !settings.doNotDisturb && !awayNow.isEmpty
        }
        channels.refresh()
        renderBubble()
        healthTask = Task { await runHealthCheck() }
    }

    var askable: [ApprovalRequest] {
        approvals.pending.filter { !lockdownHolds(.approval($0.id)) }
    }

    func lockdownHolds(_ missed: Missed) -> Bool {
        guard let lockdown = settings.lockdown else { return false }
        guard let id = listedThread(of: missed) else { return true }
        if id == lockdown.thread { return false }
        guard let kitten = lockedDownKitten, let thread = latestThreads.first(where: { $0.id == id }) else { return true }
        return KittenBoard.owner(of: thread, among: loadKittens()) != kitten
    }

    func sendLockedDown(
        _ words: String,
        snapshot: ScreenSnapshot?,
        youPicked: Bool = false,
        asked: Int? = nil,
        sent: ((String?, Bool) -> Void)? = nil,
        refused: (() -> Void)? = nil,
        unheard: ((String) -> Void)? = nil
    ) {
        let asked = asked ?? questionsAsked
        let previous = lockdownTurn
        lockdownTurn = Task {
            await previous?.value
            guard let kitten = lockedDownKitten else {
                sent?(nil, false)
                return say(CatWords.lockdownKittenGone)
            }
            await waitForThreadList()
            if let id = settings.lockdown?.thread, let thread = pinnedThread(id, of: kitten) {
                forward(words, to: thread, snapshot: snapshot, youPicked: youPicked, behavior: settings.followUpBehavior, asked: asked, refused: refused, unheard: unheard)
                sent?(id, false)
                return
            }
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                var finished = false
                func finish() {
                    guard !finished else { return }
                    finished = true
                    done.resume()
                }
                give(words, to: kitten, snapshot: snapshot, youPicked: youPicked, asked: asked, onStarted: { landing in
                    let id = landing.thread
                    if let id { self.keepLockdownThread(id, of: kitten) }
                    sent?(id, true)
                    finish()
                }, refused: {
                    refused?()
                    finish()
                })
            }
        }
    }

    private func pinnedThread(_ id: String, of kitten: Kitten) -> AgentThread? {
        if let listed = latestThreads.first(where: { $0.id == id }) { return listed }
        guard lockdownStarted == id || !threadListArrived else { return nil }
        return AgentThread(id: id, title: kitten.name, projectTitle: kitten.name, status: .running, model: effectiveFrontierModel.model, updatedAt: now(), projectPath: kitten.workspace)
    }

    private func keepLockdownThread(_ id: String, of kitten: Kitten) {
        guard settings.lockdown?.kitten == kitten.id else { return }
        lockdownStarted = id
        var updated = settings
        updated.lockdown?.thread = id
        apply(updated)
    }
}
