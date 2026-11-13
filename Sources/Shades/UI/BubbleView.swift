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
    /// Whether Messages shows this thread, so Open goes there and T3 is only for what it doesn't.
    var opensInMessages: (String) -> Bool = { _ in false }

    private let scroll = NSScrollView()
    let textView = BubbleTextView()
    private let scroller = BubbleScroller()
    private let topFade = EdgeFade(top: true)
    private let bottomFade = EdgeFade(top: false)
    private let caption = NSTextField(labelWithString: "")
    private let counter = NSTextField(labelWithString: "")
    private let heading = NSTextField(wrappingLabelWithString: "")
    private var buttons: [QuietButton] = []
    /// Whether the buttons showing open their thread in Messages, so they change once Messages can show it.
    private var opensHere: Bool?

    private var content: BubbleContent?
    private var grownWidth: CGFloat = 0
    private var followEnd = true
    private var thinkingDots = 3

    override init(frame: NSRect) {
        super.init(frame: frame)
        scroll.drawsBackground = false
        scroll.verticalScroller = scroller
        scroller.controlSize = .small
        scroller.onScrollByUser = { [weak self] in self?.followEnd = false }
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.documentView = textView
        scroll.contentView.postsBoundsChangedNotifications = true
        addSubview(scroll)
        addSubview(topFade)
        addSubview(bottomFade)
        NotificationCenter.default.addObserver(self, selector: #selector(textScrolled), name: NSView.boundsDidChangeNotification, object: scroll.contentView)

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
        textView.layoutManager?.delegate = self

        for label in [caption, counter] {
            label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            label.lineBreakMode = .byTruncatingTail
            label.isHidden = true
            addSubview(label)
        }
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        heading.isHidden = true
        addSubview(heading)
        caption.textColor = MessagesInk.soft
        counter.textColor = MessagesInk.soft
        heading.textColor = MessagesInk.text
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
        let rebuildButtons = !sameKind || self.content?.buttonKey != content.buttonKey || opensHere != content.threadID.map(opensInMessages)
        self.content = content

        let words = content.words(thinkingDots: thinkingDots)
        let body = words.body
        let code = words.isCode

        setLabel(caption, words.caption)
        setLabel(counter, words.counter)
        setLabel(heading, words.heading)
        if rebuildButtons { buildButtons(for: content) }

        let font = code ? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular) : NSFont.systemFont(ofSize: 13)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        let attributed = NSAttributedString(string: body, attributes: [
            .font: font,
            .foregroundColor: words.isSoft ? MessagesInk.soft : MessagesInk.text,
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
            // Labels carry 2 points of their own padding each side, so they sit that much further out.
            let counterWidth = counter.isHidden ? 0 : ceil(counter.intrinsicContentSize.width) + 4
            let captionWidth = counter.isHidden ? innerWidth + 4 : innerWidth - counterWidth - 2
            caption.frame = NSRect(x: padding - 2, y: y, width: captionWidth, height: captionHeight)
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
        // No bar flickering while text streams in. Once there's something to scroll it stays in sight, not just
        // while scrolling, so a long answer always has a way back to its start.
        scroll.scrollerStyle = .legacy
        scroll.hasVerticalScroller = !content.isStreaming && textHeight > visibleText
        let textWidth = scroll.contentSize.width
        textView.minSize = NSSize(width: textWidth, height: 0)
        textView.maxSize = NSSize(width: textWidth, height: .greatestFiniteMagnitude)
        textView.frame = NSRect(x: 0, y: 0, width: textWidth, height: max(textHeight, visibleText))
        if followEnd { textView.scrollToEndOfDocument(nil) }
        topFade.frame = NSRect(x: padding, y: scroll.frame.maxY - EdgeFade.height, width: innerWidth, height: EdgeFade.height)
        bottomFade.frame = NSRect(x: padding, y: scroll.frame.minY, width: innerWidth, height: EdgeFade.height)
        textScrolled()

        // A button with no background of its own lines its words up with the text above.
        var x = padding - (buttons.first?.style == .text ? 6 : 0)
        for button in buttons {
            button.setFrameOrigin(NSPoint(x: x, y: body.minY + padding))
            x += button.frame.width + 6
        }
        needsDisplay = true
        return size
    }

    /// Text hidden past an edge fades out there, so a cut line reads as more to come rather than a mistake.
    @objc private func textScrolled() {
        let shown = scroll.contentView.bounds
        topFade.isHidden = shown.minY < 1
        bottomFade.isHidden = shown.maxY > textView.frame.height - 1
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
        // Messages first. T3 is only for a thread Messages doesn't show.
        opensHere = content.threadID.map(opensInMessages)
        func open(_ threadID: String, primary: Bool = true) {
            if opensInMessages(threadID) {
                add("Open", primary ? .plain : .text, .show(threadID: threadID))
            } else {
                add(CatWords.openInT3, .text, .open(threadID: threadID))
            }
        }

        switch content {
        case .thinking, .listening:
            break
        case .reply(let text, let done, let threadID, _, let canReplace):
            guard done else { break }
            if canReplace { add("Replace", .plain, .replace(text)) }
            if let threadID { open(threadID, primary: !canReplace) }
            let copy = add("Copy", .text, .copy(text))
            let copied = copy.onPress
            copy.onPress = { [weak copy] in
                copied?()
                copy?.flash("Copied")
                BubbleController.announce("Copied")
            }
        case .line(_, let threadID), .notice(_, _, let threadID, _):
            if let threadID { open(threadID) }
        case .approval(let request, _, _):
            // The same weight for both: nothing here should lean you toward yes.
            add("Deny", .plain, .approval(request, .decline))
            add("Allow", .plain, .approval(request, .accept))
            if ApprovalPolicy.offersSessionAllow(request.kind) {
                add("Allow for this session", .text, .approval(request, .acceptForSession))
            }
        case .inbox:
            add("Open", .plain, .openMessages)
        }
    }
}

extension BubbleView: NSLayoutManagerDelegate {
    /// A command wraps only at a space, so a flag such as --reporter=line stays in one piece. What's copied is the real text.
    func layoutManager(_ layoutManager: NSLayoutManager, shouldBreakLineByWordBeforeCharacterAt charIndex: Int) -> Bool {
        guard case .approval(let request, _, _)? = content, request.kind == .command, charIndex > 0,
              let text = layoutManager.textStorage?.string as NSString?
        else { return true }
        return (CharacterSet.whitespaces as NSCharacterSet).characterIsMember(text.character(at: charIndex - 1))
    }
}

/// Only the knob of the scroll bar, so it can stay in sight without a track drawn over the bubble.
final class BubbleScroller: NSScroller {
    var onScrollByUser: (() -> Void)?

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onScrollByUser?()
        super.mouseDown(with: event)
    }
}

/// The bubble's paper fading in over the text at one edge.
final class EdgeFade: NSView {
    static let height: CGFloat = 28
    private let top: Bool

    init(top: Bool) {
        self.top = top
        super.init(frame: .zero)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let paper = MessagesInk.paper
        let clear = paper.withAlphaComponent(0)
        NSGradient(starting: top ? clear : paper, ending: top ? paper : clear)?.draw(in: bounds, angle: 90)
    }

    // Only paint, so clicks, selecting and scrolling reach the text under it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
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

/// What the bubble shows, top to bottom. VoiceOver hears these same words, so it's never told more than you see.
struct BubbleWords: Equatable {
    var caption: String?
    var counter: String?
    var heading: String?
    var body: String
    var isSoft = false
    var isCode = false
}

extension BubbleContent {
    func words(thinkingDots: Int = 0) -> BubbleWords {
        switch self {
        case .thinking(let note):
            return BubbleWords(caption: note, body: "Thinking" + String(repeating: ".", count: thinkingDots), isSoft: true)
        case .listening(let text):
            return BubbleWords(body: text.isEmpty ? "Listening…" : text, isSoft: text.isEmpty)
        case .reply(let text, _, _, let note, _):
            return BubbleWords(caption: note, body: text)
        case .line(let text, _):
            return BubbleWords(body: text)
        case .notice(let caption, let text, _, _):
            return BubbleWords(caption: caption, body: text)
        case .approval(let request, let position, let total):
            return BubbleWords(
                caption: request.threadTitle,
                counter: total > 1 ? "\(position) of \(total)" : nil,
                heading: CatWords.asks(request.kind),
                body: request.summary,
                isCode: request.kind == .command
            )
        case .inbox(let headline):
            return BubbleWords(caption: CatWords.inboxCaption, body: headline)
        }
    }

    /// What VoiceOver says as this shows. Nothing while you talk, so the microphone doesn't hear it, or while
    /// an answer is still coming in, so it's read once, whole.
    var spoken: String? {
        switch self {
        case .listening, .reply(_, false, _, _, _): return nil
        default:
            let words = words()
            return [words.caption, words.counter, words.heading, words.body].compactMap { $0 }.joined(separator: "\n")
        }
    }

    /// Something waiting on your answer, which VoiceOver says straight away.
    var isUrgent: Bool {
        switch self {
        case .approval: return true
        case .notice(_, _, _, let asks): return asks
        default: return false
        }
    }

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
        case .notice(_, _, let thread, _): return "notice|\(thread ?? "")"
        case .approval(let request, _, _): return "approval|\(request.id)"
        case .inbox: return "inbox"
        }
    }

    fileprivate var threadID: String? {
        switch self {
        case .reply(_, true, let thread, _, _), .line(_, let thread), .notice(_, _, let thread, _): return thread
        default: return nil
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
