import AppKit

/// A button you can only press with the mouse. It never takes keyboard focus, so a
/// stray Return or Space can't press it, whatever is on the screen.
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

    /// Says something else for a moment, keeping its size.
    func flash(_ word: String) {
        let original = title
        title = word
        needsDisplay = true
        Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.title = original
                self?.needsDisplay = true
            }
        }
    }

    private var label: NSAttributedString {
        let color: NSColor
        switch style {
        case .filled: color = colors?.ink ?? Ink.pillText
        case .plain: color = Ink.text
        case .text: color = Ink.soft
        }
        return NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: style == .text ? .regular : .medium),
            .foregroundColor: isArmed ? color : color.withAlphaComponent(style == .filled ? 0.75 : 0.45),
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
            (pressing && isArmed ? Ink.press : hovering && isArmed ? Ink.press : Ink.hover).setFill()
            shape.fill()
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
    }

    override var acceptsFirstResponder: Bool { false }
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

    override func accessibilityPerformPress() -> Bool {
        guard isArmed else { return false }
        onPress?()
        return true
    }
}
