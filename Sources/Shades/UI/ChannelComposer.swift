import AppKit
import ShadesCore

/// The box at the bottom of Messages, and the only thing in the window that takes the keyboard. What's typed goes
/// where the line above it says, and carries nothing but your words.
final class ChannelComposer: QuietView, NSTextViewDelegate {
    private static let pad: CGFloat = 12
    private static let lineHeight: CGFloat = 18
    private static let maxLines: CGFloat = 5
    private static let labelHeight: CGFloat = 22
    private static let fieldPad: CGFloat = 8
    private static let checkboxHeight: CGFloat = 24

    var onSend: ((String, MessageTarget) -> Void)?
    var onResize: (() -> Void)?
    /// Esc in the box, which closes a thread's pane as it does anywhere else in the window.
    var onEscape: (() -> Void)?

    private(set) var target: MessageTarget?
    /// Words typed for somewhere that's gone wait in the box, and Return doesn't send them anywhere else.
    var isHeld = false
    /// A thread's "Also send to #channel", under its box, as Slack has it.
    let alsoSend = QuietCheckbox()
    private let label = NSTextField(labelWithString: "")
    private let scroll = NSScrollView()
    let textView = PlaceholderTextView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 11)
        label.lineBreakMode = .byTruncatingTail
        label.isSelectable = false
        addSubview(label)

        textView.delegate = self
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 14)
        textView.insertionPointColor = Ink.accent
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = textView
        addSubview(scroll)
        alsoSend.isHidden = true
        addSubview(alsoSend)
        restyle()
    }

    func restyle() {
        label.textColor = MessagesInk.soft
        textView.textColor = MessagesInk.text
        alsoSend.needsDisplay = true
        needsDisplay = true
    }

    /// Whether what you send next also shows in the thread's channel.
    var alsoSends: Bool {
        get { !alsoSend.isHidden && alsoSend.isOn }
        set { alsoSend.isOn = newValue }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// `channel` is where the box is, which says who the router's answers come from, and `name` is its name as the
    /// sidebar writes it. `alsoSendTo` offers a thread's reply to its channel too.
    func show(_ target: MessageTarget?, label: String? = nil, in channel: ChannelID? = nil, name: String? = nil, alsoSendTo: String? = nil) {
        let changed = target != self.target || (alsoSendTo == nil) != alsoSend.isHidden
        self.target = target
        isHidden = target == nil
        alsoSend.isHidden = alsoSendTo == nil
        if let alsoSendTo { alsoSend.title = alsoSendTo }
        guard let target else { return }
        self.label.stringValue = label ?? CatWords.target(target, in: channel)
        textView.placeholder = CatWords.placeholder(target, in: channel, name: name)
        if changed { needsLayout = true }
    }

    var height: CGFloat {
        guard target != nil else { return 0 }
        return Self.pad + Self.labelHeight + textHeight + Self.fieldPad * 2 + (alsoSend.isHidden ? 0 : Self.checkboxHeight) + Self.pad
    }

    private var textHeight: CGFloat {
        guard let manager = textView.layoutManager, let container = textView.textContainer else { return Self.lineHeight }
        manager.ensureLayout(for: container)
        let used = ceil(manager.usedRect(for: container).height)
        return min(max(Self.lineHeight, used), Self.lineHeight * Self.maxLines)
    }

    override func layout() {
        super.layout()
        let inner = bounds.width - ChannelRowView.margin * 2
        label.frame = NSRect(x: ChannelRowView.margin - 2, y: Self.pad + 2, width: inner, height: 16)
        let field = NSRect(x: ChannelRowView.margin, y: Self.pad + Self.labelHeight, width: inner, height: textHeight + Self.fieldPad * 2)
        scroll.frame = field.insetBy(dx: 10, dy: Self.fieldPad)
        textView.minSize = NSSize(width: scroll.frame.width, height: 0)
        textView.maxSize = NSSize(width: scroll.frame.width, height: .greatestFiniteMagnitude)
        alsoSend.sizeToFit()
        alsoSend.frame.origin = NSPoint(x: ChannelRowView.margin - 2, y: field.maxY + 4)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        MessagesInk.line.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
        let field = NSRect(x: ChannelRowView.margin, y: Self.pad + Self.labelHeight, width: bounds.width - ChannelRowView.margin * 2, height: textHeight + Self.fieldPad * 2)
        MessagesInk.hover.setFill()
        NSBezierPath(roundedRect: field, xRadius: 9, yRadius: 9).fill()
    }

    func textDidChange(_ notification: Notification) {
        onResize?()
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            guard InputPanel.returnSends(NSApp.currentEvent?.modifierFlags ?? []) else { return false }
            send()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onEscape?()
            return true
        default:
            return false
        }
    }

    /// Sends this as if it had been typed and Return pressed.
    func send(_ text: String) {
        textView.string = text
        send()
    }

    var hasDraft: Bool { textView.string.contains { !$0.isWhitespace } }

    /// Puts another place's or thread's draft in the box, with nothing to undo back into the one it replaced.
    func showDraft(_ text: String) {
        textView.string = text
        textView.undoManager?.removeAllActions()
        needsLayout = true
    }

    private func send() {
        let words = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let target, !words.isEmpty, target.isReady, !isHeld else {
            NSSound.beep()
            return
        }
        textView.string = ""
        onResize?()
        onSend?(words, target)
    }
}

/// A checkbox you can only press with the mouse, in Messages' colours. Like `QuietButton`, it never takes the keyboard,
/// so pressing it leaves the keyboard where it was.
final class QuietCheckbox: NSView {
    private static let box: CGFloat = 14

    var title = "" { didSet { needsDisplay = true; setAccessibilityLabel(title) } }
    var isOn = false { didSet { if isOn != oldValue { needsDisplay = true; setAccessibilityValue(isOn) } } }
    var onChange: ((Bool) -> Void)?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 160, height: 20))
        setAccessibilityElement(true)
        setAccessibilityRole(.checkBox)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { false }

    private var label: NSAttributedString {
        NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: MessagesInk.soft])
    }

    func sizeToFit() {
        setFrameSize(NSSize(width: Self.box + 8 + ceil(label.size().width) + 4, height: 20))
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSRect(x: 1, y: (bounds.height - Self.box) / 2, width: Self.box, height: Self.box)
        let shape = NSBezierPath(roundedRect: box, xRadius: 3.5, yRadius: 3.5)
        if isOn {
            MessagesInk.link.setFill()
            shape.fill()
            let tick = NSBezierPath()
            tick.move(to: NSPoint(x: box.minX + 3.5, y: box.midY))
            tick.line(to: NSPoint(x: box.minX + 6, y: box.maxY - 3.5))
            tick.line(to: NSPoint(x: box.maxX - 3, y: box.minY + 3.5))
            tick.lineWidth = 1.8
            ChannelSpeakerLook.readable(on: MessagesInk.theme?.accent ?? ChannelSpeakerLook.yours).setStroke()
            tick.stroke()
        } else {
            MessagesInk.line.setStroke()
            shape.lineWidth = 1.2
            shape.stroke()
        }
        let text = label
        text.draw(at: NSPoint(x: box.maxX + 7, y: (bounds.height - text.size().height) / 2))
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        toggle()
    }

    override func accessibilityPerformPress() -> Bool {
        toggle()
        return true
    }

    func toggle() {
        isOn.toggle()
        onChange?(isOn)
    }
}
