import AppKit
import ShadesCore

/// All your kittens and what they're up to, over the cat. Only there when you ask for it. Each sits on a Rimlight tile
/// in its own colour, with how it's doing in Opal's status colours.
@MainActor
final class KittenPanel {
    private static let width: CGFloat = 300
    private static let padding: CGFloat = 8
    private static let tickSeconds: TimeInterval = 0.2

    let panel = QuietPanel()
    private let balloon = BalloonView()
    /// Each group's small capitals, then its kittens, top to bottom.
    private var parts: [NSView] = []
    private var rows: [KittenRow] { parts.compactMap { $0 as? KittenRow } }
    private var timer: Timer?
    private var clickMonitor: Any?
    private var tick = 0

    var anchor: () -> (frame: NSRect, visible: NSRect) = { (.zero, .zero) }
    var onOpen: ((KittenStatus) -> Void)?
    var onChange: (() -> Void)?

    init() {
        panel.contentView = balloon
    }

    var isVisible: Bool { panel.isVisible }
    var frame: NSRect { panel.frame }

    /// Opens the panel, or brings it up to date if it's already open. The kittens taking work come first, and the
    /// ones not set up yet are a group of their own.
    func show(_ statuses: [KittenStatus]) {
        parts.forEach { $0.removeFromSuperview() }
        let groups = [
            (CatWords.kittensTitle, statuses.filter { $0.state != .notSetUp }),
            (CatWords.kittenState(.notSetUp), statuses.filter { $0.state == .notSetUp }),
        ].filter { !$0.1.isEmpty }
        parts = groups.flatMap { title, members -> [NSView] in
            [KittenGroupLabel(title)] + members.map { status in
                let row = KittenRow(status: status)
                row.onPress = { [weak self] in
                    self?.onOpen?(status)
                    self?.hide()
                }
                return row
            }
        }
        parts.forEach(balloon.addSubview)
        layout()
        rows.forEach { $0.update(tick: tick) }

        guard !panel.isVisible else { return }
        panel.orderFrontRegardless()
        // Under Reduce Motion each kitten holds its first drawing.
        if !Motion.isReduced {
            let timer = Timer(timeInterval: Self.tickSeconds, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.advance() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { if !ClickAway.isPaused { self?.hide() } }
        }
        onChange?()
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        tick = 0
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

    private func height(of part: NSView) -> CGFloat {
        part is KittenGroupLabel ? KittenGroupLabel.height : KittenRow.height
    }

    private func layout() {
        place()
        var top = balloon.body.maxY - Self.padding
        for part in parts {
            let height = height(of: part)
            part.frame = NSRect(x: Self.padding, y: top - height, width: Self.width - Self.padding * 2, height: height)
            top -= height
        }
    }

    private func place() {
        let height = parts.map(height(of:)).reduce(0, +) + Self.padding * 2 + BubbleLayout.tailHeight
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

/// Small capitals over a group of kittens.
private final class KittenGroupLabel: NSView {
    static var height: CGFloat { ceil(MessagesInk.label * 1.3) + 16 }
    private let title: String

    init(_ title: String) {
        self.title = title
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let words = MessagesInk.label(title)
        words.draw(at: NSPoint(x: 10, y: bounds.height - words.size().height - 5))
    }
}

final class KittenRow: NSView {
    static let tile: CGFloat = 40
    static var height: CGFloat { max(56, ceil(nameFont.lineHeight + metaFont.lineHeight) + 22) }
    private static var nameFont: NSFont { MessagesInk.font(ofSize: MessagesInk.title, weight: .semibold) }
    private static var metaFont: NSFont { MessagesInk.font(ofSize: MessagesInk.meta) }

    var onPress: (() -> Void)?
    let status: KittenStatus
    private var tick = 0
    private var hovering = false { didSet { needsDisplay = true } }

    init(status: KittenStatus) {
        self.status = status
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("\(status.kitten.name), \(status.kitten.role), \(CatWords.kittenState(status.state))")
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
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onPress?()
    }
    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }

    /// Lilac while it works, rose when it needs you and mint once it's done, the same as the glint on its cat.
    static func color(for state: KittenStatus.State) -> UInt32? {
        switch state {
        case .working: Opal.lilac
        case .needsYou: Opal.errorText
        case .idle: Opal.good
        case .notSetUp: nil
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if hovering {
            Ink.hex(Opal.controlHover).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: Opal.Corner.control, yRadius: Opal.Corner.control).fill()
        }
        drawKitten(in: NSRect(x: 8, y: ((bounds.height - Self.tile) / 2).rounded(), width: Self.tile, height: Self.tile))

        let left: CGFloat = 8 + Self.tile + 12
        let width = bounds.width - left - 10
        let (nameFont, metaFont) = (Self.nameFont, Self.metaFont)
        let top = ((bounds.height - nameFont.lineHeight - metaFont.lineHeight - 2) / 2).rounded()
        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        let notSetUp = status.state == .notSetUp
        NSAttributedString(string: status.kitten.name, attributes: [
            .font: nameFont,
            .foregroundColor: notSetUp ? MessagesInk.soft : MessagesInk.strong,
            .paragraphStyle: truncating,
        ]).draw(in: NSRect(x: left, y: top, width: width, height: nameFont.lineHeight))

        let line = NSMutableAttributedString()
        var lineLeft = left
        let lineTop = top + nameFont.lineHeight + 2
        if let color = Self.color(for: status.state) {
            let dot: CGFloat = 6
            Ink.hex(color).setFill()
            NSBezierPath(ovalIn: NSRect(x: left, y: lineTop + (metaFont.lineHeight - dot) / 2, width: dot, height: dot)).fill()
            lineLeft += dot + 5
            line.append(NSAttributedString(string: "\(CatWords.kittenState(status.state)) · ", attributes: [.font: metaFont, .foregroundColor: Ink.hex(color)]))
        }
        line.append(NSAttributedString(string: status.kitten.role, attributes: [.font: metaFont, .foregroundColor: MessagesInk.soft]))
        line.addAttribute(.paragraphStyle, value: truncating, range: NSRange(location: 0, length: line.length))
        line.draw(in: NSRect(x: lineLeft, y: lineTop, width: left + width - lineLeft, height: metaFont.lineHeight))
    }

    /// Its cat on a tile lit in its colour. One that isn't set up yet is faded, tile and all.
    private func drawKitten(in tile: NSRect) {
        let jacket = ChannelSpeakerLook.color(of: status.kitten)
        let context = NSGraphicsContext.current?.cgContext
        let faded = status.state == .notSetUp
        if faded {
            context?.setAlpha(0.45)
            context?.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        Opal.tile(in: tile, light: jacket.map(Opal.Light.of) ?? .shades)
        CatStamp.draw(status.pose(tick: tick), jacket: jacket, in: tile.insetBy(dx: 4, dy: 4), on: self)
        if faded {
            context?.endTransparencyLayer()
            context?.setAlpha(1)
        }
    }
}

private extension NSFont {
    var lineHeight: CGFloat { ceil(ascender - descender + leading) }
}
