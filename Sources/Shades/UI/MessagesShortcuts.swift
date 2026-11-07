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
    /// Esc, which closes the jump box, the shortcuts, or a thread's pane.
    case escape
    /// ⌘⇧T and ⌘⇧M.
    case threads, activity
    /// ⌘N, the box of the place you're on.
    case compose
    /// ⌘W.
    case close
    /// ⌘/, every shortcut.
    case cheatsheet

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
            case (_, "n"): self = .compose
            case (_, "w"): self = .close
            case (_, "/"): self = .cheatsheet
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

/// Somewhere ⌘K can jump to: a place in the sidebar, or a thread.
struct JumpItem: Equatable {
    var title: String
    /// Where a thread is, such as its channel.
    var detail: String?
    var selection: ChannelSelection
}

extension JumpItem {
    static let limit = 8

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

/// ⌘K: a box over the window that jumps to a place or thread by name. It's a view inside Messages, not a window of
/// its own, so it can't make Shades the active app. The arrows move, Return opens and Esc closes.
final class JumpBoxView: QuietView, NSTextFieldDelegate {
    private static let width: CGFloat = 520
    private static let rowHeight: CGFloat = 40
    private static let fieldHeight: CGFloat = 46

    var onOpen: ((ChannelSelection) -> Void)?
    var onClose: (() -> Void)?
    let field = NSTextField()
    private(set) var items: [JumpItem] = []
    private(set) var highlighted = 0
    private var book: ChannelBook?

    override init(frame: NSRect) {
        super.init(frame: frame)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 16)
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
        }
    }

    func show(_ book: ChannelBook) {
        self.book = book
        field.textColor = MessagesInk.text
        field.placeholderAttributedString = NSAttributedString(string: CatWords.jumpPlaceholder, attributes: [.foregroundColor: MessagesInk.soft, .font: NSFont.systemFont(ofSize: 16)])
        refilter()
    }

    private func refilter() {
        guard let book else { return }
        items = JumpItem.matching(query, in: book)
        highlighted = 0
        needsLayout = true
        needsDisplay = true
    }

    func move(by step: Int) {
        guard !items.isEmpty else { return }
        highlighted = min(max(highlighted + step, 0), items.count - 1)
        needsDisplay = true
    }

    func open() {
        guard items.indices.contains(highlighted) else { return NSSound.beep() }
        onOpen?(items[highlighted].selection)
    }

    private var card: NSRect {
        let width = min(Self.width, bounds.width - 40)
        let height = Self.fieldHeight + CGFloat(max(items.count, 1)) * Self.rowHeight + 12
        return NSRect(x: (bounds.width - width) / 2, y: 70, width: width, height: height)
    }

    override func layout() {
        super.layout()
        let card = card
        field.frame = NSRect(x: card.minX + 16, y: card.minY + 12, width: card.width - 32, height: 24)
    }

    func controlTextDidChange(_ notification: Notification) {
        refilter()
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
        let row = Int((point.y - card.minY - Self.fieldHeight) / Self.rowHeight)
        guard point.y > card.minY + Self.fieldHeight, items.indices.contains(row) else { return }
        highlighted = row
        open()
    }

    override func draw(_ dirtyRect: NSRect) {
        MessagesInk.paper.withAlphaComponent(0.6).setFill()
        bounds.fill(using: .sourceOver)
        let card = card
        let shape = NSBezierPath(roundedRect: card, xRadius: 12, yRadius: 12)
        MessagesInk.sidebar.setFill()
        shape.fill()
        MessagesInk.line.setStroke()
        shape.stroke()
        MessagesInk.line.setFill()
        NSRect(x: card.minX, y: card.minY + Self.fieldHeight, width: card.width, height: 1).fill()

        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        guard !items.isEmpty else {
            NSAttributedString(string: CatWords.jumpNothing, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: MessagesInk.soft])
                .draw(at: NSPoint(x: card.minX + 16, y: card.minY + Self.fieldHeight + 11))
            return
        }
        for (index, item) in items.enumerated() {
            let row = NSRect(x: card.minX + 6, y: card.minY + Self.fieldHeight + 6 + CGFloat(index) * Self.rowHeight, width: card.width - 12, height: Self.rowHeight - 4)
            if index == highlighted {
                MessagesInk.press.setFill()
                NSBezierPath(roundedRect: row, xRadius: 7, yRadius: 7).fill()
            }
            let line = NSMutableAttributedString(string: item.title, attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: MessagesInk.text])
            if let detail = item.detail {
                line.append(NSAttributedString(string: "   \(detail)", attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: MessagesInk.soft]))
            }
            line.addAttribute(.paragraphStyle, value: truncating, range: NSRange(location: 0, length: line.length))
            line.draw(in: NSRect(x: row.minX + 10, y: row.midY - 9, width: row.width - 20, height: 18))
        }
    }
}

/// ⌘/: every shortcut, grouped, over the window, as Slack's list is.
final class CheatsheetView: QuietView {
    private static let width: CGFloat = 460
    private static let rowHeight: CGFloat = 26
    private static let headingHeight: CGFloat = 34

    var onClose: (() -> Void)?
    private let close = QuietButton("✕", style: .text)

    override init(frame: NSRect) {
        super.init(frame: frame)
        close.setAccessibilityLabel(CatWords.closeThread)
        close.onPress = { [weak self] in self?.onClose?() }
        addSubview(close)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(CatWords.shortcutGroups.flatMap { group in [group.title] + group.rows.map { "\($0.keys), \($0.does)" } }.joined(separator: ". "))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private var card: NSRect {
        let rows = CatWords.shortcutGroups.reduce(0) { $0 + $1.rows.count }
        let height = 56 + CGFloat(CatWords.shortcutGroups.count) * Self.headingHeight + CGFloat(rows) * Self.rowHeight + 16
        let width = min(Self.width, bounds.width - 40)
        return NSRect(x: (bounds.width - width) / 2, y: max((bounds.height - height) / 2, 20), width: width, height: height)
    }

    override func layout() {
        super.layout()
        close.frame.origin = NSPoint(x: card.maxX - close.frame.width - 10, y: card.minY + 14)
    }

    override func mouseUp(with event: NSEvent) {
        if !card.contains(convert(event.locationInWindow, from: nil)) { onClose?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        MessagesInk.paper.withAlphaComponent(0.6).setFill()
        bounds.fill(using: .sourceOver)
        let card = card
        let shape = NSBezierPath(roundedRect: card, xRadius: 12, yRadius: 12)
        MessagesInk.sidebar.setFill()
        shape.fill()
        MessagesInk.line.setStroke()
        shape.stroke()

        NSAttributedString(string: CatWords.shortcutsTitle, attributes: [.font: NSFont.systemFont(ofSize: 16, weight: .semibold), .foregroundColor: MessagesInk.text])
            .draw(at: NSPoint(x: card.minX + 22, y: card.minY + 18))
        var y = card.minY + 56
        for group in CatWords.shortcutGroups {
            NSAttributedString(string: group.title.uppercased(), attributes: [.font: NSFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: MessagesInk.soft, .kern: 0.5])
                .draw(at: NSPoint(x: card.minX + 22, y: y + 14))
            y += Self.headingHeight
            for row in group.rows {
                NSAttributedString(string: row.does, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: MessagesInk.text])
                    .draw(at: NSPoint(x: card.minX + 22, y: y + 4))
                let keys = NSAttributedString(string: row.keys, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium), .foregroundColor: MessagesInk.text])
                let size = keys.size()
                let pill = NSRect(x: card.maxX - 22 - size.width - 12, y: y + 2, width: size.width + 12, height: 20)
                MessagesInk.hover.setFill()
                NSBezierPath(roundedRect: pill, xRadius: 5, yRadius: 5).fill()
                keys.draw(at: NSPoint(x: pill.minX + 6, y: pill.midY - size.height / 2))
                y += Self.rowHeight
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
        case .jump, .cheatsheet, .escape, .close: break
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
            if jumpBox.isHidden { openJump(book) } else { closeJump() }
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
            var seen: Set<String> = []
            return ChannelRows.rows(.activity, in: book).compactMap { row -> String? in
                switch row {
                case .approval(let request): return book.thread(holding: request.id, else: request.threadID)
                case .question(let question): return book.thread(holding: question.id, else: question.threadID)
                case .report(let entry): return entry.threadID
                case .issue(let thread): return thread.id
                default: return nil
                }
            }.filter { seen.insert($0).inserted }
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

    private func openJump(_ book: ChannelBook) {
        cheatsheet.isHidden = true
        jumpBox.show(book)
        jumpBox.query = ""
        jumpBox.isHidden = false
        window?.makeFirstResponder(jumpBox.field)
    }

    func closeJump() {
        guard !jumpBox.isHidden else { return }
        jumpBox.isHidden = true
        if let responder = window?.firstResponder as? NSView, responder.isDescendant(of: jumpBox) { window?.makeFirstResponder(nil) }
    }

    func jumped(to selection: ChannelSelection) {
        closeJump()
        if let thread = selection.thread {
            open(thread: thread, from: selection.place)
        } else {
            select(selection)
        }
    }

    private func hideOverlays() {
        closeJump()
        cheatsheet.isHidden = true
    }
}
