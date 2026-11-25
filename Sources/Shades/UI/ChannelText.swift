import AppKit

enum ChannelMarkdown {
    static var font: NSFont { MessagesInk.font(ofSize: MessagesInk.body) }
    private static var codeFont: NSFont { .monospacedSystemFont(ofSize: MessagesInk.body - 1, weight: .regular) }
    static let copyRoom: CGFloat = 22
    static let largestTable = 400
    private static let deepestIndent = 3

    static func chipColor(_ state: String?) -> NSColor {
        switch state {
        case "open": return Ink.hex(0x1f883d)
        case "merged": return Ink.hex(0x8250df)
        case "closed": return Ink.hex(0xcf222e)
        default: return Ink.hex(0x6e7781)
        }
    }

    static func attributed(_ text: String, color: NSColor = MessagesInk.text, pulls: [String: String] = [:]) -> NSAttributedString {
        attributed(Markup(text, pulls: pulls), color: color)
    }

    static func attributed(_ markup: Markup, color: NSColor = MessagesInk.text) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, block) in markup.blocks.enumerated() {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 2
            style.paragraphSpacing = 6
            if index > 0, markup.blocks[index - 1].kind == .table { style.paragraphSpacingBefore = 8 }
            switch block.kind {
            case .paragraph:
                result.append(line(block.spans ?? [], color: color, style: style))
            case .heading:
                result.append(line(block.spans ?? [], color: color, style: style, font: MessagesInk.font(ofSize: MessagesInk.title, weight: .semibold)))
            case .item:
                let indent = CGFloat(min((block.depth ?? 1) - 1, deepestIndent)) * 14
                let marker = block.marker ?? ""
                let markerWidth: CGFloat = marker.hasSuffix(".") ? 20 : 14
                style.firstLineHeadIndent = indent
                style.headIndent = indent + markerWidth
                style.tabStops = [NSTextTab(textAlignment: .left, location: indent + markerWidth)]
                style.paragraphSpacing = 3
                let item = NSMutableAttributedString(string: marker.isEmpty ? "\t" : "\(marker)\t", attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
                item.append(line(block.spans ?? [], color: color, style: style))
                result.append(item)
            case .quote:
                let quote = NSTextBlock(fill: nil, padding: 8, color: color)
                quote.setWidth(0, type: .absoluteValueType, for: .padding, edge: .minY)
                quote.setWidth(0, type: .absoluteValueType, for: .padding, edge: .maxY)
                quote.setWidth(3, type: .absoluteValueType, for: .border, edge: .minX)
                quote.setBorderColor(color.withAlphaComponent(0.35), for: .minX)
                style.textBlocks = [quote]
                result.append(line(block.spans ?? [], color: color, style: style))
            case .code:
                result.append(code(block.code ?? "", color: color, style: style))
            case .table:
                let rows = block.rows ?? []
                if rows.map(\.count).reduce(0, +) > largestTable {
                    let text = rows.map { $0.map { $0.map(\.text).joined() }.joined(separator: " | ") }.joined(separator: "\n")
                    result.append(code(text, color: color, style: style))
                } else {
                    result.append(table(rows, color: color))
                }
            case .rule:
                let rule = NSTextBlock(fill: nil, padding: 0, color: color)
                rule.setWidth(1, type: .absoluteValueType, for: .border, edge: .minY)
                rule.setBorderColor(color.withAlphaComponent(0.25), for: .minY)
                rule.setWidth(4, type: .absoluteValueType, for: .margin, edge: .minY)
                style.textBlocks = [rule]
                result.append(NSAttributedString(string: "\u{200B}\n", attributes: [.font: MessagesInk.font(ofSize: 4), .paragraphStyle: style]))
            }
        }
        if result.string.hasSuffix("\n") { result.deleteCharacters(in: NSRange(location: result.length - 1, length: 1)) }
        return result
    }

    private static func code(_ code: String, color: NSColor, style: NSMutableParagraphStyle) -> NSAttributedString {
        let block = NSTextBlock(fill: color.withAlphaComponent(0.08), padding: 8, color: color)
        block.setWidth(copyRoom, type: .absoluteValueType, for: .padding, edge: .minY)
        style.textBlocks = [block]
        style.paragraphSpacing = 0
        style.lineSpacing = 1
        return NSAttributedString(string: code + "\n", attributes: [
            .font: codeFont, .foregroundColor: color, .paragraphStyle: style, .channelCode: ChannelCode(code),
        ])
    }

    private static func line(_ spans: [Markup.Span], color: NSColor, style: NSParagraphStyle, font: NSFont = font) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for span in spans { result.append(attributed(span, color: color, style: style, font: font)) }
        result.append(NSAttributedString(string: "\n", attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style]))
        return result
    }

    private static func attributed(_ span: Markup.Span, color: NSColor, style: NSParagraphStyle, font: NSFont) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: color, .paragraphStyle: style]
        var runFont = span.bold == true ? MessagesInk.font(ofSize: font.pointSize, weight: .semibold) : font
        if span.italic == true { runFont = NSFontManager.shared.convert(runFont, toHaveTrait: .italicFontMask) }
        if span.code == true {
            runFont = .monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular)
            attributes[.backgroundColor] = MessagesInk.hover
        }
        if span.strike == true { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        var text = span.text
        if let link = span.link {
            attributes[.link] = link
            attributes[.toolTip] = link.absoluteString
            attributes[.cursor] = NSCursor.pointingHand
            if let pull = span.pull {
                text = "\u{00A0}" + ([text] + [pull.state].compactMap { $0 }).joined(separator: " · ").replacingOccurrences(of: " ", with: "\u{00A0}") + "\u{00A0}"
                runFont = MessagesInk.font(ofSize: font.pointSize - 1, weight: .semibold)
                attributes[.foregroundColor] = NSColor.white
                attributes[.channelChip] = chipColor(pull.state)
            } else {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
        }
        attributes[.font] = runFont
        return NSAttributedString(string: text, attributes: attributes)
    }

    private static func table(_ rows: [[[Markup.Span]]], color: NSColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let table = NSTextTable()
        table.numberOfColumns = max(rows.map(\.count).max() ?? 1, 1)
        table.setValue(100, type: .percentageValueType, for: .width)
        table.collapsesBorders = true
        table.hidesEmptyCells = false
        for (rowIndex, row) in rows.enumerated() {
            for (column, cell) in row.enumerated() {
                let block = NSTextTableBlock(table: table, startingRow: rowIndex, rowSpan: 1, startingColumn: column, columnSpan: 1)
                block.setWidth(5, type: .absoluteValueType, for: .padding)
                block.setWidth(1, type: .absoluteValueType, for: .border)
                block.setBorderColor(color.withAlphaComponent(0.25))
                if rowIndex == 0 { block.backgroundColor = color.withAlphaComponent(0.06) }
                let style = NSMutableParagraphStyle()
                style.textBlocks = [block]
                result.append(line(cell, color: color, style: style, font: rowIndex == 0 ? MessagesInk.font(ofSize: font.pointSize, weight: .semibold) : font))
            }
        }
        return result
    }
}

extension NSAttributedString.Key {
    static let channelCode = NSAttributedString.Key("ShadesChannelCode")
    static let channelChip = NSAttributedString.Key("ShadesChannelChip")
}

final class ChannelCode: NSObject {
    let text: String
    init(_ text: String) { self.text = text }
}

private extension NSTextBlock {
    convenience init(fill: NSColor?, padding: CGFloat, color: NSColor) {
        self.init()
        setValue(100, type: .percentageValueType, for: .width)
        setWidth(padding, type: .absoluteValueType, for: .padding)
        setWidth(3, type: .absoluteValueType, for: .margin, edge: .maxY)
        backgroundColor = fill
    }
}

private final class ChipLayoutManager: NSLayoutManager {
    // Outside the repo: AppKit fills a selection with these greys while its window isn't key.
    private static let systemSelection: [NSColor] = [.unemphasizedSelectedContentBackgroundColor, .unemphasizedSelectedTextBackgroundColor]

    override func fillBackgroundRectArray(_ rectArray: UnsafePointer<NSRect>, count rectCount: Int, forCharacterRange charRange: NSRange, color: NSColor) {
        guard Self.systemSelection.contains(color), let fill = firstTextView?.selectedTextAttributes[.backgroundColor] as? NSColor else {
            return super.fillBackgroundRectArray(rectArray, count: rectCount, forCharacterRange: charRange, color: color)
        }
        fill.setFill()
        super.fillBackgroundRectArray(rectArray, count: rectCount, forCharacterRange: charRange, color: fill)
        color.setFill()
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        defer { super.drawBackground(forGlyphRange: glyphsToShow, at: origin) }
        guard let storage = textStorage, let container = textContainers.first else { return }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(.channelChip, in: characters) { value, range, _ in
            guard let fill = value as? NSColor else { return }
            fill.setFill()
            enumerateEnclosingRects(forGlyphRange: glyphRange(forCharacterRange: range, actualCharacterRange: nil), withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { rect, _ in
                let pill = rect.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: 0, dy: 1)
                NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
            }
        }
    }
}

final class ChannelTextBlock {
    private let layoutManager: NSLayoutManager = ChipLayoutManager()
    private let container = NSTextContainer()
    private let storage: NSTextStorage
    private var textView: ChannelTextView?
    private var origin = NSPoint.zero
    private var fitted: (width: CGFloat, maxLines: Int?)?
    private(set) var height: CGFloat = 0
    private(set) var width: CGFloat = 0
    private var right: CGFloat = 0
    private(set) var isCut = false
    private let hasBlocks: Bool
    private var cutAt: CGFloat = 0

    init(_ text: NSAttributedString) {
        storage = NSTextStorage(attributedString: text)
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        container.lineFragmentPadding = 0
        var hasBlocks = false
        text.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: text.length)) { value, _, stop in
            if (value as? NSParagraphStyle)?.textBlocks.isEmpty == false {
                hasBlocks = true
                stop.pointee = true
            }
        }
        self.hasBlocks = hasBlocks
    }

    @discardableResult
    func fit(width: CGFloat, maxLines: Int? = nil) -> CGFloat {
        if let fitted, fitted.width == width, fitted.maxLines == maxLines { return height }
        fitted = (width, maxLines)
        container.size = NSSize(width: width, height: .greatestFiniteMagnitude)
        let cutPast = maxLines.map { $0 + $0 / 3 }
        // Outside the repo: TextKit never finishes a layout that stops partway through a code block or table.
        container.maximumNumberOfLines = hasBlocks ? 0 : cutPast.map { $0 + 1 } ?? 0
        container.lineBreakMode = .byWordWrapping
        isCut = false
        let rects = lineRects
        let lines = rects.map(\.width)
        if let maxLines, let cutPast, lines.count > cutPast {
            let lastWithWords = lines.prefix(maxLines).lastIndex { $0 > 0 } ?? maxLines - 1
            if !hasBlocks {
                container.maximumNumberOfLines = lastWithWords + 1
                container.lineBreakMode = .byTruncatingTail
            }
            isCut = true
            cutAt = ceil(rects.prefix(lastWithWords + 1).map(\.maxY).max() ?? 0)
        }
        layoutManager.ensureLayout(for: container)
        height = hasBlocks && isCut ? cutAt : ceil(layoutManager.usedRect(for: container).height)
        let shown = lineRects
        right = hasBlocks ? width : ceil(shown.map(\.maxX).max() ?? 0)
        self.width = hasBlocks ? width : right - floor(shown.map(\.minX).min() ?? 0)
        return height
    }

    var view: ChannelTextView {
        if let textView { return textView }
        let view = ChannelTextView(frame: .zero, textContainer: container)
        view.selectedTextAttributes = Self.selection(on: wordsColor)
        view.clipsToBounds = true
        textView = view
        return view
    }

    func place(at origin: NSPoint, in superview: NSView) {
        self.origin = origin
        if superview.superview != nil || textView?.superview === superview { show(in: superview) }
    }

    func show(in superview: NSView) {
        if view.superview !== superview { superview.addSubview(view, positioned: .below, relativeTo: nil) }
        view.frame = NSRect(x: origin.x, y: origin.y, width: right, height: height)
    }

    func restyle(_ text: NSAttributedString) {
        storage.setAttributedString(text)
        fitted = nil
        textView?.selectedTextAttributes = Self.selection(on: wordsColor)
    }

    var codeBlocks: [(frame: NSRect, code: String)] {
        var found: [(NSRect, String)] = []
        let shown = layoutManager.characterRange(forGlyphRange: layoutManager.glyphRange(for: container), actualGlyphRange: nil)
        storage.enumerateAttribute(.channelCode, in: shown) { value, range, _ in
            guard let code = value as? ChannelCode,
                  let block = (storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)?.textBlocks.first
            else { return }
            let frame = layoutManager.boundsRect(for: block, glyphRange: layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil))
            if frame.height > 0, frame.minY < height { found.append((frame, code.text)) }
        }
        return found
    }

    private var wordsColor: NSColor? {
        storage.length > 0 ? storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor : nil
    }

    private static func selection(on words: NSColor?) -> [NSAttributedString.Key: Any] {
        MessagesInk.selection(on: words ?? MessagesInk.text)
    }

    private var lineRects: [NSRect] {
        layoutManager.ensureLayout(for: container)
        var rows: [CGFloat: NSRect] = [:]
        layoutManager.enumerateLineFragments(forGlyphRange: layoutManager.glyphRange(for: container)) { _, used, _, _, _ in
            rows[used.minY] = rows[used.minY].map { $0.union(used) } ?? used
        }
        return rows.values.sorted { $0.minY < $1.minY }
    }
}

final class ChannelTextView: NSTextView {
    override init(frame: NSRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        isEditable = false
        isSelectable = true
        isRichText = false
        drawsBackground = false
        textContainerInset = .zero
        isVerticallyResizable = false
        isHorizontallyResizable = false
        usesFontPanel = false
        importsGraphics = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticTextCompletionEnabled = false
        linkTextAttributes = [:]
    }

    override func mouseDown(with event: NSEvent) {
        guard let link = link(at: convert(event.locationInWindow, from: nil)) else { return super.mouseDown(with: event) }
        clicked(onLink: link, at: 0)
    }

    override func clicked(onLink link: Any, at charIndex: Int) {
        guard let link = link as? URL else { return }
        tryToPerform(#selector(ChannelPane.ask(toOpen:)), with: link)
    }

    // Outside the repo: NSTextView's own menu has Open Link and Open With, which open a link at once.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let menu = superview?.menu(for: event) else {
            let menu = NSMenu()
            menu.addItem(withTitle: "Copy", action: #selector(copy(_:)), keyEquivalent: "")
            return menu
        }
        if selectedRange().length > 0, let item = menu.item(withTitle: "Copy") {
            item.target = self
            item.action = #selector(copy(_:))
        }
        return menu
    }

    func link(at point: NSPoint) -> URL? {
        guard let layoutManager, let textContainer, let textStorage, layoutManager.numberOfGlyphs > 0 else { return nil }
        let glyph = layoutManager.glyphIndex(for: point, in: textContainer)
        guard layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer).contains(point) else { return nil }
        return textStorage.attribute(.link, at: layoutManager.characterIndexForGlyph(at: glyph), effectiveRange: nil) as? URL
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
    override var canBecomeKeyView: Bool { false }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        super.rightMouseDown(with: event)
    }

    override func resignFirstResponder() -> Bool {
        setSelectedRange(NSRange(location: 0, length: 0))
        return super.resignFirstResponder()
    }
}
