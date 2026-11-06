import AppKit
import ShadesCore

/// One line of the sidebar, as a value, so it's only rebuilt when something really changed.
struct ChannelSidebarItem: Equatable {
    enum Cat: Equatable {
        case kitten(KittenStatus)
        case shades
        case other
    }

    var selection: ChannelSelection
    var title: String
    var cats: [Cat] = []
    var count: Int?
    var isUnread = false

    static func groups(in book: ChannelBook) -> [(heading: String?, items: [ChannelSidebarItem])] {
        let directs = book.statuses.map { status in
            ChannelSidebarItem(
                selection: .channel(.direct(status.kitten)),
                title: status.kitten.name,
                cats: [.kitten(status)],
                isUnread: book.unread.contains(status.kitten.id)
            )
        }
        let between = book.between.map { channel in
            ChannelSidebarItem(selection: .channel(channel.id), title: book.title(of: channel.id), cats: book.others(in: channel.id).map { other in
                book.status(of: other).map(Cat.kitten) ?? .other
            })
        }
        let needsYou = ChannelSidebarItem(selection: .needsYou, title: CatWords.needsYouTitle, count: book.waiting.count)
        let everyone = ChannelSidebarItem(selection: .channel(.everyone), title: CatWords.everyone, cats: [.shades], isUnread: !book.unread.isEmpty)
        return [(nil, [needsYou, everyone]), (CatWords.directMessages, directs)] + (between.isEmpty ? [] : [(CatWords.betweenKittens, between)])
    }
}

/// The left side of the window: Needs you and Everyone, then a row for each kitten, then each pair that's talked.
final class ChannelSidebar: QuietView {
    static let width: CGFloat = 220
    /// Leaves room for the window's buttons.
    private static let top: CGFloat = 38
    private static let rowHeight: CGFloat = 32
    private static let headingHeight: CGFloat = 34

    var onSelect: ((ChannelSelection) -> Void)?
    private(set) var rows: [ChannelSidebarRow] = []

    private let scroll = QuietScrollView()
    private let list = QuietView()
    private var shownGroups: [[ChannelSidebarItem]] = []
    private var tick = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        scroll.documentView = list
        addSubview(scroll)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func row(for selection: ChannelSelection) -> ChannelSidebarRow? {
        rows.first { $0.item.selection == selection }
    }

    func show(_ book: ChannelBook, selection: ChannelSelection) {
        let groups = ChannelSidebarItem.groups(in: book)
        if groups.map(\.items) != shownGroups { rebuild(groups) }
        rows.forEach { $0.isSelected = $0.item.selection == selection }
    }

    func advance(tick: Int) {
        self.tick = tick
        rows.forEach { $0.update(tick: tick) }
    }

    private func rebuild(_ groups: [(heading: String?, items: [ChannelSidebarItem])]) {
        shownGroups = groups.map(\.items)
        list.subviews.forEach { $0.removeFromSuperview() }
        rows = []
        var y: CGFloat = 0
        for group in groups {
            if let heading = group.heading {
                y += addHeading(heading, at: y)
            }
            for item in group.items {
                let row = ChannelSidebarRow(item: item)
                row.onPress = { [weak self] in self?.onSelect?(item.selection) }
                row.update(tick: tick)
                row.frame = NSRect(x: 8, y: y, width: Self.width - 16, height: Self.rowHeight)
                list.addSubview(row)
                rows.append(row)
                y += Self.rowHeight
            }
        }
        list.frame = NSRect(x: 0, y: 0, width: Self.width, height: y + 12)
    }

    private func addHeading(_ text: String, at y: CGFloat) -> CGFloat {
        let label = NSTextField(labelWithAttributedString: NSAttributedString(string: text.uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: Ink.soft,
            .kern: 0.5,
        ]))
        label.sizeToFit()
        label.frame.origin = NSPoint(x: 16, y: y + Self.headingHeight - label.frame.height - 5)
        list.addSubview(label)
        return Self.headingHeight
    }

    override func layout() {
        super.layout()
        scroll.frame = NSRect(x: 0, y: Self.top, width: bounds.width - 1, height: max(bounds.height - Self.top, 0))
    }

    override func draw(_ dirtyRect: NSRect) {
        Ink.hover.setFill()
        bounds.fill(using: .sourceOver)
        Ink.line.setFill()
        NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height).fill(using: .sourceOver)
    }
}

final class ChannelSidebarRow: ChannelRowView {
    private static let catSide: CGFloat = 24
    private static let catInset: CGFloat = 6

    let item: ChannelSidebarItem
    var onPress: (() -> Void)?
    var isSelected = false { didSet { if isSelected != oldValue { needsDisplay = true } } }
    private var tick = 0

    init(item: ChannelSidebarItem) {
        self.item = item
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(accessibilityWords)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private var accessibilityWords: String {
        if let count = item.count { return "\(item.title), \(count)" }
        var words = [item.title]
        if case .kitten(let status)? = item.cats.first, item.cats.count == 1 { words.append(CatWords.kittenState(status.state)) }
        if item.isUnread { words.append("unread") }
        return words.joined(separator: ", ")
    }

    override var isPressable: Bool { true }
    override func press() { onPress?() }

    /// Only a kitten that's working or needs you moves, so nothing else has to redraw.
    var isLive: Bool {
        item.cats.contains {
            guard case .kitten(let status) = $0 else { return false }
            return status.state.dotColor != nil
        }
    }

    private var isFaded: Bool {
        guard case .kitten(let status)? = item.cats.first, item.cats.count == 1 else { return false }
        return status.state == .notSetUp
    }

    func update(tick: Int) {
        self.tick = tick
        if isLive { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        if isSelected || hovering {
            (isSelected ? Ink.press : Ink.hover).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
        }

        let fraction: CGFloat = isFaded ? 0.4 : 1
        let side = Self.catSide
        for (index, cat) in item.cats.enumerated() {
            let frame = NSRect(x: Self.catInset + CGFloat(index) * side / 2, y: (bounds.height - side) / 2, width: side, height: side)
            switch cat {
            case .kitten(let status):
                CatStamp.draw(status.pose(tick: isLive ? tick : 0), jacket: ChannelSpeakerLook.color(of: status.kitten), in: frame, on: self, fraction: fraction)
            case .shades:
                CatStamp.draw(CatPose(frame: .sit), jacket: nil, in: frame, on: self)
            case .other:
                CatStamp.draw(CatPose(frame: .sit), jacket: ChannelSpeakerLook.otherJacket, in: frame, on: self)
            }
        }

        var right = bounds.width - 10
        if case .kitten(let status)? = item.cats.first, item.cats.count == 1, let dot = status.state.dotColor {
            dot.setFill()
            NSBezierPath(rect: NSRect(x: right - 8, y: bounds.midY - 4, width: 8, height: 8)).fill()
            right -= 16
        }
        if item.isUnread {
            Ink.accent.setFill()
            NSBezierPath(ovalIn: NSRect(x: right - 8, y: bounds.midY - 4, width: 8, height: 8)).fill()
            right -= 16
        }
        if let count = item.count, count > 0 {
            let total = NSAttributedString(string: "\(count)", attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: Ink.soft])
            let size = total.size()
            total.draw(at: NSPoint(x: right - size.width, y: bounds.midY - size.height / 2))
            right -= size.width + 8
        }

        let left = item.cats.isEmpty ? 8 : Self.catInset + side + CGFloat(item.cats.count - 1) * side / 2 + 8
        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        NSAttributedString(string: item.title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: item.isUnread ? .semibold : item.count != nil ? .medium : .regular),
            .foregroundColor: isFaded ? Ink.soft : Ink.text,
            .paragraphStyle: truncating,
        ]).draw(in: NSRect(x: left, y: (bounds.height - 17) / 2, width: max(right - left, 0), height: 17))
    }
}
