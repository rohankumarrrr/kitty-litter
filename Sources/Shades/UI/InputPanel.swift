import AppKit

/// The small box you type into. It takes the keyboard without activating the app, so
/// whatever you were using stays frontmost.
@MainActor
final class InputPanel: NSObject, NSTextViewDelegate, NSWindowDelegate {
    private static let width: CGFloat = 320
    private static let padding: CGFloat = 12
    private static let lineHeight: CGFloat = 18
    private static let maxLines: CGFloat = 5

    let panel = QuietPanel(allowsKey: true)
    private let balloon = BalloonView()
    private let scroll = NSScrollView()
    private let textView = PlaceholderTextView()
    private let caption = NSTextField(wrappingLabelWithString: "")
    private var request: InputRequest?

    var anchor: () -> (frame: NSRect, visible: NSRect) = { (.zero, .zero) }
    var onLayout: (() -> Void)?

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

        caption.font = .systemFont(ofSize: 11)
        caption.textColor = Ink.soft
        caption.isHidden = true
        balloon.addSubview(caption)
    }

    var isVisible: Bool { panel.isVisible }
    var frame: NSRect { panel.frame }
    var typedText: String { textView.string }

    func show(_ request: InputRequest) {
        self.request = request
        textView.string = ""
        textView.placeholder = request.placeholder
        caption.stringValue = request.caption ?? ""
        caption.isHidden = request.caption == nil
        relayout()
        panel.makeKeyAndOrderFront(nil)
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
        let inner = Self.width - padding * 2
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let used = textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? 0
        let lines = max(Self.lineHeight, ceil(used))
        let visibleText = min(lines, Self.lineHeight * Self.maxLines)
        // The caption's own padding lines it up with the text above it. Its cell does the measuring,
        // since anything else comes up short over a few lines, and the last one doesn't get drawn.
        let captionHeight = caption.isHidden ? 0 : ceil(caption.cell!.cellSize(
            forBounds: NSRect(x: 0, y: 0, width: inner + 4, height: .greatestFiniteMagnitude)
        ).height) + 4
        let height = visibleText + padding * 2 + captionHeight + BubbleLayout.tailHeight

        let (frame, visible) = anchor()
        let placement = BubbleLayout.place(size: NSSize(width: Self.width, height: height), over: frame, in: visible)
        balloon.tailOnTop = placement.below
        balloon.tailX = placement.tailX
        apply(placement)

        let body = balloon.body
        scroll.frame = NSRect(x: padding, y: body.maxY - padding - visibleText, width: inner, height: visibleText)
        textView.minSize = NSSize(width: inner, height: 0)
        textView.maxSize = NSSize(width: inner, height: .greatestFiniteMagnitude)
        textView.frame = NSRect(x: 0, y: 0, width: inner, height: lines)
        caption.frame = NSRect(x: padding - 2, y: body.minY + padding - 2, width: inner + 4, height: captionHeight)
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

    /// Clicking somewhere else takes the keyboard back, and that means never mind.
    func windowDidResignKey(_ notification: Notification) {
        if request != nil { cancel() }
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

final class PlaceholderTextView: NSTextView {
    var placeholder = "" { didSet { needsDisplay = true } }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// A click into it is what gives a panel that's only key when needed the keyboard.
    override var needsPanelToBecomeKey: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        NSAttributedString(string: placeholder, attributes: [
            .font: font ?? .systemFont(ofSize: 14),
            .foregroundColor: Ink.soft,
        ]).draw(at: .zero)
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }
}
