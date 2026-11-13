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
    let recentFiles = RecentFiles()
    let pairing = PairingPanel()
    let menuBar = MenuBar()
    weak var controller: AppController?

    private var escape: UInt32?
    /// The Messages box that was typing when the talk key went down, so what you say goes there.
    private var spokenPane: ChannelPane?

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
        bubble.view.opensInMessages = { [weak self] in self?.controller?.opensInMessages($0) == true }
        bubble.view.kittenColor = { [weak self] in self?.controller?.kittenColor(ofThread: $0) }

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
        cat.onMenu = { [weak self] point in
            guard let self else { return }
            self.menuBar.popUpMenu(at: point, in: self.cat.view)
        }

        kittens.anchor = { [weak self] in
            guard let self else { return (.zero, .zero) }
            return (self.cat.destinationFrame, self.cat.visibleFrame)
        }
        kittens.onOpen = { [weak self] status in self?.controller?.kittenPressed(status) }
        kittens.onChange = { [weak self] in
            self?.bubble.reposition()
            self?.updateEscape()
        }

        channels.onClose = { [weak self] in self?.controller?.channelsClosed() }
        channels.view.onOpenThread = { [weak self] id in self?.controller?.openThread(id) }
        channels.view.onCopy = { [weak self] text in self?.copyToPasteboard(text) }
        channels.view.onOpenLink = { NSWorkspace.shared.open($0) }
        channels.view.onAction = { [weak self] action in self?.controller?.messagesAction(action) }
        channels.view.onSeen = { [weak self] selection in
            self?.controller?.messagesAction(.seen(selection, keepingUnread: self?.channels.view.keptUnread ?? []))
        }
        channels.view.onShowOnPhone = { [weak self] id in self?.controller?.showOnPhonePressed(id) }
        channels.view.onAttach = { [weak self] composer, anchor in self?.showRecentFiles(for: composer, under: anchor) }
        channels.view.onMic = { [weak self] in self?.controller?.micPressed(in: .messages) }
        channels.view.onStopListening = { [weak self] in self?.controller?.cancelListening() }
        input.onMic = { [weak self] in self?.controller?.micPressed(in: .ask) }
        channels.view.onCloseWindow = { [weak self] in self?.hideChannels() }

        menuBar.onAsk = { [weak self] in self?.controller?.askPressed() }
        menuBar.onFix = { [weak self] in self?.controller?.fixPressed() }
        menuBar.onKittens = { [weak self] in self?.controller?.kittensPressed() }
        menuBar.onMessages = { [weak self] in self?.controller?.channelsPressed() }
        menuBar.messagesSummary = { [weak self] in self?.controller?.messagesMenuLine }
        menuBar.onSettings = { [weak self] in self?.controller?.settingsPressed() }
        menuBar.canPairPhone = { [weak self] in self?.controller?.phone != nil }
        menuBar.onPairPhone = { [weak self] in self?.controller?.pairPhone() }
        menuBar.isDoNotDisturb = { [weak self] in self?.controller?.settings.doNotDisturb == true }
        menuBar.onDoNotDisturb = { [weak self] in self?.controller?.doNotDisturbPressed() }
        pairing.onClose = { [weak self] in
            self?.controller?.pairingClosed()
            self?.updateEscape()
        }

        channels.view.sidebar.onSettings = { [weak self] in self?.controller?.settingsPressed(overMessages: true) }
        channels.view.onSettings = { [weak self] in self?.controller?.settingsPressed(overMessages: true) }
        settingsPanel.onChange = { [weak self] in self?.controller?.settingsEdited($0) }
        settingsPanel.onDoNotDisturb = { [weak self] in self?.controller?.doNotDisturbPressed() }
        settingsPanel.onNotifications = { [weak self] channel, picked in self?.controller?.setNotifications(picked, for: channel) }
        settingsPanel.onPairPhone = { [weak self] in self?.controller?.pairPhone() }
    }

    func start() {
        cat.start()
        if let controller { showTalkKey(controller.settings.talkKey) }
        claim(.ask) { [weak self] in self?.controller?.askPressed() }
        claim(.fix) { [weak self] in self?.controller?.fixPressed() }
        claim(.messages) { [weak self] in self?.controller?.messagesHotkeyPressed() }
    }

    /// The menu only shows a shortcut the app holds, so one another app has isn't offered as working.
    private func claim(_ shortcut: Shortcut, run: @escaping () -> Void) {
        if Hotkeys.shared.register(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers, handler: run) == nil {
            controller?.shortcutTaken(shortcut.label)
        } else {
            menuBar.held.append(shortcut)
        }
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
    func catDoNotDisturb(_ on: Bool) { cat.setDoNotDisturb(on) }

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

    /// Asks the window server which window a click there would reach, which reads where windows are and nothing in
    /// them. The cat and its word let clicks through, so they never count, and one of ours behind your work doesn't.
    func isOwnWindow(at region: CGRect) -> Bool {
        let front = NSWindow.windowNumber(at: NSPoint(x: region.midX, y: region.midY), belowWindowWithWindowNumber: 0)
        return NSApp.windows.contains { $0.isVisible && $0.windowNumber == front }
    }

    // MARK: - The bubble and input

    func showBubble(_ content: BubbleContent?) {
        if content != nil { pill.hide() }
        bubble.show(content)
    }

    var isPointerOnBubble: Bool { bubble.isVisible && bubble.panel.frame.contains(NSEvent.mouseLocation) }

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

    func showListening(in box: VoiceBox?) {
        input.mic.showListening(box == .ask)
        channels.view.showListening(in: box == .messages ? spokenPane : nil)
    }

    /// The mics name the talk key, so it's easier to find.
    private func showTalkKey(_ key: HoldKey) {
        let tip = CatWords.speakTip(talkKey: key)
        input.mic.toolTip = tip
        channels.view.micTip = tip
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
    var isChannelsInFront: Bool { channels.isInFront }

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

    /// Only looks for recent files when you press Attach, off the main thread, since Spotlight can take a moment. What
    /// you pick is attached as if you'd dropped it there.
    private func showRecentFiles(for composer: ChannelComposer, under anchor: NSView) {
        guard let find = controller?.recentFiles else { return }
        Task { [weak self, weak composer, weak anchor] in
            let files = await Task.detached { find() }.value
            guard let self, let anchor, anchor.window != nil else { return }
            self.recentFiles.show(files, under: anchor) { file in
                composer?.attach([.file(file)])
            }
        }
    }

    var isMessagesBoxTyping: Bool {
        channels.panel.isKeyWindow && channels.view.typingPane != nil
    }

    func holdMessagesBox() {
        spokenPane = channels.view.typingPane
        spokenPane?.startSpeaking()
    }

    func sendInMessages(_ text: String) {
        spokenPane?.spoke(text)
        spokenPane = nil
    }

    func releaseMessagesBox() {
        spokenPane?.stopSpeaking()
        spokenPane = nil
    }

    // MARK: - Everything else

    func showStatus(_ status: String, needsYou: Bool) {
        menuBar.show(status: status, needsYou: needsYou)
    }

    func showSettings(_ form: SettingsForm, overMessages: Bool) {
        let messages = channels.panel.frame
        let corner = overMessages && channels.panel.isVisible
            ? NSPoint(x: messages.midX + SettingsPanel.width / 2, y: messages.maxY - 44)
            : menuBar.corner
        settingsPanel.show(form, near: corner)
    }

    func settingsChanged(_ form: SettingsForm) {
        settingsPanel.update(form)
        showTalkKey(form.settings.talkKey)
    }

    func showText(size: TextSize, font: String?) {
        channels.apply(size, font: font)
    }

    func showPairing(_ card: PhonePairingCard?) {
        defer { updateEscape() }
        guard let card else { return pairing.hide() }
        pairing.show(card, centeredIn: cat.visibleFrame)
    }

    func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func openSettings(_ pane: Permissions.Pane) {
        Permissions.openSettings(pane)
    }

    // MARK: - Esc

    /// Esc is only taken from other apps while there's something up for it to dismiss.
    private func updateEscape() {
        let wanted = bubble.isVisible || kittens.isVisible || pairing.isVisible
        if wanted, escape == nil {
            escape = Hotkeys.shared.register(keyCode: kVK_Escape, modifiers: 0) { [weak self] in self?.escapePressed() }
        } else if !wanted, let id = escape {
            Hotkeys.shared.unregister(id)
            escape = nil
        }
    }

    func escapePressed() {
        if input.isVisible {
            input.cancel()
        } else if kittens.isVisible {
            kittens.hide()
        } else if pairing.isVisible, !bubble.isVisible {
            pairing.close()
        } else {
            controller?.bubbleDismissed(byClick: false)
        }
    }
}
