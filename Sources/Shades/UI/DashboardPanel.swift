import AppKit
import ShadesCore

/// A short list of what your agents are up to. Click one to open it in T3.
@MainActor
final class DashboardPanel {
    private static let width: CGFloat = 300
    private static let rowHeight: CGFloat = 44
    private static let maxVisibleRows: CGFloat = 7
    private static let padding: CGFloat = 6

    let panel = QuietPanel()
    private let balloon = BalloonView()
    private let scroll = NSScrollView()
    private let list = FlippedView()
    private let empty = NSTextField(labelWithString: "Nothing running. I'm napping.")
    private var clickMonitor: Any?
    private var threads: [AgentThread] = []

    var onOpen: ((String) -> Void)?
    var onHide: (() -> Void)?
    /// The top-right corner to hang from, under the menu bar icon.
    var anchor: () -> NSPoint = { .zero }

    init() {
        panel.contentView = balloon
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = list
        balloon.addSubview(scroll)
        empty.font = .systemFont(ofSize: 13)
        empty.textColor = Ink.soft
        balloon.addSubview(empty)
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show() {
        reload()
        panel.orderFrontRegardless()
        if clickMonitor == nil {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.hide() }
            }
        }
    }

    func hide() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        panel.orderOut(nil)
        onHide?()
    }

    func update(_ threads: [AgentThread]) {
        self.threads = threads
        if panel.isVisible { reload() }
    }

    private func reload() {
        list.subviews.forEach { $0.removeFromSuperview() }
        let padding = Self.padding
        let inner = Self.width - padding * 2
        let tailBand = BubbleLayout.tailHeight

        let rows = CGFloat(threads.count)
        let visibleRows = min(rows, Self.maxVisibleRows)
        let contentHeight = threads.isEmpty ? 44 : visibleRows * Self.rowHeight
        let height = contentHeight + padding * 2 + tailBand

        let top = anchor()
        panel.setFrame(NSRect(x: top.x - Self.width, y: top.y - height, width: Self.width, height: height), display: false)

        // No tail on this one: it hangs from the menu bar rather than speaking.
        balloon.frame = NSRect(x: 0, y: 0, width: Self.width, height: height)
        let body = balloon.body
        scroll.frame = NSRect(x: padding, y: body.minY + padding, width: inner, height: contentHeight)
        list.frame = NSRect(x: 0, y: 0, width: inner, height: rows * Self.rowHeight)
        empty.isHidden = !threads.isEmpty
        scroll.isHidden = threads.isEmpty
        empty.sizeToFit()
        empty.frame.origin = NSPoint(x: padding + 10, y: body.midY - empty.frame.height / 2)

        for (index, thread) in threads.enumerated() {
            let row = ThreadRow(thread: thread, frame: NSRect(x: 0, y: CGFloat(index) * Self.rowHeight, width: inner, height: Self.rowHeight))
            row.onPress = { [weak self] in
                self?.onOpen?(thread.id)
                self?.hide()
            }
            list.addSubview(row)
        }
        balloon.needsDisplay = true
        panel.invalidateShadow()
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class ThreadRow: NSView {
    var onPress: (() -> Void)?
    private let thread: AgentThread
    private var hovering = false { didSet { needsDisplay = true } }

    init(thread: AgentThread, frame: NSRect) {
        self.thread = thread
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("\(thread.title), \(CatWords.status(thread))")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        if hovering {
            Ink.hover.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9).fill()
        }
        // A square dot, to match the cat's pixels.
        let dot = NSRect(x: 10, y: 11, width: 8, height: 8)
        thread.dotColor.setFill()
        NSBezierPath(rect: dot).fill()

        let width = bounds.width - 38
        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        NSAttributedString(string: thread.title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: Ink.text,
            .paragraphStyle: truncating,
        ]).draw(in: NSRect(x: 28, y: 6, width: width, height: 17))
        let detail = [thread.projectTitle, CatWords.status(thread)].compactMap { $0 }.joined(separator: " · ")
        NSAttributedString(string: detail, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: Ink.soft,
            .paragraphStyle: truncating,
        ]).draw(in: NSRect(x: 28, y: 24, width: width, height: 14))
    }
}
