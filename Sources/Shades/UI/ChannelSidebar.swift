import AppKit
import ShadesCore

struct ChannelSidebarItem: Equatable {
    enum Icon: Equatable {
        case activity
        case threads
        case kitten(KittenStatus)
        case shades
    }

    var place: ChannelPlace
    var title: String
    var icon: Icon
    var badge = 0
    var unread = 0
    var isUnread: Bool { unread > 0 }

    static func groups(in book: ChannelBook) -> [(heading: String?, items: [ChannelSidebarItem])] {
        let activity = ChannelSidebarItem(place: .activity, title: CatWords.activityTitle, icon: .activity, badge: book.waiting.count)
        let threads = ChannelSidebarItem(place: .threads, title: CatWords.threadsTitle, icon: .threads, unread: book.unreadThreads(in: .threads).count)
        let shades = ChannelSidebarItem(place: .channel(.shades), title: CatWords.shades, icon: .shades, unread: book.unreadThreads(in: .channel(.shades)).count)
        let kittens = book.statuses.filter { !$0.kitten.planned }.map { status in
            let id = ChannelID.of(status.kitten)
            return ChannelSidebarItem(place: .channel(id), title: book.name(of: id), icon: .kitten(status), badge: book.badge(of: id), unread: book.unreadThreads(in: .channel(id)).count)
        }
        return [(nil, [activity, threads]), (CatWords.kittensHeading, [shades] + kittens)]
    }

    static func places(in book: ChannelBook) -> [ChannelPlace] {
        groups(in: book).flatMap(\.items).map(\.place)
    }
}

final class ChannelSidebar: QuietView {
    static let width: CGFloat = 220
    private static let top: CGFloat = 38
    private static var rowHeight: CGFloat { MessagesInk.body + 17 }
    private static var headingHeight: CGFloat { MessagesInk.label + 21 }
    private static let footerHeight: CGFloat = 68

    var onSelect: ((ChannelPlace) -> Void)?
    var onMarkRead: ((ChannelPlace) -> Void)?
    var onMarkAllRead: (() -> Void)?
    var onShortcuts: (() -> Void)?
    var onSettings: (() -> Void)?
    var onDoNotDisturb: (() -> Void)?
    private(set) var rows: [ChannelSidebarRow] = []
    let shortcutsButton = QuietButton(CatWords.shortcutsButton, style: .text)
    let settingsButton = QuietButton(CatWords.settingsButton, style: .text)
    let quietButton = QuietButton(CatWords.doNotDisturb, style: .text)
    let quietOnButton = QuietButton(CatWords.doNotDisturbOn, style: .plain)

    var focus: String? {
        didSet {
            guard focus != oldValue else { return }
            focusLine.text = focus
            needsLayout = true
        }
    }
    let focusLine = FocusLine()

    private let scroll = QuietScrollView()
    private let list = QuietView()
    private var shownGroups: [[ChannelSidebarItem]] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        scroll.documentView = list
        addSubview(focusLine)
        addSubview(scroll)
        addSubview(shortcutsButton)
        addSubview(settingsButton)
        addSubview(quietButton)
        addSubview(quietOnButton)
        quietOnButton.isHidden = true
        quietButton.setAccessibilityRole(.checkBox)
        quietButton.setAccessibilityValue(0)
        quietOnButton.setAccessibilityRole(.checkBox)
        quietOnButton.setAccessibilityValue(1)
        quietButton.onPress = { [weak self] in self?.onDoNotDisturb?() }
        quietOnButton.onPress = { [weak self] in self?.onDoNotDisturb?() }
        shortcutsButton.onPress = { [weak self] in self?.onShortcuts?() }
        settingsButton.onPress = { [weak self] in self?.onSettings?() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func row(for place: ChannelPlace) -> ChannelSidebarRow? {
        rows.first { $0.item.place == place }
    }

    func show(_ book: ChannelBook, selection: ChannelPlace) {
        let groups = ChannelSidebarItem.groups(in: book)
        if groups.map(\.items) != shownGroups { rebuild(groups) }
        rows.forEach { $0.isSelected = $0.item.place == selection }
        quietButton.isHidden = book.waiting.doNotDisturb
        quietOnButton.isHidden = !book.waiting.doNotDisturb
    }

    func restyle() {
        shownGroups = []
        focusLine.needsDisplay = true
        needsLayout = true
        needsDisplay = true
    }

    func motionChanged() {
        rows.forEach { $0.motionChanged() }
    }

    private func rebuild(_ groups: [(heading: String?, items: [ChannelSidebarItem])]) {
        shownGroups = groups.map(\.items)
        list.subviews.forEach { $0.removeFromSuperview() }
        rows = []
        var y: CGFloat = 0
        let count = groups.reduce(0) { $0 + $1.items.count }
        let anyUnread = groups.contains { $0.items.contains(where: \.isUnread) }
        for group in groups {
            if let heading = group.heading {
                y += addHeading(heading, at: y)
            }
            for item in group.items {
                let row = ChannelSidebarRow(item: item, light: .drifting(rows.count, of: count))
                row.onPress = { [weak self] in self?.onSelect?(item.place) }
                row.onMarkRead = { [weak self] in self?.onMarkRead?(item.place) }
                if anyUnread { row.onMarkAllRead = { [weak self] in self?.onMarkAllRead?() } }
                row.frame = NSRect(x: 8, y: y, width: bounds.width - 16, height: Self.rowHeight)
                list.addSubview(row)
                rows.append(row)
                y += Self.rowHeight
            }
        }
        list.frame = NSRect(x: 0, y: 0, width: bounds.width, height: y + 12)
    }

    private func addHeading(_ text: String, at y: CGFloat) -> CGFloat {
        let label = NSTextField(labelWithAttributedString: MessagesInk.label(text))
        label.sizeToFit()
        label.frame.origin = NSPoint(x: 16, y: y + Self.headingHeight - label.frame.height - 5)
        list.addSubview(label)
        return Self.headingHeight
    }

    override func layout() {
        super.layout()
        let focusWidth = max(bounds.width - 32, 0)
        let focusHeight = focus == nil ? 0 : focusLine.height(for: focusWidth)
        focusLine.isHidden = focus == nil
        focusLine.frame = NSRect(x: 16, y: Self.top, width: focusWidth, height: focusHeight)
        let listTop = Self.top + (focusHeight > 0 ? focusHeight + 10 : 0)
        scroll.frame = NSRect(x: 0, y: listTop, width: bounds.width - 1, height: max(bounds.height - listTop - Self.footerHeight, 0))
        list.frame.size.width = bounds.width
        rows.forEach { $0.frame.size.width = bounds.width - 16 }
        let top = bounds.height - Self.footerHeight + 6
        quietButton.frame.origin = NSPoint(x: 10, y: top)
        quietOnButton.frame.origin = NSPoint(x: 10, y: top)
        shortcutsButton.frame.origin = NSPoint(x: 10, y: top + quietButton.frame.height + 4)
        settingsButton.frame.origin = NSPoint(x: shortcutsButton.frame.maxX + 4, y: shortcutsButton.frame.minY)
    }

    override func draw(_ dirtyRect: NSRect) {
        MessagesInk.sidebar.setFill()
        bounds.fill(using: .sourceOver)
    }
}

final class FocusLine: QuietView {
    private static let mostLines = 3

    var text: String? {
        didSet {
            setAccessibilityElement(text != nil)
            setAccessibilityRole(.staticText)
            setAccessibilityLabel(text)
            needsDisplay = true
        }
    }

    private var words: NSAttributedString {
        let wrapping = NSMutableParagraphStyle()
        wrapping.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: text ?? "", attributes: [
            .font: MessagesInk.font(ofSize: MessagesInk.meta + 1, weight: .medium),
            .foregroundColor: MessagesInk.link,
            .paragraphStyle: wrapping,
        ])
    }

    func height(for width: CGFloat) -> CGFloat {
        let font = MessagesInk.font(ofSize: MessagesInk.meta + 1, weight: .medium)
        let most = ceil(NSLayoutManager().defaultLineHeight(for: font) * CGFloat(Self.mostLines))
        let needed = words.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading]).height
        return min(ceil(needed), most)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        words.draw(with: bounds, options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine])
    }
}

final class ChannelSidebarRow: ChannelRowView {
    private static let tileSide: CGFloat = 22
    private static let tileInset: CGFloat = 6
    private static let catSide: CGFloat = 16
    private static let dotSide: CGFloat = 8

    let item: ChannelSidebarItem
    private let light: Opal.Light
    var onPress: (() -> Void)?
    var onMarkRead: (() -> Void)?
    var onMarkAllRead: (() -> Void)?
    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            setAccessibilityValue(isSelected ? 1 : 0)
            NSAccessibility.post(element: self, notification: .valueChanged)
            needsDisplay = true
            dot?.ground = ground
        }
    }
    private let cat: SidebarCat?
    private let dot: SidebarDot?

    init(item: ChannelSidebarItem, light: Opal.Light = .drifting(0, of: 1)) {
        self.item = item
        self.light = light
        if case .kitten(let status) = item.icon {
            cat = SidebarCat(status: status, jacket: ChannelSpeakerLook.color(of: status.kitten))
            dot = item.badge == 0 ? status.state.dotColor.map { SidebarDot(color: $0, ground: MessagesInk.sidebar) } : nil
        } else {
            cat = nil
            dot = nil
        }
        super.init(frame: .zero)
        [cat, dot].compactMap { $0 }.forEach(addSubview)
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityValue(0)
        setAccessibilityLabel(accessibilityWords)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private var accessibilityWords: String {
        var words = [item.title]
        if case .kitten(let status) = item.icon { words.append(CatWords.kittenState(status.state)) }
        if item.badge > 0 { words.append("\(item.badge) waiting") }
        if item.isUnread { words.append(CatWords.unread(item.unread)) }
        return words.joined(separator: ", ")
    }

    override var isPressable: Bool { true }
    override func press() { onPress?() }

    override var actions: [(name: String, run: () -> Void)] {
        let all: [(name: String, run: (() -> Void)?)] = [
            (CatWords.markRead, item.isUnread ? onMarkRead : nil),
            (CatWords.markAllRead, onMarkAllRead),
        ]
        return all.compactMap { action in action.run.map { (action.name, $0) } }
    }

    var isLive: Bool { cat?.moves ?? false }

    func motionChanged() {
        cat?.needsDisplay = true
    }

    private var ground: NSColor { isSelected ? MessagesInk.press : hovering ? MessagesInk.hover : MessagesInk.sidebar }

    private var tile: NSRect {
        NSRect(x: Self.tileInset, y: ((bounds.height - Self.tileSide) / 2).rounded(), width: Self.tileSide, height: Self.tileSide)
    }

    override func hoverChanged() {
        super.hoverChanged()
        dot?.ground = ground
    }

    override func layout() {
        super.layout()
        let tile = tile
        cat?.frame = tile.insetBy(dx: (Self.tileSide - Self.catSide) / 2, dy: (Self.tileSide - Self.catSide) / 2)
        dot?.frame = NSRect(x: tile.maxX - Self.dotSide + 2, y: tile.maxY - Self.dotSide + 2, width: Self.dotSide, height: Self.dotSide).insetBy(dx: -2, dy: -2)
    }

    override func draw(_ dirtyRect: NSRect) {
        if isSelected || hovering {
            ground.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: Opal.Corner.control, yRadius: Opal.Corner.control).fill()
        }

        let tile = tile
        let cat = tile.insetBy(dx: (Self.tileSide - Self.catSide) / 2, dy: (Self.tileSide - Self.catSide) / 2)
        switch item.icon {
        case .kitten(let status):
            Opal.tile(in: tile, light: ChannelSpeakerLook.color(of: status.kitten).map(Opal.Light.of) ?? .shades)
        case .shades:
            Opal.tile(in: tile, light: .shades)
            CatStamp.draw(CatPose(frame: .sit), jacket: nil, in: cat, on: self)
        case .activity:
            drawGlyph("bell.fill", on: tile)
        case .threads:
            drawGlyph("bubble.left.and.bubble.right.fill", on: tile)
        }

        let lit = item.isUnread || item.badge > 0
        var right = bounds.width - 8
        if item.badge > 0 {
            let count = NSAttributedString(string: "\(item.badge)", attributes: [.font: MessagesInk.font(ofSize: MessagesInk.meta, weight: .semibold, tabular: true), .foregroundColor: MessagesInk.onBadge])
            let size = count.size()
            let width = max(ceil(size.width) + 10, 18)
            let pill = NSRect(x: right - width, y: (bounds.midY - 9).rounded(), width: width, height: 18)
            MessagesInk.badge.setFill()
            NSBezierPath(roundedRect: pill, xRadius: 9, yRadius: 9).fill()
            count.draw(at: NSPoint(x: pill.midX - size.width / 2, y: pill.midY - size.height / 2))
            right = pill.minX - 6
        } else if item.isUnread {
            let count = NSAttributedString(string: "\(item.unread)", attributes: [.font: MessagesInk.font(ofSize: MessagesInk.meta, tabular: true), .foregroundColor: MessagesInk.soft])
            let size = count.size()
            count.draw(at: NSPoint(x: right - ceil(size.width) - 4, y: (bounds.midY - size.height / 2).rounded()))
            right -= ceil(size.width) + 10
        }

        let left = tile.maxX + 9
        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        let name = NSAttributedString(string: item.title, attributes: [
            .font: MessagesInk.font(ofSize: MessagesInk.body, weight: lit ? .semibold : isSelected ? .medium : .regular),
            .foregroundColor: lit || isSelected ? MessagesInk.strong : MessagesInk.soft,
            .paragraphStyle: truncating,
        ])
        let height = ceil(name.size().height)
        name.draw(in: NSRect(x: left, y: ((bounds.height - height) / 2).rounded(), width: max(right - left, 0), height: height))
    }

    private func drawGlyph(_ name: String, on tile: NSRect) {
        Opal.tile(in: tile, light: light)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
        else { return }
        let white = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            MessagesInk.strong.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        let size = symbol.size
        white.draw(in: NSRect(x: tile.midX - size.width / 2, y: tile.midY - size.height / 2, width: size.width, height: size.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}
