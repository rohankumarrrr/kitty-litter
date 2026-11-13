import AppKit

/// When a quiet control may take the keyboard: with Full Keyboard Access on, in a window that already has it, and
/// never from a click. So Tab reaches it, focus never makes a panel key or The Kitty Litter active, and pressing it
/// with the mouse leaves the keyboard where it was.
@MainActor
enum QuietFocus {
    /// The system's Keyboard navigation setting. Tests and the demo stand in for it.
    static var fullKeyboardAccess = { NSApplication.shared.isFullKeyboardAccessEnabled }

    static func allows(_ view: NSView) -> Bool {
        guard fullKeyboardAccess(), view.window?.isKeyWindow == true else { return false }
        let type = NSApplication.shared.currentEvent?.type
        return type != .leftMouseDown && type != .rightMouseDown && type != .otherMouseDown
    }

    static func shows(_ view: NSView) -> Bool {
        view.window?.isKeyWindow == true && view.window?.firstResponder === view
    }

    /// When one takes the keyboard. From then on its window gaining or losing the keyboard redraws it too, which
    /// AppKit doesn't do on its own, so the ring never stays on a window you've moved on from.
    static func took(_ view: NSView) {
        _ = keyChanges
        view.needsDisplay = true
    }

    private static let keyChanges: Void = {
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
                let window = note.object as? NSWindow
                MainActor.assumeIsolated { (window?.firstResponder as? NSView)?.needsDisplay = true }
            }
        }
    }()

    /// Just inside the shape, so nothing around it clips the ring. Opal's is violet.
    static func ring(_ rect: NSRect, radius: CGFloat, color: NSColor = MessagesInk.accent) {
        let ring = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: radius - 1, yRadius: radius - 1)
        ring.lineWidth = 2
        color.setStroke()
        ring.stroke()
    }

    static func isSpace(_ event: NSEvent) -> Bool { event.charactersIgnoringModifiers == " " }
}

/// A button you press with the mouse, or with Space once Tab has reached it. Only Space presses it, so a stray Return
/// can't, whatever is on the screen. Every one is an Opal capsule.
final class QuietButton: NSView {
    enum Style {
        /// The violet primary, one a view at most.
        case filled
        /// Quiet: on Opal's control colour with a faint hairline.
        case plain
        /// Just its words, until you point at it.
        case text
    }

    var onPress: (() -> Void)?
    /// A disarmed button shows dim and ignores clicks.
    var isArmed = true { didSet { needsDisplay = true } }
    /// A symbol drawn in place of its words, which VoiceOver still reads.
    var symbol: String? { didSet { needsDisplay = true } }
    /// Its symbol in the accent, while what it started is going.
    var isLit = false { didSet { needsDisplay = true } }

    let style: Style
    private var title: String
    private var hovering = false { didSet { needsDisplay = true } }
    private var pressing = false { didSet { needsDisplay = true } }
    private var flashed: String? { didSet { needsDisplay = true } }
    private var flashTimer: Timer?

    private static let height: CGFloat = 26
    private static func width(of label: NSAttributedString, _ style: Style) -> CGFloat {
        ceil(label.size().width) + (style == .text ? 14 : 24)
    }

    init(_ title: String, style: Style = .plain, onPress: (() -> Void)? = nil) {
        self.title = title
        self.style = style
        self.onPress = onPress
        super.init(frame: .zero)
        setFrameSize(NSSize(width: Self.width(of: label, style), height: Self.height))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Says something else from now on, at the size that takes.
    func retitle(_ word: String) {
        guard word != title else { return }
        title = word
        setFrameSize(NSSize(width: Self.width(of: label, style), height: Self.height))
        setAccessibilityLabel(word)
        needsDisplay = true
    }

    /// Says something else for a moment, keeping its size.
    func flash(_ word: String) {
        flashed = word
        flashTimer?.invalidate()
        flashTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.flashed = nil }
        }
    }

    private var ink: NSColor {
        guard isArmed else { return Ink.hex(Opal.faint) }
        switch style {
        case .filled: return MessagesInk.strong
        case .plain: return MessagesInk.text
        case .text: return hovering || pressing ? MessagesInk.text : MessagesInk.soft
        }
    }

    private var fill: UInt32? {
        let lit = isArmed && (hovering || pressing)
        switch style {
        case .filled: return pressing && isArmed ? Opal.primaryPressed : lit ? Opal.primaryHover : Opal.primary
        case .plain: return pressing && isArmed ? Opal.fieldEdge : lit ? Opal.controlHover : Opal.control
        case .text: return pressing && isArmed ? Opal.controlHover : lit ? Opal.control : nil
        }
    }

    private var label: NSAttributedString {
        NSAttributedString(string: flashed ?? title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: style == .text ? .regular : .medium),
            .foregroundColor: ink,
        ])
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        let shape = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        if let fill {
            Ink.hex(fill).withAlphaComponent(isArmed ? 1 : 0.4).setFill()
            shape.fill()
        }
        if style == .plain {
            let edge = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius - 0.5, yRadius: radius - 0.5)
            Ink.hex(Opal.fieldEdge).setStroke()
            edge.stroke()
        }
        if let symbol {
            drawSymbol(symbol)
        } else {
            let text = label
            let size = text.size()
            text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
        }
        if QuietFocus.shows(self) {
            // The primary's ring goes inside it, in white, since its fill is violet already.
            if style == .filled {
                QuietFocus.ring(bounds.insetBy(dx: 2, dy: 2), radius: radius - 2, color: MessagesInk.strong)
            } else {
                QuietFocus.ring(bounds, radius: radius)
            }
        }
    }

    private func drawSymbol(_ name: String) {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .medium))
        else { return }
        let color = isLit ? MessagesInk.link : ink
        let tinted = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        let size = image.size
        tinted.draw(in: NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height))
    }

    override var acceptsFirstResponder: Bool { QuietFocus.allows(self) }
    // AppKit's own reads the system's setting itself, which the demo and tests stand in for.
    override var canBecomeKeyView: Bool { QuietFocus.allows(self) && !isHiddenOrHasHiddenAncestor }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func mouseDown(with event: NSEvent) { pressing = true }

    override func mouseUp(with event: NSEvent) {
        pressing = false
        guard isArmed, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onPress?()
    }

    override func becomeFirstResponder() -> Bool {
        QuietFocus.took(self)
        return true
    }

    override func resignFirstResponder() -> Bool {
        pressing = false
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard QuietFocus.isSpace(event) else { return super.keyDown(with: event) }
        if !event.isARepeat { pressing = true }
    }

    override func keyUp(with event: NSEvent) {
        guard QuietFocus.isSpace(event), pressing else { return super.keyUp(with: event) }
        pressing = false
        if isArmed { onPress?() }
    }

    override func accessibilityPerformPress() -> Bool {
        guard isArmed else { return false }
        onPress?()
        return true
    }
}

extension QuietButton {
    static let micSide: CGFloat = 26

    /// A box's mic, which talks into it in place of typing.
    static func mic() -> QuietButton {
        let mic = QuietButton(CatWords.speak, style: .text)
        mic.symbol = "mic"
        mic.setFrameSize(NSSize(width: micSide, height: micSide))
        return mic
    }

    /// While it hears you it says so, and VoiceOver hears what pressing it does now.
    func showListening(_ listening: Bool) {
        guard listening != isLit else { return }
        isLit = listening
        symbol = listening ? "mic.fill" : "mic"
        setAccessibilityLabel(listening ? CatWords.doneSpeaking : CatWords.speak)
    }
}
