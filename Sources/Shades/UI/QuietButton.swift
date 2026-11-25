import AppKit

@MainActor
enum QuietFocus {
    static var fullKeyboardAccess = { NSApplication.shared.isFullKeyboardAccessEnabled }

    static func allows(_ view: NSView) -> Bool {
        guard fullKeyboardAccess(), view.window?.isKeyWindow == true else { return false }
        let type = NSApplication.shared.currentEvent?.type
        return type != .leftMouseDown && type != .rightMouseDown && type != .otherMouseDown
    }

    static func shows(_ view: NSView) -> Bool {
        view.window?.isKeyWindow == true && view.window?.firstResponder === view
    }

    // Outside the repo: AppKit doesn't redraw a view when its window gains or loses the keyboard.
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

    static func ring(_ rect: NSRect, radius: CGFloat, color: NSColor = MessagesInk.accent) {
        let ring = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: radius - 1, yRadius: radius - 1)
        ring.lineWidth = 2
        color.setStroke()
        ring.stroke()
    }

    static func isSpace(_ event: NSEvent) -> Bool { event.charactersIgnoringModifiers == " " }

    static func isOpen(_ view: NSView) -> Bool {
        var ancestor = view.superview
        while let next = ancestor {
            if (next as? TabGate)?.letsTabIn == false { return false }
            ancestor = next.superview
        }
        return true
    }
}

@MainActor
protocol TabGate: NSView {
    var letsTabIn: Bool { get }
}

final class QuietButton: NSView {
    enum Style {
        case filled
        case plain
        case text
    }

    var onPress: (() -> Void)?
    var isArmed = true { didSet { needsDisplay = true } }
    var symbol: String? { didSet { needsDisplay = true } }
    var isLit = false { didSet { needsDisplay = true } }
    var showsChevrons = false { didSet { setFrameSize(NSSize(width: naturalWidth, height: Self.height)); needsDisplay = true } }

    let style: Style
    private var title: String
    private var hovering = false { didSet { needsDisplay = true } }
    private var pressing = false { didSet { needsDisplay = true } }
    private var flashed: String? { didSet { needsDisplay = true } }
    private var flashTimer: Timer?

    private static let height: CGFloat = 26
    private static let chevronsWidth: CGFloat = 13
    private var naturalWidth: CGFloat {
        ceil(label.size().width) + (style == .text ? 14 : 24) + (showsChevrons ? Self.chevronsWidth : 0)
    }

    init(_ title: String, style: Style = .plain, onPress: (() -> Void)? = nil) {
        self.title = title
        self.style = style
        self.onPress = onPress
        super.init(frame: .zero)
        setFrameSize(NSSize(width: naturalWidth, height: Self.height))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func retitle(_ word: String) {
        guard word != title else { return }
        title = word
        setFrameSize(NSSize(width: naturalWidth, height: Self.height))
        setAccessibilityLabel(word)
        needsDisplay = true
    }

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
            .font: MessagesInk.font(ofSize: MessagesInk.meta + 1, weight: style == .text ? .regular : .medium),
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
            let room = bounds.width - (showsChevrons ? Self.chevronsWidth : 0)
            text.draw(at: NSPoint(x: (room - size.width) / 2, y: (bounds.height - size.height) / 2))
            if showsChevrons { drawChevrons(rightOf: (room + size.width) / 2) }
        }
        if QuietFocus.shows(self) {
            if style == .filled {
                QuietFocus.ring(bounds.insetBy(dx: 2, dy: 2), radius: radius - 2, color: MessagesInk.strong)
            } else {
                QuietFocus.ring(bounds, radius: radius)
            }
        }
    }

    private func drawChevrons(rightOf x: CGFloat) {
        guard let image = Self.symbol("chevron.up.chevron.down", size: 8, weight: .semibold, color: ink) else { return }
        let size = image.size
        image.draw(in: NSRect(x: x + 5, y: (bounds.height - size.height) / 2, width: size.width, height: size.height))
    }

    private func drawSymbol(_ name: String) {
        guard let image = Self.symbol(name, size: 13, weight: .medium, color: isLit ? MessagesInk.link : ink) else { return }
        let size = image.size
        image.draw(in: NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height))
    }

    private static var symbols: [String: NSImage] = [:]

    private static func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSImage? {
        let key = "\(name) \(size) \(weight.rawValue) \(color)"
        if let tinted = symbols[key] { return tinted }
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: weight))
        else { return nil }
        let tinted = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        symbols[key] = tinted
        return tinted
    }

    override var acceptsFirstResponder: Bool { QuietFocus.allows(self) }
    override var canBecomeKeyView: Bool { QuietFocus.allows(self) && !isHiddenOrHasHiddenAncestor && QuietFocus.isOpen(self) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

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
        scrollToVisible(bounds)
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

    static func mic() -> QuietButton {
        let mic = QuietButton(CatWords.speak, style: .text)
        mic.symbol = "mic"
        mic.setFrameSize(NSSize(width: micSide, height: micSide))
        return mic
    }

    func showListening(_ listening: Bool) {
        guard listening != isLit else { return }
        isLit = listening
        symbol = listening ? "mic.fill" : "mic"
        setAccessibilityLabel(listening ? CatWords.doneSpeaking : CatWords.speak)
    }
}
