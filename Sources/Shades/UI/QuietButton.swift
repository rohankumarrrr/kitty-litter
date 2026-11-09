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

    /// Just inside the shape, so nothing around it clips the ring.
    static func ring(_ rect: NSRect, radius: CGFloat, color: NSColor = MessagesInk.link) {
        let ring = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: radius - 1, yRadius: radius - 1)
        ring.lineWidth = 2
        color.setStroke()
        ring.stroke()
    }

    static func isSpace(_ event: NSEvent) -> Bool { event.charactersIgnoringModifiers == " " }
}

/// A button you press with the mouse, or with Space once Tab has reached it. Only Space presses it, so a stray Return
/// can't, whatever is on the screen.
final class QuietButton: NSView {
    enum Style {
        case filled, plain, text
    }

    var onPress: (() -> Void)?
    /// A disarmed button shows dim and ignores clicks.
    var isArmed = true { didSet { needsDisplay = true } }
    /// A filled one's own colours, such as a theme's, in place of the plain pill.
    var colors: (fill: NSColor, ink: NSColor)? { didSet { needsDisplay = true } }

    let style: Style
    private var title: String
    private var hovering = false { didSet { needsDisplay = true } }
    private var pressing = false { didSet { needsDisplay = true } }
    private var flashed: String? { didSet { needsDisplay = true } }
    private var flashTimer: Timer?

    private static let height: CGFloat = 26

    init(_ title: String, style: Style = .plain, onPress: (() -> Void)? = nil) {
        self.title = title
        self.style = style
        self.onPress = onPress
        super.init(frame: .zero)
        setFrameSize(NSSize(width: ceil(label.size().width) + (style == .text ? 12 : 22), height: Self.height))
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
        setFrameSize(NSSize(width: ceil(label.size().width) + (style == .text ? 12 : 22), height: Self.height))
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
        switch style {
        case .filled: colors?.ink ?? Ink.pillText
        case .plain: Ink.text
        case .text: Ink.soft
        }
    }

    private var label: NSAttributedString {
        NSAttributedString(string: flashed ?? title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: style == .text ? .regular : .medium),
            .foregroundColor: isArmed ? ink : ink.withAlphaComponent(style == .filled ? 0.75 : 0.45),
        ])
    }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        switch style {
        case .filled:
            let fill = colors?.fill ?? Ink.pill
            (isArmed ? fill : fill.withAlphaComponent(0.4)).setFill()
            shape.fill()
            if pressing { NSColor(white: 0.5, alpha: 0.3).setFill(); shape.fill() }
        case .plain:
            ((hovering || pressing) && isArmed ? Ink.press : Ink.hover).setFill()
            shape.fill()
            // A shade more than hover, so pressing shows.
            if pressing && isArmed { Ink.hover.setFill(); shape.fill() }
        case .text:
            if pressing && isArmed {
                Ink.press.setFill()
                shape.fill()
            } else if hovering && isArmed {
                Ink.hover.setFill()
                shape.fill()
            }
        }
        let text = label
        let size = text.size()
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
        if QuietFocus.shows(self) {
            // A filled one's ring goes inside it, in its ink, since its fill can be the accent.
            if style == .filled {
                QuietFocus.ring(bounds.insetBy(dx: 2, dy: 2), radius: 6, color: ink)
            } else {
                QuietFocus.ring(bounds, radius: 8)
            }
        }
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
