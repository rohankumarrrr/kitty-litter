import AppKit
import Carbon.HIToolbox
import ShadesContext
import ShadesCore

/// All the windows, behind the `CatStage` the flows talk to.
@MainActor
final class AppStage: CatStage {
    private static let wordSeconds: TimeInterval = 1.2

    let cat = CatController()
    let bubble = BubbleController()
    let input = InputPanel()
    let pill = SayPill()
    let kittens = KittenPanel()
    let channels = ChannelsWindow()
    let settingsPanel = SettingsPanel()
    let themeMenu = ThemeMenu()
    let pairing = PairingPanel()
    let menuBar = MenuBar()
    weak var controller: AppController?

    private var escape: UInt32?

    init() {
        bubble.anchor = { [weak self] in
            guard let self else { return (.zero, .zero) }
            // Stack above whatever else is open over the cat, so both stay readable.
            let frame = self.input.isVisible ? self.input.frame
                : self.kittens.isVisible ? self.kittens.frame
                : self.cat.destinationFrame
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
        cat.view.registerForDraggedTypes(Drop.types)
        cat.view.onDrop = { [weak self] pasteboard in
            guard let drop = Drop(pasteboard) else {
                self?.controller?.dropped(nil)
                return false
            }
            Task { [weak self] in
                let snapshot = await Task.detached { drop.snapshot() }.value
                self?.controller?.dropped(snapshot)
            }
            return true
        }
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

        channels.onClose = { [weak self] in self?.controller?.channelsClosed() }
        channels.view.pane.onOpenThread = { [weak self] id in self?.controller?.openThread(id) }
        channels.view.pane.onCopy = { [weak self] text in self?.copyToPasteboard(text) }
        channels.view.pane.onAction = { [weak self] action in self?.controller?.messagesAction(action) }
        channels.view.onSeen = { [weak self] selection in self?.controller?.messagesAction(.seen(selection)) }
        channels.view.sidebar.onTheme = { [weak self] anchor in self?.showThemeMenu(under: anchor) }
        channels.view.onDropTheme = { [weak self] file in self?.controller?.themeChosen(.file(file)) }

        menuBar.onAsk = { [weak self] in self?.controller?.askPressed() }
        menuBar.onFix = { [weak self] in self?.controller?.fixPressed() }
        menuBar.onKittens = { [weak self] in self?.controller?.kittensPressed() }
        menuBar.onMessages = { [weak self] in self?.controller?.channelsPressed() }
        menuBar.messagesSummary = { [weak self] in self?.controller?.messagesMenuLine }
        menuBar.onSettings = { [weak self] in self?.controller?.settingsPressed() }
        menuBar.canPairPhone = { [weak self] in self?.controller?.phone != nil }
        menuBar.onPairPhone = { [weak self] in self?.controller?.pairPhone() }
        pairing.onClose = { [weak self] in self?.controller?.pairingClosed() }
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
        let messages = Hotkeys.shared.register(keyCode: Shortcut.messages.keyCode, modifiers: Shortcut.messages.modifiers) { [weak self] in
            self?.controller?.messagesHotkeyPressed()
        }
        if messages == nil { controller?.shortcutTaken(Shortcut.messagesLabel) }
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

    /// Where you are, for the cat to come to. The demo fixes it while it records, so a recording doesn't depend on the
    /// real pointer.
    var pointer: () -> CGPoint = { NSEvent.mouseLocation }

    func catComeToYou(arrived: @escaping () -> Void) {
        let mouse = pointer()
        // Beside the pointer rather than under it, so it isn't in your way.
        let spot = CGPoint(x: mouse.x + 28, y: mouse.y - CGFloat(CatArt.points) - 12)
        let close = hypot(spot.x - cat.frame.minX, spot.y - cat.frame.minY) < 120
        cat.run(to: close ? cat.brain.position : spot, arrived: arrived)
    }

    func catRun(toRegion region: CGRect, arrived: @escaping () -> Void) {
        let size = CGSize(width: CatArt.points, height: CatArt.points)
        cat.run(to: ScreenBounds.perch(on: region, size: size, screens: NSScreen.screens.map(\.visibleFrame)), arrived: arrived)
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

    // MARK: - Messages

    var isChannelsVisible: Bool { channels.panel.isVisible }

    func showChannels(_ book: ChannelBook, selecting selection: ChannelSelection?) {
        channels.show(book, centeredIn: cat.visibleFrame)
        if let selection { channels.view.select(selection) }
    }

    func updateChannels(_ book: ChannelBook) {
        channels.update(book)
    }

    func hideChannels() {
        channels.panel.close()
    }

    func showTheme(_ theme: ColorTheme?) {
        channels.apply(theme)
    }

    /// Only looks for themes when you open it.
    private func showThemeMenu(under anchor: NSView) {
        guard let controller else { return }
        themeMenu.show(controller.installedThemes(), current: controller.theme, under: anchor) { [weak controller] choice in
            controller?.themeChosen(choice)
        }
    }

    var isMessagesBoxTyping: Bool {
        let composer = channels.view.pane.composer
        return channels.panel.isKeyWindow && channels.panel.firstResponder === composer.textView && composer.target != nil
    }

    func holdMessagesBox() {
        channels.view.pane.startSpeaking()
    }

    func sendInMessages(_ text: String) {
        channels.view.pane.spoke(text)
    }

    func releaseMessagesBox() {
        channels.view.pane.stopSpeaking()
    }

    // MARK: - Everything else

    func showStatus(_ status: String, needsYou: Bool) {
        menuBar.show(status: status, needsYou: needsYou)
    }

    func showSettings(_ settings: Settings, onSave: @escaping (Settings) -> Void) {
        settingsPanel.show(settings, near: menuBar.corner, onSave: onSave)
    }

    func showPairing(_ card: PhonePairingCard?) {
        guard let card else { return pairing.hide() }
        pairing.show(card, centeredIn: cat.visibleFrame)
    }

    func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Esc

    /// Esc is only taken from other apps while there's something up for it to dismiss.
    private func updateEscape() {
        let wanted = bubble.isVisible || kittens.isVisible
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
        } else if kittens.isVisible {
            kittens.hide()
        } else {
            controller?.bubbleDismissed(byClick: false)
        }
    }
}
