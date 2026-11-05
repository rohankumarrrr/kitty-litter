import AppKit
import ShadesCore

/// All your kittens and what they're up to, over the cat. Only there when you ask for it.
@MainActor
final class KittenPanel {
    private static let width: CGFloat = 280
    private static let rowHeight: CGFloat = 46
    private static let padding: CGFloat = 6
    private static let tickSeconds: TimeInterval = 0.2

    let panel = QuietPanel()
    private let balloon = BalloonView()
    private let renderer = CatRenderer()
    private var rows: [KittenRow] = []
    private var timer: Timer?
    private var clickMonitor: Any?
    private var tick = 0

    var anchor: () -> (frame: NSRect, visible: NSRect) = { (.zero, .zero) }
    var onOpen: ((String) -> Void)?
    var onChange: (() -> Void)?

    init() {
        panel.contentView = balloon
    }

    var isVisible: Bool { panel.isVisible }
    var frame: NSRect { panel.frame }

    /// Opens the panel, or brings it up to date if it's already open.
    func show(_ statuses: [KittenStatus]) {
        rows.forEach { $0.removeFromSuperview() }
        rows = statuses.map { status in
            let row = KittenRow(status: status, renderer: renderer)
            row.onPress = { [weak self] threadID in
                self?.onOpen?(threadID)
                self?.hide()
            }
            balloon.addSubview(row)
            return row
        }
        layout()
        rows.forEach { $0.update(tick: tick) }

        guard !panel.isVisible else { return }
        panel.orderFrontRegardless()
        let timer = Timer(timeInterval: Self.tickSeconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
        onChange?()
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        panel.orderOut(nil)
        onChange?()
    }

    func reposition() {
        guard panel.isVisible else { return }
        place()
    }

    private func advance() {
        tick += 1
        rows.forEach { $0.update(tick: tick) }
    }

    private func layout() {
        place()
        let body = balloon.body
        for (index, row) in rows.enumerated() {
            row.frame = NSRect(
                x: Self.padding,
                y: body.maxY - Self.padding - Self.rowHeight * CGFloat(index + 1),
                width: Self.width - Self.padding * 2,
                height: Self.rowHeight
            )
        }
    }

    private func place() {
        let height = Self.rowHeight * CGFloat(rows.count) + Self.padding * 2 + BubbleLayout.tailHeight
        let (over, visible) = anchor()
        let placement = BubbleLayout.place(size: NSSize(width: Self.width, height: height), over: over, in: visible)
        balloon.tailX = placement.tailX
        balloon.tailOnTop = placement.below
        panel.setFrame(placement.frame, display: true)
        balloon.frame = NSRect(origin: .zero, size: placement.frame.size)
        balloon.needsDisplay = true
        panel.invalidateShadow()
    }
}

private final class KittenRow: NSView {
    private static let scale: CGFloat = 2

    var onPress: ((String) -> Void)?
    private let status: KittenStatus
    private let renderer: CatRenderer
    private var tick = 0
    private var hovering = false { didSet { needsDisplay = true } }

    init(status: KittenStatus, renderer: CatRenderer) {
        self.status = status
        self.renderer = renderer
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(status.threadID == nil ? .staticText : .button)
        let count = status.things > 0 ? ", \(CatWords.things(status.things))" : ""
        setAccessibilityLabel("\(status.kitten.name), \(status.kitten.role), \(CatWords.kittenState(status.state))\(count)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { false }

    func update(tick: Int) {
        self.tick = tick
        // A kitten that isn't set up doesn't move, so there's nothing to redraw.
        if status.state != .notSetUp { needsDisplay = true }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        guard status.threadID != nil else { return }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)), let threadID = status.threadID else { return }
        onPress?(threadID)
    }

    override func draw(_ dirtyRect: NSRect) {
        if hovering {
            Ink.hover.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9).fill()
        }
        drawKitten()

        let notSetUp = status.state == .notSetUp
        let left: CGFloat = 50
        let width = bounds.width - left - 28
        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        // The name gives up room for the count, so truncating it can't hide how much there is.
        var nameWidth = width
        if status.things > 0 {
            let things = NSAttributedString(string: CatWords.things(status.things), attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: Ink.soft,
            ])
            let thingsWidth = ceil(things.size().width)
            things.draw(at: NSPoint(x: left + width - thingsWidth, y: 8))
            nameWidth -= thingsWidth + 6
        }
        NSAttributedString(string: status.kitten.name, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: notSetUp ? Ink.soft : Ink.text,
            .paragraphStyle: truncating,
        ]).draw(in: NSRect(x: left, y: 6, width: nameWidth, height: 17))
        NSAttributedString(string: "\(status.kitten.role) · \(CatWords.kittenState(status.state))", attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: Ink.soft,
            .paragraphStyle: truncating,
        ]).draw(in: NSRect(x: left, y: 24, width: width, height: 14))

        // A square dot, to match the cat's pixels and the dashboard.
        Self.color(for: status.state).setFill()
        NSBezierPath(rect: NSRect(x: bounds.width - 20, y: bounds.midY - 4, width: 8, height: 8)).fill()
    }

    private func drawKitten() {
        let side = CGFloat(CatArt.grid) * Self.scale
        let theme: CatTheme = effectiveAppearance.isDark ? .dark : .light
        let cgImage = renderer.image(for: status.pose(tick: tick), theme: theme, jacket: status.kitten.color)
        let image = NSImage(cgImage: cgImage, size: NSSize(width: side, height: side))
        image.draw(
            in: NSRect(x: 10, y: (bounds.height - side) / 2, width: side, height: side),
            from: .zero,
            operation: .sourceOver,
            fraction: status.state == .notSetUp ? 0.4 : 1,
            respectFlipped: true,
            hints: [.interpolation: NSNumber(value: NSImageInterpolation.none.rawValue)]
        )
    }

    /// The same colours as the glint and the dashboard, so a status always looks the same.
    private static func color(for state: KittenStatus.State) -> NSColor {
        switch state {
        case .working: return Ink.hex(CatGlint.thinking(bright: true).color!)
        case .needsYou: return Ink.hex(CatGlint.attention(bright: true).color!)
        case .idle: return Ink.soft
        case .notSetUp: return .clear
        }
    }
}
