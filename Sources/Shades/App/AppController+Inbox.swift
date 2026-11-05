import Foundation
import ShadesCore

/// One place for a kitten's reports: what shipped, and what needs you. A report is an agent's words,
/// so here it's only ever something to read. All that goes back to a thread is what you typed or said.
extension AppController {
    /// A thread whose reports go in the inbox. Without a run ID there's no telling reports apart, so it keeps to the bubble.
    func goesToInbox(_ thread: AgentThread) -> Bool {
        thread.lastRunID != nil && loadKittens().contains { $0.usesInbox && KittenBoard.belongs(thread, to: $0) }
    }

    /// Anything an inbox kitten finished that isn't filed yet, however long ago. Runs on every list, so a finish while
    /// the app was off looks exactly like one while it was on, and no event has to be caught.
    func fileOwedReports() {
        let candidates = watch.threads.filter { inbox.owes($0) && !filing.contains($0.id) && !hiddenThreads.contains($0.id) }
        // So kittens are only read from disk when there's something to check.
        guard !candidates.isEmpty else { return }
        let kittens = loadKittens()
        guard !kittens.isEmpty else { return }
        var skipped = false
        for thread in candidates {
            if kittens.contains(where: { $0.usesInbox && KittenBoard.belongs(thread, to: $0) }) {
                filing.insert(thread.id)
                reportOn(thread, failed: thread.status == .failed)
            } else {
                // Saved, so turning the inbox on for its kitten later doesn't bring this up again.
                // shortcut: this grows by a short line per thread, prune it if that ever matters.
                inbox.skip(thread)
                skipped = true
            }
        }
        if skipped { keepInbox() }
    }

    /// The run only counts as handled once this has sorted it and saved, so stopping at any point before that
    /// means it's filed on the next launch.
    func file(_ report: String?, of thread: AgentThread, failed: Bool, startedAnother next: String?) async {
        let sorted = await sort(report, of: thread, failed: failed)
        // All it did was start another thread, unless it also has something for you.
        if let next, !failed, sorted?.decision == nil, sorted?.shipped == nil {
            passedOn(thread, to: next)
            inbox.skip(thread)
            keepInbox()
            return
        }
        let before = inbox.entries
        inbox.file(sorted ?? unsorted(report), from: thread, at: now(), id: { UUID().uuidString })
        keepInbox()
        if inbox.entries != before { nudgeInbox() }
        inboxChanged()
    }

    /// A failure never goes near the model, so no report can call one shipped. `nil` means the model's answer didn't work out.
    private func sort(_ report: String?, of thread: AgentThread, failed: Bool) async -> SortedReport? {
        if failed { return SortedReport(decision: opening(of: report).map(CatWords.failedRow) ?? CatWords.failedWithoutReport) }
        guard let report, report.contains(where: { !$0.isWhitespace }) else {
            return SortedReport(decision: CatWords.reportUnreadable)
        }
        let prompt = summaryPrompt(Prompts.sortReport(report, title: thread.title), about: thread)
        let reply = await firstOf(seconds: Self.summaryTimeout) { [self] in await summarize(prompt) }
        return (reply ?? nil).flatMap(SortedReport.init(reply:))
    }

    /// It's a decision, because a false alarm beats a lost report.
    private func unsorted(_ report: String?) -> SortedReport {
        SortedReport(decision: opening(of: report) ?? CatWords.reportUnreadable)
    }

    private func opening(of report: String?) -> String? {
        report.map { ReportDigest.firstSentences(of: $0) }.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// What's saved, plus any question a thread has stopped to ask. That's answered in T3, since a message would
    /// only queue behind it, and it goes away by itself, so it's never saved.
    var inboxEntries: [InboxEntry] {
        let questions = latestThreads.filter { $0.pendingQuestion != nil && goesToInbox($0) }.compactMap { thread -> InboxEntry? in
            guard let question = thread.pendingQuestion else { return nil }
            return InboxEntry(
                id: "question-\(question.id)",
                kind: .decision,
                text: CatWords.question(question),
                threadID: question.threadID,
                threadTitle: question.threadTitle,
                at: thread.updatedAt,
                questionID: question.id
            )
        }
        return Inbox.panelOrder(inbox.entries + questions)
    }

    /// Whatever was waiting when the app last stopped gets said again. Saving straight away keeps
    /// the point the inbox started from, so a run that ends before the next launch still counts.
    func startInbox() {
        keepInbox()
        if !inbox.entries.isEmpty { inboxNudge = true }
        renderBubble()
    }

    /// Says there's something new in there, unless you're already looking.
    func nudgeInbox() {
        if !stage.isInboxVisible { inboxNudge = true }
    }

    func inboxPressed() {
        if stage.isInboxVisible {
            stage.hideInbox()
            return
        }
        inboxNudge = false
        stage.hideKittens()
        stage.showInbox(inboxEntries)
        renderBubble()
    }

    var inboxMenuLine: String? {
        CatWords.inboxSummary(inboxEntries)
    }

    func inboxAction(_ action: InboxAction) {
        switch action {
        case .reply(let entry):
            openReply(to: entry)
        case .open(let threadID):
            backend.open(threadID: threadID)
            stage.hideInbox()
        case .done(let id):
            inbox.remove(id)
            keepInbox()
            inboxChanged()
        case .clearShipped:
            inbox.clearShipped()
            keepInbox()
            inboxChanged()
        }
    }

    private func openReply(to entry: InboxEntry) {
        guard entry.questionID == nil else { return }
        stage.hideInput()
        inboxReplyIsOpen = true
        stage.showInput(InputRequest(
            placeholder: CatWords.replyPlaceholder(talkKey: settings.talkKey),
            caption: entry.text,
            allowsEmpty: false,
            onSubmit: { [weak self] words in
                self?.inboxReplyIsOpen = false
                self?.reply(words, to: entry)
            },
            onCancel: { [weak self] in self?.inboxReplyIsOpen = false }
        ))
    }

    /// Takes no snapshot, so no caller can pass one, and doesn't go near the router, whose thread is what would carry the screen.
    func reply(_ words: String, to entry: InboxEntry) {
        let text = Prompts.forwarded(words: words, snapshot: nil, screenshotPath: nil, screenLeftOut: false)
        inbox.markReplied(entry.id, at: now())
        keepInbox()
        inboxChanged()
        say(CatWords.sentTo(entry.threadTitle), threadID: entry.threadID)
        forwardTask = Task {
            var heardBack = false
            do {
                for try await event in backend.forward(threadID: entry.threadID, text: text, attachments: []) {
                    if case .started = event { continue }
                    heardBack = true
                }
            } catch {
                // Losing the connection partway through a turn doesn't mean your words didn't arrive.
                if heardBack { return }
                inbox.markReplied(entry.id, at: nil)
                keepInbox()
                inboxChanged()
                say(CatWords.problem(error, while: .agents))
            }
        }
    }

    func keepInbox() {
        do {
            try saveInbox(inbox)
            inboxSaveFailed = false
        } catch {
            inboxSaveFailed = true
        }
    }

    private func inboxChanged() {
        if stage.isInboxVisible { stage.showInbox(inboxEntries) }
        renderBubble()
    }
}
