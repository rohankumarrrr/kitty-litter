import AppKit
import ShadesCore

/// The top of the pane: who you're looking at, and a way to what they've got open.
final class ChannelHeader: QuietView {
    static let height: CGFloat = 66
    /// What's under the title bar, so nothing clickable has to compete with dragging the window.
    private static let top: CGFloat = 24

    var onIssues: (() -> Void)?
    private var title = ""
    private var subtitle: String?
    private var cats: [ChannelSpeakerLook] = []
    private var issuesButton: QuietButton?

    func show(_ selection: ChannelSelection, in book: ChannelBook) {
        var issues: Int?
        switch selection {
        case .needsYou:
            title = CatWords.needsYouTitle
            subtitle = CatWords.needsYouSubtitle
            cats = []
        case .channel(.everyone):
            title = CatWords.everyone
            subtitle = CatWords.everyoneSubtitle
            cats = []
        case .channel(let id):
            let others = book.others(in: id)
            title = book.title(of: id)
            cats = others.map { ChannelSpeakerLook($0, in: book) }
            let status = others.count == 1 ? book.status(of: others[0]) : nil
            subtitle = status.map { "\($0.kitten.role) · \(CatWords.kittenState($0.state))" }
            issues = status.flatMap { status in book.issues.first { $0.kitten == status.kitten }?.threads.count }
        }
        setIssues(issues)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel([title, subtitle].compactMap { $0 }.joined(separator: ", "))
        needsDisplay = true
    }

    private func setIssues(_ count: Int?) {
        issuesButton?.removeFromSuperview()
        issuesButton = nil
        guard let count, count > 0 else { return }
        let button = QuietButton(CatWords.issues(count), style: .text) { [weak self] in self?.onIssues?() }
        button.frame.origin = NSPoint(x: bounds.width - ChannelRowView.margin - button.frame.width + 6, y: Self.top + 3)
        button.autoresizingMask = [.minXMargin]
        addSubview(button)
        issuesButton = button
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
        let room = (issuesButton?.frame.minX ?? bounds.width - ChannelRowView.margin) - left - 8
        let name = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: Ink.text,
            .paragraphStyle: truncating,
        ])
        if let subtitle {
            name.draw(in: NSRect(x: left, y: Self.top - 1, width: room, height: 18))
            NSAttributedString(string: subtitle, attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: Ink.soft,
                .paragraphStyle: truncating,
            ]).draw(in: NSRect(x: left, y: Self.top + 18, width: room, height: 14))
        } else {
            name.draw(in: NSRect(x: left, y: Self.top + 7, width: room, height: 18))
        }

        Ink.line.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }
}

/// The right side of the window: a header, then rows measured at the current width.
final class ChannelPane: QuietView {
    private static let stickyDistance: CGFloat = 40
    private static let topPad: CGFloat = 6
    private static let bottomPad: CGFloat = 14

    var onOpenThread: ((String) -> Void)?
    var onCopy: ((String) -> Void)?
    var onSelect: ((ChannelSelection) -> Void)?
    var onAction: ((MessagesAction) -> Void)?

    private let now: () -> Date = Date.init
    private let header = ChannelHeader()
    private let scroll = QuietScrollView()
    private let document = QuietView()
    let composer = ChannelComposer()
    private var selection: ChannelSelection = .needsYou
    private var book: ChannelBook?
    /// Somewhere you chose to send to instead of the usual. It holds until you send or look elsewhere.
    private var picked: MessageTarget?
    private(set) var shown: [ChannelRow] = []
    private var views: [ChannelRowView] = []
    private var expanded: Set<String> = []
    private var stackedSize = NSSize.zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        scroll.documentView = document
        addSubview(scroll)
        addSubview(header)
        addSubview(composer)
        header.onIssues = { [weak self] in self?.onSelect?(.needsYou) }
        composer.onSend = { [weak self] words, target in
            guard let self else { return }
            let shownIn: ChannelID? = if case .channel(let id) = self.selection { id } else { nil }
            self.picked = nil
            self.onAction?(.send(words, to: target, shownIn: shownIn))
            self.updateComposer()
            self.arrange(force: true)
        }
        composer.onRetarget = { [weak self] in self?.pick($0) }
        composer.onResize = { [weak self] in self?.arrange(force: true) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        arrange()
    }

    func arrange(force: Bool = false) {
        let box = composer.height
        header.frame = NSRect(x: 0, y: 0, width: bounds.width, height: ChannelHeader.height)
        scroll.frame = NSRect(x: 0, y: ChannelHeader.height, width: bounds.width, height: max(bounds.height - ChannelHeader.height - box, 0))
        composer.frame = NSRect(x: 0, y: bounds.height - box, width: bounds.width, height: box)
        if force { composer.needsLayout = true }
        guard stackedSize != scroll.contentSize else { return }
        let wasAtBottom = isNearBottom
        stack()
        if wasAtBottom { scrollToBottom() }
    }

    /// Selecting something shows its latest. A refresh only follows along if you were already at the bottom.
    func show(_ selection: ChannelSelection, in book: ChannelBook, isNewSelection: Bool) {
        let isNew = isNewSelection || selection != self.selection
        if isNew { picked = nil }
        self.selection = selection
        self.book = book
        updateComposer(keepingDraft: !isNew)
        arrange()
        header.show(selection, in: book)
        let rows = ChannelRows.rows(selection, in: book)
        guard isNewSelection || rows != shown else { return }

        let wasAtBottom = isNearBottom
        let kept = isNewSelection ? 0 : zip(shown, rows).prefix { $0 == $1 }.count
        views[kept...].forEach { $0.removeFromSuperview() }
        views = Array(views[..<kept]) + rows[kept...].map { view(for: $0, in: book, among: rows, selection: selection) }
        for view in views[kept...] { document.addSubview(view) }
        shown = rows
        stack()

        if isNewSelection {
            scrollOffset = selection == .needsYou ? 0 : bottomOffset
        } else if wasAtBottom {
            scrollToBottom()
        }
    }

    /// Nothing on the screen is kept once the window closes.
    func forget() {
        views.forEach { $0.removeFromSuperview() }
        views = []
        shown = []
        expanded = []
        book = nil
        picked = nil
        composer.clear()
        stack()
    }

    /// Typing goes here next, or back where it usually goes for `nil`.
    func pick(_ target: MessageTarget?) {
        picked = target
        updateComposer()
        arrange(force: true)
        // Choosing where to reply means you're about to type. The panel never activates Shades, so your app stays in front.
        if target != nil {
            window?.makeKey()
            window?.makeFirstResponder(composer.textView)
        }
    }

    private func updateComposer(keepingDraft: Bool = false) {
        var target = book.flatMap { picked ?? MessageTarget.standard(for: selection, in: $0) }
        // Words already typed go where the box said when you started, so a refresh can't send them somewhere else.
        if keepingDraft, picked == nil, composer.hasDraft, let current = composer.target, let book, current.isStill(in: book) {
            target = current
        }
        let kitten: Kitten? = if case .channel(let id) = selection {
            book?.statuses.first { id == .direct($0.kitten) && $0.state != .notSetUp }?.kitten
        } else { nil }
        composer.show(target, picked: picked != nil, kitten: kitten)
    }

    /// Replying is only offered where there's a box to reply from.
    private var canReply: Bool {
        book.map { MessageTarget.standard(for: selection, in: $0) != nil } ?? false
    }

    /// Times are worked out as they're drawn, so a redraw brings them up to date.
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

    // MARK: Rows

    private func view(for row: ChannelRow, in book: ChannelBook, among rows: [ChannelRow], selection: ChannelSelection) -> ChannelRowView {
        switch row {
        case .day(let date):
            return DayRowView(date: date, now: now)
        case .subject(let title, let threadID):
            let view = SubjectRowView(title: title)
            view.onPress = { [weak self] in self?.onOpenThread?(threadID) }
            return view
        case .message(let message):
            let view = MessageRowView(message: message, look: ChannelSpeakerLook(message.speaker, in: book))
            view.isExpanded = expanded.contains(message.id)
            if canReply, !message.threadID.isEmpty {
                view.onReply = { [weak self] in self?.pick(.thread(id: message.threadID, title: message.threadTitle)) }
            }
            if !message.threadID.isEmpty { view.onOpen = { [weak self] in self?.onOpenThread?(message.threadID) } }
            view.onCopy = { [weak self] in self?.onCopy?($0) }
            view.onShowMore = { [weak self, weak view] in
                self?.expanded.insert(message.id)
                view?.isExpanded = true
                self?.stack()
            }
            return view
        case .heading(let status):
            return HeadingRowView(status: status)
        case .issue(let thread):
            let view = IssueRowView(thread: thread, now: now)
            view.onPress = { [weak self] in self?.onOpenThread?(thread.id) }
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
            return NoteRowView(text: text, isCentered: selection != .needsYou || rows.count == 1)
        }
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
        buttons.append(openButton(request.threadID))
        return CardRowView(look: look(kitten, in: book), heading: heading(kitten, title: request.threadTitle), at: request.createdAt, text: request.summary, buttons: buttons)
    }

    private func card(for question: AgentQuestion, in book: ChannelBook) -> CardRowView {
        let kitten = book.kitten(of: question.id)
        var buttons: [CardRowView.Button] = []
        if let form = question.form {
            buttons = question.options.indices.filter { form.values.indices.contains($0) }.map { index in
                CardRowView.Button(title: question.options[index]) { [weak self] in self?.onAction?(.pick(question, option: index)) }
            }
            if form.takesOwnWords {
                buttons.append(CardRowView.Button(title: CatWords.answerInWords) { [weak self] in self?.pick(.question(question)) })
            }
        }
        buttons.append(openButton(question.threadID))
        let text = question.text.isEmpty ? CatWords.unreadableQuestion : question.text
        let footer = question.form == nil ? CatWords.answerInT3 : nil
        return CardRowView(look: look(kitten, in: book), heading: heading(kitten, title: question.threadTitle), at: nil, text: text, footer: footer, buttons: buttons)
    }

    private func card(for entry: InboxEntry, in book: ChannelBook) -> CardRowView {
        let kitten = book.kitten(of: entry.id)
        let reply = CardRowView.Button(title: entry.kind == .decision ? "Reply" : "Ask") { [weak self] in
            self?.pick(.thread(id: entry.threadID, title: entry.threadTitle))
        }
        var buttons = [reply]
        if entry.kind == .decision {
            buttons.append(CardRowView.Button(title: "Done") { [weak self] in self?.onAction?(.inbox(.done(id: entry.id))) })
        }
        buttons.append(openButton(entry.threadID))
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

    private func openButton(_ threadID: String) -> CardRowView.Button {
        CardRowView.Button(title: "Open in T3", isWayOut: true) { [weak self] in self?.onOpenThread?(threadID) }
    }

    private func stack() {
        stackedSize = scroll.contentSize
        let width = stackedSize.width
        let clipHeight = stackedSize.height
        let heights = views.map { $0.fit(width: width) }
        let total = heights.reduce(0, +) + Self.topPad + Self.bottomPad
        var y = isLoneNote ? max((clipHeight - total) / 2, 0) : Self.topPad
        for (view, height) in zip(views, heights) {
            view.frame = NSRect(x: 0, y: y, width: width, height: height)
            view.needsDisplay = true
            y += height
        }
        document.frame = NSRect(x: 0, y: 0, width: width, height: max(total, clipHeight))
    }

    private var isLoneNote: Bool {
        views.count == 1 && views[0] is NoteRowView
    }

    // MARK: Scrolling

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
