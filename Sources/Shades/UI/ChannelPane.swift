import AppKit
import ShadesCore

/// The top of the pane: who you're looking at, and a way to what they've got open. In a thread, a way back to its
/// channel, and which thread and project it is.
final class ChannelHeader: QuietView {
    static let height: CGFloat = 66
    /// What's under the title bar, so nothing clickable has to compete with dragging the window.
    private static let top: CGFloat = 24

    var onIssues: (() -> Void)?
    var onBack: (() -> Void)?
    var onOpen: (() -> Void)?
    private var title = ""
    private var subtitle: String?
    private var cats: [ChannelSpeakerLook] = []
    private var rightButton: QuietButton?
    private var backButton: QuietButton?

    func show(_ selection: ChannelSelection, in book: ChannelBook) {
        var right: (title: String, action: () -> Void)?
        var back: String?
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
            if let count = status.flatMap({ status in book.issues.first { $0.kitten == status.kitten }?.threads.count }), count > 0 {
                right = (CatWords.issues(count), { [weak self] in self?.onIssues?() })
            }
        case .thread(let id, let channel):
            let name = book.title(ofThread: id, in: channel)
            title = name.isEmpty ? CatWords.newTopic : name
            subtitle = book.threads[id].map(CatWords.threadDetails)
            cats = []
            back = CatWords.back(to: book.title(of: channel))
            if book.knows(thread: id, in: channel) { right = (CatWords.openInT3, { [weak self] in self?.onOpen?() }) }
        }
        setButtons(right: right, back: back)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel([title, subtitle].compactMap { $0 }.joined(separator: ", "))
        needsDisplay = true
    }

    private func setButtons(right: (title: String, action: () -> Void)?, back: String?) {
        rightButton?.removeFromSuperview()
        backButton?.removeFromSuperview()
        rightButton = right.map { right in
            let button = QuietButton(right.title, style: .text, onPress: right.action)
            button.frame.origin = NSPoint(x: bounds.width - ChannelRowView.margin - button.frame.width + 6, y: Self.top + 3)
            button.autoresizingMask = [.minXMargin]
            return button
        }
        backButton = back.map { back in
            let button = QuietButton(back, style: .text) { [weak self] in self?.onBack?() }
            button.frame.origin = NSPoint(x: ChannelRowView.catLeft - 6, y: Self.top + 3)
            return button
        }
        for button in [rightButton, backButton].compactMap({ $0 }) { addSubview(button) }
    }

    override func draw(_ dirtyRect: NSRect) {
        let side: CGFloat = 32
        var left = ChannelRowView.catLeft
        for (index, cat) in cats.enumerated() {
            let frame = NSRect(x: left + CGFloat(index) * side / 2, y: Self.top, width: side, height: side)
            CatStamp.draw(CatPose(frame: .sit), jacket: cat.jacket, in: frame, on: self)
        }
        left = cats.isEmpty ? left : left + side + CGFloat(cats.count - 1) * side / 2 + 12
        if let backButton { left = backButton.frame.maxX + 6 }

        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        let room = (rightButton?.frame.minX ?? bounds.width - ChannelRowView.margin) - left - 8
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
    /// Answers to the parts of a question so far, by its ID. Nothing goes until every part has one, as T3 wants.
    private var partAnswers: [String: [String]] = [:]
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
        header.onBack = { [weak self] in
            guard let self else { return }
            self.onSelect?(self.selection.place)
        }
        header.onOpen = { [weak self] in
            guard let self, case .thread(let id, _) = self.selection else { return }
            self.onOpenThread?(id)
        }
        composer.onSend = { [weak self] words, target in
            guard let self else { return }
            switch target {
            case .question(let question):
                guard self.part(of: question)?.part.takesOwnWords == true else {
                    NSSound.beep()
                    self.composer.textView.string = words
                    return
                }
                self.answer(question, with: words)
            case .newThread(let kitten):
                // The new topic opens on its own, so what you add next goes into it too.
                let topic = "sent-\(UUID().uuidString)"
                self.onAction?(.startTopic(words, with: kitten, id: topic))
                self.onSelect?(.thread(topic, in: .direct(kitten)))
            default:
                self.onAction?(.send(words, to: target, shownIn: self.selection.channelID))
                self.updateComposer()
                self.arrange(force: true)
            }
        }
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
        partAnswers = partAnswers.filter { id, _ in book.waiting.questions.contains { $0.id == id } }
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
        partAnswers = [:]
        composer.clear()
        stack()
    }

    /// Opens a thread on its own, where the box goes only into it. Choosing to reply means you're about to type, so
    /// the box takes the keyboard then. The panel never activates Shades, so your app stays in front.
    func open(thread id: String, in channel: ChannelID, typing: Bool) {
        onSelect?(.thread(id, in: channel))
        guard typing else { return }
        window?.makeKey()
        window?.makeFirstResponder(composer.textView)
    }

    /// Where an approval, question or report is talked about: its kitten's DM, or Everyone for the cat's own work.
    private func channel(of kitten: Kitten?) -> ChannelID {
        kitten.map(ChannelID.direct) ?? .everyone
    }

    private func updateComposer(keepingDraft: Bool = false) {
        var target = book.flatMap { MessageTarget.standard(for: selection, in: $0, answered: partAnswers.mapValues(\.count)) }
        // Words already typed go where the box said when you started, so a refresh can't send them somewhere else.
        if keepingDraft, composer.hasDraft, let current = composer.target, let book, current.isStill(in: book) {
            target = current
        }
        var label: String?
        if case .question(let question)? = target, let part = part(of: question) { label = CatWords.answering(part.part.text) }
        composer.show(target, label: label)
    }

    /// The part of a question that's next to answer.
    private func part(of question: AgentQuestion) -> (index: Int, part: AnswerForm.Part)? {
        guard let parts = question.form?.parts else { return nil }
        let index = partAnswers[question.id]?.count ?? 0
        return parts.indices.contains(index) ? (index, parts[index]) : nil
    }

    private func answer(_ question: AgentQuestion, with answer: String) {
        let answers = (partAnswers[question.id] ?? []) + [answer]
        if answers.count >= question.form?.parts.count ?? 1 {
            partAnswers[question.id] = nil
            onAction?(.answer(question, answers))
        } else {
            partAnswers[question.id] = answers
            rebuild(.question(question))
        }
        updateComposer()
        arrange(force: true)
    }

    /// For a row whose look changed while its value didn't.
    private func rebuild(_ row: ChannelRow) {
        guard let book, let index = shown.firstIndex(of: row) else { return }
        let fresh = view(for: row, in: book, among: shown, selection: selection)
        views[index].removeFromSuperview()
        views[index] = fresh
        document.addSubview(fresh)
        stack()
    }

    /// Replying in a thread is offered from a channel you can write in. In the thread itself, the box already does it.
    private var canReply: Bool {
        guard case .channel = selection, let book else { return false }
        return MessageTarget.standard(for: selection, in: book) != nil
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
        case .subject(let title, let project, let threadID):
            let view = SubjectRowView(title: title, project: project)
            if let channel = selection.channelID { view.onPress = { [weak self] in self?.open(thread: threadID, in: channel, typing: false) } }
            return view
        case .message(let message):
            let view = MessageRowView(message: message, look: ChannelSpeakerLook(message.speaker, in: book))
            view.isExpanded = expanded.contains(message.id)
            if canReply, !message.threadID.isEmpty, let channel = selection.channelID {
                view.onReply = { [weak self] in self?.open(thread: message.threadID, in: channel, typing: true) }
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
        var text = question.text
        if let (index, part) = part(of: question) {
            text = CatWords.part(index, of: question.form?.parts.count ?? 1, part.text)
            buttons = part.options.indices.filter { part.values.indices.contains($0) }.map { option in
                CardRowView.Button(title: part.options[option]) { [weak self] in self?.answer(question, with: part.values[option]) }
            }
            if part.takesOwnWords {
                let thread = book.thread(holding: question.id, else: question.threadID)
                buttons.append(CardRowView.Button(title: CatWords.answerInWords) { [weak self] in
                    guard let self else { return }
                    self.open(thread: thread, in: self.channel(of: kitten), typing: true)
                })
            }
        }
        buttons.append(openButton(question.threadID))
        text = text.isEmpty ? CatWords.unreadableQuestion : text
        let footer = question.form == nil ? CatWords.answerInT3 : nil
        return CardRowView(look: look(kitten, in: book), heading: heading(kitten, title: question.threadTitle), at: nil, text: text, footer: footer, buttons: buttons)
    }

    private func card(for entry: InboxEntry, in book: ChannelBook) -> CardRowView {
        let kitten = book.kitten(of: entry.id)
        let reply = CardRowView.Button(title: entry.kind == .decision ? "Reply" : "Ask") { [weak self] in
            guard let self else { return }
            self.open(thread: entry.threadID, in: self.channel(of: kitten), typing: true)
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
        CardRowView.Button(title: CatWords.openInT3, isWayOut: true) { [weak self] in self?.onOpenThread?(threadID) }
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
