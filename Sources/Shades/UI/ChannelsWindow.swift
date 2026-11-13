import AppKit
import ShadesContext
import ShadesCore

/// A window that stays open beside your work without ever activating Shades, so the app you were in
/// stays in front and the cat can still tell what you're looking at. It takes the keyboard only when
/// you click into the box at the bottom, the way the Ask box does, and nothing typed there takes your
/// screen. It isn't a `QuietPanel`, because those float over everything, and this one is big enough to get in the way.
final class ChannelsPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: ChannelsWindow.size),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        level = .normal
        hidesOnDeactivate = false
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        contentMinSize = ChannelsWindow.minimumSize
        backgroundColor = MessagesInk.sidebar
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true
        // Rows come and go, so Tab works out its way round again whenever they do.
        autorecalculatesKeyViewLoop = true
        title = CatWords.appName
        // Shades' own captures leave out all its windows. This keeps Messages out of anyone else's too, such as a
        // kitten's own screen tools, so one kitten can't be shown another's messages.
        sharingType = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        QuietPanel.performEdit(event, from: self) || shortcut(event) || super.performKeyEquivalent(with: event)
    }

    /// A click raises it and gives it the keyboard, since you've clicked into it, without activating anything, so
    /// the app you were in stays the active one.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            orderFrontRegardless()
            if !isKeyWindow { makeKey() }
        }
        // ⌥ with the arrows, and Esc, have no ⌘, so they'd otherwise go straight to whatever has the keyboard.
        if event.type == .keyDown, !event.modifierFlags.contains(.command), shortcut(event) { return }
        super.sendEvent(event)
    }

    private func shortcut(_ event: NSEvent) -> Bool {
        guard let shortcut = MessagesShortcut(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers, modifiers: event.modifierFlags) else { return false }
        // A box with words in it keeps ⌥ and the arrows for moving through them, and Esc for itself, which in Messages'
        // own boxes closes the thread's pane anyway.
        if let text = firstResponder as? NSTextView, text.isEditable, shortcut == .escape || (shortcut.movesInText && !text.string.isEmpty) {
            return false
        }
        return handle(shortcut)
    }

    /// Does what a shortcut says, and only while Messages has the keyboard, so none of them is ever global.
    @discardableResult
    func handle(_ shortcut: MessagesShortcut) -> Bool {
        guard isKeyWindow, let view = contentView as? ChannelsView else { return false }
        return view.perform(shortcut)
    }
}

/// The sidebar flush on the window's chrome, then the pane for the place you're looking at and beside it a thread's pane
/// when one is open, as Slack lays them out, together in one page panel inset from the window, as Opal lays out a main
/// window. They're apart from the window so they can be drawn with no window on the screen.
final class ChannelsView: QuietView {
    /// How wide a thread's pane opens until you drag its edge, and the narrowest you can drag it.
    static let threadWidths: ClosedRange<CGFloat> = 320...460
    /// The narrowest the place beside a thread's pane gets, however wide you drag the thread's.
    static let narrowestPlace: CGFloat = 360

    /// How many places and threads ⌘[ can go back through.
    static let historyKept = 50

    let sidebar = ChannelSidebar()
    let pane = ChannelPane(role: .place)
    let threadPane = ChannelPane(role: .thread)
    let threadEdge = ThreadEdge()
    private let panelEdge = PanelEdge()
    let jumpBox = JumpBoxView()
    let cheatsheet = CheatsheetView()
    private(set) var selection: ChannelSelection = .activity
    private(set) var book: ChannelBook?
    /// The places and threads you've looked at, oldest first, for ⌘[ and ⌘].
    var history: [ChannelSelection] = [.activity]
    var historyIndex = 0
    var isTravelling = false
    /// ⌘W, which closes the window.
    var onCloseWindow: (() -> Void)?
    /// ⌘,, which opens Settings over the window.
    var onSettings: (() -> Void)?
    /// You've seen what's there, which is what takes its unread dot away.
    var onSeen: ((ChannelSelection) -> Void)?
    /// Threads you've marked unread since you came here, which stay unread while you're still looking.
    private(set) var keptUnread: Set<String> = []
    /// How wide you've dragged a thread's pane, for every thread after it, or `nil` until you have.
    var chosenThreadWidth: CGFloat? {
        didSet {
            needsLayout = true
            needsDisplay = true
            onChooseThreadWidth?(chosenThreadWidth)
        }
    }
    var onChooseThreadWidth: ((CGFloat?) -> Void)?
    /// Opens a thread in T3.
    var onOpenThread: ((String) -> Void)? { didSet { panes.forEach { $0.onOpenThread = onOpenThread } } }
    var onCopy: ((String) -> Void)? { didSet { panes.forEach { $0.onCopy = onCopy } } }
    var onAction: ((MessagesAction) -> Void)? { didSet { panes.forEach { $0.onAction = onAction } } }
    var onOpenLink: ((URL) -> Void)? { didSet { panes.forEach { $0.onOpenLink = onOpenLink } } }
    var onShowOnPhone: ((String) -> Void)? { didSet { panes.forEach { $0.onShowOnPhone = onShowOnPhone } } }
    /// Attach in a box, which offers recent files.
    var onAttach: ((ChannelComposer, NSView) -> Void)? { didSet { panes.forEach { $0.onAttach = onAttach } } }
    /// A box's mic, pressed once its box has the keyboard, so what you say goes where its line says.
    var onMic: (() -> Void)?
    var onStopListening: (() -> Void)?
    /// What the mics say when the pointer rests on them.
    var micTip = "" { didSet { panes.forEach { $0.composer.mic.toolTip = micTip } } }

    private var panes: [ChannelPane] { [pane, threadPane] }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(sidebar)
        addSubview(pane)
        addSubview(threadPane)
        addSubview(threadEdge)
        addSubview(panelEdge)
        threadPane.isHidden = true
        threadEdge.isHidden = true
        threadEdge.onDrag = { [weak self] x in self?.dragThreadEdge(to: x) }
        threadPane.parts = pane.parts
        jumpBox.isHidden = true
        cheatsheet.isHidden = true
        addSubview(jumpBox)
        addSubview(cheatsheet)
        jumpBox.onOpen = { [weak self] in self?.jumped(to: $0) }
        jumpBox.onClose = { [weak self] in self?.closeJump() }
        jumpBox.onFind = { [weak self] in self?.onAction?(.find($0)) }
        cheatsheet.onClose = { [weak self] in self?.cheatsheet.isHidden = true }
        sidebar.onSelect = { [weak self] in self?.select(ChannelSelection($0)) }
        sidebar.onShortcuts = { [weak self] in self?.perform(.cheatsheet) }
        sidebar.onDoNotDisturb = { [weak self] in self?.onAction?(.doNotDisturb) }
        for pane in panes {
            pane.onSelect = { [weak self] in self?.select($0) }
            pane.onOpen = { [weak self] thread, place, typing, report in self?.open(thread: thread, from: place, typing: typing, replyingTo: report) }
            pane.onClose = { [weak self] in self?.closeThread() }
            pane.onMarkUnread = { [weak self] thread, message in self?.markUnread(thread, from: message) }
            pane.composer.onEscape = { [weak self] in self?.perform(.escape) }
            pane.composer.onMic = { [weak self, weak pane] in
                pane?.focusComposer()
                self?.onMic?()
            }
            pane.composer.onStopListening = { [weak self] in self?.onStopListening?() }
        }
        registerForDraggedTypes(Drop.types)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        arrange()
    }

    /// How wide a thread's pane is beside the rest of the window: as wide as you `chose` by dragging its edge, or 45%
    /// of the room until you have, and never so wide that the place beside it is too narrow to read.
    static func threadWidth(in width: CGFloat, chosen: CGFloat? = nil) -> CGFloat {
        let room = width - ChannelSidebar.width - Opal.Space.inset
        let wanted = chosen ?? min(max(room * 0.45, threadWidths.lowerBound), threadWidths.upperBound)
        return max(min(wanted, room - narrowestPlace), threadWidths.lowerBound)
    }

    /// The edge let go of at `x`, which makes the thread's pane reach from there to the panel's right side, as far as
    /// it can.
    func dragThreadEdge(to x: CGFloat) {
        chosenThreadWidth = Self.threadWidth(in: bounds.width, chosen: panel.maxX - x)
    }

    /// The page the place and its thread sit on: flush against the sidebar, and inset from the window on its other sides.
    var panel: NSRect {
        let inset = Opal.Space.inset
        return NSRect(x: ChannelSidebar.width, y: inset, width: max(bounds.width - ChannelSidebar.width - inset, 0), height: max(bounds.height - inset * 2, 0))
    }

    private func arrange() {
        sidebar.frame = NSRect(x: 0, y: 0, width: ChannelSidebar.width, height: bounds.height)
        let panel = panel
        let thread = selection.thread == nil ? 0 : Self.threadWidth(in: bounds.width, chosen: chosenThreadWidth)
        threadPane.isHidden = thread == 0
        threadEdge.isHidden = thread == 0
        pane.frame = NSRect(x: panel.minX, y: panel.minY, width: max(panel.width - thread, 0), height: panel.height)
        if thread > 0 {
            threadPane.frame = NSRect(x: panel.maxX - thread, y: panel.minY, width: thread, height: panel.height)
            // Mostly over the thread's side, so the channel's scroller beside it still takes its own drags.
            threadEdge.frame = NSRect(x: threadPane.frame.minX - 2, y: panel.minY, width: 6, height: panel.height)
        }
        panelEdge.frame = panel
        jumpBox.frame = bounds
        cheatsheet.frame = bounds
    }

    /// Everything shows again from what's in memory, in the same turn.
    func show(_ book: ChannelBook) {
        let isFresh = self.book == nil
        self.book = book
        // A new topic carries on in its own thread once T3 has one.
        if let thread = selection.thread, let started = book.started[thread] { selection.thread = started }
        arrange()
        sidebar.show(book, selection: selection.place)
        pane.show(selection, in: book, isNewSelection: isFresh)
        if selection.thread != nil { threadPane.show(selection, in: book, isNewSelection: isFresh) }
        jumpBox.readAhead(book)
        if !jumpBox.isHidden { jumpBox.update(book) }
        onSeen?(selection)
    }

    func select(_ selection: ChannelSelection) {
        let old = self.selection
        self.selection = selection
        if selection.thread != old.thread { threadPane.leaveThread() }
        if selection != old { keptUnread = [] }
        if !isTravelling, selection != history[historyIndex] {
            history = Array(history[...historyIndex].suffix(Self.historyKept - 1)) + [selection]
            historyIndex = history.count - 1
        }
        guard let book else { return }
        arrange()
        sidebar.show(book, selection: selection.place)
        pane.show(selection, in: book, isNewSelection: selection.place != old.place)
        if selection.thread != nil { threadPane.show(selection, in: book, isNewSelection: selection.thread != old.thread || old.thread == nil) }
        onSeen?(selection)
    }

    /// Opens a thread in the pane beside `place`, or beside where you are. `typing` means you're about to type, so its
    /// box takes the keyboard, and `report` is the inbox row whose Reply or Ask opened it.
    func open(thread id: String, from place: ChannelPlace? = nil, typing: Bool = false, replyingTo report: InboxEntry? = nil) {
        select(.thread(id, in: place ?? selection.place))
        threadPane.replying(to: report)
        if typing { threadPane.focusComposer() }
    }

    func markUnread(_ thread: String, from message: String) {
        keptUnread.insert(thread)
        onAction?(.markUnread(thread, from: message))
    }

    func closeThread() {
        guard selection.thread != nil else { return }
        if window?.firstResponder === threadPane.composer.textView { window?.makeFirstResponder(nil) }
        select(selection.closed)
    }

    /// The pane whose box has the keyboard.
    var typingPane: ChannelPane? {
        panes.first { !$0.isHidden && window?.firstResponder === $0.composer.textView && $0.composer.target != nil }
    }

    /// The mic in the box you're talking into shows it, or none does.
    func showListening(in listening: ChannelPane?) {
        panes.forEach { $0.composer.mic.showListening($0 === listening) }
    }

    /// Draws everything again in the colours there are now, since a row keeps the colours it was made with.
    func restyle() {
        sidebar.restyle()
        panes.forEach { $0.restyle() }
        jumpBox.needsDisplay = true
        cheatsheet.needsDisplay = true
        if let book { sidebar.show(book, selection: selection.place) }
        needsDisplay = true
    }

    /// A file or picture goes with what you type in the pane it's let go over, as Slack's does.
    private func box(for drag: NSDraggingInfo) -> ChannelComposer? {
        let point = convert(drag.draggingLocation, from: nil)
        let pane = [threadPane, pane].first { !$0.isHidden && $0.frame.contains(point) }
        guard let composer = pane?.composer, !composer.isHidden else { return nil }
        return composer
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return Drop.all(sender.draggingPasteboard).contains(where: \.isFile) && box(for: sender) != nil ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let box = box(for: sender) else { return false }
        return box.attach(Drop.all(sender.draggingPasteboard))
    }

    override func draw(_ dirtyRect: NSRect) {
        MessagesInk.sidebar.setFill()
        dirtyRect.fill()
        let panel = panel
        MessagesInk.paper.setFill()
        NSBezierPath(roundedRect: panel, xRadius: Opal.Corner.panel, yRadius: Opal.Corner.panel).fill()
        guard selection.thread != nil else { return }
        MessagesInk.line.setFill()
        NSRect(x: threadPane.frame.minX, y: panel.minY, width: 1, height: panel.height).fill()
    }
}

/// The panel's rounded corners and its edge, drawn over what scrolls in it, since the panes inside are square. It never
/// takes a click.
final class PanelEdge: QuietView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let radius = Opal.Corner.panel
        let outside = NSBezierPath(rect: bounds)
        outside.append(NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius))
        outside.windingRule = .evenOdd
        MessagesInk.sidebar.setFill()
        outside.fill()
        Ink.hex(Opal.chromeBorder).setStroke()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius - 0.5, yRadius: radius - 0.5).stroke()
    }
}

/// The line between a place and its thread's pane, which you drag to make the thread's pane wider or narrower, as in
/// Slack. It draws nothing, since `ChannelsView` draws the line.
final class ThreadEdge: QuietView {
    /// Where the pointer is, across the window.
    var onDrag: ((CGFloat) -> Void)?

    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseDragged(with event: NSEvent) {
        guard let superview else { return }
        onDrag?(superview.convert(event.locationInWindow, from: nil).x)
    }
}

/// The Messages window: Activity, your threads, #general, a channel for each kitten and your DM with the cat, with a
/// thread's pane beside them. Closing it keeps everything as it was, so it opens again just as you left it.
@MainActor
final class ChannelsWindow: NSObject, NSWindowDelegate {
    nonisolated static let size = NSSize(width: 1040, height: 620)
    /// Room for the sidebar, then a channel and a thread's pane beside it at their narrowest, 360 and 320, in the panel
    /// inset 8 from the window's edge.
    nonisolated static let minimumSize = NSSize(width: 908, height: 440)
    private static let frameName = "Channels"
    private static let threadWidthKey = "ChannelsThreadWidth"
    private static let tickSeconds: TimeInterval = 0.2
    private static let ticksPerTimeRefresh = 300

    let panel = ChannelsPanel()
    let view = ChannelsView(frame: NSRect(origin: .zero, size: ChannelsWindow.size))
    var onClose: (() -> Void)?

    private var isPlaced = false
    private var timer: Timer?
    private var tick = 0

    init(defaults: UserDefaults = .standard) {
        super.init()
        panel.contentView = view
        panel.delegate = self
        view.chosenThreadWidth = (defaults.object(forKey: Self.threadWidthKey) as? Double).map { CGFloat($0) }
        view.onChooseThreadWidth = { defaults.set($0.map(Double.init), forKey: Self.threadWidthKey) }
    }

    /// Opens it on the cat's screen the first time and where you left it after that, or brings it to the front.
    func show(_ book: ChannelBook, centeredIn visible: NSRect) {
        update(book)
        if !isPlaced {
            isPlaced = true
            if !panel.setFrameUsingName(Self.frameName) { panel.setFrame(Self.centered(in: visible), display: false) }
            // A window left narrower than a thread's pane needs grows to fit it.
            if panel.frame.width < Self.minimumSize.width || panel.frame.height < Self.minimumSize.height {
                var frame = panel.frame
                frame.size = NSSize(width: max(frame.width, Self.minimumSize.width), height: max(frame.height, Self.minimumSize.height))
                panel.setFrame(frame, display: false)
            }
            panel.setFrameAutosaveName(Self.frameName)
        }
        panel.orderFrontRegardless()
        updateTimer()
    }

    func update(_ book: ChannelBook) {
        view.show(book)
    }

    /// Open where you can see it, since clicking back into your work leaves it open behind.
    var isInFront: Bool {
        panel.isVisible && panel.isOnActiveSpace && FrontWindow.isOnTop(panel.windowNumber)
    }

    /// Messages' words at another size or in another font, where you were.
    func apply(_ size: TextSize, font: String?) {
        guard size != MessagesInk.textSize || font != MessagesInk.fontFamily else { return }
        MessagesInk.textSize = size
        MessagesInk.fontFamily = font
        view.restyle()
    }

    static func centered(in visible: NSRect) -> NSRect {
        NSRect(
            x: (visible.midX - size.width / 2).rounded(),
            y: (visible.midY - size.height / 2).rounded(),
            width: size.width,
            height: size.height
        )
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
        onClose?()
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        updateTimer()
    }

    /// The cats only move while there's some of the window to see.
    private func updateTimer() {
        let wanted = panel.isVisible && panel.occlusionState.contains(.visible)
        if !wanted {
            timer?.invalidate()
            timer = nil
        } else if timer == nil {
            let timer = Timer(timeInterval: Self.tickSeconds, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.advance() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    private func advance() {
        tick += 1
        view.sidebar.advance(tick: tick)
        if tick % Self.ticksPerTimeRefresh == 0 {
            view.pane.refreshTimes()
            view.threadPane.refreshTimes()
        }
    }
}
