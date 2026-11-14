import Foundation
import ShadesCore

/// Lockdown: every ask goes straight to one kitten, with no router to pick, and everything else waits the way Do Not
/// Disturb has it wait, for a session that's shared on screen. That kitten's own bubbles, notifications and pushes still
/// come. Typing in another kitten's channel or thread in Messages still goes where you typed.
extension AppController {
    /// The kitten every ask goes to, or `nil` if Lockdown's off or its kitten isn't set up any more.
    var lockedDownKitten: Kitten? {
        guard let id = settings.lockdown?.kitten else { return nil }
        return loadKittens().first { $0.id == id && !$0.planned }
    }

    /// Whether anything that comes by itself waits for later, with Do Not Disturb or Lockdown on.
    var isHolding: Bool { settings.doNotDisturb || settings.lockdown != nil }

    /// Picking the kitten it's on for turns it off, as a ticked item in a Mac menu does.
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

    /// The next ask starts a thread of its own, rather than carrying on in the last one.
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

    /// Whether Lockdown keeps this for later: anything but its kitten's own, including the cat's own lines.
    func lockdownHolds(_ missed: Missed) -> Bool {
        guard let lockdown = settings.lockdown else { return false }
        guard let id = listedThread(of: missed) else { return true }
        if id == lockdown.thread { return false }
        guard let kitten = lockedDownKitten, let thread = latestThreads.first(where: { $0.id == id }) else { return true }
        return KittenBoard.owner(of: thread, among: loadKittens()) != kitten
    }

    /// Your words, with your screen as that kitten may have it, straight to Lockdown's kitten. The first starts a thread
    /// in its project, the way the router's pick would, and the rest carry on there, steered or queued as Settings says.
    /// One at a time, so a second ask can't start a second thread while the first is still starting.
    /// `sent` hears the thread they went to, or `nil` if they went nowhere for a reason other than `refused`'s, and
    /// whether it's one they started.
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
            if let id = settings.lockdown?.thread, let thread = latestThreads.first(where: { $0.id == id }) ?? (lockdownStarted?.id == id ? lockdownStarted : nil) {
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
                give(words, to: kitten, snapshot: snapshot, youPicked: youPicked, asked: asked, onStarted: { id in
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

    /// T3 can take a moment to list a new thread, so the next ask carries on in it meanwhile. Its own checks on the
    /// screen then go by where it was started, as `give`'s did.
    private func keepLockdownThread(_ id: String, of kitten: Kitten) {
        guard settings.lockdown?.kitten == kitten.id else { return }
        lockdownStarted = AgentThread(id: id, title: kitten.name, projectTitle: kitten.name, status: .running, model: settings.frontierModel.model, updatedAt: now(), runtimeMode: settings.frontierMode, projectPath: kitten.workspace)
        var updated = settings
        updated.lockdown?.thread = id
        apply(updated)
    }
}
