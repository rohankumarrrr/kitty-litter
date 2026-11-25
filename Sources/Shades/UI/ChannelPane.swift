import AppKit
import ShadesCore

final class ChannelHeader: QuietView {
    static let height: CGFloat = 56
    private static let tileSide: CGFloat = 30

    var onIssues: (() -> Void)?
    var onClose: (() -> Void)?
    var onOpen: (() -> Void)?
    var onNotifications: ((ChannelID, ChannelNotifications) -> Void)?
    var onBacklog: ((String) -> Void)?
    private let notificationsMenu = NotificationsMenu()
    var onPhone: (() -> Void)?
    private var title = ""
    private var subtitle: String?
    private var cat: ChannelSpeakerLook?
    private var buttons: [QuietButton] = []

    static func words(for place: ChannelPlace, in book: ChannelBook) -> (title: String, subtitle: String?) {
        switch place {
        case .activity:
            return (CatWords.activityTitle, CatWords.activitySubtitle)
        case .threads:
            return (CatWords.threadsTitle, CatWords.threadsSubtitle)
        case .channel(.shades):
            return (CatWords.shades, CatWords.shadesSubtitle)
        case .channel(let id):
            let status = book.statuses.first { .of($0.kitten) == id }
            return (book.name(of: id), status.map { "\($0.kitten.role) · \(CatWords.kittenState($0.state))" })
        }
    }

    static func words(forThread id: String, in book: ChannelBook) -> (title: String, subtitle: String?) {
        let home = book.home(ofThread: id).map(book.name) ?? ""
        let name = book.title(ofThread: id)
        let details = book.talks.contains(id) ? nil : book.listed[id].map(CatWords.threadDetails)
        let about = [name.isEmpty ? CatWords.newThread : name, details].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return (CatWords.threadTitle, [home, about].filter { !$0.isEmpty }.joined(separator: "  ·  "))
    }

    func show(_ place: ChannelPlace, in book: ChannelBook, backlogs: [String: Backlog] = [:]) {
        (title, subtitle) = Self.words(for: place, in: book)
        cat = nil
        var right: [Action] = []
        switch place {
        case .channel(.shades):
            cat = ChannelSpeakerLook(.cat, in: book)
        case .channel(.kitten(let kitten)):
            cat = ChannelSpeakerLook(.kitten(kitten), in: book)
            if let count = book.issues.first(where: { $0.kitten.id == kitten })?.threads.count, count > 0 {
                right = [Action(CatWords.issues(count)) { [weak self] in self?.onIssues?() }]
            }
            if let count = backlogs[kitten]?.items.count, count > 0 {
                right.append(Action(CatWords.backlog(count)) { [weak self] in self?.onBacklog?(kitten) })
            }
        case .activity, .threads:
            break
        }
        if case .channel(let id) = place { right.append(notificationsButton(for: id, in: book)) }
        setButtons(right)
        describe()
    }

    private func notificationsButton(for id: ChannelID, in book: ChannelBook) -> Action {
        let current = book.waiting.notifications[id.settingsKey] ?? ChannelNotifications()
        let phone = book.waiting.phone
        return Action(current.muted ? CatWords.muted : CatWords.notifications, symbol: current.muted ? "bell.slash" : "bell") { [weak self] in
            guard let self, let anchor = self.buttons.last else { return }
            self.notificationsMenu.show(current, phone: phone, under: anchor) { [weak self] in self?.onNotifications?(id, $0) }
        }
    }

    func show(thread id: String, in book: ChannelBook) {
        (title, subtitle) = Self.words(forThread: id, in: book)
        cat = nil
        var right: [Action] = []
        if book.hasPhone, book.catsWork.contains(id), book.home(ofThread: id) == .shades {
            right.append(Action(book.onPhone.contains(id) ? CatWords.hideFromPhone : CatWords.showOnPhone) { [weak self] in self?.onPhone?() })
        }
        if book.knows(thread: id) { right.append(Action(CatWords.openInT3, symbol: "arrow.up.forward.app") { [weak self] in self?.onOpen?() }) }
        right.append(Action(CatWords.closeThread, symbol: "xmark") { [weak self] in self?.onClose?() })
        setButtons(right)
        describe()
    }

    private func describe() {
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel([title, subtitle].compactMap { $0 }.joined(separator: ", "))
        needsDisplay = true
    }

    private struct Action {
        var title: String
        var symbol: String?
        var run: () -> Void

        init(_ title: String, symbol: String? = nil, run: @escaping () -> Void) {
            self.title = title
            self.symbol = symbol
            self.run = run
        }
    }

    private func setButtons(_ right: [Action]) {
        buttons.forEach { $0.removeFromSuperview() }
        var edge = bounds.width - ChannelRowView.margin + 6
        buttons = right.reversed().map { action in
            let button = action.symbol.map { MessageToolbar.button(action.title, symbol: $0, onPress: action.run) } ?? QuietButton(action.title, style: .text, onPress: action.run)
            edge -= button.frame.width
            button.frame.origin = NSPoint(x: edge, y: ((Self.height - button.frame.height) / 2).rounded())
            button.autoresizingMask = [.minXMargin]
            return button
        }.reversed()
        buttons.forEach(addSubview)
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    var windowButtonsEnd: CGFloat? {
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { window?.standardWindowButton($0) }
            .filter { !$0.isHidden }
            .map { convert($0.bounds, from: $0) }
            .filter { $0.intersects(bounds) }
            .map(\.maxX).max()
    }

    override func draw(_ dirtyRect: NSRect) {
        var left = windowButtonsEnd.map { max($0 + 14, ChannelRowView.margin) } ?? ChannelRowView.margin
        if let cat {
            let tile = NSRect(x: left, y: ((Self.height - Self.tileSide) / 2).rounded(), width: Self.tileSide, height: Self.tileSide)
            Opal.tile(in: tile, light: cat.jacket.map(Opal.Light.of) ?? .shades)
            CatStamp.draw(CatPose(frame: .sit), jacket: cat.jacket, in: tile.insetBy(dx: 3, dy: 3), on: self)
            left = tile.maxX + 10
        }

        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        let room = max((buttons.first?.frame.minX ?? bounds.width - ChannelRowView.margin) - left - 8, 0)
        let name = NSAttributedString(string: title, attributes: [
            .font: MessagesInk.font(ofSize: MessagesInk.toolbarTitle, weight: .semibold),
            .foregroundColor: MessagesInk.strong,
            .paragraphStyle: truncating,
        ])
        let line = subtitle.flatMap { $0.isEmpty ? nil : NSAttributedString(string: $0, attributes: [
            .font: MessagesInk.font(ofSize: MessagesInk.meta),
            .foregroundColor: MessagesInk.soft,
            .paragraphStyle: truncating,
        ]) }
        let nameHeight = ceil(name.size().height)
        let lineHeight = line.map { ceil($0.size().height) + 1 } ?? 0
        let top = ((bounds.height - nameHeight - lineHeight) / 2).rounded()
        name.draw(in: NSRect(x: left, y: top, width: room, height: nameHeight))
        line?.draw(in: NSRect(x: left, y: top + nameHeight + 1, width: room, height: lineHeight))

        MessagesInk.line.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }
}

final class MessageList: QuietView {
    var onFocus: ((Bool) -> Void)?
    var onStep: ((Int) -> Void)?
    var onSpace: (() -> Void)?
    var onCopy: (() -> Bool)?
    var onKeyChange: (() -> Void)?
    private var keyObservers: [NSObjectProtocol] = []

    override var acceptsFirstResponder: Bool {
        guard window?.isKeyWindow == true else { return false }
        let type = NSApplication.shared.currentEvent?.type
        return type != .leftMouseDown && type != .rightMouseDown && type != .otherMouseDown
    }

    override var canBecomeKeyView: Bool { acceptsFirstResponder && !isHiddenOrHasHiddenAncestor }

    override func becomeFirstResponder() -> Bool {
        QuietFocus.took(self)
        onFocus?(true)
        return true
    }

    override func resignFirstResponder() -> Bool {
        onFocus?(false)
        return true
    }

    override func keyDown(with event: NSEvent) {
        let plain = event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        switch (event.keyCode, plain) {
        case (126, true), (125, true):
            if window?.firstResponder !== self { window?.makeFirstResponder(self) }
            onStep?(event.keyCode == 126 ? -1 : 1)
        case (_, true) where QuietFocus.isSpace(event) && window?.firstResponder === self:
            onSpace?()
        default:
            super.keyDown(with: event)
        }
    }

    @objc func copy(_ sender: Any?) {
        if onCopy?() != true { NSSound.beep() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        keyObservers.forEach(NotificationCenter.default.removeObserver)
        guard let window else { return keyObservers = [] }
        keyObservers = [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onKeyChange?() }
            }
        }
    }
}

final class PartAnswers {
    var answers: [String: [[String]]] = [:]
    var picked: [String: [String]] = [:]
}

final class ChannelPane: QuietView {
    enum Role {
        case place
        case thread
    }

    private enum Box: Hashable {
        case place(ChannelPlace)
        case thread(String)
    }

    private struct Draft {
        var text: String
        var target: MessageTarget
    }

    private static let stickyDistance: CGFloat = 40
    private static let topPad: CGFloat = 6
    private static let bottomPad: CGFloat = 14
    static let page = 60
    private static let overscan: CGFloat = 600
    private var firstPage: Int { role == .thread ? Self.page / 2 : Self.page }
    private static let reuseReach = 64
    private static let wordsKept = 2_000

    let role: Role
    var onOpenThread: ((String) -> Void)?
    var onCopy: ((String) -> Void)?
    var onSelect: ((ChannelSelection) -> Void)?
    var onOpen: ((_ thread: String, _ place: ChannelPlace?, _ typing: Bool, _ report: InboxEntry?) -> Void)?
    var onClose: (() -> Void)?
    var onAction: ((MessagesAction) -> Void)?
    var onMarkUnread: ((_ thread: String, _ message: String) -> Void)?
    var onMarkRead: (([String]) -> Void)?
    var onOpenLink: ((URL) -> Void)?
    var onShowOnPhone: ((String) -> Void)?
    var onAttach: ((ChannelComposer, NSView) -> Void)?
    var onBacklog: ((String) -> Void)?
    var backlogs: [String: Backlog] = [:] {
        didSet {
            guard backlogs != oldValue, role == .place, let book else { return }
            header.show(selection.place, in: book, backlogs: backlogs)
        }
    }
    var parts = PartAnswers()

    private let now: () -> Date = Date.init
    private let header = ChannelHeader()
    private let scroll = QuietScrollView()
    let list = MessageList()
    private weak var current: ChannelRowView? {
        didSet {
            guard current !== oldValue else { return }
            oldValue?.isFocused = false
            oldValue?.isCurrent = false
            current?.isCurrent = true
            current?.isFocused = window?.firstResponder === list
        }
    }
    let composer = ChannelComposer()
    let linkBar = LinkBar()
    private(set) var selection: ChannelSelection = .activity
    private var book: ChannelBook?
    private var replyingTo: InboxEntry?
    private var spokenTo: (selection: ChannelSelection, target: MessageTarget, answered: Int)?
    private var drafts: [Box: Draft] = [:]
    private var held: MessageTarget?
    private(set) var shown: [ChannelRow] = [] {
        didSet { newLine = shown.indices.lazy.compactMap { index in if case .new(let count) = self.shown[index] { (index, count) } else { nil } }.first }
    }
    private var newLine: (index: Int, count: Int)?
    private var views: [ChannelRowView] = []
    private var frames: [NSRect] = []
    private var first = 0
    private var words: [String: MessageWords] = [:]
    private var pulls: [String: String] = [:]
    private var expanded: Set<String> = []
    private var newFrom: [String: String] = [:]
    private var jump: QuietButton?
    private var stackedSize = NSSize.zero
    private var isPaging = false
    private var isShowing = false

    private var document: MessageList { list }

    init(role: Role) {
        self.role = role
        super.init(frame: .zero)
        scroll.documentView = document
        list.onFocus = { [weak self] in self?.listFocused($0) }
        list.onStep = { [weak self] in self?.step($0) }
        list.onSpace = { [weak self] in
            guard let row = self?.current, row.isPressable else { return NSSound.beep() }
            row.press()
        }
        list.onCopy = { [weak self] in (self?.current as? MessageRowView)?.copyMessage() ?? false }
        list.onKeyChange = { [weak self] in self?.current?.focusChanged() }
        addSubview(scroll)
        addSubview(header)
        addSubview(composer)
        addSubview(linkBar)
        linkBar.onOpen = { [weak self] link in
            self?.showLink(nil)
            if Markup.opens(link) { self?.onOpenLink?(link) }
        }
        linkBar.onShowPicture = { [weak self] link in
            self?.showLink(nil)
            self?.onAction?(.showPicture(link))
        }
        linkBar.onCancel = { [weak self] in self?.showLink(nil) }
        header.onIssues = { [weak self] in self?.onSelect?(.activity) }
        header.onClose = { [weak self] in self?.onClose?() }
        header.onNotifications = { [weak self] in self?.onAction?(.notifications($0, $1)) }
        header.onBacklog = { [weak self] in self?.onBacklog?($0) }
        header.onOpen = { [weak self] in
            guard let self, let id = self.selection.thread else { return }
            self.onOpenThread?(id)
        }
        header.onPhone = { [weak self] in
            guard let self, let id = self.selection.thread else { return }
            self.onShowOnPhone?(id)
        }
        composer.onSend = { [weak self] words, target, files, alternate in
            guard let self else { return }
            let named = target == .router ? MessageTarget.mentioned(in: words, among: self.book?.mentionable ?? []) : nil
            switch named.map(MessageTarget.newThread) ?? target {
            case .question(let question):
                guard self.part(of: question)?.part.takesOwnWords == true else {
                    NSSound.beep()
                    self.composer.textView.string = words
                    return
                }
                self.answer(question, with: [words])
            case .newThread(let kitten):
                let topic = "sent-\(UUID().uuidString)"
                let typing = self.window?.firstResponder === self.composer.textView
                self.onAction?(.startTopic(words, with: kitten, id: topic, files: files))
                self.onOpen?(topic, nil, typing, nil)
            case .thread(let id, _, _):
                let alsoSent = self.composer.alsoSends
                self.composer.alsoSends = false
                self.onAction?(.send(words, to: target, shownIn: self.book?.home(ofThread: id) ?? .shades, alsoSent: alsoSent, files: files, alternate: alternate))
                self.updateComposer()
                self.arrange(force: true)
            default:
                self.onAction?(.send(words, to: target, shownIn: self.selection.channelID, files: files))
                self.updateComposer()
                self.arrange(force: true)
            }
        }
        composer.onResize = { [weak self] in self?.typed() }
        composer.onAttach = { [weak self] anchor in
            guard let self else { return }
            self.onAttach?(self.composer, anchor)
        }
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        arrange()
        showJump()
    }

    func arrange(force: Bool = false) {
        let box = composer.height
        let bar = min(linkBar.height(for: bounds.width), max(bounds.height - ChannelHeader.height - box, 0))
        header.frame = NSRect(x: 0, y: 0, width: bounds.width, height: ChannelHeader.height)
        scroll.frame = NSRect(x: 0, y: ChannelHeader.height, width: bounds.width, height: max(bounds.height - ChannelHeader.height - box - bar, 0))
        linkBar.frame = NSRect(x: 0, y: bounds.height - box - bar, width: bounds.width, height: bar)
        composer.frame = NSRect(x: 0, y: bounds.height - box, width: bounds.width, height: box)
        if force { composer.needsLayout = true }
        guard stackedSize != scroll.contentSize else { return }
        let wasAtBottom = isNearBottom
        stack()
        if wasAtBottom, followsLatest { scrollToBottom() }
        attach()
    }

    private func shows(_ selection: ChannelSelection) -> Box? {
        switch role {
        case .place: return .place(selection.place)
        case .thread: return selection.thread.map(Box.thread)
        }
    }

    private func box(of selection: ChannelSelection, in book: ChannelBook) -> Box? {
        guard role == .thread, let thread = selection.thread else { return shows(selection) }
        return .thread(book.started[thread] ?? thread)
    }

    func show(_ selection: ChannelSelection, in book: ChannelBook, isNewSelection: Bool) {
        isShowing = true
        defer { isShowing = false }
        let isNewSelection = isNewSelection || shows(selection) != shows(self.selection)
        if let thread = selection.thread, thread == replyingTo?.threadID {} else { replyingTo = nil }
        parts.answers = parts.answers.filter { id, _ in book.waiting.questions.contains { $0.id == id } }
        parts.picked = parts.picked.filter { id, _ in book.waiting.questions.contains { $0.id == id } }
        for (topic, thread) in book.started {
            if let draft = drafts.removeValue(forKey: .thread(topic)) { drafts[.thread(thread)] = draft }
        }
        let isNewBox = box(of: selection, in: book) != box(of: self.selection, in: book)
        let restored = isNewBox ? swapDraft(for: selection, in: book) : nil
        self.selection = selection
        self.book = book
        if isNewSelection { linkBar.show(nil) }
        updateComposer(keepingDraft: !isNewBox, typedFor: restored)
        arrange()
        newFrom = isNewSelection ? book.newFrom : newFrom.merging(book.newFrom) { _, now in now }
        let rows: [ChannelRow]
        switch role {
        case .place:
            header.show(selection.place, in: book, backlogs: backlogs)
            rows = ChannelRows.rows(selection.place, in: book, newFrom: newFrom)
        case .thread:
            guard let thread = selection.thread else { return }
            header.show(thread: thread, in: book)
            rows = ChannelRows.thread(thread, in: book, newFrom: newFrom)
        }
        let pullsChanged = book.pulls != pulls
        pulls = book.pulls
        if pullsChanged, !isNewSelection, rows == shown { return restyle() }
        guard isNewSelection || rows != shown else { return }

        let wasAtBottom = isNearBottom
        let anchors = isNewSelection ? [] : inSight
        let start = followsLatest ? (isNewSelection || wasAtBottom ? max(rows.count - firstPage, 0) : refreshedStart(in: rows)) : 0
        var old: [(row: ChannelRow, view: ChannelRowView?)] = isNewSelection ? [] : zip(shown[first...], views).map { ($0, $1) }
        var cursor = rows.indices.contains(start) ? old.firstIndex { $0.row == rows[start] } ?? 0 : 0
        let previous = views
        views = rows[start...].map { row in
            if let match = old[cursor..<min(cursor + Self.reuseReach, old.count)].firstIndex(where: { $0.row == row }), let kept = old[match].view {
                old[match].view = nil
                cursor = match + 1
                return kept
            }
            return view(for: row, in: book, among: rows)
        }
        let kept = Set(views.map(ObjectIdentifier.init))
        previous.filter { !kept.contains(ObjectIdentifier($0)) }.forEach { $0.removeFromSuperview() }
        first = start
        shown = rows
        if words.count > Self.wordsKept {
            let showing = Set(rows.compactMap(\.messageID))
            words = words.filter { showing.contains($0.key) }
        }
        stack()

        if isNewSelection {
            scrollOffset = followsLatest ? bottomOffset : 0
        } else if wasAtBottom, followsLatest {
            scrollToBottom()
        } else if followsLatest, !anchors.isEmpty {
            keep(anchors)
        }
        attach()
        pageIfNeeded()
        if pullsChanged, !isNewSelection { restyle() }
        keepCurrent()
        showJump()
    }

    @discardableResult
    func reveal(_ messageID: String) -> Bool {
        guard let index = shown.firstIndex(where: { $0.messageID == messageID }) else { return false }
        while first > index { layOutPageAbove() }
        let frame = frames[index - first]
        scrollOffset = min(max(frame.midY - scroll.contentSize.height / 2, 0), bottomOffset)
        attach()
        views.lazy.compactMap { $0 as? MessageRowView }.first { $0.message.id == messageID }?.flash()
        return true
    }

    @objc func ask(toOpen link: URL) {
        guard Markup.opens(link) else { return NSSound.beep() }
        showLink(link)
    }

    func ask(toShowPicture link: URL) {
        guard Markup.opens(link) else { return NSSound.beep() }
        showLink(link, picture: true)
    }

    private func showLink(_ link: URL?, picture: Bool = false) {
        linkBar.show(link, picture: picture)
        arrange()
    }

    private func refreshedStart(in rows: [ChannelRow]) -> Int {
        guard shown.indices.contains(first) else { return max(rows.count - Self.page, 0) }
        return shown[first...].prefix(Self.reuseReach).lazy.compactMap { rows.firstIndex(of: $0) }.first ?? max(rows.count - (shown.count - first), 0)
    }

    func restyle() {
        composer.restyle()
        header.needsDisplay = true
        jump?.removeFromSuperview()
        jump = nil
        if isHidden {
            views.forEach { $0.removeFromSuperview() }
            views = []
            frames = []
            shown = []
            first = 0
            showJump()
            return
        }
        guard let book else { return }
        let offset = scrollOffset
        views.forEach { $0.removeFromSuperview() }
        views = shown[first...].map { view(for: $0, in: book, among: shown) }
        stack()
        scrollOffset = offset
        attach()
        keepCurrent()
        showJump()
    }

    func focusComposer() {
        guard composer.target != nil else { return }
        window?.makeKey()
        window?.makeFirstResponder(composer.textView)
    }

    func leaveThread() {
        replyingTo = nil
        composer.alsoSends = false
    }

    func replying(to entry: InboxEntry?) {
        replyingTo = entry
        updateComposer(keepingDraft: true)
        arrange(force: true)
    }

    func reply(to entry: InboxEntry) {
        onOpen?(entry.threadID, .channel(book?.home(of: book?.kitten(of: entry.id)) ?? .shades), true, entry)
    }

    private func swapDraft(for selection: ChannelSelection, in book: ChannelBook) -> MessageTarget? {
        if let left = box(of: self.selection, in: book) {
            drafts[left] = composer.hasDraft ? composer.target.map { Draft(text: composer.textView.string, target: $0) } : nil
        }
        held = nil
        let draft = box(of: selection, in: book).flatMap { drafts.removeValue(forKey: $0) }
        composer.showDraft(draft?.text ?? "")
        guard let draft else { return nil }
        if case .starting = draft.target {} else if !draft.target.isStill(in: book) { held = draft.target }
        return draft.target
    }

    private func typed() {
        if held != nil, !composer.hasDraft { updateComposer() }
        arrange(force: true)
    }

    private func updateComposer(keepingDraft: Bool = false, typedFor restored: MessageTarget? = nil) {
        var target: MessageTarget?
        var also: String?
        if let book {
            switch role {
            case .place:
                target = MessageTarget.standard(for: selection.place, in: book)
            case .thread:
                if let thread = selection.thread {
                    target = MessageTarget.reply(in: thread, of: book, answered: parts.answers.mapValues(\.count))
                    if let replyingTo, replyingTo.threadID == thread, !book.talks.contains(thread) {
                        let title = book.title(ofThread: thread)
                        target = .thread(id: thread, title: title.isEmpty ? replyingTo.threadTitle : title, report: replyingTo.id)
                    }
                }
            }
        }
        if let spokenTo, spokenTo.selection == selection { target = spokenTo.target }
        if composer.hasDraft, let typedFor = restored ?? (keepingDraft ? composer.target : nil), let book, typedFor.isStill(in: book) {
            target = typedFor
        }
        if !composer.hasDraft { held = nil }
        if let held { target = held }
        if case .thread(let id, _, _)? = target, let home = book?.home(ofThread: id), home != .shades {
            also = book.map { CatWords.alsoSendTo($0.name(of: home)) }
        }
        var label: String?
        if case .question(let question)? = target, let part = part(of: question) { label = CatWords.answering(part.part.text) }
        if held != nil { label = CatWords.heldDraft }
        composer.isHeld = held != nil
        composer.show(target, label: label, alsoSendTo: also, mentionable: book?.mentionable ?? [])
    }

    func startSpeaking() {
        spokenTo = composer.target.map { target in
            let answered = if case .question(let question) = target { parts.answers[question.id]?.count ?? 0 } else { 0 }
            return (selection, target, answered)
        }
    }

    func spoke(_ text: String) {
        let spot = spokenTo
        spokenTo = nil
        if let spot, let book, let away = box(of: spot.selection, in: book), away != box(of: selection, in: book) {
            let typed = drafts[away]?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            drafts[away] = Draft(text: typed.isEmpty ? text : "\(typed) \(text)", target: drafts[away]?.target ?? spot.target)
            NSSound.beep()
            return
        }
        let typed = composer.textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = typed.isEmpty ? text : "\(typed) \(text)"
        let samePart = if case .question(let question) = spot?.target { parts.answers[question.id]?.count ?? 0 == spot?.answered } else { true }
        guard let spot, spot.selection == selection, let book, spot.target.isReady, spot.target.isStill(in: book), samePart else {
            composer.textView.string = words
            updateComposer(keepingDraft: true)
            arrange(force: true)
            NSSound.beep()
            return
        }
        composer.textView.string = ""
        composer.onSend?(words, spot.target, composer.takeAttachments(), false)
        arrange(force: true)
    }

    func stopSpeaking() {
        spokenTo = nil
        updateComposer(keepingDraft: true)
        arrange(force: true)
    }

    private func part(of question: AgentQuestion) -> (index: Int, part: AnswerForm.Part)? {
        guard let parts = question.form?.parts else { return nil }
        let index = self.parts.answers[question.id]?.count ?? 0
        return parts.indices.contains(index) ? (index, parts[index]) : nil
    }

    private func answer(_ question: AgentQuestion, with answer: [String]) {
        parts.picked[question.id] = nil
        let answers = (parts.answers[question.id] ?? []) + [answer]
        if answers.count >= question.form?.parts.count ?? 1 {
            parts.answers[question.id] = nil
            onAction?(.answer(question, answers))
        } else {
            parts.answers[question.id] = answers
            rebuild(.question(question))
        }
        updateComposer()
        arrange(force: true)
    }

    private func toggle(_ value: String, of question: AgentQuestion) {
        var picked = parts.picked[question.id] ?? []
        if let at = picked.firstIndex(of: value) { picked.remove(at: at) } else { picked.append(value) }
        parts.picked[question.id] = picked
        rebuild(.question(question))
    }

    private func rebuild(_ row: ChannelRow) {
        guard let book, let index = shown.firstIndex(of: row), index >= first else { return }
        let fresh = view(for: row, in: book, among: shown)
        views[index - first].removeFromSuperview()
        views[index - first] = fresh
        stack()
        attach()
    }

    func refreshTimes() {
        document.subviews.forEach { $0.needsDisplay = true }
    }

    var longMessageRow: MessageRowView? {
        shownMessageRows.first(where: \.isCut)
    }

    var shownMessageRows: [MessageRowView] {
        views.compactMap { $0 as? MessageRowView }
    }

    var distanceFromBottom: CGFloat {
        document.frame.height - scroll.contentView.bounds.maxY
    }

    var scrollOffset: CGFloat {
        get { scroll.contentView.bounds.minY }
        set {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: newValue))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    private func view(for row: ChannelRow, in book: ChannelBook, among rows: [ChannelRow]) -> ChannelRowView {
        switch row {
        case .day(let date):
            return DayRowView(date: date, now: now)
        case .parent(let post):
            let view = messageView(post.parent, in: book)
            view.replyBar = ReplyBar(post, in: book)
            view.onPress = { [weak self] in self?.onOpen?(post.threadID, nil, false, nil) }
            if MessageTarget.reply(in: post.threadID, of: book) != nil {
                view.onReply = { [weak self] in self?.onOpen?(post.threadID, nil, true, nil) }
            }
            if book.knows(thread: post.threadID) { view.onOpen = { [weak self] in self?.onOpenThread?(post.threadID) } }
            if post.isUnread { view.onMarkRead = { [weak self] in self?.onMarkRead?([post.threadID]) } }
            offerMarkUnread(on: view, post.parent, in: post.threadID, of: book)
            return view
        case .message(let message):
            let view = messageView(message, in: book)
            if !message.threadID.isEmpty, book.knows(thread: message.threadID) {
                view.onOpen = { [weak self] in self?.onOpenThread?(message.threadID) }
            }
            offerMarkUnread(on: view, message, in: message.threadID, of: book)
            return view
        case .alsoSent(let message, let threadID, let parent):
            let view = messageView(message, in: book)
            view.context = CatWords.repliedToThread(parent)
            view.onPress = { [weak self] in self?.onOpen?(threadID, nil, false, nil) }
            offerMarkUnread(on: view, message, in: threadID, of: book)
            return view
        case .digest(let digest):
            let view = ThreadDigestRowView(digest: digest, in: book, now: now)
            view.onPress = { [weak self] in self?.onOpen?(digest.threadID, nil, false, nil) }
            if digest.isUnread {
                view.onMarkRead = { [weak self] in self?.onMarkRead?([digest.threadID]) }
            } else if book.canMarkUnread(digest.threadID) {
                let latest = digest.latest ?? digest.parent
                view.onMarkUnread = { [weak self] in self?.onMarkUnread?(digest.threadID, latest.id) }
            }
            return view
        case .replies(let count):
            return RepliesRowView(count: count)
        case .new(let count):
            return NewRowView(count: count)
        case .heading(let status):
            return HeadingRowView(status: status)
        case .issue(let thread):
            let view = IssueRowView(thread: thread, now: now)
            if let home = book.threads[thread.id]?.home {
                view.onPress = { [weak self] in self?.onOpen?(thread.id, .channel(home), false, nil) }
            } else {
                view.onPress = { [weak self] in self?.onOpenThread?(thread.id) }
            }
            return view
        case .section(let title, let kind):
            return SectionRowView(title: title, onClear: kind.map { kind in { [weak self] in self?.onAction?(.inbox(.clear(kind))) } })
        case .approval(let request):
            return card(for: request, in: book)
        case .question(let question):
            return card(for: question, in: book)
        case .report(let entry):
            return card(for: entry, in: book)
        case .note(let text):
            return NoteRowView(text: text, isCentered: followsLatest || rows.count == 1)
        case .older(let isLoading):
            return OlderRowView(isLoading: isLoading) { [weak self] in self?.loadOlder() }
        }
    }

    private func messageView(_ message: ChannelMessage, in book: ChannelBook) -> MessageRowView {
        let look = ChannelSpeakerLook(message.speaker, in: book)
        let laidOut = words[message.id].flatMap { $0.message == message && $0.pulls == pulls ? $0 : nil } ?? MessageWords(message, look: look, pulls: pulls)
        laidOut.paint(for: look)
        words[message.id] = laidOut
        let view = MessageRowView(message: message, look: look, words: laidOut)
        view.isExpanded = expanded.contains(message.id)
        view.onCopy = { [weak self] in self?.onCopy?($0) }
        if message.canTryAgain { view.onTryAgain = { [weak self] in self?.onAction?(.tryAgain(message.exchangeID)) } }
        if message.reactions != nil { view.onReact = { [weak self] in self?.onAction?(.react(message.id, $0)) } }
        view.onShowPicture = { [weak self] in self?.ask(toShowPicture: $0) }
        view.onShowMore = { [weak self, weak view] in
            self?.expanded.insert(message.id)
            view?.isExpanded = true
            self?.stack()
            self?.attach()
        }
        return view
    }

    private func offerMarkUnread(on view: MessageRowView, _ message: ChannelMessage, in thread: String, of book: ChannelBook) {
        guard book.canMarkUnread(thread), !message.isSending else { return }
        view.onMarkUnread = { [weak self] in self?.onMarkUnread?(thread, message.id) }
    }

    private func look(_ kitten: Kitten?, in book: ChannelBook) -> ChannelSpeakerLook {
        ChannelSpeakerLook(kitten.map { .kitten($0.id) } ?? .someoneElse, in: book)
    }

    private func heading(_ kitten: Kitten?, title: String) -> String {
        kitten.map { "\($0.name) · \(ChannelBook.title(of: title, owner: $0))" } ?? title
    }

    private func card(for request: ApprovalRequest, in book: ChannelBook) -> CardRowView {
        let kitten = book.kitten(of: request.id)
        var buttons = [
            CardRowView.Button(title: "Deny") { [weak self] in self?.onAction?(.approval(request, .decline)) },
            CardRowView.Button(title: "Allow") { [weak self] in self?.onAction?(.approval(request, .accept)) },
        ]
        if ApprovalPolicy.offersSessionAllow(request.kind) {
            buttons.append(CardRowView.Button(title: "Allow for this session") { [weak self] in self?.onAction?(.approval(request, .acceptForSession)) })
        }
        buttons.append(CardRowView.Button(title: CatWords.ignore) { [weak self] in self?.onAction?(.ignore(request)) })
        buttons.append(openButton(book.thread(holding: request.id, else: request.threadID), in: book))
        return CardRowView(look: look(kitten, in: book), heading: heading(kitten, title: request.threadTitle), at: request.createdAt, text: request.summary, footer: CatWords.ignoreLeavesItWaiting, buttons: buttons)
    }

    private func card(for question: AgentQuestion, in book: ChannelBook) -> CardRowView {
        let kitten = book.kitten(of: question.id)
        var buttons: [CardRowView.Button] = []
        var text = question.text
        var footer = question.form == nil ? CatWords.answerInT3 : nil
        if let (index, part) = part(of: question) {
            let count = question.form?.parts.count ?? 1
            text = CatWords.part(index, of: count, part.text)
            let picked = parts.picked[question.id] ?? []
            buttons = part.options.indices.filter { part.values.indices.contains($0) }.map { option in
                let value = part.values[option]
                guard part.picksSeveral else {
                    return CardRowView.Button(title: part.options[option]) { [weak self] in self?.answer(question, with: [value]) }
                }
                return CardRowView.Button(title: part.options[option], isPicked: picked.contains(value)) { [weak self] in self?.toggle(value, of: question) }
            }
            if part.picksSeveral, !buttons.isEmpty {
                buttons.append(CardRowView.Button(title: index + 1 < count ? CatWords.nextPart : CatWords.sendPicked, isArmed: !picked.isEmpty) { [weak self] in
                    guard let self, let picked = self.parts.picked[question.id], !picked.isEmpty else { return }
                    self.answer(question, with: part.values.filter(picked.contains))
                })
                footer = CatWords.picksSeveral
            }
            if part.takesOwnWords {
                let thread = book.thread(holding: question.id, else: question.threadID)
                let home = book.home(ofThread: thread) ?? book.home(of: kitten)
                buttons.append(CardRowView.Button(title: CatWords.answerInWords) { [weak self] in
                    self?.onOpen?(thread, .channel(home), true, nil)
                })
            }
        }
        buttons.append(openButton(book.thread(holding: question.id, else: question.threadID), in: book))
        text = text.isEmpty ? CatWords.unreadableQuestion : text
        return CardRowView(look: look(kitten, in: book), heading: heading(kitten, title: question.threadTitle), at: nil, text: text, footer: footer, buttons: buttons)
    }

    private func card(for entry: InboxEntry, in book: ChannelBook) -> CardRowView {
        let kitten = book.kitten(of: entry.id)
        if let change = entry.change { return card(for: change, of: entry, by: kitten, in: book) }
        if let ask = entry.ask { return card(for: ask, of: entry, by: kitten, in: book) }
        let reply = CardRowView.Button(title: entry.kind == .decision ? "Reply" : "Ask") { [weak self] in self?.reply(to: entry) }
        var buttons = [reply]
        if entry.kind == .decision {
            buttons.append(CardRowView.Button(title: "Done") { [weak self] in self?.onAction?(.inbox(.done(id: entry.id))) })
        }
        buttons.append(openButton(entry.threadID, in: book))
        return CardRowView(
            look: look(kitten, in: book),
            heading: heading(kitten, title: entry.threadTitle),
            at: entry.at,
            text: entry.text,
            answer: entry.answer,
            footer: entry.repliedAt == nil ? nil : CatWords.inboxSent,
            buttons: buttons
        )
    }

    private func card(for change: ChangeRequest, of entry: InboxEntry, by kitten: Kitten?, in book: ChannelBook) -> CardRowView {
        var buttons = [CardRowView.Button(title: "Deny") { [weak self] in self?.onAction?(.inbox(.deny(id: entry.id))) }]
        if change.problem == nil {
            buttons.append(CardRowView.Button(title: "Allow") { [weak self] in self?.onAction?(.inbox(.allow(id: entry.id))) })
        }
        buttons.append(ignoreButton(entry))
        buttons.append(openButton(entry.threadID, in: book))
        return CardRowView(
            look: look(kitten, in: book),
            heading: heading(kitten, title: entry.threadTitle),
            at: entry.at,
            text: CatWords.changeCard(change, by: kitten?.name ?? "The kitten"),
            answer: CatWords.changeReview(change),
            buttons: buttons
        )
    }

    private func card(for ask: AskRequest, of entry: InboxEntry, by kitten: Kitten?, in book: ChannelBook) -> CardRowView {
        var buttons = [
            CardRowView.Button(title: "Deny") { [weak self] in self?.onAction?(.inbox(.deny(id: entry.id))) },
            CardRowView.Button(title: "Allow") { [weak self] in self?.onAction?(.inbox(.allow(id: entry.id))) },
        ]
        if ask.readFromWords { buttons.append(CardRowView.Button(title: "Reply") { [weak self] in self?.reply(to: entry) }) }
        buttons.append(ignoreButton(entry))
        buttons.append(openButton(entry.threadID, in: book))
        return CardRowView(
            look: look(kitten, in: book),
            heading: heading(kitten, title: entry.threadTitle),
            at: entry.at,
            text: CatWords.askCard(ask, decision: ask.readFromWords ? entry.text : nil, by: kitten?.name ?? "The kitten"),
            answer: CatWords.askReview(ask),
            footer: entry.repliedAt == nil ? nil : CatWords.inboxSent,
            buttons: buttons
        )
    }

    private func ignoreButton(_ entry: InboxEntry) -> CardRowView.Button {
        CardRowView.Button(title: CatWords.ignore) { [weak self] in self?.onAction?(.inbox(.ignore(id: entry.id))) }
    }

    private func openButton(_ threadID: String, in book: ChannelBook) -> CardRowView.Button {
        guard book.threads[threadID] != nil, let home = book.home(ofThread: threadID) else {
            return CardRowView.Button(title: CatWords.openInT3, isWayOut: true) { [weak self] in self?.onOpenThread?(threadID) }
        }
        return CardRowView.Button(title: CatWords.viewThread, isWayOut: true) { [weak self] in self?.onOpen?(threadID, .channel(home), false, nil) }
    }

    private func stack() {
        stackedSize = scroll.contentSize
        let width = stackedSize.width
        let clipHeight = stackedSize.height
        let heights = views.map { $0.fit(width: width) }
        let total = heights.reduce(0, +) + Self.topPad + Self.bottomPad
        var y = isLoneNote ? max((clipHeight - total) / 2, 0) : Self.topPad
        frames = heights.map { height in
            defer { y += height }
            return NSRect(x: 0, y: y, width: width, height: height)
        }
        for (view, frame) in zip(views, frames) where view.superview === document && view.frame != frame {
            view.frame = frame
        }
        document.frame = NSRect(x: 0, y: 0, width: width, height: max(total, clipHeight))
    }

    private func attach() {
        let near = scroll.contentView.bounds.insetBy(dx: 0, dy: -Self.overscan)
        let typing = (window?.firstResponder as? NSView).flatMap { responder in views.first { responder.isDescendant(of: $0) } }
        for (view, frame) in zip(views, frames) {
            let wanted = frame.intersects(near) || view === typing
            if wanted, view.superview !== document {
                view.frame = frame
                document.addSubview(view)
            } else if !wanted, view.superview === document {
                view.removeFromSuperview()
            }
        }
    }

    private func listFocused(_ focused: Bool) {
        if focused, current.map({ row in !views.contains { $0 === row } }) ?? true {
            let seen = scroll.contentView.bounds
            let showing = views.indices.filter { views[$0].takesFocus && frames[$0].intersects(seen) }
            current = (followsLatest ? showing.last : showing.first).map { views[$0] }
        }
        current?.isFocused = focused
        if focused, let current { reveal(current) }
    }

    private func step(_ step: Int) {
        guard var index = current.flatMap({ row in views.firstIndex { $0 === row } }) else { return listFocused(true) }
        repeat {
            index += step
            if index < 0, first > 0 {
                let before = views.count
                layOutPageAbove()
                index += views.count - before
            }
        } while views.indices.contains(index) && !views[index].takesFocus
        guard views.indices.contains(index) else { return }
        current = views[index]
        reveal(views[index])
    }

    private func reveal(_ row: ChannelRowView) {
        guard let index = views.firstIndex(where: { $0 === row }) else { return }
        let frame = frames[index]
        let seen = scroll.contentView.bounds
        if frame.minY < seen.minY || frame.height > seen.height {
            scrollOffset = max(frame.minY - Self.topPad, 0)
        } else if frame.maxY > seen.maxY {
            scrollOffset = min(frame.maxY + Self.topPad - seen.height, bottomOffset)
        }
        attach()
    }

    private func keepCurrent() {
        if let row = current, views.contains(where: { $0 === row }) { return }
        current = nil
        if window?.firstResponder === list { listFocused(true) }
    }

    var currentRow: ChannelRowView? { current }

    var visibleHeight: CGFloat { scroll.contentSize.height }

    @objc private func scrolled(_ notification: Notification) {
        attach()
        pageIfNeeded()
        showJump()
    }

    private func showJump() {
        let line = newLine
        let above = line.map { $0.index < first || frames.indices.contains($0.index - first) && frames[$0.index - first].maxY <= scroll.contentView.bounds.minY } ?? false
        guard let line, above, !isHidden else {
            jump?.removeFromSuperview()
            jump = nil
            return
        }
        let title = CatWords.jumpToNew(line.count)
        if jump?.accessibilityLabel() != title {
            jump?.removeFromSuperview()
            let button = QuietButton(title, style: .filled) { [weak self] in self?.jumpToNew() }
            let shadow = NSShadow()
            shadow.shadowColor = Ink.hex(Opal.black).withAlphaComponent(Opal.shadowAlpha)
            shadow.shadowBlurRadius = 6
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            button.wantsLayer = true
            button.shadow = shadow
            addSubview(button, positioned: .above, relativeTo: scroll)
            jump = button
        }
        jump?.frame.origin = NSPoint(x: ((bounds.width - (jump?.frame.width ?? 0)) / 2).rounded(), y: ChannelHeader.height + 8)
    }

    func jumpToNew() {
        guard let line = newLine else { return }
        while first > line.index { layOutPageAbove() }
        guard frames.indices.contains(line.index - first) else { return }
        scrollOffset = min(max(frames[line.index - first].minY - Self.topPad, 0), bottomOffset)
        attach()
        showJump()
    }

    var jumpTitle: String? { jump?.accessibilityLabel() }

    private func pageIfNeeded() {
        guard !isPaging, book != nil else { return }
        isPaging = true
        while first > 0, scroll.contentView.bounds.minY < scroll.contentSize.height {
            let anchors = inSight
            layOutPageAbove()
            keep(anchors)
        }
        attach()
        isPaging = false
        if !isShowing, first == 0, views.first is OlderRowView, views.first?.superview === document { loadOlder() }
    }

    private func loadOlder() {
        guard case .older(isLoading: false)? = shown.first, let channel = selection.channelID else { return }
        onAction?(.older(channel))
    }

    private var inSight: [(view: ChannelRowView, above: CGFloat)] {
        let seen = scroll.contentView.bounds
        return frames.indices.reversed()
            .filter { frames[$0].maxY > seen.minY && frames[$0].minY < seen.maxY && !(views[$0] is OlderRowView) }
            .map { (views[$0], seen.minY - frames[$0].minY) }
    }

    private func layOutPageAbove() {
        guard let book else { return }
        let start = max(first - Self.page, 0)
        views = shown[start..<first].map { view(for: $0, in: book, among: shown) } + views
        first = start
        stack()
    }

    private func keep(_ anchors: [(view: ChannelRowView, above: CGFloat)]) {
        guard let anchor = anchors.first(where: { anchor in views.contains { $0 === anchor.view } }) else { return }
        while first > 0, let index = views.firstIndex(where: { $0 === anchor.view }), frames[index].minY + anchor.above < 0 {
            layOutPageAbove()
        }
        guard let index = views.firstIndex(where: { $0 === anchor.view }) else { return }
        scrollOffset = min(max(frames[index].minY + anchor.above, 0), bottomOffset)
    }

    private var isLoneNote: Bool {
        views.count == 1 && views[0] is NoteRowView
    }

    private var followsLatest: Bool { role == .thread || selection.channelID != nil }

    private var isNearBottom: Bool {
        distanceFromBottom <= Self.stickyDistance
    }

    private var bottomOffset: CGFloat {
        max(document.frame.height - scroll.contentSize.height, 0)
    }

    private func scrollToBottom() {
        scrollOffset = bottomOffset
    }
}
