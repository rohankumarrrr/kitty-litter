import AppKit
import Carbon.HIToolbox
import ShadesCore

/// All the windows, behind the `CatStage` the flows talk to.
@MainActor
final class AppStage: CatStage {
    private static let wordSeconds: TimeInterval = 1.2

    let cat = CatController()
    let bubble = BubbleController()
    let input = InputPanel()
    let pill = SayPill()
    let dashboard = DashboardPanel()
    let kittens = KittenPanel()
    let settingsPanel = SettingsPanel()
    let menuBar = MenuBar()
    weak var controller: AppController?

    private var escape: UInt32?

    init() {
        bubble.anchor = { [weak self] in
            guard let self else { return (.zero, .zero) }
            // Stack above whatever else is open over the cat, so both stay readable.
            let frame = self.input.isVisible ? self.input.frame : self.kittens.isVisible ? self.kittens.frame : self.cat.destinationFrame
            return (frame, self.cat.visibleFrame)
        }
        bubble.onDismiss = { [weak self] byClick in self?.controller?.bubbleDismissed(byClick: byClick) }
        bubble.onVisibilityChange = { [weak self] in self?.updateEscape() }
        bubble.view.onAction = { [weak self] action in self?.controller?.bubbleAction(action) }

        input.anchor = { [weak self] in
            guard let self else { return (.zero, .zero) }
            return (self.cat.destinationFrame, self.cat.visibleFrame)
        }
        input.onLayout = { [weak self] in
            guard let self else { return }
            self.bubble.reposition()
            self.pill.follow(self.pillAnchor, in: self.cat.visibleFrame)
            self.updateEscape()
        }

        cat.onMove = { [weak self] in
            guard let self else { return }
            self.pill.follow(self.pillAnchor, in: self.cat.visibleFrame)
            self.input.reposition()
            self.kittens.reposition()
            self.bubble.reposition()
        }
        cat.onClick = { [weak self] in self?.controller?.catClicked() }
        cat.onShiftClick = { [weak self] in self?.controller?.kittensPressed() }
        cat.onStroke = { [weak self] in self?.catPet() }
        cat.onRightClick = { [weak self] event in
            guard let self else { return }
            self.menuBar.popUpMenu(at: event.locationInWindow, in: self.cat.view)
        }

        kittens.anchor = { [weak self] in
            guard let self else { return (.zero, .zero) }
            return (self.cat.destinationFrame, self.cat.visibleFrame)
        }
        kittens.onOpen = { [weak self] id in self?.controller?.openThread(id) }
        kittens.onChange = { [weak self] in
            self?.bubble.reposition()
            self?.updateEscape()
        }

        dashboard.anchor = { [weak self] in self?.menuBar.corner ?? .zero }
        dashboard.onHide = { [weak self] in self?.updateEscape() }
        dashboard.onOpen = { [weak self] id in self?.controller?.openThread(id) }

        menuBar.onAsk = { [weak self] in self?.controller?.askPressed() }
        menuBar.onFix = { [weak self] in self?.controller?.fixPressed() }
        menuBar.onDashboard = { [weak self] in self?.toggleDashboard() }
        menuBar.onKittens = { [weak self] in self?.controller?.kittensPressed() }
        menuBar.onSettings = { [weak self] in self?.controller?.settingsPressed() }
        menuBar.onOpenThread = { [weak self] id in self?.controller?.openThread(id) }
    }

    func start() {
        cat.start()
        let ask = Hotkeys.shared.register(keyCode: Shortcut.ask.keyCode, modifiers: Shortcut.ask.modifiers) { [weak self] in
            self?.controller?.askPressed()
        }
        if ask == nil { controller?.shortcutTaken(Shortcut.askLabel) }
        let fix = Hotkeys.shared.register(keyCode: Shortcut.fix.keyCode, modifiers: Shortcut.fix.modifiers) { [weak self] in
            self?.controller?.fixPressed()
        }
        if fix == nil { controller?.shortcutTaken(Shortcut.fixLabel) }
    }

    // MARK: - The cat

    func catWake() { cat.wake() }

    func catSay(_ word: String) {
        guard !bubble.isVisible else { return }
        pill.say(word, over: pillAnchor, in: cat.visibleFrame, seconds: Self.wordSeconds)
    }

    func catHold(_ word: String?) {
        guard let word else {
            pill.hide()
            return
        }
        pill.say(word, over: pillAnchor, in: cat.visibleFrame, seconds: nil)
    }

    private var pillAnchor: NSRect { input.isVisible ? input.frame : cat.frame }

    func catStatus(_ status: CatStatus) { cat.setStatus(status) }
    func catLevel(_ level: Float) { cat.setLevel(level) }
    func catAgentsBusy(_ busy: Bool) { cat.setAgentsBusy(busy) }
    func catCelebrate() { cat.celebrate() }

    func catPet() {
        catSay(cat.pet())
    }

    func catComeToYou(arrived: @escaping () -> Void) {
        let mouse = NSEvent.mouseLocation
        // Beside the pointer rather than under it, so it isn't in your way.
        let spot = CGPoint(x: mouse.x + 28, y: mouse.y - CGFloat(CatArt.points) - 12)
        let close = hypot(spot.x - cat.frame.minX, spot.y - cat.frame.minY) < 120
        cat.run(to: close ? cat.brain.position : spot, arrived: arrived)
    }

    func catRun(toRegion region: CGRect, arrived: @escaping () -> Void) {
        // Perches on top of it, the way it sits on bubbles on the site.
        let spot = CGPoint(x: region.midX - CGFloat(CatArt.points) / 2, y: region.maxY - 3)
        cat.run(to: spot, arrived: arrived)
        input.reposition()
        bubble.reposition()
    }

    func catGoHome() {
        cat.goHome()
        input.reposition()
        bubble.reposition()
    }

    // MARK: - The bubble and input

    func showBubble(_ content: BubbleContent?) {
        if content != nil { pill.hide() }
        bubble.show(content)
    }

    var isInputVisible: Bool { input.isVisible }

    func showInput(_ request: InputRequest) {
        input.show(request)
        bubble.reposition()
    }

    func setInputText(_ text: String) {
        input.setText(text)
    }

    func submitInput(_ text: String) {
        input.submit(text)
    }

    func hideInput() {
        input.cancel()
    }

    // MARK: - The kittens

    var isKittensVisible: Bool { kittens.isVisible }

    func showKittens(_ statuses: [KittenStatus]) {
        kittens.show(statuses)
    }

    func hideKittens() {
        kittens.hide()
    }

    // MARK: - Everything else

    func showThreads(_ threads: [AgentThread], status: String) {
        dashboard.update(threads)
        let needsYou = threads.contains { !$0.pendingApprovals.isEmpty || $0.status == .waitingForApproval || $0.status == .waitingForAnswer }
        menuBar.show(status: status, threads: threads, needsYou: needsYou)
    }

    func toggleDashboard() {
        dashboard.toggle()
        updateEscape()
    }

    func showSettings(_ settings: Settings, onSave: @escaping (Settings) -> Void) {
        settingsPanel.show(settings, near: menuBar.corner, onSave: onSave)
    }

    func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Esc

    /// Esc is only taken from other apps while there's something up for it to dismiss.
    private func updateEscape() {
        let wanted = bubble.isVisible || dashboard.isVisible || kittens.isVisible
        if wanted, escape == nil {
            escape = Hotkeys.shared.register(keyCode: kVK_Escape, modifiers: 0) { [weak self] in self?.escapePressed() }
        } else if !wanted, let id = escape {
            Hotkeys.shared.unregister(id)
            escape = nil
        }
    }

    private func escapePressed() {
        if input.isVisible {
            input.cancel()
        } else if dashboard.isVisible {
            dashboard.hide()
        } else if kittens.isVisible {
            kittens.hide()
        } else {
            controller?.bubbleDismissed(byClick: false)
        }
    }
}
