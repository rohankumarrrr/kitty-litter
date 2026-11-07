import AppKit
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
        backgroundColor = MessagesInk.paper
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true
        title = CatWords.messagesTitle
        // Shades' own captures leave out all its windows. This keeps Messages out of anyone else's too, such as a
        // kitten's own screen tools, so one kitten can't be shown another's messages.
        sharingType = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        QuietPanel.performEdit(event, from: self) || super.performKeyEquivalent(with: event)
    }

    /// A click raises it without activating anything.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { orderFrontRegardless() }
        super.sendEvent(event)
    }
}

/// The sidebar, the pane for the place you're looking at, and beside it a thread's pane when one is open, as Slack
/// lays them out. They're apart from the window so they can be drawn with no window on the screen.
final class ChannelsView: QuietView {
    /// What a theme file can be: T3 Code's and VS Code's are JSON, and iTerm2's a property list or JSON.
    static let themeFiles: Set<String> = ["json", "itermcolors", "plist"]
    static let threadWidths: ClosedRange<CGFloat> = 320...460

    let sidebar = ChannelSidebar()
    let pane = ChannelPane(role: .place)
    let threadPane = ChannelPane(role: .thread)
    private(set) var selection: ChannelSelection = .activity
    private(set) var book: ChannelBook?
    /// You've seen what's there, which is what takes its unread dot away.
    var onSeen: ((ChannelSelection) -> Void)?
    /// A theme file let go of anywhere on the window.
    var onDropTheme: ((URL) -> Void)?
    /// Opens a thread in T3.
    var onOpenThread: ((String) -> Void)? { didSet { panes.forEach { $0.onOpenThread = onOpenThread } } }
    var onCopy: ((String) -> Void)? { didSet { panes.forEach { $0.onCopy = onCopy } } }
    var onAction: ((MessagesAction) -> Void)? { didSet { panes.forEach { $0.onAction = onAction } } }

    private var panes: [ChannelPane] { [pane, threadPane] }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(sidebar)
        addSubview(pane)
        addSubview(threadPane)
        threadPane.isHidden = true
        threadPane.parts = pane.parts
        sidebar.onSelect = { [weak self] in self?.select(ChannelSelection($0)) }
        for pane in panes {
            pane.onSelect = { [weak self] in self?.select($0) }
            pane.onOpen = { [weak self] thread, place, typing, report in self?.open(thread: thread, from: place, typing: typing, replyingTo: report) }
            pane.onClose = { [weak self] in self?.closeThread() }
            pane.composer.onEscape = { [weak self] in self?.closeThread() }
        }
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        arrange()
    }

    /// How wide a thread's pane is beside the rest of the window.
    static func threadWidth(in width: CGFloat) -> CGFloat {
        min(max((width - ChannelSidebar.width) * 0.45, threadWidths.lowerBound), threadWidths.upperBound)
    }

    private func arrange() {
        let width = ChannelSidebar.width
        sidebar.frame = NSRect(x: 0, y: 0, width: width, height: bounds.height)
        let thread = selection.thread == nil ? 0 : Self.threadWidth(in: bounds.width)
        threadPane.isHidden = thread == 0
        pane.frame = NSRect(x: width, y: 0, width: max(bounds.width - width - thread, 0), height: bounds.height)
        if thread > 0 { threadPane.frame = NSRect(x: bounds.width - thread, y: 0, width: thread, height: bounds.height) }
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
        onSeen?(selection)
    }

    func select(_ selection: ChannelSelection) {
        let old = self.selection
        self.selection = selection
        if selection.thread != old.thread { threadPane.forgetReport() }
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

    func closeThread() {
        guard selection.thread != nil else { return }
        if window?.firstResponder === threadPane.composer.textView { window?.makeFirstResponder(nil) }
        select(selection.closed)
    }

    /// The pane whose box has the keyboard.
    var typingPane: ChannelPane? {
        panes.first { !$0.isHidden && window?.firstResponder === $0.composer.textView && $0.composer.target != nil }
    }

    /// Draws everything again in the colours there are now, since a row keeps the colours it was made with.
    func restyle() {
        sidebar.restyle()
        panes.forEach { $0.restyle() }
        if let book { sidebar.show(book, selection: selection.place) }
        needsDisplay = true
    }

    private func themeFile(in drag: NSDraggingInfo) -> URL? {
        let files = drag.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard files.count == 1, let file = files.first, Self.themeFiles.contains(file.pathExtension.lowercased()) else { return nil }
        return file
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        themeFile(in: sender) == nil ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let file = themeFile(in: sender) else { return false }
        onDropTheme?(file)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        MessagesInk.paper.setFill()
        dirtyRect.fill()
        guard selection.thread != nil else { return }
        MessagesInk.line.setFill()
        NSRect(x: threadPane.frame.minX, y: 0, width: 1, height: bounds.height).fill()
    }
}

/// The Messages window: Activity, your threads, #general, a channel for each kitten and your DM with the cat, with a
/// thread's pane beside them. Closing it keeps everything as it was, so it opens again just as you left it.
@MainActor
final class ChannelsWindow: NSObject, NSWindowDelegate {
    nonisolated static let size = NSSize(width: 1040, height: 620)
    /// Room for the sidebar, a channel and a thread's pane beside it.
    nonisolated static let minimumSize = NSSize(width: 900, height: 440)
    private static let frameName = "Channels"
    private static let tickSeconds: TimeInterval = 0.2
    private static let ticksPerTimeRefresh = 300

    let panel = ChannelsPanel()
    let view = ChannelsView(frame: NSRect(origin: .zero, size: ChannelsWindow.size))
    var onClose: (() -> Void)?

    private var isPlaced = false
    private var timer: Timer?
    private var tick = 0

    override init() {
        super.init()
        panel.contentView = view
        panel.delegate = self
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

    /// Messages in a theme's colours, or Shades' own with `nil`. Its buttons, scrollers and cats follow the theme's
    /// light or dark.
    func apply(_ theme: ColorTheme?) {
        MessagesInk.theme = theme
        panel.appearance = MessagesInk.appearance
        panel.backgroundColor = MessagesInk.paper
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
