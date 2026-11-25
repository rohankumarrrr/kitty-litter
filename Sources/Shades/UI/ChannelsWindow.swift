import AppKit
import ShadesContext
import ShadesCore

class ChannelsPanel: NSPanel {
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
        autorecalculatesKeyViewLoop = true
        title = CatWords.appName
        sharingType = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        QuietPanel.performEdit(event, from: self) || shortcut(event) || super.performKeyEquivalent(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            orderFrontRegardless()
            if !isKeyWindow { makeKey() }
        }
        // Outside the repo: AppKit hands keys without ⌘ straight to whatever has the keyboard.
        if event.type == .keyDown, !event.modifierFlags.contains(.command), shortcut(event) || movesOn(event) { return }
        super.sendEvent(event)
    }

    // Outside the repo: AppKit's ⌃Tab moves out of a text view, but anywhere else here it leaves no window with the keyboard.
    private func movesOn(_ event: NSEvent) -> Bool {
        guard event.keyCode == 48, event.modifierFlags.contains(.control), !(firstResponder is NSTextView) else { return false }
        if event.modifierFlags.contains(.shift) { selectPreviousKeyView(nil) } else { selectNextKeyView(nil) }
        return true
    }

    private func shortcut(_ event: NSEvent) -> Bool {
        guard let shortcut = MessagesShortcut(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers, modifiers: event.modifierFlags) else { return false }
        if let text = firstResponder as? NSTextView, text.isEditable, shortcut == .escape || (shortcut.movesInText && !text.string.isEmpty) {
            return false
        }
        return handle(shortcut)
    }

    @discardableResult
    func handle(_ shortcut: MessagesShortcut) -> Bool {
        guard isKeyWindow, let view = contentView as? ChannelsView else { return false }
        return view.perform(shortcut)
    }
}

final class ChannelsView: QuietView {
    static let threadWidths: ClosedRange<CGFloat> = 320...460
    static let narrowestPlace: CGFloat = 360
    static let sidebarWidths: ClosedRange<CGFloat> = 180...360

    static let historyKept = 50

    let sidebar = ChannelSidebar()
    let pane = ChannelPane(role: .place)
    let threadPane = ChannelPane(role: .thread)
    let sidebarEdge = ResizeEdge()
    let threadEdge = ResizeEdge()
    private let panelEdge = PanelEdge()
    let jumpBox = JumpBoxView()
    let cheatsheet = CheatsheetView()
    let backlogSheet = BacklogSheet()
    private(set) var selection: ChannelSelection = .activity
    private(set) var book: ChannelBook?
    var readPriorities: ([Kitten]) -> Priorities = { _ in Priorities() }
    private(set) var priorities = Priorities()
    var history: [ChannelSelection] = [.activity]
    var historyIndex = 0
    var isTravelling = false
    var onCloseWindow: (() -> Void)?
    var onSettings: (() -> Void)?
    var onSeen: ((ChannelSelection) -> Void)?
    private(set) var keptUnread: Set<String> = []
    var chosenThreadWidth: CGFloat? {
        didSet {
            needsLayout = true
            needsDisplay = true
            onChooseThreadWidth?(chosenThreadWidth)
        }
    }
    var onChooseThreadWidth: ((CGFloat?) -> Void)?
    var chosenSidebarWidth: CGFloat? {
        didSet {
            needsLayout = true
            needsDisplay = true
            onChooseSidebarWidth?(chosenSidebarWidth)
        }
    }
    var onChooseSidebarWidth: ((CGFloat?) -> Void)?
    var isSidebarHidden = false {
        didSet {
            guard isSidebarHidden != oldValue else { return }
            if isSidebarHidden, let responder = window?.firstResponder as? NSView, responder.isDescendant(of: sidebar) { window?.makeFirstResponder(nil) }
            needsLayout = true
            needsDisplay = true
            onHideSidebar?(isSidebarHidden)
        }
    }
    var onHideSidebar: ((Bool) -> Void)?
    var onOpenThread: ((String) -> Void)? { didSet { panes.forEach { $0.onOpenThread = onOpenThread } } }
    var onCopy: ((String) -> Void)? { didSet { panes.forEach { $0.onCopy = onCopy } } }
    var onAction: ((MessagesAction) -> Void)? { didSet { panes.forEach { $0.onAction = onAction } } }
    var onOpenLink: ((URL) -> Void)? { didSet { panes.forEach { $0.onOpenLink = onOpenLink } } }
    var onShowOnPhone: ((String) -> Void)? { didSet { panes.forEach { $0.onShowOnPhone = onShowOnPhone } } }
    var onAttach: ((ChannelComposer, NSView) -> Void)? { didSet { panes.forEach { $0.onAttach = onAttach } } }
    var onMic: (() -> Void)?
    var onStopListening: (() -> Void)?
    var micTip = "" { didSet { panes.forEach { $0.composer.mic.toolTip = micTip } } }

    private var panes: [ChannelPane] { [pane, threadPane] }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(sidebar)
        addSubview(pane)
        addSubview(threadPane)
        addSubview(sidebarEdge)
        addSubview(threadEdge)
        addSubview(panelEdge)
        threadPane.isHidden = true
        threadEdge.isHidden = true
        sidebarEdge.onDrag = { [weak self] x in self?.dragSidebarEdge(to: x) }
        threadEdge.onDrag = { [weak self] x in self?.dragThreadEdge(to: x) }
        threadPane.parts = pane.parts
        jumpBox.isHidden = true
        cheatsheet.isHidden = true
        addSubview(jumpBox)
        addSubview(cheatsheet)
        backlogSheet.isHidden = true
        addSubview(backlogSheet)
        backlogSheet.onClose = { [weak self] in self?.backlogSheet.isHidden = true }
        pane.onBacklog = { [weak self] in self?.showBacklog(of: $0) }
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

    static func threadWidth(in room: CGFloat, chosen: CGFloat? = nil) -> CGFloat {
        let wanted = chosen ?? min(max(room * 0.45, threadWidths.lowerBound), threadWidths.upperBound)
        return max(min(wanted, room - narrowestPlace), threadWidths.lowerBound)
    }

    static func sidebarWidth(in width: CGFloat, chosen: CGFloat? = nil) -> CGFloat {
        let wanted = min(max(chosen ?? ChannelSidebar.width, sidebarWidths.lowerBound), sidebarWidths.upperBound)
        let room = width - Opal.Space.inset - narrowestPlace - threadWidths.lowerBound
        return min(wanted, max(room, ChannelSidebar.width))
    }

    func dragThreadEdge(to x: CGFloat) {
        chosenThreadWidth = Self.threadWidth(in: panel.width, chosen: panel.maxX - x)
    }

    func dragSidebarEdge(to x: CGFloat) {
        isSidebarHidden = x < Self.sidebarWidths.lowerBound / 2
        if !isSidebarHidden { chosenSidebarWidth = Self.sidebarWidth(in: bounds.width, chosen: x) }
    }

    var panel: NSRect {
        let inset = Opal.Space.inset
        let left = isSidebarHidden ? inset : Self.sidebarWidth(in: bounds.width, chosen: chosenSidebarWidth)
        return NSRect(x: left, y: inset, width: max(bounds.width - left - inset, 0), height: max(bounds.height - inset * 2, 0))
    }

    private func arrange() {
        let panel = panel
        sidebar.isHidden = isSidebarHidden
        sidebarEdge.isHidden = isSidebarHidden
        if !isSidebarHidden {
            sidebar.frame = NSRect(x: 0, y: 0, width: panel.minX, height: bounds.height)
            sidebarEdge.frame = NSRect(x: panel.minX - ResizeEdge.lineInset, y: panel.minY, width: 6, height: panel.height)
        }
        let thread = selection.thread == nil ? 0 : Self.threadWidth(in: panel.width, chosen: chosenThreadWidth)
        threadPane.isHidden = thread == 0
        threadEdge.isHidden = thread == 0
        pane.frame = NSRect(x: panel.minX, y: panel.minY, width: max(panel.width - thread, 0), height: panel.height)
        if thread > 0 {
            threadPane.frame = NSRect(x: panel.maxX - thread, y: panel.minY, width: thread, height: panel.height)
            threadEdge.frame = NSRect(x: threadPane.frame.minX - ResizeEdge.lineInset, y: panel.minY, width: 6, height: panel.height)
        }
        panelEdge.frame = panel
        jumpBox.frame = bounds
        cheatsheet.frame = bounds
        backlogSheet.frame = bounds
    }

    func show(_ book: ChannelBook) {
        let isFresh = self.book == nil
        self.book = book
        if let thread = selection.thread, let started = book.started[thread] { selection.thread = started }
        arrange()
        sidebar.show(book, selection: selection.place)
        pane.show(selection, in: book, isNewSelection: isFresh)
        if selection.thread != nil { threadPane.show(selection, in: book, isNewSelection: isFresh) }
        jumpBox.readAhead(book)
        if !jumpBox.isHidden { jumpBox.update(book) }
        onSeen?(selection)
    }

    func refreshPriorities() {
        guard let book else { return }
        let read = readPriorities(book.statuses.map(\.kitten))
        guard read != priorities else { return }
        priorities = read
        sidebar.focus = read.focus
        pane.backlogs = read.backlogs
        if !backlogSheet.isHidden, let kitten = backlogSheet.kitten {
            backlogSheet.show(read.backlogs[kitten] ?? Backlog(), of: kitten, named: book.name(of: ChannelID.kitten(kitten)))
        }
    }

    func showBacklog(of kitten: String) {
        refreshPriorities()
        guard let book else { return }
        closeJump()
        cheatsheet.isHidden = true
        backlogSheet.show(priorities.backlogs[kitten] ?? Backlog(), of: kitten, named: book.name(of: ChannelID.kitten(kitten)))
        backlogSheet.isHidden = false
    }

    func select(_ selection: ChannelSelection) {
        let old = self.selection
        self.selection = selection
        if selection.thread != old.thread { threadPane.leaveThread() }
        if selection != old { keptUnread = [] }
        if selection.place != old.place { backlogSheet.isHidden = true }
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

    var typingPane: ChannelPane? {
        panes.first { !$0.isHidden && window?.firstResponder === $0.composer.textView && $0.composer.target != nil }
    }

    func showListening(in listening: ChannelPane?) {
        panes.forEach { $0.composer.mic.showListening($0 === listening) }
    }

    func restyle() {
        sidebar.restyle()
        panes.forEach { $0.restyle() }
        jumpBox.needsDisplay = true
        cheatsheet.needsDisplay = true
        backlogSheet.needsLayout = true
        backlogSheet.needsDisplay = true
        backlogSheet.list.needsDisplay = true
        if let book { sidebar.show(book, selection: selection.place) }
        needsDisplay = true
    }

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

final class ResizeEdge: QuietView {
    static let lineInset: CGFloat = 2

    var onDrag: ((CGFloat) -> Void)?
    private var grab: CGFloat = 0

    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        grab = convert(event.locationInWindow, from: nil).x - Self.lineInset
    }

    override func mouseDragged(with event: NSEvent) {
        guard let superview else { return }
        onDrag?(superview.convert(event.locationInWindow, from: nil).x - grab)
    }
}

@MainActor
final class ChannelsWindow: NSObject, NSWindowDelegate {
    nonisolated static let size = NSSize(width: 1040, height: 620)
    nonisolated static let minimumSize = NSSize(width: 908, height: 440)
    private static let frameName = "Channels"
    private static let threadWidthKey = "ChannelsThreadWidth"
    private static let sidebarWidthKey = "ChannelsSidebarWidth"
    private static let sidebarHiddenKey = "ChannelsSidebarHidden"
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
        view.chosenSidebarWidth = (defaults.object(forKey: Self.sidebarWidthKey) as? Double).map { CGFloat($0) }
        view.onChooseSidebarWidth = { defaults.set($0.map(Double.init), forKey: Self.sidebarWidthKey) }
        view.isSidebarHidden = defaults.bool(forKey: Self.sidebarHiddenKey)
        view.onHideSidebar = { defaults.set($0, forKey: Self.sidebarHiddenKey) }
    }

    func show(_ book: ChannelBook, centeredIn visible: NSRect) {
        update(book)
        view.refreshPriorities()
        if !isPlaced {
            isPlaced = true
            if !panel.setFrameUsingName(Self.frameName) { panel.setFrame(Self.centered(in: visible), display: false) }
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

    var isInFront: Bool {
        panel.isVisible && panel.isOnActiveSpace && FrontWindow.isOnTop(panel.windowNumber)
    }

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

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
        Opal.forgetKept()
        onClose?()
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        updateTimer()
    }

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
            view.refreshPriorities()
        }
    }
}
