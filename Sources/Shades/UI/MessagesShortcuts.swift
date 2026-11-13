import AppKit
import ShadesCore

/// The keys Messages answers to while it has the keyboard, taken from T3 Code's, the Claude app's and Slack's own.
/// None of them is a global hotkey, so they do nothing while another app has the keyboard.
enum MessagesShortcut: Hashable {
    /// ⌘⇧[ and ⌘⇧], the thread above or below in the place you're looking at.
    case previousThread, nextThread
    /// ⌥↑ and ⌥↓, the place above or below in the sidebar.
    case previousPlace, nextPlace
    /// ⌥⇧↑ and ⌥⇧↓, the channel above or below that has something new.
    case previousUnread, nextUnread
    /// ⌘[ and ⌘], through the places and threads you've looked at.
    case back, forward
    /// ⌘1 to ⌘9, a row of the sidebar.
    case place(Int)
    /// ⌘K, a box for jumping to a place or thread by name.
    case jump
    /// ⌘F, the same box finding a message by its words.
    case search
    /// Esc, which closes the jump box, the shortcuts, or a thread's pane.
    case escape
    /// ⌘⇧T and ⌘⇧M.
    case threads, activity
    /// ⌘N, the box of the place you're on.
    case compose
    /// ⌘B, which hides the sidebar or shows it again, as in T3 Code.
    case toggleSidebar
    /// ⌘W.
    case close
    /// ⌘/, every shortcut.
    case cheatsheet
    /// ⌘,, every setting, as in any Mac app.
    case settings

    /// Physical keys, so they're where they are whatever the layout, as in T3 Code and Slack.
    private enum Key {
        static let leftBracket: UInt16 = 33
        static let rightBracket: UInt16 = 30
        static let up: UInt16 = 126
        static let down: UInt16 = 125
        static let escape: UInt16 = 53
        static let digits: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]
    }

    /// What a key means in Messages, or `nil` for one it leaves alone. Letters go by what the key types.
    init?(keyCode: UInt16, characters: String?, modifiers: NSEvent.ModifierFlags) {
        let held = modifiers.intersection([.command, .shift, .option, .control])
        let typed = characters?.lowercased() ?? ""
        switch held {
        case [.command, .shift]:
            switch (keyCode, typed) {
            case (Key.leftBracket, _): self = .previousThread
            case (Key.rightBracket, _): self = .nextThread
            case (_, "t"): self = .threads
            case (_, "m"): self = .activity
            default: return nil
            }
        case [.command]:
            if let number = Key.digits[keyCode] {
                self = .place(number)
                return
            }
            switch (keyCode, typed) {
            case (Key.leftBracket, _): self = .back
            case (Key.rightBracket, _): self = .forward
            case (_, "k"): self = .jump
            case (_, "f"): self = .search
            case (_, "n"): self = .compose
            case (_, "b"): self = .toggleSidebar
            case (_, "w"): self = .close
            case (_, "/"): self = .cheatsheet
            case (_, ","): self = .settings
            default: return nil
            }
        case [.option]:
            switch keyCode {
            case Key.up: self = .previousPlace
            case Key.down: self = .nextPlace
            default: return nil
            }
        case [.option, .shift]:
            switch keyCode {
            case Key.up: self = .previousUnread
            case Key.down: self = .nextUnread
            default: return nil
            }
        case []:
            guard keyCode == Key.escape else { return nil }
            self = .escape
        default:
            return nil
        }
    }

    /// One a text box would want for itself while it has words in it: ⌥ and the arrows move by paragraph there.
    var movesInText: Bool {
        [.previousPlace, .nextPlace, .previousUnread, .nextUnread].contains(self)
    }
}

/// Somewhere ⌘K can jump to: a place in the sidebar, or a thread. Or a message ⌘F found, which the pane scrolls to.
struct JumpItem: Equatable {
    var title: String
    /// Where a thread is, such as its channel.
    var detail: String?
    var selection: ChannelSelection
    var found: FoundMessage?
}

extension JumpItem {
    static let limit = 8

    /// Who said it, then where and when, with its words under them. A phone names some threads its own way.
    init(_ found: FoundMessage, in book: ChannelBook, now: Date, threadTitle: ((String) -> String)? = nil) {
        let channel = (found.selection.thread.flatMap(book.home(ofThread:)) ?? found.selection.channelID).map(book.title(of:))
        let thread = found.selection.thread.map(threadTitle ?? book.title(ofThread:))
        let place = [thread, channel].compactMap { $0 }.filter { !$0.isEmpty }
        self.init(title: book.name(of: found.message.speaker), detail: (place + [CatWords.age(of: found.message.at, now: now)]).joined(separator: " · "), selection: found.selection, found: found)
    }

    /// Every place, then every thread you can open, newest first, worked out from what's in memory.
    static func all(in book: ChannelBook) -> [JumpItem] {
        let places = ChannelSidebarItem.groups(in: book).flatMap(\.items).map { item in
            JumpItem(title: item.place.channelID.map(book.title) ?? item.title, detail: nil, selection: ChannelSelection(item.place))
        }
        let threads = book.threads.values
            .filter { !$0.isStarting }
            .sorted { ($0.latest.at, $0.id) > ($1.latest.at, $1.id) }
            .map { thread in
                JumpItem(title: book.title(ofThread: thread.id), detail: book.title(of: thread.home), selection: .thread(thread.id, in: .channel(thread.home)))
            }
        return places + threads
    }

    /// What's named by every word you've typed, those whose name starts with it first. With nothing typed, the places
    /// and the newest threads.
    static func matching(_ query: String, in book: ChannelBook) -> [JumpItem] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        let all = all(in: book)
        guard !words.isEmpty else { return Array(all.prefix(limit)) }
        let typed = query.trimmingCharacters(in: .whitespaces).lowercased()
        let found = all.enumerated().compactMap { index, item -> (rank: Int, index: Int, item: JumpItem)? in
            let title = item.title.lowercased()
            let named = title + " " + (item.detail?.lowercased() ?? "")
            guard words.allSatisfy(named.contains) else { return nil }
            let bare = title.hasPrefix("#") ? String(title.dropFirst()) : title
            let rank = bare.hasPrefix(typed) || title.hasPrefix(typed) ? 0 : title.split(separator: " ").contains { $0.hasPrefix(words[0]) } ? 1 : 2
            return (rank, index, item)
        }
        return found.sorted { ($0.rank, $0.index) < ($1.rank, $1.index) }.prefix(limit).map(\.item)
    }
}

/// ⌘K: a box over the window that jumps to a place or thread by name, and ⌘F, the same box finding a message by its
/// words. It's a view inside Messages, not a window of its own, so it can't make Shades the active app. The arrows
/// move, Return opens and Esc closes.
final class JumpBoxView: QuietView, NSTextFieldDelegate {
    enum Mode {
        case jump, search
    }

    private static let width: CGFloat = 520
    private static var fieldHeight: CGFloat { MessagesInk.title + 32 }
    private static let footerHeight: CGFloat = 26
    /// How long typing pauses before T3 is asked, so it's asked about what you meant rather than every letter.
    private static let askAfter: TimeInterval = 0.35

    var onOpen: ((JumpItem) -> Void)?
    var onClose: (() -> Void)?
    /// Words for T3 to look for, once typing pauses in Search.
    var onFind: ((String) -> Void)?
    let field = NSTextField()
    private(set) var mode = Mode.jump
    private(set) var items: [JumpItem] = []
    private(set) var highlighted = 0
    /// Search found more than there's room for.
    private(set) var hasMore = false
    private var book: ChannelBook?
    private var asking: Timer?
    private let plainWords = PlainWords()

    private var rowHeight: CGFloat { mode == .search ? MessagesInk.title + MessagesInk.body + 27 : MessagesInk.title + 26 }

    override init(frame: NSRect) {
        super.init(frame: frame)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = MessagesInk.font(ofSize: MessagesInk.title + 2)
        field.delegate = self
        addSubview(field)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(CatWords.jumpTitle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var query: String {
        get { field.stringValue }
        set {
            field.stringValue = newValue
            refilter()
            askSoon()
        }
    }

    /// Opens it as ⌘K's or ⌘F's, with whatever's typed in it.
    func show(_ book: ChannelBook, mode: Mode = .jump) {
        self.book = book
        self.mode = mode
        field.font = MessagesInk.font(ofSize: MessagesInk.title + 2)
        field.textColor = MessagesInk.text
        let placeholder = mode == .search ? CatWords.searchPlaceholder : CatWords.jumpPlaceholder
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [.foregroundColor: MessagesInk.soft, .font: MessagesInk.font(ofSize: MessagesInk.title + 2)])
        setAccessibilityLabel(mode == .search ? CatWords.searchTitle : CatWords.jumpTitle)
        refilter()
        askSoon()
    }

    /// Messages shows a new book, whose words Search reads ahead, open or not, so the first search seldom waits.
    func readAhead(_ book: ChannelBook) {
        plainWords.readAhead(book)
    }

    /// What Messages has read changed while it's open, such as the threads T3 found. What's highlighted stays.
    func update(_ book: ChannelBook) {
        let current = items.indices.contains(highlighted) ? items[highlighted] : nil
        self.book = book
        refilter()
        if let current, let index = items.firstIndex(where: { $0.selection == current.selection && $0.found?.message.id == current.found?.message.id }) {
            highlighted = index
        }
    }

    private func refilter() {
        guard let book else { return }
        switch mode {
        case .jump:
            items = JumpItem.matching(query, in: book)
            hasMore = false
        case .search:
            let now = Date()
            let (found, more) = MessageSearch.find(query, in: book, limit: searchLimit, reading: plainWords)
            items = found.map { JumpItem($0, in: book, now: now) }
            hasMore = more
        }
        highlighted = 0
        needsLayout = true
        needsDisplay = true
    }

    /// As many as fit over the window, up to ⌘K's eight.
    private var searchLimit: Int {
        min(max(Int((bounds.height - 160) / rowHeight), 3), JumpItem.limit)
    }

    /// Search asks T3 once typing pauses, for threads Messages hasn't read. No words asks it to stop looking.
    private func askSoon() {
        asking?.invalidate()
        asking = nil
        guard mode == .search else { return }
        let words = query
        let timer = Timer(timeInterval: Self.askAfter, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isHidden else { return }
                self.onFind?(words)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        asking = timer
    }

    /// Under the row when there's nothing to show: what to type, that T3 is still looking, or that nothing has it.
    private var nothing: String {
        guard mode == .search else { return CatWords.jumpNothing }
        if MessageSearch.words(in: query).isEmpty { return CatWords.searchHint }
        return book?.searchingT3 != nil ? CatWords.searchingT3 : CatWords.searchNothing
    }

    /// Under Search's messages: that T3 is still looking, or that there are more than fit.
    private var footer: String? {
        guard mode == .search, !items.isEmpty else { return nil }
        if book?.searchingT3 != nil { return CatWords.searchingT3 }
        return hasMore ? CatWords.searchMore(items.count) : nil
    }

    func move(by step: Int) {
        guard !items.isEmpty else { return }
        highlighted = min(max(highlighted + step, 0), items.count - 1)
        needsDisplay = true
    }

    func open() {
        guard items.indices.contains(highlighted) else { return NSSound.beep() }
        onOpen?(items[highlighted])
    }

    private var card: NSRect {
        let width = min(Self.width, bounds.width - 40)
        let height = Self.fieldHeight + CGFloat(max(items.count, 1)) * rowHeight + 12 + (footer == nil ? 0 : Self.footerHeight)
        return NSRect(x: (bounds.width - width) / 2, y: 70, width: width, height: height)
    }

    /// Room before the field for its magnifying glass, as Spotlight has.
    private static let glassRoom: CGFloat = 26

    override func layout() {
        super.layout()
        let card = card
        field.frame = NSRect(x: card.minX + 16 + Self.glassRoom, y: card.minY + 12, width: card.width - 32 - Self.glassRoom, height: MessagesInk.title + 10)
    }

    func controlTextDidChange(_ notification: Notification) {
        refilter()
        askSoon()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveUp(_:)): move(by: -1)
        case #selector(NSResponder.moveDown(_:)): move(by: 1)
        case #selector(NSResponder.insertNewline(_:)): open()
        case #selector(NSResponder.cancelOperation(_:)): onClose?()
        default: return false
        }
        return true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let card = card
        guard card.contains(point) else { return onClose?() ?? () }
        let row = Int((point.y - card.minY - Self.fieldHeight) / rowHeight)
        guard point.y > card.minY + Self.fieldHeight, items.indices.contains(row) else { return }
        highlighted = row
        open()
    }

    override func draw(_ dirtyRect: NSRect) {
        MessagesInk.sidebar.withAlphaComponent(0.55).setFill()
        bounds.fill(using: .sourceOver)
        let card = card
        Opal.glass(NSBezierPath(roundedRect: card, xRadius: Opal.Corner.popover, yRadius: Opal.Corner.popover))
        MessagesInk.line.setFill()
        NSRect(x: card.minX, y: card.minY + Self.fieldHeight, width: card.width, height: 1).fill()
        if let glass = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: MessagesInk.title, weight: .medium)) {
            let tinted = NSImage(size: glass.size, flipped: false) { rect in
                glass.draw(in: rect)
                MessagesInk.soft.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: card.minX + 18, y: field.frame.midY - glass.size.height / 2, width: glass.size.width, height: glass.size.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }

        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        guard !items.isEmpty else {
            NSAttributedString(string: nothing, attributes: [.font: MessagesInk.font(ofSize: MessagesInk.body), .foregroundColor: MessagesInk.soft])
                .draw(at: NSPoint(x: card.minX + 16, y: card.minY + Self.fieldHeight + 11))
            return
        }
        for (index, item) in items.enumerated() {
            let row = NSRect(x: card.minX + 6, y: card.minY + Self.fieldHeight + 6 + CGFloat(index) * rowHeight, width: card.width - 12, height: rowHeight - 4)
            if index == highlighted {
                MessagesInk.press.setFill()
                NSBezierPath(roundedRect: row, xRadius: Opal.Corner.control, yRadius: Opal.Corner.control).fill()
            }
            let line = NSMutableAttributedString(string: item.title, attributes: [.font: MessagesInk.font(ofSize: MessagesInk.title, weight: .medium), .foregroundColor: MessagesInk.text])
            if let detail = item.detail {
                line.append(NSAttributedString(string: "   \(detail)", attributes: [.font: MessagesInk.font(ofSize: MessagesInk.meta + 1), .foregroundColor: MessagesInk.soft]))
            }
            line.addAttribute(.paragraphStyle, value: truncating, range: NSRange(location: 0, length: line.length))
            let lineHeight = MessagesInk.title + 4
            guard let found = item.found else {
                line.draw(in: NSRect(x: row.minX + 10, y: row.midY - lineHeight / 2, width: row.width - 20, height: lineHeight))
                continue
            }
            line.draw(in: NSRect(x: row.minX + 10, y: row.minY + 7, width: row.width - 20, height: lineHeight))
            let words = NSMutableAttributedString(string: found.snippet, attributes: [.font: MessagesInk.font(ofSize: MessagesInk.body), .foregroundColor: MessagesInk.soft, .paragraphStyle: truncating])
            for mark in found.marks where NSMaxRange(mark) <= words.length {
                words.addAttributes([.font: MessagesInk.font(ofSize: MessagesInk.body, weight: .semibold), .foregroundColor: MessagesInk.text], range: mark)
            }
            words.draw(in: NSRect(x: row.minX + 10, y: row.minY + 7 + lineHeight + 2, width: row.width - 20, height: MessagesInk.body + 5))
        }
        if let footer {
            NSAttributedString(string: footer, attributes: [.font: MessagesInk.font(ofSize: MessagesInk.meta + 1, tabular: true), .foregroundColor: MessagesInk.soft])
                .draw(at: NSPoint(x: card.minX + 16, y: card.maxY - Self.footerHeight))
        }
    }
}

/// ⌘/: every shortcut, grouped, over the window, as Slack's list is. Like a menu, it stays one size whatever the text size.
final class CheatsheetView: QuietView {
    private static let width: CGFloat = 460
    private static let rowHeight: CGFloat = 26
    private static let headingHeight: CGFloat = 34

    var onClose: (() -> Void)?
    private let close = MessageToolbar.button(CatWords.closeThread, symbol: "xmark")

    override init(frame: NSRect) {
        super.init(frame: frame)
        close.onPress = { [weak self] in self?.onClose?() }
        addSubview(close)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(CatWords.shortcutGroups.flatMap { group in [group.title] + group.rows.map { "\($0.keys), \($0.does)" } }.joined(separator: ". "))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private typealias Groups = ArraySlice<(title: String, rows: [(keys: String, does: String)])>

    private static func height(of groups: Groups) -> CGFloat {
        56 + CGFloat(groups.count) * headingHeight + CGFloat(groups.reduce(0) { $0 + $1.rows.count }) * rowHeight + 16
    }

    /// One column, or the first group beside the rest where one won't fit, as in a short window.
    private var columns: [Groups] {
        let groups = CatWords.shortcutGroups[...]
        return Self.height(of: groups) + 30 <= bounds.height ? [groups] : [groups.prefix(1), groups.dropFirst()]
    }

    var card: NSRect {
        let columns = columns
        let height = columns.map(Self.height).max() ?? 0
        let width = min(Self.width * CGFloat(columns.count), bounds.width - 40)
        return NSRect(x: (bounds.width - width) / 2, y: max((bounds.height - height) / 2, 20), width: width, height: height)
    }

    override func layout() {
        super.layout()
        close.frame.origin = NSPoint(x: card.maxX - close.frame.width - 10, y: card.minY + 14)
    }

    override func mouseUp(with event: NSEvent) {
        if !card.contains(convert(event.locationInWindow, from: nil)) { onClose?() }
    }

    /// Floating glass, with each shortcut's keys on a chip.
    override func draw(_ dirtyRect: NSRect) {
        MessagesInk.sidebar.withAlphaComponent(0.55).setFill()
        bounds.fill(using: .sourceOver)
        let card = card
        Opal.glass(NSBezierPath(roundedRect: card, xRadius: Opal.Corner.popover, yRadius: Opal.Corner.popover))

        NSAttributedString(string: CatWords.shortcutsTitle, attributes: [.font: MessagesInk.font(ofSize: 15, weight: .semibold), .foregroundColor: MessagesInk.strong])
            .draw(at: NSPoint(x: card.minX + 22, y: card.minY + 18))
        let columns = columns
        let columnWidth = card.width / CGFloat(columns.count)
        for (index, column) in columns.enumerated() {
            let left = card.minX + CGFloat(index) * columnWidth
            var y = card.minY + 56
            for group in column {
                MessagesInk.label(group.title, size: 11).draw(at: NSPoint(x: left + 22, y: y + 13))
                y += Self.headingHeight
                for row in group.rows {
                    NSAttributedString(string: row.does, attributes: [.font: MessagesInk.font(ofSize: 13), .foregroundColor: MessagesInk.text])
                        .draw(at: NSPoint(x: left + 22, y: y + 4))
                    let keys = NSAttributedString(string: row.keys, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium), .foregroundColor: MessagesInk.text])
                    let size = keys.size()
                    let chip = NSRect(x: left + columnWidth - 22 - ceil(size.width) - 16, y: y + 2, width: ceil(size.width) + 16, height: 22)
                    let shape = NSBezierPath(roundedRect: chip.insetBy(dx: 0.5, dy: 0.5), xRadius: 10.5, yRadius: 10.5)
                    Ink.hex(Opal.control).setFill()
                    shape.fill()
                    Ink.hex(Opal.fieldEdge).setStroke()
                    shape.stroke()
                    keys.draw(at: NSPoint(x: chip.midX - size.width / 2, y: chip.midY - size.height / 2))
                    y += Self.rowHeight
                }
            }
        }
    }
}

/// What each shortcut does, all from what's in memory, so the window lays out in the same turn.
extension ChannelsView {
    /// The panel only calls this while Messages has the keyboard. `true` if the key did something, or was Messages'
    /// own and had nowhere to go.
    @discardableResult
    func perform(_ shortcut: MessagesShortcut) -> Bool {
        guard let book else { return false }
        switch shortcut {
        case .jump, .search, .cheatsheet, .escape, .close, .settings: break
        default: hideOverlays()
        }
        switch shortcut {
        case .previousThread: return step(thread: -1, in: book)
        case .nextThread: return step(thread: 1, in: book)
        case .previousPlace: return step(place: -1, in: book)
        case .nextPlace: return step(place: 1, in: book)
        case .previousUnread: return step(unread: -1, in: book)
        case .nextUnread: return step(unread: 1, in: book)
        case .back: return travel(-1, in: book)
        case .forward: return travel(1, in: book)
        case .place(let number):
            let places = ChannelSidebarItem.places(in: book)
            guard places.indices.contains(number - 1) else { return false }
            select(ChannelSelection(places[number - 1]))
            return true
        case .jump:
            toggleBox(.jump, book)
            return true
        case .search:
            toggleBox(.search, book)
            return true
        case .escape:
            if !jumpBox.isHidden {
                closeJump()
            } else if !cheatsheet.isHidden {
                cheatsheet.isHidden = true
            } else if selection.thread != nil {
                closeThread()
            } else {
                return false
            }
            return true
        case .threads:
            select(.threads)
            return true
        case .activity:
            select(.activity)
            return true
        case .toggleSidebar:
            isSidebarHidden.toggle()
            return true
        case .compose:
            // The place's own box, or the thread's where the place has none, such as Threads.
            guard let pane = [pane, threadPane].first(where: { !$0.isHidden && $0.composer.target != nil }) else { return false }
            pane.focusComposer()
            return true
        case .close:
            onCloseWindow?()
            return true
        case .cheatsheet:
            closeJump()
            cheatsheet.isHidden.toggle()
            return true
        case .settings:
            onSettings?()
            return true
        }
    }

    /// The threads the place you're on leads to, top to bottom, which ⌘⇧[ and ⌘⇧] step through.
    func threadOrder(in book: ChannelBook) -> [String] {
        switch selection.place {
        case .channel(let id):
            return book.threads(in: id)
        case .threads:
            return book.yours.map(\.id)
        case .activity:
            // Only those a click there opens beside a channel. Anything else opens in T3, so no key leads a box to it.
            return ChannelRows.activityThreads(in: book, answered: pane.parts.answers.mapValues(\.count))
        }
    }

    private func step(thread step: Int, in book: ChannelBook) -> Bool {
        let order = threadOrder(in: book)
        guard !order.isEmpty else { return false }
        let target: Int
        if let open = selection.thread, let index = order.firstIndex(of: open) {
            target = index + step
            guard order.indices.contains(target) else { return true }
        } else {
            // With none open, the newest: a channel's is at the bottom, and Threads and Activity put theirs at the top.
            target = selection.channelID == nil ? 0 : order.count - 1
        }
        open(thread: order[target])
        return true
    }

    private func step(place step: Int, in book: ChannelBook) -> Bool {
        let places = ChannelSidebarItem.places(in: book)
        let index = places.firstIndex(of: selection.place) ?? 0
        let target = min(max(index + step, 0), places.count - 1)
        if target != index { select(ChannelSelection(places[target])) }
        return true
    }

    /// Round from where you are to the next channel in bold, as Slack does.
    private func step(unread step: Int, in book: ChannelBook) -> Bool {
        let items = ChannelSidebarItem.groups(in: book).flatMap(\.items)
        let index = items.firstIndex { $0.place == selection.place } ?? 0
        for offset in 1..<max(items.count, 1) {
            let item = items[((index + step * offset) % items.count + items.count) % items.count]
            guard item.place.channelID != nil, item.isUnread || item.badge > 0 else { continue }
            select(ChannelSelection(item.place))
            return true
        }
        return true
    }

    private func travel(_ step: Int, in book: ChannelBook) -> Bool {
        let target = historyIndex + step
        guard history.indices.contains(target) else { return true }
        var selection = history[target]
        // A new thread you started may have its own ID by now.
        if let thread = selection.thread, let started = book.started[thread] { selection.thread = started }
        historyIndex = target
        isTravelling = true
        select(selection)
        isTravelling = false
        return true
    }

    /// ⌘K and ⌘F open the box, close it if it's already theirs, and turn it into the other's with what's typed in it.
    private func toggleBox(_ mode: JumpBoxView.Mode, _ book: ChannelBook) {
        if jumpBox.isHidden {
            openJump(book, mode: mode)
        } else if jumpBox.mode == mode {
            closeJump()
        } else {
            jumpBox.show(book, mode: mode)
        }
    }

    private func openJump(_ book: ChannelBook, mode: JumpBoxView.Mode) {
        cheatsheet.isHidden = true
        jumpBox.field.stringValue = ""
        jumpBox.show(book, mode: mode)
        jumpBox.isHidden = false
        window?.makeFirstResponder(jumpBox.field)
    }

    func closeJump() {
        guard !jumpBox.isHidden else { return }
        jumpBox.isHidden = true
        if let responder = window?.firstResponder as? NSView, responder.isDescendant(of: jumpBox) { window?.makeFirstResponder(nil) }
    }

    /// Opens what the box found, and for a message, scrolls the pane it's in to it.
    func jumped(to item: JumpItem) {
        closeJump()
        let selection = item.selection
        if let thread = selection.thread {
            open(thread: thread, from: selection.place)
        } else {
            select(selection)
        }
        guard let message = item.found?.message.id else { return }
        (selection.thread == nil ? pane : threadPane).reveal(message)
    }

    private func hideOverlays() {
        closeJump()
        cheatsheet.isHidden = true
    }
}
