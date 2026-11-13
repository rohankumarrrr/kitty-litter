import AppKit

/// The small box you type into: Opal's glass with a field in it, like a command box. It takes the keyboard without
/// activating the app, so whatever you were using stays frontmost.
@MainActor
final class InputPanel: NSObject, NSTextViewDelegate, NSWindowDelegate {
    private static let width: CGFloat = 320
    /// Around the field, so its corners sit inside the glass's.
    private static let padding: CGFloat = 8
    /// Inside the field, around the words.
    private static let inside = NSSize(width: 10, height: 7)
    private static let maxLines: CGFloat = 5

    let panel = QuietPanel(allowsKey: true)
    private let balloon = AskBoxView()
    private let scroll = NSScrollView()
    private let textView = PlaceholderTextView()
    private let caption = NSTextField(wrappingLabelWithString: "")
    private let attachment = DropChip()
    let mic = QuietButton.mic()
    private var request: InputRequest?

    var anchor: () -> (frame: NSRect, visible: NSRect) = { (.zero, .zero) }
    var onLayout: (() -> Void)?
    var onMic: (() -> Void)?

    override init() {
        super.init()
        panel.contentView = balloon
        panel.delegate = self

        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = textView
        balloon.addSubview(scroll)

        textView.delegate = self
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.insertionPointColor = MessagesInk.link
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false

        caption.isHidden = true
        balloon.addSubview(caption)
        balloon.addSubview(attachment)

        mic.onPress = { [weak self] in self?.onMic?() }
        balloon.addSubview(mic)
        textView.textColor = MessagesInk.text
        caption.textColor = MessagesInk.soft
    }

    var isVisible: Bool { panel.isVisible }
    var frame: NSRect { panel.frame }
    var typedText: String { textView.string }

    func show(_ request: InputRequest) {
        self.request = request
        textView.font = MessagesInk.font(ofSize: MessagesInk.body + 1)
        caption.font = MessagesInk.font(ofSize: MessagesInk.meta)
        textView.string = ""
        textView.placeholder = request.placeholder
        caption.stringValue = request.caption ?? ""
        caption.isHidden = request.caption == nil
        attachment.name = request.attachment
        relayout()
        panel.fadeIn()
        panel.makeKey()
        panel.makeFirstResponder(textView)
    }

    func setText(_ text: String) {
        textView.string = text
        textView.needsDisplay = true
        relayout()
        textView.scrollToEndOfDocument(nil)
    }

    func hide() {
        request = nil
        panel.orderOut(nil)
        onLayout?()
    }

    func reposition() {
        guard panel.isVisible else { return }
        let (frame, visible) = anchor()
        let placement = BubbleLayout.place(size: panel.frame.size, over: frame, in: visible)
        apply(placement)
    }

    private func relayout() {
        let padding = Self.padding
        let inside = Self.inside
        let fieldWidth = Self.width - padding * 2
        let side = QuietButton.micSide
        let textWidth = fieldWidth - inside.width - side - 4
        let lineHeight = ceil(textView.layoutManager!.defaultLineHeight(for: textView.font!))
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let used = textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? 0
        let lines = max(lineHeight, ceil(used))
        let visibleText = min(lines, lineHeight * Self.maxLines)
        let chipRow = attachment.isHidden ? 0 : DropChip.height + 6
        let fieldHeight = visibleText + inside.height * 2 + chipRow
        // The caption's cell does the measuring, since anything else comes up short over a few lines, and the last one
        // doesn't get drawn.
        let captionHeight = caption.isHidden ? 0 : ceil(caption.cell!.cellSize(
            forBounds: NSRect(x: 0, y: 0, width: fieldWidth - inside.width * 2 + 4, height: .greatestFiniteMagnitude)
        ).height)
        let height = padding * 2 + fieldHeight + (caption.isHidden ? 0 : captionHeight + 6) + BubbleLayout.tailHeight

        let (frame, visible) = anchor()
        let placement = BubbleLayout.place(size: NSSize(width: Self.width, height: height), over: frame, in: visible)
        apply(placement)

        let body = balloon.body
        let field = NSRect(x: padding, y: body.maxY - padding - fieldHeight, width: fieldWidth, height: fieldHeight)
        balloon.field = field
        var top = field.maxY - inside.height
        if !attachment.isHidden {
            top -= DropChip.height
            attachment.frame = NSRect(x: field.minX + inside.width - 4, y: top, width: min(attachment.fittingSize.width, textWidth), height: DropChip.height)
            top -= 6
        }
        scroll.frame = NSRect(x: field.minX + inside.width, y: top - visibleText, width: textWidth, height: visibleText)
        textView.minSize = NSSize(width: textWidth, height: 0)
        textView.maxSize = NSSize(width: textWidth, height: .greatestFiniteMagnitude)
        textView.frame = NSRect(x: 0, y: 0, width: textWidth, height: lines)
        // Level with the first line, at the field's right, as the mic is in The Kitty Litter's box.
        mic.frame = NSRect(x: field.maxX - 4 - side, y: top - (lineHeight + side) / 2, width: side, height: side)
        // The caption's own padding lines it up with the words in the field.
        caption.frame = NSRect(x: field.minX + inside.width - 2, y: field.minY - 6 - captionHeight, width: fieldWidth - inside.width * 2 + 4, height: captionHeight)
        balloon.needsDisplay = true
        panel.invalidateShadow()
    }

    private func apply(_ placement: BubbleLayout.Placement) {
        balloon.tailX = placement.tailX
        balloon.tailOnTop = placement.below
        if panel.frame != placement.frame {
            panel.setFrame(placement.frame, display: true)
            panel.invalidateShadow()
            onLayout?()
        }
    }

    func textDidChange(_ notification: Notification) {
        relayout()
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            // Letting the text view handle it is what adds the new line.
            guard Self.returnSends(NSApp.currentEvent?.modifierFlags ?? []) else { return false }
            submit()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            cancel()
            return true
        default:
            return false
        }
    }

    /// Return sends, and Shift-Return starts a new line. AppKit reports both as the same command.
    static func returnSends(_ modifiers: NSEvent.ModifierFlags) -> Bool {
        !modifiers.contains(.shift)
    }

    /// Its field's ring says it has the keyboard.
    func windowDidBecomeKey(_ notification: Notification) {
        balloon.needsDisplay = true
    }

    /// Clicking somewhere else takes the keyboard back, and that means never mind.
    func windowDidResignKey(_ notification: Notification) {
        balloon.needsDisplay = true
        if request != nil, !ClickAway.isPaused { cancel() }
    }

    private func submit() {
        guard let request else { return }
        let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty && !request.allowsEmpty {
            NSSound.beep()
            return
        }
        self.request = nil
        panel.orderOut(nil)
        onLayout?()
        request.onSubmit(text)
    }

    /// Sends this as if it had been typed and Return pressed.
    func submit(_ text: String) {
        textView.string = text
        submit()
    }

    func cancel() {
        guard let request else { return }
        self.request = nil
        panel.orderOut(nil)
        onLayout?()
        request.onCancel()
    }
}

class PlaceholderTextView: NSTextView {
    var placeholder = "" { didSet { needsDisplay = true } }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// A click into it is what gives a panel that's only key when needed the keyboard.
    override var needsPanelToBecomeKey: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        NSAttributedString(string: placeholder, attributes: [
            .font: font ?? .systemFont(ofSize: 14),
            .foregroundColor: MessagesInk.soft,
        ]).draw(at: .zero)
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }
}

/// The Ask box's glass, with its field drawn in it.
private final class AskBoxView: BalloonView {
    var field = NSRect.zero { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        Opal.field(in: field, focused: window?.isKeyWindow == true)
    }
}

/// A file or link dropped on the cat, as a chip in the box, the way an attachment sits in any box you type in.
private final class DropChip: NSView {
    static let height: CGFloat = 22
    private static let clip = NSImage(systemSymbolName: "paperclip", accessibilityDescription: nil)?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .medium))

    var name: String? {
        didSet {
            isHidden = name == nil
            setAccessibilityLabel(name)
            needsDisplay = true
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        isHidden = true
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private var label: NSAttributedString {
        let style = NSMutableParagraphStyle()
        // A long file name keeps its start and its kind, as Finder shows it.
        style.lineBreakMode = .byTruncatingMiddle
        return NSAttributedString(string: name ?? "", attributes: [
            .font: MessagesInk.font(ofSize: MessagesInk.meta),
            .foregroundColor: MessagesInk.text,
            .paragraphStyle: style,
        ])
    }

    override var fittingSize: NSSize {
        NSSize(width: ceil(label.size().width) + 32, height: Self.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        Ink.hex(Opal.control).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        if let clip = Self.clip {
            let tinted = NSImage(size: clip.size, flipped: false) { rect in
                clip.draw(in: rect)
                MessagesInk.soft.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: 9, y: (bounds.height - clip.size.height) / 2, width: clip.size.width, height: clip.size.height))
        }
        let words = label
        let height = ceil(words.size().height)
        words.draw(with: NSRect(x: 22, y: (bounds.height - height) / 2, width: bounds.width - 32, height: height), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}
