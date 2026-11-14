import AppKit
import ShadesCore

/// A kitten's backlog over the window, as Slack shows a channel's pins: what it's doing, then what's next and what can
/// wait, each with when you asked and your words. It only reads `backlog.md`, so changing it is asking the kitten. It's
/// drawn in the window rather than as a popover or menu, which are windows of their own that a screen share would show.
final class BacklogSheet: QuietView {
    private static let width: CGFloat = 520
    private static let top: CGFloat = 70

    var onClose: (() -> Void)?
    /// Whose it is, by the kitten's ID, while it's open.
    private(set) var kitten: String?
    let close = MessageToolbar.button(CatWords.closeThread, symbol: "xmark")
    private let scroll = QuietScrollView()
    let list = BacklogList()
    private var name = ""

    override init(frame: NSRect) {
        super.init(frame: frame)
        scroll.documentView = list
        addSubview(scroll)
        close.onPress = { [weak self] in self?.onClose?() }
        addSubview(close)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(_ backlog: Backlog, of kitten: String, named name: String) {
        self.kitten = kitten
        self.name = name
        list.items = backlog.items
        setAccessibilityLabel(([CatWords.backlogTitle, name] + backlog.items.map(BacklogList.spoken)).joined(separator: ". "))
        needsLayout = true
        needsDisplay = true
    }

    var card: NSRect {
        let width = min(Self.width, bounds.width - 40)
        let height = min(Self.top + list.height(for: width) + 16, bounds.height - 40)
        return NSRect(x: ((bounds.width - width) / 2).rounded(), y: max(((bounds.height - height) / 2).rounded(), 20), width: width, height: height)
    }

    override func layout() {
        super.layout()
        let card = card
        close.frame.origin = NSPoint(x: card.maxX - close.frame.width - 10, y: card.minY + 14)
        scroll.frame = NSRect(x: card.minX, y: card.minY + Self.top, width: card.width, height: max(card.height - Self.top - 16, 0))
        list.frame = NSRect(x: 0, y: 0, width: card.width, height: list.height(for: card.width))
    }

    override func mouseUp(with event: NSEvent) {
        if !card.contains(convert(event.locationInWindow, from: nil)) { onClose?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        MessagesInk.sidebar.withAlphaComponent(0.55).setFill()
        bounds.fill(using: .sourceOver)
        let card = card
        Opal.glass(NSBezierPath(roundedRect: card, xRadius: Opal.Corner.popover, yRadius: Opal.Corner.popover))
        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        let room = card.width - 44 - close.frame.width
        NSAttributedString(string: CatWords.backlogTitle, attributes: [.font: MessagesInk.font(ofSize: 15, weight: .semibold), .foregroundColor: MessagesInk.strong, .paragraphStyle: truncating])
            .draw(in: NSRect(x: card.minX + 22, y: card.minY + 16, width: room, height: 20))
        NSAttributedString(string: CatWords.backlogKeeper(name), attributes: [.font: MessagesInk.font(ofSize: MessagesInk.meta), .foregroundColor: MessagesInk.soft, .paragraphStyle: truncating])
            .draw(in: NSRect(x: card.minX + 22, y: card.minY + 38, width: room, height: 16))
    }
}

/// The items under small-capital headings for their levels, with a hairline between rows, as Opal's tables have. Drawn
/// rather than made of views, and measured at the sheet's width.
final class BacklogList: QuietView {
    private static let inset: CGFloat = 22
    private static let headingHeight: CGFloat = 30
    private static let mostAboutLines: CGFloat = 2

    var items: [Backlog.Item] = [] { didSet { needsDisplay = true } }

    private enum Piece {
        case heading(String)
        case item(Backlog.Item)
        case empty
    }

    /// The level's own word, then what, when and your words, for VoiceOver.
    static func spoken(_ item: Backlog.Item) -> String {
        [item.level.rawValue, item.what, item.date, item.words].compactMap { $0 }.joined(separator: ", ")
    }

    private var pieces: [Piece] {
        guard !items.isEmpty else { return [.empty] }
        return Backlog.Level.allCases.flatMap { level -> [Piece] in
            let these = items.filter { $0.level == level }
            return these.isEmpty ? [] : [.heading(level.rawValue)] + these.map(Piece.item)
        }
    }

    private func what(_ text: String, color: NSColor = MessagesInk.text) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: MessagesInk.font(ofSize: MessagesInk.body), .foregroundColor: color])
    }

    /// When you asked and your words, in quotes, on at most two lines.
    private func about(_ item: Backlog.Item) -> NSAttributedString? {
        let line = [item.date, item.words.map { "\u{201C}\($0)\u{201D}" }].compactMap { $0 }.joined(separator: " · ")
        return line.isEmpty ? nil : NSAttributedString(string: line, attributes: [.font: MessagesInk.font(ofSize: MessagesInk.meta), .foregroundColor: MessagesInk.soft])
    }

    private func measure(_ text: NSAttributedString, width: CGFloat, lines: CGFloat? = nil) -> CGFloat {
        let needed = ceil(text.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
        guard let lines, let font = text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont else { return needed }
        return min(needed, ceil(NSLayoutManager().defaultLineHeight(for: font) * lines))
    }

    /// Each piece and where it goes, top to bottom, at `width`.
    private func laidOut(width: CGFloat) -> (pieces: [(Piece, NSRect)], height: CGFloat) {
        let room = max(width - Self.inset * 2, 0)
        var y: CGFloat = 0
        var placed: [(Piece, NSRect)] = []
        for piece in pieces {
            let height: CGFloat
            switch piece {
            case .heading:
                height = Self.headingHeight
            case .empty:
                height = measure(what(CatWords.backlogEmpty), width: room) + 16
            case .item(let item):
                let about = about(item).map { measure($0, width: room, lines: Self.mostAboutLines) + 3 } ?? 0
                height = measure(what(item.what), width: room) + about + 16
            }
            placed.append((piece, NSRect(x: Self.inset, y: y, width: room, height: height)))
            y += height
        }
        return (placed, y)
    }

    func height(for width: CGFloat) -> CGFloat {
        laidOut(width: width).height
    }

    override func draw(_ dirtyRect: NSRect) {
        let placed = laidOut(width: bounds.width).pieces
        for (index, (piece, rect)) in placed.enumerated() {
            switch piece {
            case .heading(let level):
                MessagesInk.label(level).draw(at: NSPoint(x: rect.minX, y: rect.maxY - MessagesInk.label - 10))
            case .empty:
                what(CatWords.backlogEmpty, color: MessagesInk.soft).draw(with: rect.insetBy(dx: 0, dy: 8), options: [.usesLineFragmentOrigin, .usesFontLeading])
            case .item(let item):
                let words = what(item.what)
                let wordsHeight = measure(words, width: rect.width)
                words.draw(with: NSRect(x: rect.minX, y: rect.minY + 8, width: rect.width, height: wordsHeight), options: [.usesLineFragmentOrigin, .usesFontLeading])
                if let about = about(item) {
                    let aboutRect = NSRect(x: rect.minX, y: rect.minY + 8 + wordsHeight + 3, width: rect.width, height: measure(about, width: rect.width, lines: Self.mostAboutLines))
                    about.draw(with: aboutRect, options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine])
                }
                if index + 1 < placed.count, case .item = placed[index + 1].0 {
                    MessagesInk.line.setFill()
                    NSRect(x: rect.minX, y: rect.maxY - 1, width: rect.width, height: 1).fill()
                }
            }
        }
    }
}
