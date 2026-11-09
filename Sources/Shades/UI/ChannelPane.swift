import AppKit
import ShadesCore

/// The top of a pane: the place you're looking at and a way to what its kitten has open, or for a thread, which
/// channel it's in, a way to T3 and a way to close it.
final class ChannelHeader: QuietView {
    static let height: CGFloat = 66
    /// What's under the title bar, so nothing clickable has to compete with dragging the window.
    private static let top: CGFloat = 24

    var onIssues: (() -> Void)?
    var onClose: (() -> Void)?
    var onOpen: (() -> Void)?
    var onNotifications: ((ChannelID, ChannelNotifications) -> Void)?
    private let notificationsMenu = NotificationsMenu()
    private var title = ""
    private var subtitle: String?
    private var cats: [ChannelSpeakerLook] = []
    private var buttons: [QuietButton] = []

    /// What the header says for a place, which a phone shows too.
    static func words(for place: ChannelPlace, in book: ChannelBook) -> (title: String, subtitle: String?) {
        switch place {
        case .activity:
            return (CatWords.activityTitle, CatWords.activitySubtitle)
        case .threads:
            return (CatWords.threadsTitle, CatWords.threadsSubtitle)
        case .channel(.general):
            return (book.title(of: .general), CatWords.generalSubtitle)
        case .channel(.shades):
            return (CatWords.shades, CatWords.shadesSubtitle)
        case .channel(let id):
            let status = book.statuses.first { .of($0.kitten) == id }
            return (book.title(of: id), status.map { "\($0.kitten.role) · \(CatWords.kittenState($0.state))" })
        }
    }

    /// For a thread: which channel it's in, then its title, project and how it's going.
    static func words(forThread id: String, in book: ChannelBook) -> (title: String, subtitle: String?) {
        let home = book.home(ofThread: id).map(book.title) ?? ""
        let name = book.title(ofThread: id)
        // The router's own folder isn't a project you'd know.
        let details = book.talks.contains(id) ? nil : book.listed[id].map(CatWords.threadDetails)
        let about = [name.isEmpty ? CatWords.newThread : name, details].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return (CatWords.threadTitle, [home, about].filter { !$0.isEmpty }.joined(separator: "  ·  "))
    }

    func show(_ place: ChannelPlace, in book: ChannelBook) {
        (title, subtitle) = Self.words(for: place, in: book)
        cats = []
        var right: [(String, () -> Void)] = []
        switch place {
        case .channel(.shades):
            cats = [ChannelSpeakerLook(.cat, in: book)]
        case .channel(.kitten(let kitten)):
            cats = [ChannelSpeakerLook(.kitten(kitten), in: book)]
            if let count = book.issues.first(where: { $0.kitten.id == kitten })?.threads.count, count > 0 {
                right = [(CatWords.issues(count), { [weak self] in self?.onIssues?() })]
            }
        case .activity, .threads, .channel(.general):
            break
        }
        if case .channel(let id) = place { right.append(notificationsButton(for: id, in: book)) }
        setButtons(right)
        describe()
    }

    /// Says when the channel's muted, so you know why it's quiet.
    private func notificationsButton(for id: ChannelID, in book: ChannelBook) -> (String, () -> Void) {
        let current = book.waiting.notifications[id.settingsKey] ?? ChannelNotifications()
        let phone = book.waiting.phone
        return (current.muted ? CatWords.muted : CatWords.notifications, { [weak self] in
            guard let self, let anchor = self.buttons.last else { return }
            self.notificationsMenu.show(current, phone: phone, under: anchor) { [weak self] in self?.onNotifications?(id, $0) }
        })
    }

    func show(thread id: String, in book: ChannelBook) {
        (title, subtitle) = Self.words(forThread: id, in: book)
        cats = []
        var right: [(String, () -> Void)] = []
        if book.knows(thread: id) { right.append((CatWords.openInT3, { [weak self] in self?.onOpen?() })) }
        right.append(("✕", { [weak self] in self?.onClose?() }))
        setButtons(right)
        buttons.last?.setAccessibilityLabel(CatWords.closeThread)
        describe()
    }

    private func describe() {
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel([title, subtitle].compactMap { $0 }.joined(separator: ", "))
        needsDisplay = true
    }

    private func setButtons(_ right: [(String, () -> Void)]) {
        buttons.forEach { $0.removeFromSuperview() }
        var edge = bounds.width - ChannelRowView.margin + 6
        buttons = right.reversed().map { title, action in
            let button = QuietButton(title, style: .text, onPress: action)
            edge -= button.frame.width
            button.frame.origin = NSPoint(x: edge, y: Self.top + 3)
            button.autoresizingMask = [.minXMargin]
            return button
        }.reversed()
        buttons.forEach(addSubview)
    }

    override func draw(_ dirtyRect: NSRect) {
        let side: CGFloat = 32
        var left = ChannelRowView.catLeft
        for (index, cat) in cats.enumerated() {
            let frame = NSRect(x: left + CGFloat(index) * side / 2, y: Self.top, width: side, height: side)
            CatStamp.draw(CatPose(frame: .sit), jacket: cat.jacket, in: frame, on: self)
        }
        left = cats.isEmpty ? left : left + side + CGFloat(cats.count - 1) * side / 2 + 12

        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        let room = (buttons.first?.frame.minX ?? bounds.width - ChannelRowView.margin) - left - 8
        let name = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: MessagesInk.text,
            .paragraphStyle: truncating,
        ])
        if let subtitle, !subtitle.isEmpty {
            name.draw(in: NSRect(x: left, y: Self.top - 1, width: room, height: 18))
            NSAttributedString(string: subtitle, attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: MessagesInk.soft,
                .paragraphStyle: truncating,
            ]).draw(in: NSRect(x: left, y: Self.top + 18, width: room, height: 14))
        } else {
            name.draw(in: NSRect(x: left, y: Self.top + 7, width: room, height: 18))
        }

        MessagesInk.line.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }
}

/// Answers to the parts of a question so far, by its ID, shared by both panes, since a question shows in Activity and
/// in its thread. Nothing goes until every part has one, as T3 wants.
final class PartAnswers {
    var answers: [String: [[String]]] = [:]
    /// The options picked so far for the part that's next, where it takes several.
    var picked: [String: [String]] = [:]
}

/// One side of the window: a header, then rows measured at the current width, then a box. The main pane shows a place
/// from the sidebar, and the thread pane beside it shows one thread, as Slack does. Only the rows near what you can
/// see are views in the window, and a long one lays out its newest rows first and older ones as you scroll up to
/// them, so it opens, scrolls and updates as quickly as a short one.
final class ChannelPane: QuietView {
    enum Role {
        /// Activity, Threads, a channel or the DM.
        case place
        /// One thread, beside the place it was opened from.
        case thread
    }

    /// Whose box it is: a place's, or a thread's.
    private enum Box: Hashable {
        case place(ChannelPlace)
        case thread(String)
    }

    /// Words typed in a box you've moved away from, and where they were going.
    private struct Draft {
        var text: String
        var target: MessageTarget
    }

    private static let stickyDistance: CGFloat = 40
    private static let topPad: CGFloat = 6
    private static let bottomPad: CGFloat = 14
    /// How many rows are laid out at a time.
    static let page = 60
    /// How far past what you can see rows are kept in the window, so scrolling finds them ready.
    private static let overscan: CGFloat = 600
    /// How many of a thread's newest rows its pane lays out when it opens. It's narrow, so that's still more than
    /// fills it, and opening one from the keyboard never waits on the rest.
    private var firstPage: Int { role == .thread ? Self.page / 2 : Self.page }
    /// How far a refresh looks ahead for a row it already has a view for, which covers rows coming and going at the top.
    private static let reuseReach = 64
    /// How many messages' laid-out words are kept between looks before only what's showing is.
    private static let wordsKept = 2_000

    let role: Role
    /// Opens a thread in T3.
    var onOpenThread: ((String) -> Void)?
    var onCopy: ((String) -> Void)?
    var onSelect: ((ChannelSelection) -> Void)?
    /// Opens a thread in the thread pane: from `place`, or where you are with `nil`. `typing` puts the keyboard in its
    /// box, and `report` is the inbox row whose Reply or Ask opened it.
    var onOpen: ((_ thread: String, _ place: ChannelPlace?, _ typing: Bool, _ report: InboxEntry?) -> Void)?
    var onClose: (() -> Void)?
    var onAction: ((MessagesAction) -> Void)?
    /// Makes a message in a thread, and everything after it, new to you again.
    var onMarkUnread: ((_ thread: String, _ message: String) -> Void)?
    /// Opens a web address, only ever after you've seen it in the link bar and pressed Open.
    var onOpenLink: ((URL) -> Void)?
    var parts = PartAnswers()

    private let now: () -> Date = Date.init
    private let header = ChannelHeader()
    private let scroll = QuietScrollView()
    private let document = QuietView()
    let composer = ChannelComposer()
    let linkBar = LinkBar()
    private(set) var selection: ChannelSelection = .activity
    private var book: ChannelBook?
    /// The inbox row whose Reply or Ask opened this thread, until you look elsewhere. All you send here is about it.
    private var replyingTo: InboxEntry?
    /// Where the box pointed when the talk key went down, so nothing arriving meanwhile can move what you say.
    private var spokenTo: (selection: ChannelSelection, target: MessageTarget, answered: Int)?
    /// What you'd typed in each place or thread you've moved away from, as Slack keeps a draft in each, so words only
    /// ever go where they were typed. It's in memory only.
    private var drafts: [Box: Draft] = [:]
    /// Words brought back to a box whose target went meanwhile, such as a question answered in T3. They wait there,
    /// and Return sends them nowhere else, until the box is cleared.
    private var held: MessageTarget?
    private(set) var shown: [ChannelRow] = [] {
        didSet { newLine = shown.indices.lazy.compactMap { index in if case .new(let count) = self.shown[index] { (index, count) } else { nil } }.first }
    }
    /// Where the New line is among them, and how much is new under it.
    private var newLine: (index: Int, count: Int)?
    /// Views for the rows from `first` on. Each is only in the window while it's near what you can see.
    private var views: [ChannelRowView] = []
    /// Where each of `views` goes. Moving a view that isn't in the window still costs, so it only moves once it's in.
    private var frames: [NSRect] = []
    private var first = 0
    private var words: [String: MessageWords] = [:]
    /// The state of each pull request, as the rows' chips show it.
    private var pulls: [String: String] = [:]
    private var expanded: Set<String> = []
    /// Where each thread's New line was when you came here, so it stays put once what's under it counts as seen.
    private var newFrom: [String: String] = [:]
    /// Up to the New line, while it's above what you can see.
    private var jump: QuietButton?
    private var stackedSize = NSSize.zero
    private var isPaging = false
    /// Showing something scrolls it too, but only you scrolling back to the top loads what's older.
    private var isShowing = false

    init(role: Role) {
        self.role = role
        super.init(frame: .zero)
        scroll.documentView = document
        addSubview(scroll)
        addSubview(header)
        addSubview(composer)
        addSubview(linkBar)
        linkBar.onOpen = { [weak self] link in
            self?.showLink(nil)
            if Markup.opens(link) { self?.onOpenLink?(link) }
        }
        linkBar.onCancel = { [weak self] in self?.showLink(nil) }
        header.onIssues = { [weak self] in self?.onSelect?(.activity) }
        header.onClose = { [weak self] in self?.onClose?() }
        header.onNotifications = { [weak self] in self?.onAction?(.notifications($0, $1)) }
        header.onOpen = { [weak self] in
            guard let self, let id = self.selection.thread else { return }
            self.onOpenThread?(id)
        }
        composer.onSend = { [weak self] words, target, file in
            guard let self else { return }
            switch target {
            case .question(let question):
                guard self.part(of: question)?.part.takesOwnWords == true else {
                    NSSound.beep()
                    self.composer.textView.string = words
                    return
                }
                self.answer(question, with: [words])
            case .newThread(let kitten):
                // The new thread opens in the pane, and the keyboard goes with it if you were typing.
                let topic = "sent-\(UUID().uuidString)"
                let typing = self.window?.firstResponder === self.composer.textView
                self.onAction?(.startTopic(words, with: kitten, id: topic, file: file))
                self.onOpen?(topic, nil, typing, nil)
            case .thread(let id, _, _):
                let alsoSent = self.composer.alsoSends
                self.composer.alsoSends = false
                self.onAction?(.send(words, to: target, shownIn: self.book?.home(ofThread: id), alsoSent: alsoSent, file: file))
                self.updateComposer()
                self.arrange(force: true)
            default:
                self.onAction?(.send(words, to: target, shownIn: self.selection.channelID, file: file))
                self.updateComposer()
                self.arrange(force: true)
            }
        }
        composer.onResize = { [weak self] in self?.typed() }
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

    /// What this pane shows of a selection: the place, or the thread.
    private func shows(_ selection: ChannelSelection) -> Box? {
        switch role {
        case .place: return .place(selection.place)
        case .thread: return selection.thread.map(Box.thread)
        }
    }

    /// Whose box a selection has. A new topic's is still its own once T3 has started its thread.
    private func box(of selection: ChannelSelection, in book: ChannelBook) -> Box? {
        guard role == .thread, let thread = selection.thread else { return shows(selection) }
        return .thread(book.started[thread] ?? thread)
    }

    /// Showing something new shows its latest. A refresh only follows along if you were already at the bottom.
    func show(_ selection: ChannelSelection, in book: ChannelBook, isNewSelection: Bool) {
        isShowing = true
        defer { isShowing = false }
        let isNewSelection = isNewSelection || shows(selection) != shows(self.selection)
        if let thread = selection.thread, thread == replyingTo?.threadID {} else { replyingTo = nil }
        parts.answers = parts.answers.filter { id, _ in book.waiting.questions.contains { $0.id == id } }
        parts.picked = parts.picked.filter { id, _ in book.waiting.questions.contains { $0.id == id } }
        // What you'd typed in a new topic waits in the thread T3 started for it.
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
            header.show(selection.place, in: book)
            rows = ChannelRows.rows(selection.place, in: book, newFrom: newFrom)
        case .thread:
            guard let thread = selection.thread else { return }
            header.show(thread: thread, in: book)
            rows = ChannelRows.thread(thread, in: book, newFrom: newFrom)
        }
        let pullsChanged = book.pulls != pulls
        pulls = book.pulls
        // A pull request's chip changes with its state, which the rows themselves don't say.
        if pullsChanged, !isNewSelection, rows == shown { return restyle() }
        guard isNewSelection || rows != shown else { return }

        let wasAtBottom = isNearBottom
        let anchors = isNewSelection ? [] : inSight
        // Following along at the bottom goes back to the newest page, so what's laid out doesn't keep growing.
        let start = followsLatest ? (isNewSelection || wasAtBottom ? max(rows.count - firstPage, 0) : refreshedStart(in: rows)) : 0
        // A refresh keeps the view of each row that's still there, wherever it's moved to.
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
            let showing = Set(rows.compactMap { row -> String? in
                switch row {
                case .message(let message), .alsoSent(let message, _, _): return message.id
                case .parent(let post): return post.parent.id
                default: return nil
                }
            })
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
        // Older posts that came in above what you're reading are laid out the way scrolling up to them would.
        pageIfNeeded()
        if pullsChanged, !isNewSelection { restyle() }
        showJump()
    }

    /// A link pressed in one of this pane's messages. It only shows where the link goes, and Open in the bar is what
    /// opens it, so nothing a kitten writes can open anything by itself. Only web addresses are links at all.
    @objc func ask(toOpen link: URL) {
        guard Markup.opens(link) else { return NSSound.beep() }
        showLink(link)
    }

    private func showLink(_ link: URL?) {
        linkBar.show(link)
        arrange()
    }

    /// Where the laid-out rows start after a refresh: at the first row still there, or as many from the end.
    private func refreshedStart(in rows: [ChannelRow]) -> Int {
        guard shown.indices.contains(first) else { return max(rows.count - Self.page, 0) }
        return shown[first...].prefix(Self.reuseReach).lazy.compactMap { rows.firstIndex(of: $0) }.first ?? max(rows.count - (shown.count - first), 0)
    }

    /// Makes every row again in the colours there are now, where you were. A pane that's closed lets its rows go
    /// instead, and makes them when it next opens.
    func restyle() {
        composer.restyle()
        header.needsDisplay = true
        // Made again in the new colours.
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
        showJump()
    }

    /// Puts the keyboard in the box, since choosing to reply means you're about to type. The panel never activates
    /// Shades, so your app stays in front.
    func focusComposer() {
        guard composer.target != nil else { return }
        window?.makeKey()
        window?.makeFirstResponder(composer.textView)
    }

    /// Another thread, or none, is open now. Coming back some other way than Reply on its report is just the thread,
    /// and Also send was for a reply in this one.
    func leaveThread() {
        replyingTo = nil
        composer.alsoSends = false
    }

    /// What you send here stops that report asking and gets its answer. Words already in the box still go where they
    /// were going.
    func replying(to entry: InboxEntry?) {
        replyingTo = entry
        updateComposer(keepingDraft: true)
        arrange(force: true)
    }

    /// Opens a report's thread beside its channel, ready to type.
    func reply(to entry: InboxEntry) {
        onOpen?(entry.threadID, .channel(book?.home(of: book?.kitten(of: entry.id)) ?? .general), true, entry)
    }

    /// Leaves what you'd typed where you typed it, and brings back what you'd typed in `selection`'s box, still going
    /// where it was then. That's `nil` if there's nothing to bring back.
    private func swapDraft(for selection: ChannelSelection, in book: ChannelBook) -> MessageTarget? {
        if let left = box(of: self.selection, in: book) {
            drafts[left] = composer.hasDraft ? composer.target.map { Draft(text: composer.textView.string, target: $0) } : nil
        }
        held = nil
        let draft = box(of: selection, in: book).flatMap { drafts.removeValue(forKey: $0) }
        composer.showDraft(draft?.text ?? "")
        guard let draft else { return nil }
        // A new topic that's started moves on to its thread. Anything else that's gone keeps your words waiting.
        if case .starting = draft.target {} else if !draft.target.isStill(in: book) { held = draft.target }
        return draft.target
    }

    /// Once held words are cleared away, the box points wherever it would now.
    private func typed() {
        if held != nil, !composer.hasDraft { updateComposer() }
        arrange(force: true)
    }

    /// `typedFor` is where a draft that's just been brought back was going.
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
                    // Even a thread T3 no longer lists, such as an archived one, takes a reply to its report.
                    // A question waiting in the same thread doesn't take words meant for the report. Type an answer is for that.
                    if let replyingTo, replyingTo.threadID == thread, !book.talks.contains(thread) {
                        let title = book.title(ofThread: thread)
                        target = .thread(id: thread, title: title.isEmpty ? replyingTo.threadTitle : title, report: replyingTo.id)
                    }
                }
            }
        }
        // Words already typed go where the box said when you started, so a refresh can't send them somewhere else.
        if let spokenTo, spokenTo.selection == selection { target = spokenTo.target }
        if composer.hasDraft, let typedFor = restored ?? (keepingDraft ? composer.target : nil), let book, typedFor.isStill(in: book) {
            target = typedFor
        }
        if !composer.hasDraft { held = nil }
        if let held { target = held }
        if case .thread(let id, _, _)? = target, let home = book?.home(ofThread: id), home != .shades {
            also = book.map { CatWords.alsoSendTo($0.title(of: home)) }
        }
        var label: String?
        if case .question(let question)? = target, let part = part(of: question) { label = CatWords.answering(part.part.text) }
        if held != nil { label = CatWords.heldDraft }
        let channel = selection.channelID
        composer.isHeld = held != nil
        composer.show(target, label: label, in: channel, name: channel.flatMap { book?.name(of: $0) }, alsoSendTo: also)
    }

    /// The talk key went down while you were typing here.
    func startSpeaking() {
        spokenTo = composer.target.map { target in
            let answered = if case .question(let question) = target { parts.answers[question.id]?.count ?? 0 } else { 0 }
            return (selection, target, answered)
        }
    }

    /// What you said goes after anything you'd typed, and is sent where the box pointed when you started, as if you'd
    /// pressed Return. If that's gone, such as a question answered meanwhile, it waits in the box instead.
    func spoke(_ text: String) {
        let spot = spokenTo
        spokenTo = nil
        // Said for a box you've since moved away from, it waits there after whatever you'd typed.
        if let spot, let book, let away = box(of: spot.selection, in: book), away != box(of: selection, in: book) {
            let typed = drafts[away]?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            drafts[away] = Draft(text: typed.isEmpty ? text : "\(typed) \(text)", target: drafts[away]?.target ?? spot.target)
            NSSound.beep()
            return
        }
        let typed = composer.textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = typed.isEmpty ? text : "\(typed) \(text)"
        // A question in parts has to be on the same part, or what you said would answer the next one.
        let samePart = if case .question(let question) = spot?.target { parts.answers[question.id]?.count ?? 0 == spot?.answered } else { true }
        guard let spot, spot.selection == selection, let book, spot.target.isReady, spot.target.isStill(in: book), samePart else {
            composer.textView.string = words
            updateComposer(keepingDraft: true)
            arrange(force: true)
            NSSound.beep()
            return
        }
        composer.textView.string = ""
        composer.onSend?(words, spot.target, composer.takeAttachment())
        arrange(force: true)
    }

    func stopSpeaking() {
        spokenTo = nil
        updateComposer(keepingDraft: true)
        arrange(force: true)
    }

    /// The part of a question that's next to answer.
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

    /// For a row whose look changed while its value didn't.
    private func rebuild(_ row: ChannelRow) {
        guard let book, let index = shown.firstIndex(of: row), index >= first else { return }
        let fresh = view(for: row, in: book, among: shown)
        views[index - first].removeFromSuperview()
        views[index - first] = fresh
        stack()
        attach()
    }

    /// Times are worked out as they're drawn, so a redraw brings them up to date. Rows out of the window are drawn
    /// fresh when they come back.
    func refreshTimes() {
        document.subviews.forEach { $0.needsDisplay = true }
    }

    var longMessageRow: MessageRowView? {
        shownMessageRows.first(where: \.isCut)
    }

    /// Every message laid out so far, in the window or not.
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

    // MARK: Rows

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
            return view
        case .replies(let count):
            return RepliesRowView(count: count)
        case .new(let count):
            return NewRowView(count: count)
        case .heading(let status):
            return HeadingRowView(status: status)
        case .issue(let thread):
            let view = IssueRowView(thread: thread, now: now)
            // A thread Messages has read opens beside its channel, and anything else in T3.
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

    /// Deny comes first and nothing is pressed by Return, so allowing always takes a click of its own.
    private func card(for request: ApprovalRequest, in book: ChannelBook) -> CardRowView {
        let kitten = book.kitten(of: request.id)
        var buttons = [
            CardRowView.Button(title: "Deny") { [weak self] in self?.onAction?(.approval(request, .decline)) },
            CardRowView.Button(title: "Allow") { [weak self] in self?.onAction?(.approval(request, .accept)) },
        ]
        if ApprovalPolicy.offersSessionAllow(request.kind) {
            buttons.append(CardRowView.Button(title: "Allow for this session") { [weak self] in self?.onAction?(.approval(request, .acceptForSession)) })
        }
        buttons.append(openButton(book.thread(holding: request.id, else: request.threadID), in: book))
        return CardRowView(look: look(kitten, in: book), heading: heading(kitten, title: request.threadTitle), at: request.createdAt, text: request.summary, buttons: buttons)
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
            // Picking only marks an option, so nothing goes until you press this.
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

    /// The thread beside where it lives, once Messages has read it. T3 is only for the rest.
    private func openButton(_ threadID: String, in book: ChannelBook) -> CardRowView.Button {
        guard book.threads[threadID] != nil, let home = book.home(ofThread: threadID) else {
            return CardRowView.Button(title: CatWords.openInT3, isWayOut: true) { [weak self] in self?.onOpenThread?(threadID) }
        }
        return CardRowView.Button(title: CatWords.viewThread, isWayOut: true) { [weak self] in self?.onOpen?(threadID, .channel(home), false, nil) }
    }

    /// Lays out every row that has a view. A row only draws again when its size changes or it comes back into the window.
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

    /// Puts the rows near what you can see in the window and takes the rest out, except one you're selecting words in.
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

    /// How tall the part of the pane you can scroll through is.
    var visibleHeight: CGFloat { scroll.contentSize.height }

    @objc private func scrolled(_ notification: Notification) {
        attach()
        pageIfNeeded()
        showJump()
    }

    /// A way up to the New line while it's above what you can see, saying how much is new under it.
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
            button.colors = (MessagesInk.link, MessagesInk.onLink)
            // It floats over messages, which can be the same colour.
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.shadowBlurRadius = 6
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            button.wantsLayer = true
            button.shadow = shadow
            addSubview(button, positioned: .above, relativeTo: scroll)
            jump = button
        }
        jump?.frame.origin = NSPoint(x: ((bounds.width - (jump?.frame.width ?? 0)) / 2).rounded(), y: ChannelHeader.height + 8)
    }

    /// Scrolls up so the New line is at the top, laying out what's above first if it has to.
    func jumpToNew() {
        guard let line = newLine else { return }
        while first > line.index { layOutPageAbove() }
        guard frames.indices.contains(line.index - first) else { return }
        scrollOffset = min(max(frames[line.index - first].minY - Self.topPad, 0), bottomOffset)
        attach()
        showJump()
    }

    /// Whether the way up to the New line is showing, and what it says.
    var jumpTitle: String? { jump?.accessibilityLabel() }

    /// Scrolling up near the oldest row laid out lays out the page before it, without moving what you're looking at.
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

    /// Scrolled back near the top of a channel with older posts, it loads them, as Slack does.
    private func loadOlder() {
        guard case .older(isLoading: false)? = shown.first, let channel = selection.channelID else { return }
        onAction?(.older(channel))
    }

    /// The rows you can see, lowest first, and how far above the top of the pane each starts. Never Load older, which
    /// goes once it has. An older thread comes in where it started, which can be among what you're reading, so keeping
    /// the lowest row moves the least of it.
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

    /// The lowest of them that's still there stays where it was, with rows that came in above it laid out first.
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

    // MARK: Scrolling

    /// A conversation keeps its latest in view, as a chat does. Activity and Threads read from the top.
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
