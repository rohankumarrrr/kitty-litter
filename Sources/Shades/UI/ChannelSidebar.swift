import AppKit
import ShadesCore

/// One line of the sidebar, as a value, so it's only rebuilt when something really changed.
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
    /// What's waiting on you there, as Slack counts mentions.
    var badge = 0
    var isUnread = false

    static func groups(in book: ChannelBook) -> [(heading: String?, items: [ChannelSidebarItem])] {
        let activity = ChannelSidebarItem(place: .activity, title: CatWords.activityTitle, icon: .activity, badge: book.waiting.count)
        let threads = ChannelSidebarItem(place: .threads, title: CatWords.threadsTitle, icon: .threads, isUnread: book.yours.contains { book.unreadThreads.contains($0.id) })
        let shades = ChannelSidebarItem(place: .channel(.shades), title: CatWords.shades, icon: .shades, isUnread: book.isUnread(.shades))
        // A kitten that's only planned isn't there until it's set up.
        let kittens = book.statuses.filter { !$0.kitten.planned }.map { status in
            let id = ChannelID.of(status.kitten)
            return ChannelSidebarItem(place: .channel(id), title: book.name(of: id), icon: .kitten(status), badge: book.badge(of: id), isUnread: book.isUnread(id))
        }
        return [(nil, [activity, threads]), (CatWords.kittensHeading, [shades] + kittens)]
    }

    /// Every place, top to bottom, the way the sidebar lists them.
    static func places(in book: ChannelBook) -> [ChannelPlace] {
        groups(in: book).flatMap(\.items).map(\.place)
    }
}

/// The left side of the window, flush on its chrome: Activity and Threads, then the cat and each kitten, as Slack lists
/// its channels.
final class ChannelSidebar: QuietView {
    /// How wide it is until you drag its edge.
    static let width: CGFloat = 220
    /// Leaves room for the window's buttons.
    private static let top: CGFloat = 38
    private static var rowHeight: CGFloat { MessagesInk.body + 17 }
    private static var headingHeight: CGFloat { MessagesInk.label + 21 }
    private static let footerHeight: CGFloat = 68

    var onSelect: ((ChannelPlace) -> Void)?
    var onShortcuts: (() -> Void)?
    var onSettings: (() -> Void)?
    var onDoNotDisturb: (() -> Void)?
    private(set) var rows: [ChannelSidebarRow] = []
    let shortcutsButton = QuietButton(CatWords.shortcutsButton, style: .text)
    let settingsButton = QuietButton(CatWords.settingsButton, style: .text)
    /// One switch, which says so when it's on.
    let quietButton = QuietButton(CatWords.doNotDisturb, style: .text)
    let quietOnButton = QuietButton(CatWords.doNotDisturbOn, style: .plain)

    /// What comes first right now, from `FOCUS.md`, over the places, or `nil` with no focus.
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
    private var tick = 0

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
        // Two buttons look like one switch, so VoiceOver hears a checkbox that's ticked or not.
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

    /// The next `show` makes every row again, in the colours there are now.
    func restyle() {
        shownGroups = []
        focusLine.needsDisplay = true
        needsLayout = true
        needsDisplay = true
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
        let count = groups.reduce(0) { $0 + $1.items.count }
        for group in groups {
            if let heading = group.heading {
                y += addHeading(heading, at: y)
            }
            for item in group.items {
                let row = ChannelSidebarRow(item: item, light: .drifting(rows.count, of: count))
                row.onPress = { [weak self] in self?.onSelect?(item.place) }
                row.update(tick: tick)
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
        // You can drag it wider or narrower, and the rows follow.
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

/// The focus as written, quiet and in lilac, Opal's colour for what's now, on up to three lines. It has no tooltip,
/// since a tooltip is a window of its own, and screen shares leave out only this one.
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

/// A place, with its Rimlight tile: a kitten's cat lit in its colour, the cat's in its own hue, and a glyph for the rest.
final class ChannelSidebarRow: ChannelRowView {
    private static let tileSide: CGFloat = 22
    private static let tileInset: CGFloat = 6
    /// The cat a point to each of its pixels, so it stays crisp.
    private static let catSide: CGFloat = 16
    private static let dotSide: CGFloat = 8

    let item: ChannelSidebarItem
    /// A tile's light when it isn't a kitten's or the cat's, drifting down the list.
    private let light: Opal.Light
    var onPress: (() -> Void)?
    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            setAccessibilityValue(isSelected ? 1 : 0)
            NSAccessibility.post(element: self, notification: .valueChanged)
            needsDisplay = true
        }
    }
    private var tick = 0

    init(item: ChannelSidebarItem, light: Opal.Light = .drifting(0, of: 1)) {
        self.item = item
        self.light = light
        super.init(frame: .zero)
        setAccessibilityElement(true)
        // One place shows at a time, as with tabs, so VoiceOver says which is selected.
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
        if item.isUnread { words.append("unread") }
        return words.joined(separator: ", ")
    }

    override var isPressable: Bool { true }
    override func press() { onPress?() }

    /// Only a kitten that's working or needs you moves, so nothing else has to redraw. Under Reduce Motion, none do.
    var isLive: Bool {
        guard !Motion.isReduced, case .kitten(let status) = item.icon else { return false }
        return status.state.dotColor != nil
    }

    func update(tick: Int) {
        self.tick = tick
        if isLive { needsDisplay = true }
    }

    /// What the row sits on, which the status dot's ring matches.
    private var ground: NSColor { isSelected ? MessagesInk.press : hovering ? MessagesInk.hover : MessagesInk.sidebar }

    override func draw(_ dirtyRect: NSRect) {
        if isSelected || hovering {
            ground.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: Opal.Corner.control, yRadius: Opal.Corner.control).fill()
        }

        let side = Self.tileSide
        let tile = NSRect(x: Self.tileInset, y: ((bounds.height - side) / 2).rounded(), width: side, height: side)
        let cat = tile.insetBy(dx: (side - Self.catSide) / 2, dy: (side - Self.catSide) / 2)
        switch item.icon {
        case .kitten(let status):
            let color = ChannelSpeakerLook.color(of: status.kitten)
            Opal.tile(in: tile, light: color.map(Opal.Light.of) ?? .shades)
            CatStamp.draw(status.pose(tick: isLive ? tick : 0), jacket: color, in: cat, on: self)
            // A count says it needs you in the same rose, so the dot shows only without one. The pose and the words
            // VoiceOver hears carry the state, so the dot is decoration.
            if item.badge == 0, let dot = status.state.dotColor { drawDot(dot, on: tile) }
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

    /// A status dot on the tile's corner, ringed in what the row sits on, as Slack marks who's around.
    private func drawDot(_ color: NSColor, on tile: NSRect) {
        let side = Self.dotSide
        let dot = NSRect(x: tile.maxX - side + 2, y: tile.maxY - side + 2, width: side, height: side)
        ground.setFill()
        NSBezierPath(ovalIn: dot.insetBy(dx: -2, dy: -2)).fill()
        color.setFill()
        NSBezierPath(ovalIn: dot).fill()
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
