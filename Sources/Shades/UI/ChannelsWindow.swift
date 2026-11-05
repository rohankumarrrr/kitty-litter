import AppKit
import ShadesCore

/// A window that stays open beside your work without ever taking the keyboard, so the app you're
/// in keeps its selection and the cat can still tell what you're looking at. It isn't a
/// `QuietPanel`, because those float over everything, and this one is big enough to get in the way.
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
        backgroundColor = Ink.paper
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// A click raises it without activating anything.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { orderFrontRegardless() }
        super.sendEvent(event)
    }
}

/// The sidebar and the pane. They're apart from the window so they can be drawn with no window on the screen.
final class ChannelsView: QuietView {
    let sidebar = ChannelSidebar()
    let pane = ChannelPane()
    private(set) var selection: ChannelSelection = .issues
    private var book: ChannelBook?

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(sidebar)
        addSubview(pane)
        sidebar.onSelect = { [weak self] in self?.select($0) }
        pane.onSelect = { [weak self] in self?.select($0) }
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
        arrange()
        sidebar.show(book, selection: selection)
        pane.show(selection, in: book, isNewSelection: isFresh)
    }

    func select(_ selection: ChannelSelection) {
        self.selection = selection
        guard let book else { return }
        sidebar.show(book, selection: selection)
        pane.show(selection, in: book, isNewSelection: true)
    }

    func forget() {
        book = nil
        pane.forget()
    }

    override func draw(_ dirtyRect: NSRect) {
        Ink.paper.setFill()
        dirtyRect.fill()
    }
}

/// The Channels window: your DMs with each kitten, what they say to each other, and what each has open.
/// It only reads, and closing it forgets every word.
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
        view.forget()
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
