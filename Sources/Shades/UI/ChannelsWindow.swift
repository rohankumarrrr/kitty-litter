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

/// The sidebar and the pane. They're apart from the window so they can be drawn with no window on the screen.
final class ChannelsView: QuietView {
    /// What a theme file can be: T3 Code's and VS Code's are JSON, and iTerm2's a property list or JSON.
    static let themeFiles: Set<String> = ["json", "itermcolors", "plist"]

    let sidebar = ChannelSidebar()
    let pane = ChannelPane()
    private(set) var selection: ChannelSelection = .needsYou
    private var book: ChannelBook?
    /// You've seen what's there, which is what takes its unread dot away.
    var onSeen: ((ChannelSelection) -> Void)?
    /// A theme file let go of anywhere on the window.
    var onDropTheme: ((URL) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(sidebar)
        addSubview(pane)
        sidebar.onSelect = { [weak self] in self?.select($0) }
        pane.onSelect = { [weak self] in self?.select($0) }
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        arrange()
    }

    private func arrange() {
        let width = ChannelSidebar.width
        sidebar.frame = NSRect(x: 0, y: 0, width: width, height: bounds.height)
        pane.frame = NSRect(x: width, y: 0, width: max(bounds.width - width, 0), height: bounds.height)
    }

    /// The selection survives closing the window, since it holds only IDs.
    func show(_ book: ChannelBook) {
        let isFresh = self.book == nil
        self.book = book
        // A new topic carries on in its own thread once T3 has one.
        if case .thread(let id, let channel) = selection, let started = book.started[id] { selection = .thread(started, in: channel) }
        arrange()
        sidebar.show(book, selection: selection.place)
        pane.show(selection, in: book, isNewSelection: isFresh)
        onSeen?(selection)
    }

    func select(_ selection: ChannelSelection) {
        self.selection = selection
        guard let book else { return }
        sidebar.show(book, selection: selection.place)
        pane.show(selection, in: book, isNewSelection: true)
        onSeen?(selection)
    }

    /// Draws everything again in the colours there are now, since a row keeps the colours it was made with.
    func restyle() {
        sidebar.restyle()
        pane.restyle()
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
    }
}

/// The Messages window: what needs you, a group chat with every kitten, your DMs with each, and what
/// they say to each other. Closing it keeps everything as it was, so it opens again just as you left it.
@MainActor
final class ChannelsWindow: NSObject, NSWindowDelegate {
    nonisolated static let size = NSSize(width: 820, height: 560)
    nonisolated static let minimumSize = NSSize(width: 640, height: 420)
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
        if tick % Self.ticksPerTimeRefresh == 0 { view.pane.refreshTimes() }
    }
}
