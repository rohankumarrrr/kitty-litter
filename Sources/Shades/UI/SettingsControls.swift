import AppKit

/// What Settings' own controls share with `QuietButton`: a click leaves the keyboard where it was, Tab reaches one only
/// with Keyboard navigation on, and Space presses it.
class SettingsControl: NSView {
    var hovering = false { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { QuietFocus.allows(self) }
    override var canBecomeKeyView: Bool { QuietFocus.allows(self) && !isHiddenOrHasHiddenAncestor }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { false }

    override func becomeFirstResponder() -> Bool {
        QuietFocus.took(self)
        return true
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return true
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
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        press(at: point)
    }

    override func keyDown(with event: NSEvent) {
        guard QuietFocus.isSpace(event) else { return super.keyDown(with: event) }
        if !event.isARepeat { press(at: nil) }
    }

    override func accessibilityPerformPress() -> Bool {
        press(at: nil)
        return true
    }

    /// A click there, or Space and VoiceOver's press with `nil`.
    func press(at point: NSPoint?) {}

    var showsFocus: Bool { QuietFocus.shows(self) }
}

/// A page's name at the top of Settings, underlined in the rim's light while it's open, as Opal's tabs are. Never a
/// pill.
final class SettingsTab: SettingsControl {
    static let height: CGFloat = 30
    private static let font = NSFont.systemFont(ofSize: 13, weight: .medium)

    let title: String
    var isOpen = false { didSet { needsDisplay = true; setAccessibilityValue(isOpen) } }
    var onPress: (() -> Void)?

    init(_ title: String) {
        self.title = title
        super.init(frame: .zero)
        setFrameSize(NSSize(width: ceil(words.size().width), height: Self.height))
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(title)
        setAccessibilityValue(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private var words: NSAttributedString {
        NSAttributedString(string: title, attributes: [
            .font: Self.font,
            .foregroundColor: isOpen ? MessagesInk.strong : hovering ? MessagesInk.text : MessagesInk.soft,
        ])
    }

    override func press(at point: NSPoint?) { onPress?() }

    override func draw(_ dirtyRect: NSRect) {
        let text = words
        text.draw(at: NSPoint(x: 0, y: 4))
        if isOpen { Opal.rimLine(in: NSRect(x: 0, y: bounds.height - 2, width: bounds.width, height: 2)) }
        if showsFocus { QuietFocus.ring(NSRect(x: -5, y: 1, width: bounds.width + 10, height: text.size().height + 6), radius: 6) }
    }
}

/// A few close choices side by side, the chosen one raised on the track, as Opal's segmented control is. The arrow
/// keys move between them once Tab has reached it.
final class QuietSegments: SettingsControl {
    static let height: CGFloat = 26
    private static let font = NSFont.systemFont(ofSize: 12, weight: .medium)

    let titles: [String]
    private(set) var selected: Int { didSet { needsDisplay = true; setAccessibilityValue(titles[selected]) } }
    var onPick: ((Int) -> Void)?

    init(_ titles: [String], selected: Int) {
        self.titles = titles
        self.selected = selected
        super.init(frame: .zero)
        // Every segment as wide as the widest, as macOS draws them.
        let widest = titles.map { ceil(NSAttributedString(string: $0, attributes: [.font: Self.font]).size().width) }.max() ?? 0
        setFrameSize(NSSize(width: (widest + 24) * CGFloat(titles.count) + 4, height: Self.height))
        setAccessibilityElement(true)
        setAccessibilityRole(.radioGroup)
        setAccessibilityValue(titles[selected])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// The same as clicking the segment that says this.
    func pick(_ title: String) {
        titles.firstIndex(of: title).map(pick)
    }

    private func pick(_ index: Int) {
        guard titles.indices.contains(index), index != selected else { return }
        selected = index
        onPick?(index)
    }

    private func segment(_ index: Int) -> NSRect {
        let width = (bounds.width - 4) / CGFloat(titles.count)
        return NSRect(x: 2 + width * CGFloat(index), y: 2, width: width, height: bounds.height - 4)
    }

    override func press(at point: NSPoint?) {
        guard let point else { return }
        titles.indices.first { segment($0).contains(point) }.map(pick)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: pick(selected - 1)
        case 124: pick(selected + 1)
        default: super.keyDown(with: event)
        }
    }

    override func accessibilityChildren() -> [Any]? {
        titles.indices.map { index in
            SegmentElement(title: titles[index], isOn: index == selected, frame: NSAccessibility.screenRect(fromView: self, rect: segment(index)), parent: self) { [weak self] in
                self?.pick(index)
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        Ink.hex(Opal.control).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        Ink.hex(Opal.fieldEdge).setStroke()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius - 0.5, yRadius: radius - 0.5).stroke()
        for (index, title) in titles.enumerated() {
            let rect = segment(index)
            if index == selected {
                let chosen = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
                Ink.hex(Opal.controlHover).setFill()
                chosen.fill()
                NSColor(white: 1, alpha: 0.07).setStroke()
                chosen.stroke()
            }
            let words = NSAttributedString(string: title, attributes: [
                .font: Self.font,
                .foregroundColor: index == selected ? MessagesInk.strong : MessagesInk.text,
            ])
            let size = words.size()
            words.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
        }
        if showsFocus { QuietFocus.ring(bounds, radius: radius) }
    }
}

/// One segment, as VoiceOver finds it: a radio button that picks it.
private final class SegmentElement: NSAccessibilityElement {
    private let onPress: () -> Void

    init(title: String, isOn: Bool, frame: NSRect, parent: NSView, onPress: @escaping () -> Void) {
        self.onPress = onPress
        super.init()
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(title)
        setAccessibilityValue(isOn)
        setAccessibilityFrame(frame)
        setAccessibilityParent(parent)
    }

    override func accessibilityPerformPress() -> Bool {
        onPress()
        return true
    }
}

/// On or off for a whole row, at its right, as macOS's own Settings has it. Violet when it's on.
final class QuietSwitch: SettingsControl {
    private static let track = NSSize(width: 32, height: 18)

    var title = "" { didSet { setAccessibilityLabel(title) } }
    var isOn = false { didSet { if isOn != oldValue { needsDisplay = true; setAccessibilityValue(isOn) } } }
    var onChange: ((Bool) -> Void)?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.track.width + 4, height: Self.track.height + 4))
        setAccessibilityElement(true)
        setAccessibilityRole(.checkBox)
        setAccessibilitySubrole(.switch)
        setAccessibilityValue(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func toggle() {
        isOn.toggle()
        onChange?(isOn)
    }

    override func press(at point: NSPoint?) { toggle() }

    override func draw(_ dirtyRect: NSRect) {
        let track = NSRect(origin: NSPoint(x: 2, y: 2), size: Self.track)
        let radius = track.height / 2
        let shape = NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius)
        if isOn {
            MessagesInk.accent.setFill()
            shape.fill()
        } else {
            Ink.hex(Opal.control).setFill()
            shape.fill()
            // An edge at the 3:1 a control needs, on glass.
            let edge = NSBezierPath(roundedRect: track.insetBy(dx: 0.6, dy: 0.6), xRadius: radius - 0.6, yRadius: radius - 0.6)
            edge.lineWidth = 1.2
            MessagesInk.dim.setStroke()
            edge.stroke()
        }
        let knob: CGFloat = track.height - 4
        let x = isOn ? track.maxX - knob - 2 : track.minX + 2
        (isOn ? MessagesInk.onAccent : MessagesInk.text).setFill()
        NSBezierPath(ovalIn: NSRect(x: x, y: track.minY + 2, width: knob, height: knob)).fill()
        if showsFocus { QuietFocus.ring(bounds, radius: bounds.height / 2) }
    }
}

/// A box you type in, as Opal's field: raised, with a hairline edge, and a violet ring and lilac insertion point while
/// it has the keyboard.
final class OpalField: NSTextField {
    override class var cellClass: AnyClass? {
        get { OpalFieldCell.self }
        set {}
    }

    convenience init(_ value: String, placeholder: String) {
        self.init(frame: .zero)
        stringValue = value
        isBordered = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        isEditable = true
        isSelectable = true
        font = MessagesInk.font(ofSize: MessagesInk.body)
        textColor = MessagesInk.text
        placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [.font: font!, .foregroundColor: MessagesInk.soft])
    }

    private var isEditing: Bool { currentEditor() != nil && window?.isKeyWindow == true }

    override func draw(_ dirtyRect: NSRect) {
        Opal.field(in: bounds, focused: isEditing)
        super.draw(dirtyRect)
    }

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        (currentEditor() as? NSTextView)?.insertionPointColor = MessagesInk.link
        needsDisplay = true
        return true
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        needsDisplay = true
    }

    /// The ring goes when its window gives up the keyboard, and comes back with it.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        guard let window else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(keyChanged), name: name, object: window)
        }
    }

    @objc private func keyChanged() { needsDisplay = true }
}

/// Its words inset from the field's edge, the same while you type as while it draws.
private final class OpalFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        super.drawingRect(forBounds: rect.insetBy(dx: 8, dy: 5))
    }
}
