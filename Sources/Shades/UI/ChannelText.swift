import AppKit

/// Inline markdown only. Links come out as plain words, so nothing in a message can act.
enum ChannelMarkdown {
    static let font = NSFont.systemFont(ofSize: 13)

    static func attributed(_ text: String, color: NSColor = MessagesInk.text) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        let plain: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard let parsed = try? AttributedString(markdown: text, options: options) else {
            return NSAttributedString(string: text, attributes: plain)
        }

        let result = NSMutableAttributedString()
        for run in parsed.runs {
            var attributes = plain
            let intent = run.inlinePresentationIntent ?? []
            var runFont = intent.contains(.stronglyEmphasized) ? NSFont.systemFont(ofSize: font.pointSize, weight: .semibold) : font
            if intent.contains(.emphasized) { runFont = NSFontManager.shared.convert(runFont, toHaveTrait: .italicFontMask) }
            if intent.contains(.code) {
                runFont = .monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular)
                attributes[.backgroundColor] = Ink.hover
            }
            if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            attributes[.font] = runFont
            result.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }
        return result
    }
}

/// Some text laid out at one width, cut short to a number of lines if asked, in a text view you can select and copy
/// from. Pressing in it gives Messages the keyboard, the way pressing in the box does, which still leaves your app in
/// front, so Command-C has somewhere to go. It's measured without a view, and only gets one once the row it's in is
/// shown, since most of a long conversation never is.
final class ChannelTextBlock {
    private let layoutManager = NSLayoutManager()
    private let container = NSTextContainer()
    private let storage: NSTextStorage
    private var textView: ChannelTextView?
    private var origin = NSPoint.zero
    private var fitted: (width: CGFloat, maxLines: Int?)?
    private(set) var height: CGFloat = 0
    /// The widest line, so a bubble can be no wider than its words.
    private(set) var width: CGFloat = 0
    /// Where the words end, which for centred words is past `width`.
    private var right: CGFloat = 0
    private(set) var isCut = false

    init(_ text: NSAttributedString) {
        storage = NSTextStorage(attributedString: text)
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        container.lineFragmentPadding = 0
    }

    @discardableResult
    func fit(width: CGFloat, maxLines: Int? = nil) -> CGFloat {
        if let fitted, fitted.width == width, fitted.maxLines == maxLines { return height }
        fitted = (width, maxLines)
        container.size = NSSize(width: width, height: .greatestFiniteMagnitude)
        // One line past the most it can show is enough to tell it's cut, however long it goes on.
        container.maximumNumberOfLines = maxLines.map { $0 + 1 } ?? 0
        container.lineBreakMode = .byWordWrapping
        isCut = false
        let lines = lineRects.map(\.width)
        if let maxLines, lines.count > maxLines {
            // A blank line at the end would look like the end of the message, so it stops short of one.
            let lastWithWords = lines.prefix(maxLines).lastIndex { $0 > 0 } ?? maxLines - 1
            container.maximumNumberOfLines = lastWithWords + 1
            container.lineBreakMode = .byTruncatingTail
            isCut = true
        }
        layoutManager.ensureLayout(for: container)
        height = ceil(layoutManager.usedRect(for: container).height)
        // With a text view on it, the used rect is as wide as the container, so the lines say how wide the words are.
        let shown = lineRects
        self.width = ceil(shown.map(\.width).max() ?? 0)
        right = ceil(shown.map(\.maxX).max() ?? 0)
        return height
    }

    var view: ChannelTextView {
        if let textView { return textView }
        let view = ChannelTextView(frame: .zero, textContainer: container)
        view.selectedTextAttributes = Self.selection(on: wordsColor)
        textView = view
        return view
    }

    /// Puts the words in `superview` with their top left at `origin`, as wide as they are, so pressing beside them
    /// doesn't start a selection. A row that isn't shown only remembers where they go.
    func place(at origin: NSPoint, in superview: NSView) {
        self.origin = origin
        if superview.superview != nil || textView?.superview === superview { show(in: superview) }
    }

    func show(in superview: NSView) {
        if view.superview !== superview { superview.addSubview(view) }
        view.frame = NSRect(x: origin.x, y: origin.y, width: right, height: height)
    }

    /// The same words in another colour, such as after a theme change, without reading or measuring them again.
    func recolor(_ color: NSColor) {
        storage.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: storage.length))
        textView?.selectedTextAttributes = Self.selection(on: color)
    }

    private var wordsColor: NSColor? {
        storage.length > 0 ? storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor : nil
    }

    /// A tint of the words' own colour shows on any bubble, where the system's blue might not.
    private static func selection(on words: NSColor?) -> [NSAttributedString.Key: Any] {
        [.backgroundColor: NSColor(name: nil) { _ in
            (words ?? MessagesInk.text).usingColorSpace(.sRGB)?.withAlphaComponent(0.3) ?? .selectedTextBackgroundColor
        }]
    }

    /// What each line's words take up.
    private var lineRects: [NSRect] {
        layoutManager.ensureLayout(for: container)
        var rects: [NSRect] = []
        layoutManager.enumerateLineFragments(forGlyphRange: layoutManager.glyphRange(for: container)) { _, used, _, _, _ in
            rects.append(used)
        }
        return rects
    }
}

/// Words in Messages, which you can select and copy but not change. Like the reply in the cat's bubble, pressing in
/// them is what gives the window the keyboard, and only because you asked.
final class ChannelTextView: NSTextView {
    override init(frame: NSRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        isEditable = false
        isSelectable = true
        // Plain words when copied, so pasting doesn't bring along a bubble's white text. What's shown keeps its look.
        isRichText = false
        drawsBackground = false
        textContainerInset = .zero
        isVerticallyResizable = false
        isHorizontallyResizable = false
        usesFontPanel = false
        importsGraphics = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        // Nothing to check in words you can't change, and a window full of them shouldn't wake the spelling service.
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticTextCompletionEnabled = false
        linkTextAttributes = [:]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { true }

    /// A right-click is about these words too, so Copy in its menu has them.
    override func rightMouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        super.rightMouseDown(with: event)
    }

    /// Only one selection at a time, as there would be in one long page.
    override func resignFirstResponder() -> Bool {
        setSelectedRange(NSRange(location: 0, length: 0))
        return super.resignFirstResponder()
    }
}
