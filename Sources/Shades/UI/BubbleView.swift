import AppKit
import ShadesContext
import ShadesCore

final class BubbleView: BalloonView {
    private static let inset = NSEdgeInsets(top: 15, left: 18, bottom: 16, right: 18)
    private static let maxWidth: CGFloat = 340
    private static let minWidth: CGFloat = 96
    private static let maxTextHeight: CGFloat = 280
    private static let maxCodeHeight: CGFloat = 120
    private static let rowGap: CGFloat = 12
    private static let buttonGap: CGFloat = 8
    private static let codePadding: CGFloat = 8

    var onAction: ((BubbleAction) -> Void)?
    var opensInMessages: (String) -> Bool = { _ in false }
    var kittenColor: (String) -> UInt32? = { _ in nil }

    private let scroll = NSScrollView()
    let textView = BubbleTextView()
    private let scroller = BubbleScroller()
    private let caption = NSTextField(labelWithString: "")
    private let counter = NSTextField(labelWithString: "")
    private let heading = NSTextField(wrappingLabelWithString: "")
    private var buttons: [QuietButton] = []
    private var leadingButtons = 0
    private var opensHere: Bool?
    private var codeBlock: NSRect?

    private var content: BubbleContent?
    private var grownWidth: CGFloat = 0
    private var followEnd = false
    private var thinkingDots = 3

    override init(frame: NSRect) {
        super.init(frame: frame)
        look = .card(.shades)
        scroll.drawsBackground = false
        scroll.verticalScroller = scroller
        scroller.controlSize = .small
        scroller.onScrollByUser = { [weak self] in self?.followEnd = false }
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.documentView = textView
        scroll.contentView.postsBoundsChangedNotifications = true
        addSubview(scroll)
        NotificationCenter.default.addObserver(self, selector: #selector(textScrolled), name: NSView.boundsDidChangeNotification, object: scroll.contentView)

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.usesFontPanel = false
        textView.linkTextAttributes = [:]
        textView.onScrollByUser = { [weak self] in self?.followEnd = false }
        textView.layoutManager?.delegate = self

        for label in [caption, counter] {
            label.lineBreakMode = .byTruncatingTail
            label.isHidden = true
            label.textColor = MessagesInk.soft
            addSubview(label)
        }
        heading.isHidden = true
        heading.textColor = MessagesInk.strong
        addSubview(heading)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let codeBlock else { return }
        MessagesInk.text.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: codeBlock, xRadius: Opal.Corner.control, yRadius: Opal.Corner.control).fill()
    }

    func update(_ content: BubbleContent, keepingWidth: Bool, limitHeight: CGFloat) -> NSSize {
        let sameKind = keepingWidth && self.content?.kind == content.kind
        if !sameKind {
            grownWidth = 0
            followEnd = content.followsEnd
        }
        let rebuild = !sameKind || self.content?.buttonKey != content.buttonKey || opensHere != content.threadID.map(opensInMessages)
        self.content = content

        let words = content.words(thinkingDots: thinkingDots)
        let body = words.body
        let code = words.isCode

        caption.font = MessagesInk.font(ofSize: MessagesInk.meta, tabular: true)
        counter.font = caption.font
        heading.font = MessagesInk.font(ofSize: MessagesInk.title, weight: .semibold)
        setLabel(caption, words.caption)
        setLabel(counter, words.counter)
        setLabel(heading, words.heading)
        if rebuild {
            look = .card(content.speaker.flatMap(kittenColor).map(Opal.Light.of) ?? .shades)
            buildButtons(for: content)
        }

        let font = code ? NSFont.monospacedSystemFont(ofSize: MessagesInk.body - 1, weight: .regular) : MessagesInk.font(ofSize: MessagesInk.body)
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
        let inset = Self.inset
        let content = self.content!
        let codeRoom = code ? Self.codePadding * 2 : 0
        let groupGap = leadingButtons > 0 && leadingButtons < buttons.count ? Self.rowGap : 0
        let buttonsWidth = buttons.reduce(0) { $0 + $1.frame.width } + CGFloat(max(0, buttons.count - 1)) * Self.buttonGap + groupGap
        let inner = Self.maxWidth - inset.left - inset.right

        // Outside the repo: once NSLayoutManager has laid the same words out before, its usedRect comes back as wide as its container.
        let natural = ceil(textView.attributedString().boundingRect(
            with: NSSize(width: inner - codeRoom, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).width) + codeRoom
        var extras: CGFloat = 0
        if !caption.isHidden { extras = max(extras, ceil(caption.intrinsicContentSize.width)) }
        if !heading.isHidden { extras = max(extras, ceil(heading.attributedStringValue.size().width)) }
        var innerWidth = min(inner, max(natural + 1, buttonsWidth, extras, Self.minWidth - inset.left - inset.right))
        if content.fixedWidth { innerWidth = inner }
        innerWidth = max(innerWidth, grownWidth)
        grownWidth = innerWidth
        let width = innerWidth + inset.left + inset.right
        let textWidth = innerWidth - codeRoom

        let container = textView.textContainer!
        let manager = textView.layoutManager!
        container.size = NSSize(width: textWidth, height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        let textHeight = ceil(manager.usedRect(for: container).height)

        var chrome = inset.top + inset.bottom + codeRoom
        var captionHeight: CGFloat = 0
        if !caption.isHidden || !counter.isHidden {
            captionHeight = ceil(caption.intrinsicContentSize.height)
            chrome += captionHeight + 6
        }
        var headingHeight: CGFloat = 0
        if !heading.isHidden {
            headingHeight = ceil(heading.attributedStringValue.boundingRect(
                with: NSSize(width: innerWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).height)
            chrome += headingHeight + 6
        }
        let buttonsHeight: CGFloat = buttons.isEmpty ? 0 : 26
        if !buttons.isEmpty { chrome += buttonsHeight + Self.rowGap }

        let room = limitHeight - chrome - BubbleLayout.tailHeight
        let cap = min(room, code ? Self.maxCodeHeight : Self.maxTextHeight)
        let visibleText = max(18, min(textHeight, cap))

        let height = chrome + visibleText + BubbleLayout.tailHeight
        let size = NSSize(width: width, height: height)
        setFrameSize(size)

        var y = body.maxY - inset.top
        if !caption.isHidden || !counter.isHidden {
            y -= captionHeight
            // Outside the repo: an NSTextField label pads its words by 2 points on each side.
            let counterWidth = counter.isHidden ? 0 : ceil(counter.intrinsicContentSize.width) + 4
            let captionWidth = counter.isHidden ? innerWidth + 4 : innerWidth - counterWidth - 2
            caption.frame = NSRect(x: inset.left - 2, y: y, width: captionWidth, height: captionHeight)
            counter.frame = NSRect(x: inset.left + innerWidth - counterWidth, y: y, width: counterWidth + 2, height: captionHeight)
            y -= 6
        }
        if !heading.isHidden {
            y -= headingHeight
            heading.frame = NSRect(x: inset.left - 2, y: y, width: innerWidth + 4, height: headingHeight)
            y -= 6
        }
        y -= visibleText + codeRoom
        codeBlock = code ? NSRect(x: inset.left, y: y, width: innerWidth, height: visibleText + codeRoom) : nil
        let textX = inset.left + codeRoom / 2
        scroll.frame = NSRect(x: textX, y: y + codeRoom / 2, width: width - 4 - textX, height: visibleText)
        let scrolls = !content.isStreaming && textHeight > visibleText
        if scrolls && !scroll.hasVerticalScroller {
            scroll.hasVerticalScroller = true
            scroll.flashScrollers()
        }
        scroll.hasVerticalScroller = scrolls
        textView.minSize = NSSize(width: textWidth, height: 0)
        textView.maxSize = NSSize(width: max(textWidth, scroll.contentSize.width), height: .greatestFiniteMagnitude)
        textView.frame = NSRect(x: 0, y: 0, width: max(textWidth, scroll.contentSize.width), height: max(textHeight, visibleText))
        if followEnd { textView.scrollToEndOfDocument(nil) }
        textScrolled()

        var x = inset.left - (buttons.first?.style == .text ? 7 : 0)
        for button in buttons.prefix(leadingButtons) {
            button.setFrameOrigin(NSPoint(x: x, y: body.minY + inset.bottom))
            x += button.frame.width + Self.buttonGap
        }
        x = width - inset.right + (buttons.last?.style == .text ? 7 : 0)
        for button in buttons.dropFirst(leadingButtons).reversed() {
            x -= button.frame.width
            button.setFrameOrigin(NSPoint(x: x, y: body.minY + inset.bottom))
            x -= Self.buttonGap
        }
        needsDisplay = true
        return size
    }

    @objc private func textScrolled() {
        let shown = scroll.contentView.bounds
        textView.fades = (top: shown.minY >= 1, bottom: shown.maxY < textView.frame.height - 1)
    }

    private func buildButtons(for content: BubbleContent) {
        buttons.forEach { $0.removeFromSuperview() }
        buttons = []
        leadingButtons = 0

        @discardableResult
        func add(_ title: String, _ style: QuietButton.Style, _ action: BubbleAction) -> QuietButton {
            let button = QuietButton(title, style: style) { [weak self] in self?.onAction?(action) }
            buttons.append(button)
            addSubview(button)
            return button
        }
        opensHere = content.threadID.map(opensInMessages)
        func open(_ threadID: String) {
            if opensInMessages(threadID) {
                add("Open", .plain, .show(threadID: threadID))
            } else {
                add(CatWords.openInT3, .plain, .open(threadID: threadID))
            }
        }

        switch content {
        case .thinking, .listening:
            break
        case .reply(let text, let done, let threadID, _, let canReplace):
            guard done else { break }
            let copy = add("Copy", .text, .copy(text))
            let copied = copy.onPress
            copy.onPress = { [weak copy] in
                copied?()
                copy?.flash("Copied")
                BubbleController.announce("Copied")
            }
            if let threadID { open(threadID) }
            if canReplace { add("Replace", .filled, .replace(text)) }
        case .line(_, let threadID), .notice(_, _, let threadID, _):
            if let threadID { open(threadID) }
            if let pane = content.settingsPane { add(CatWords.openSystemSettings, .plain, .settings(pane)) }
        case .approval(let request, _, _):
            if ApprovalPolicy.offersSessionAllow(request.kind) {
                add("Allow for this session", .text, .approval(request, .acceptForSession))
                leadingButtons = 1
            }
            add("Deny", .plain, .approval(request, .decline))
            add("Allow", .filled, .approval(request, .accept))
        case .inbox:
            add("Open", .plain, .openMessages)
        }
    }
}

extension BubbleView: NSLayoutManagerDelegate {
    func layoutManager(_ layoutManager: NSLayoutManager, shouldBreakLineByWordBeforeCharacterAt charIndex: Int) -> Bool {
        guard case .approval(let request, _, _)? = content, request.kind == .command, charIndex > 0,
              let text = layoutManager.textStorage?.string as NSString?
        else { return true }
        return (CharacterSet.whitespaces as NSCharacterSet).characterIsMember(text.character(at: charIndex - 1))
    }
}

final class BubbleScroller: NSScroller {
    var onScrollByUser: (() -> Void)?

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onScrollByUser?()
        super.mouseDown(with: event)
    }
}

final class BubbleTextView: NSTextView {
    private static let fadeHeight: CGFloat = 28

    var onScrollByUser: (() -> Void)?
    var fades = (top: false, bottom: false) {
        didSet { if fades != oldValue { needsDisplay = true } }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { isSelectable }

    override func draw(_ dirtyRect: NSRect) {
        guard fades.top || fades.bottom, let context = NSGraphicsContext.current?.cgContext else { return super.draw(dirtyRect) }
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        super.draw(dirtyRect)
        context.setBlendMode(.destinationOut)
        let shown = visibleRect
        let solid = NSColor.black
        let clear = NSColor.black.withAlphaComponent(0)
        if fades.top {
            NSGradient(starting: solid, ending: clear)?.draw(in: NSRect(x: shown.minX, y: shown.minY, width: shown.width, height: Self.fadeHeight), angle: 90)
        }
        if fades.bottom {
            NSGradient(starting: clear, ending: solid)?.draw(in: NSRect(x: shown.minX, y: shown.maxY - Self.fadeHeight, width: shown.width, height: Self.fadeHeight), angle: 90)
        }
        context.endTransparencyLayer()
    }

    override func scrollWheel(with event: NSEvent) {
        onScrollByUser?()
        super.scrollWheel(with: event)
    }
}

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

    var spoken: String? {
        switch self {
        case .listening, .reply(_, false, _, _, _): return nil
        default:
            let words = words()
            return [words.caption, words.counter, words.heading, words.body].compactMap { $0 }.joined(separator: "\n")
        }
    }

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

    fileprivate var settingsPane: Permissions.Pane? {
        guard case .line(let text, nil) = self else { return nil }
        let panes: [String: Permissions.Pane] = [
            CatWords.needsScreenRecording: .screenRecording,
            CatWords.needsMicrophone: .microphone,
            CatWords.needsAccessibility: .accessibility,
            CatWords.needsInputMonitoring: .inputMonitoring,
        ]
        return panes[text]
    }

    fileprivate var buttonKey: String {
        switch self {
        case .thinking, .listening: return ""
        case .reply(let text, let done, let thread, _, let canReplace): return done ? "reply|\(thread ?? "")|\(canReplace)|\(text)" : ""
        case .line(_, let thread): return "line|\(thread ?? "")|\(settingsPane?.rawValue ?? "")"
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

    fileprivate var speaker: String? {
        switch self {
        case .notice(_, _, let thread, _): return thread
        case .approval(let request, _, _): return request.threadID
        default: return nil
        }
    }

    fileprivate var followsEnd: Bool {
        if case .listening = self { return true }
        return false
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
