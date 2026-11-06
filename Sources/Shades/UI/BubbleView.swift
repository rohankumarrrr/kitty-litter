import AppKit
import ShadesCore

/// What goes inside the speech bubble. It lays itself out and says how big it wants to be.
final class BubbleView: BalloonView {
    private static let padding: CGFloat = 14
    private static let maxWidth: CGFloat = 340
    private static let minWidth: CGFloat = 96
    private static let maxTextHeight: CGFloat = 280
    private static let maxCodeHeight: CGFloat = 120
    private static let rowGap: CGFloat = 10

    var onAction: ((BubbleAction) -> Void)?

    private let scroll = NSScrollView()
    let textView = BubbleTextView()
    private let caption = NSTextField(labelWithString: "")
    private let counter = NSTextField(labelWithString: "")
    private let heading = NSTextField(wrappingLabelWithString: "")
    private var buttons: [QuietButton] = []

    private var content: BubbleContent?
    private var grownWidth: CGFloat = 0
    private var followEnd = true
    private var thinkingDots = 3

    override init(frame: NSRect) {
        super.init(frame: frame)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        scroll.documentView = textView
        addSubview(scroll)

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        // Its own width, not the scroll view's, which runs on into the padding for the scroll bar.
        textView.textContainer?.widthTracksTextView = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.usesFontPanel = false
        textView.linkTextAttributes = [:]
        textView.onScrollByUser = { [weak self] in self?.followEnd = false }

        for label in [caption, counter] {
            label.font = .systemFont(ofSize: 11)
            label.textColor = Ink.soft
            label.lineBreakMode = .byTruncatingTail
            label.isHidden = true
            addSubview(label)
        }
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        heading.textColor = Ink.text
        heading.isHidden = true
        addSubview(heading)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Draws this content and returns the size the whole window should be.
    func update(_ content: BubbleContent, keepingWidth: Bool, limitHeight: CGFloat) -> NSSize {
        let sameKind = keepingWidth && self.content?.kind == content.kind
        if !sameKind {
            grownWidth = 0
            followEnd = true
        }
        let rebuildButtons = !sameKind || self.content?.buttonKey != content.buttonKey
        self.content = content

        var captionText: String?
        var counterText: String?
        var headingText: String?
        var body = ""
        var soft = false
        var code = false

        switch content {
        case .thinking(let note):
            captionText = note
            body = "Thinking" + String(repeating: ".", count: thinkingDots)
            soft = true
        case .listening(let text):
            body = text.isEmpty ? "Listening..." : text
            soft = text.isEmpty
        case .reply(let text, _, _, let note, _):
            captionText = note
            body = text
        case .line(let text, _):
            body = text
        case .notice(let noticeCaption, let text, _):
            captionText = noticeCaption
            body = text
        case .approval(let request, let position, let total):
            captionText = request.threadTitle
            counterText = total > 1 ? "\(position) of \(total)" : nil
            headingText = CatWords.asks(request.kind)
            body = request.summary
            code = request.kind == .command
        case .inbox(let headline):
            captionText = CatWords.inboxCaption
            body = headline
        }

        setLabel(caption, captionText)
        setLabel(counter, counterText)
        setLabel(heading, headingText)
        if rebuildButtons { buildButtons(for: content) }

        let font = code ? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular) : NSFont.systemFont(ofSize: 13)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        let attributed = NSAttributedString(string: body, attributes: [
            .font: font,
            .foregroundColor: soft ? Ink.soft : Ink.text,
            .paragraphStyle: style,
        ])
        if textView.string != body || textView.font != font {
            textView.textStorage?.setAttributedString(attributed)
        }
        // Anything worth keeping can be selected, and "Thinking..." isn't.
        textView.isSelectable = content.hasSelectableText
        return layout(limitHeight: limitHeight, code: code)
    }

    func advanceThinking() {
        thinkingDots = thinkingDots % 3 + 1
    }

    func setButtonsArmed(_ armed: Bool, where match: (QuietButton) -> Bool = { _ in true }) {
        buttons.filter(match).forEach { $0.isArmed = armed }
    }

    private func setLabel(_ label: NSTextField, _ text: String?) {
        label.stringValue = text ?? ""
        label.isHidden = text == nil
    }

    private func layout(limitHeight: CGFloat, code: Bool) -> NSSize {
        let padding = Self.padding
        let content = self.content!
        let buttonsWidth = buttons.reduce(0) { $0 + $1.frame.width } + CGFloat(max(0, buttons.count - 1)) * 6
        let inner = Self.maxWidth - padding * 2

        // Measured by the text view's own layout, so what's reserved is exactly what it draws.
        let container = textView.textContainer!
        let manager = textView.layoutManager!
        container.size = NSSize(width: inner, height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        let natural = ceil(manager.usedRect(for: container).width)
        var extras: CGFloat = 0
        if !caption.isHidden { extras = max(extras, ceil(caption.intrinsicContentSize.width)) }
        if !heading.isHidden { extras = max(extras, ceil(heading.attributedStringValue.size().width)) }
        var innerWidth = min(inner, max(natural + 1, buttonsWidth, extras, Self.minWidth - padding * 2))
        if content.fixedWidth { innerWidth = inner }
        // While text streams the bubble only ever widens, so lines don't jump about.
        innerWidth = max(innerWidth, grownWidth)
        grownWidth = innerWidth
        let width = innerWidth + padding * 2

        container.size = NSSize(width: innerWidth, height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        let textHeight = ceil(manager.usedRect(for: container).height)

        var chrome = padding * 2
        var captionHeight: CGFloat = 0
        if !caption.isHidden || !counter.isHidden {
            captionHeight = 14
            chrome += captionHeight + 4
        }
        var headingHeight: CGFloat = 0
        if !heading.isHidden {
            headingHeight = ceil(heading.attributedStringValue.boundingRect(
                with: NSSize(width: innerWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).height)
            chrome += headingHeight + 4
        }
        let buttonsHeight: CGFloat = buttons.isEmpty ? 0 : 26
        if !buttons.isEmpty { chrome += buttonsHeight + Self.rowGap }

        let room = limitHeight - chrome - BubbleLayout.tailHeight
        let cap = min(room, code ? Self.maxCodeHeight : Self.maxTextHeight)
        let visibleText = max(18, min(textHeight, cap))

        let height = chrome + visibleText + BubbleLayout.tailHeight
        let size = NSSize(width: width, height: height)
        setFrameSize(size)

        // Top down, inside the message part of the view.
        var y = body.maxY - padding
        if !caption.isHidden || !counter.isHidden {
            y -= captionHeight
            // Labels carry 2 points of their own padding, so they sit that much further out.
            let counterWidth = counter.isHidden ? 0 : ceil(counter.intrinsicContentSize.width) + 4
            caption.frame = NSRect(x: padding - 2, y: y, width: innerWidth - counterWidth - 2, height: captionHeight)
            counter.frame = NSRect(x: padding + innerWidth - counterWidth, y: y, width: counterWidth + 2, height: captionHeight)
            y -= 4
        }
        if !heading.isHidden {
            y -= headingHeight
            heading.frame = NSRect(x: padding - 2, y: y, width: innerWidth + 4, height: headingHeight)
            y -= 4
        }
        y -= visibleText
        // The scroll bar lives in the right padding, so it never covers the words.
        let scrollWidth = innerWidth + padding - 3
        scroll.frame = NSRect(x: padding, y: y, width: scrollWidth, height: visibleText)
        textView.minSize = NSSize(width: scrollWidth, height: 0)
        textView.maxSize = NSSize(width: scrollWidth, height: .greatestFiniteMagnitude)
        textView.frame = NSRect(x: 0, y: 0, width: scrollWidth, height: max(textHeight, visibleText))
        // No bar flickering while text streams in; it's there once there's something to scroll.
        scroll.hasVerticalScroller = !content.isStreaming && textHeight > visibleText
        if followEnd { textView.scrollToEndOfDocument(nil) }

        // A button with no background of its own lines its words up with the text above.
        var x = padding - (buttons.first?.style == .text ? 6 : 0)
        for button in buttons {
            button.setFrameOrigin(NSPoint(x: x, y: body.minY + padding))
            x += button.frame.width + 6
        }
        needsDisplay = true
        return size
    }

    private func buildButtons(for content: BubbleContent) {
        buttons.forEach { $0.removeFromSuperview() }
        buttons = []

        @discardableResult
        func add(_ title: String, _ style: QuietButton.Style, _ action: BubbleAction) -> QuietButton {
            let button = QuietButton(title, style: style) { [weak self] in self?.onAction?(action) }
            buttons.append(button)
            addSubview(button)
            return button
        }

        switch content {
        case .thinking, .listening:
            break
        case .reply(let text, let done, let threadID, _, let canReplace):
            guard done else { break }
            if canReplace { add("Replace", .plain, .replace(text)) }
            if let threadID { add("Open in T3", .text, .open(threadID: threadID)) }
            let copy = add("Copy", .text, .copy(text))
            let copied = copy.onPress
            copy.onPress = { [weak copy] in
                copied?()
                copy?.flash("Copied")
            }
        case .line(_, let threadID):
            if let threadID { add("Open in T3", .text, .open(threadID: threadID)) }
        case .notice(_, _, let threadID):
            if let threadID { add("Open in T3", .text, .open(threadID: threadID)) }
        case .approval(let request, _, _):
            // The same weight for both: nothing here should lean you toward yes.
            add("Deny", .plain, .approval(request, .decline))
            add("Allow", .plain, .approval(request, .accept))
            if ApprovalPolicy.offersSessionAllow(request.kind) {
                add("Allow for this session", .text, .approval(request, .acceptForSession))
            }
        case .inbox:
            add("Open", .text, .openInbox)
        }
    }
}

/// The reply text. Clicking it is the one thing that gives the bubble the keyboard,
/// so you can select and copy, and only because you asked.
final class BubbleTextView: NSTextView {
    var onScrollByUser: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { isSelectable }

    override func scrollWheel(with event: NSEvent) {
        onScrollByUser?()
        super.scrollWheel(with: event)
    }
}

extension BubbleContent {
    fileprivate var kind: Int {
        switch self {
        case .thinking: return 0
        case .listening: return 1
        case .reply: return 2
        case .line: return 3
        case .notice: return 4
        case .approval: return 5
        case .inbox: return 6
        }
    }

    fileprivate var buttonKey: String {
        switch self {
        case .thinking, .listening: return ""
        case .reply(let text, let done, let thread, _, let canReplace): return done ? "reply|\(thread ?? "")|\(canReplace)|\(text)" : ""
        case .line(_, let thread): return "line|\(thread ?? "")"
        case .notice(_, _, let thread): return "notice|\(thread ?? "")"
        case .approval(let request, _, _): return "approval|\(request.id)"
        case .inbox: return "inbox"
        }
    }

    fileprivate var hasSelectableText: Bool {
        switch self {
        case .thinking, .listening, .inbox: return false
        case .reply, .line, .notice, .approval: return true
        }
    }

    fileprivate var isStreaming: Bool {
        if case .reply(_, let done, _, _, _) = self { return !done }
        return false
    }

    fileprivate var fixedWidth: Bool {
        if case .approval = self { return true }
        if case .notice = self { return true }
        return false
    }
}
