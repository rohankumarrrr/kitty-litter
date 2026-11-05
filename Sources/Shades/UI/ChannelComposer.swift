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

    var onSend: ((String, MessageTarget) -> Void)?
    /// Starts something new instead, or goes back to where typing usually goes.
    var onRetarget: ((MessageTarget?) -> Void)?
    var onResize: (() -> Void)?

    private(set) var target: MessageTarget?
    private var kitten: Kitten?
    private var isPicked = false
    private let label = NSTextField(labelWithString: "")
    private let newTopic = QuietButton(CatWords.newTopic, style: .text)
    private let cancel = QuietButton("Cancel", style: .text)
    private let scroll = NSScrollView()
    let textView = PlaceholderTextView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 11)
        label.textColor = Ink.soft
        label.lineBreakMode = .byTruncatingTail
        label.isSelectable = false
        addSubview(label)
        newTopic.onPress = { [weak self] in
            guard let kitten = self?.kitten else { return }
            self?.onRetarget?(.newThread(kitten))
        }
        cancel.onPress = { [weak self] in self?.onRetarget?(nil) }
        addSubview(newTopic)
        addSubview(cancel)

        textView.delegate = self
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = Ink.text
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// `kitten` is whose DM this is, if it's one, which is what lets you start something new.
    func show(_ target: MessageTarget?, picked: Bool, kitten: Kitten?) {
        let changed = target != self.target
        self.target = target
        self.kitten = kitten
        isPicked = picked
        isHidden = target == nil
        guard let target else { return }
        label.stringValue = CatWords.target(target)
        textView.placeholder = CatWords.placeholder(target)
        cancel.isHidden = !picked
        if case .newThread = target { newTopic.isHidden = true } else { newTopic.isHidden = kitten == nil }
        if changed { needsLayout = true }
    }

    var height: CGFloat {
        guard target != nil else { return 0 }
        return Self.pad + Self.labelHeight + textHeight + Self.fieldPad * 2 + Self.pad
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
        var right = bounds.width - ChannelRowView.margin + 6
        for button in [cancel, newTopic] where !button.isHidden {
            right -= button.frame.width
            button.frame.origin = NSPoint(x: right, y: Self.pad - 2)
        }
        label.frame = NSRect(x: ChannelRowView.margin - 2, y: Self.pad + 2, width: max(right - ChannelRowView.margin - 4, 40), height: 16)
        let field = NSRect(x: ChannelRowView.margin, y: Self.pad + Self.labelHeight, width: inner, height: textHeight + Self.fieldPad * 2)
        scroll.frame = field.insetBy(dx: 10, dy: Self.fieldPad)
        textView.minSize = NSSize(width: scroll.frame.width, height: 0)
        textView.maxSize = NSSize(width: scroll.frame.width, height: .greatestFiniteMagnitude)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        Ink.line.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
        let field = NSRect(x: ChannelRowView.margin, y: Self.pad + Self.labelHeight, width: bounds.width - ChannelRowView.margin * 2, height: textHeight + Self.fieldPad * 2)
        Ink.hover.setFill()
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
            if isPicked { onRetarget?(nil) }
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

    private func send() {
        let words = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let target, !words.isEmpty, target.isReady else {
            NSSound.beep()
            return
        }
        textView.string = ""
        onResize?()
        onSend?(words, target)
    }

    func clear() {
        textView.string = ""
    }
}
