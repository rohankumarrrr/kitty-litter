import AppKit
import ShadesCore

/// One line of the sidebar, as a value, so it's only rebuilt when something really changed.
struct ChannelSidebarItem: Equatable {
    enum Icon: Equatable {
        case activity
        case threads
        case general
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
        let general = ChannelSidebarItem(place: .channel(.general), title: book.name(of: .general), icon: .general, isUnread: book.isUnread(.general))
        let kittens = book.statuses.map { status in
            let id = ChannelID.of(status.kitten)
            return ChannelSidebarItem(place: .channel(id), title: book.name(of: id), icon: .kitten(status), badge: book.badge(of: id), isUnread: book.isUnread(id))
        }
        let shades = ChannelSidebarItem(place: .channel(.shades), title: CatWords.shades, icon: .shades)
        return [(nil, [activity, threads]), (CatWords.channelsHeading, [general] + kittens), (CatWords.directMessages, [shades])]
    }

    /// Every place, top to bottom, the way the sidebar lists them.
    static func places(in book: ChannelBook) -> [ChannelPlace] {
        groups(in: book).flatMap(\.items).map(\.place)
    }
}

/// The left side of the window: Activity and Threads, then #general and a channel for each kitten, then the DM.
final class ChannelSidebar: QuietView {
    static let width: CGFloat = 220
    /// Leaves room for the window's buttons.
    private static let top: CGFloat = 38
    private static let rowHeight: CGFloat = 30
    private static let headingHeight: CGFloat = 32
    private static let footerHeight: CGFloat = 68

    var onSelect: ((ChannelPlace) -> Void)?
    /// Theme was pressed, so its menu can open under it.
    var onTheme: ((NSView) -> Void)?
    var onShortcuts: (() -> Void)?
    var onSettings: (() -> Void)?
    var onDoNotDisturb: (() -> Void)?
    private(set) var rows: [ChannelSidebarRow] = []
    let themeButton = QuietButton(CatWords.themeButton, style: .text)
    let shortcutsButton = QuietButton(CatWords.shortcutsButton, style: .text)
    let settingsButton = QuietButton(CatWords.settingsButton, style: .text)
    /// One switch, which says so when it's on.
    let quietButton = QuietButton(CatWords.doNotDisturb, style: .text)
    let quietOnButton = QuietButton(CatWords.doNotDisturbOn, style: .plain)

    private let scroll = QuietScrollView()
    private let list = QuietView()
    private var shownGroups: [[ChannelSidebarItem]] = []
    private var tick = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        scroll.documentView = list
        addSubview(scroll)
        addSubview(themeButton)
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
        themeButton.onPress = { [weak self] in
            guard let self else { return }
            self.onTheme?(self.themeButton)
        }
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
        for group in groups {
            if let heading = group.heading {
                y += addHeading(heading, at: y)
            }
            for item in group.items {
                let row = ChannelSidebarRow(item: item)
                row.onPress = { [weak self] in self?.onSelect?(item.place) }
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
            .font: MessagesInk.font(ofSize: 10, weight: .semibold),
            .foregroundColor: MessagesInk.soft,
            .kern: 0.5,
        ]))
        label.sizeToFit()
        label.frame.origin = NSPoint(x: 16, y: y + Self.headingHeight - label.frame.height - 5)
        list.addSubview(label)
        return Self.headingHeight
    }

    override func layout() {
        super.layout()
        scroll.frame = NSRect(x: 0, y: Self.top, width: bounds.width - 1, height: max(bounds.height - Self.top - Self.footerHeight, 0))
        let top = bounds.height - Self.footerHeight + 6
        quietButton.frame.origin = NSPoint(x: 10, y: top)
        quietOnButton.frame.origin = NSPoint(x: 10, y: top)
        themeButton.frame.origin = NSPoint(x: 10, y: top + quietButton.frame.height + 4)
        shortcutsButton.frame.origin = NSPoint(x: themeButton.frame.maxX + 4, y: themeButton.frame.minY)
        settingsButton.frame.origin = NSPoint(x: shortcutsButton.frame.maxX + 4, y: themeButton.frame.minY)
    }

    override func draw(_ dirtyRect: NSRect) {
        MessagesInk.sidebar.setFill()
        bounds.fill(using: .sourceOver)
        MessagesInk.line.setFill()
        NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height).fill(using: .sourceOver)
    }
}

final class ChannelSidebarRow: ChannelRowView {
    private static let iconSide: CGFloat = 22
    private static let iconInset: CGFloat = 6

    let item: ChannelSidebarItem
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

    init(item: ChannelSidebarItem) {
        self.item = item
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

    private var isFaded: Bool {
        guard case .kitten(let status) = item.icon else { return false }
        return status.state == .notSetUp
    }

    func update(tick: Int) {
        self.tick = tick
        if isLive { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        if isSelected || hovering {
            (isSelected ? MessagesInk.press : MessagesInk.hover).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
        }

        let side = Self.iconSide
        let frame = NSRect(x: Self.iconInset, y: (bounds.height - side) / 2, width: side, height: side)
        switch item.icon {
        case .kitten(let status):
            CatStamp.draw(status.pose(tick: isLive ? tick : 0), jacket: ChannelSpeakerLook.color(of: status.kitten), in: frame, on: self, fraction: isFaded ? 0.4 : 1)
        case .shades:
            CatStamp.draw(CatPose(frame: .sit), jacket: nil, in: frame, on: self)
        case .activity:
            drawSymbol("bell", in: frame)
        case .threads:
            drawSymbol("bubble.left.and.bubble.right", in: frame)
        case .general:
            drawSymbol("number", in: frame)
        }

        var right = bounds.width - 10
        if case .kitten(let status) = item.icon, let dot = status.state.dotColor {
            dot.setFill()
            NSBezierPath(rect: NSRect(x: right - 8, y: bounds.midY - 4, width: 8, height: 8)).fill()
            right -= 16
        }
        if item.badge > 0 {
            let count = NSAttributedString(string: "\(item.badge)", attributes: [.font: MessagesInk.font(ofSize: 11, weight: .bold, tabular: true), .foregroundColor: MessagesInk.onBadge])
            let size = count.size()
            let pill = NSRect(x: right - max(size.width + 10, 18), y: bounds.midY - 9, width: max(size.width + 10, 18), height: 18)
            MessagesInk.badge.setFill()
            NSBezierPath(roundedRect: pill, xRadius: 9, yRadius: 9).fill()
            count.draw(at: NSPoint(x: pill.midX - size.width / 2, y: pill.midY - size.height / 2))
            right = pill.minX - 6
        }

        let left = Self.iconInset + side + 8
        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        NSAttributedString(string: item.title, attributes: [
            .font: MessagesInk.font(ofSize: 13, weight: item.isUnread || item.badge > 0 ? .bold : .regular),
            .foregroundColor: isFaded ? MessagesInk.soft : item.isUnread || item.badge > 0 || isSelected ? MessagesInk.text : MessagesInk.soft,
            .paragraphStyle: truncating,
        ]).draw(in: NSRect(x: left, y: (bounds.height - 17) / 2, width: max(right - left, 0), height: 17))
    }

    private func drawSymbol(_ name: String, in frame: NSRect) {
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .medium))
        else { return }
        let tinted = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            (self.item.isUnread || self.item.badge > 0 || self.isSelected ? MessagesInk.text : MessagesInk.soft).set()
            rect.fill(using: .sourceAtop)
            return true
        }
        let size = symbol.size
        tinted.draw(in: NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}
