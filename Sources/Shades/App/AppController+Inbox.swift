import Foundation
import ShadesCore

/// One place for a kitten's reports: what shipped, and what needs you. A report is an agent's words,
/// so here it's only ever something to read. All that goes back to a thread is what you typed or said.
extension AppController {
    private static let kittenRecheck: TimeInterval = 60

    /// A thread whose reports go in the inbox. Without a run ID there's no telling reports apart, so it keeps to the bubble.
    func goesToInbox(_ thread: AgentThread) -> Bool {
        thread.lastRunID != nil && !hiddenThreads.contains(thread.id) && loadKittens().contains { $0.usesInbox && KittenBoard.belongs(thread, to: $0) }
    }

    /// Anything an inbox kitten finished that isn't filed yet, however long ago. Runs on every list, so a finish while
    /// the app was off looks exactly like one while it was on, and no event has to be caught.
    func fileOwedReports() {
        // A kitten's file can be fixed while the app runs, so this only holds for a minute.
        if now().timeIntervalSince(notForInboxSince) > Self.kittenRecheck {
            notForInbox = []
            notForInboxSince = now()
        }
        let candidates = watch.threads.filter { thread in
            inbox.owes(thread) && !filing.contains(thread.id) && !hiddenThreads.contains(thread.id)
                && !notForInbox.contains(thread.lastRunID ?? "")
        }
        // So kittens are only read from disk when there's something to check.
        guard !candidates.isEmpty else { return }
        let kittens = loadKittens()
        var skipped = false
        for thread in candidates {
            let owners = kittens.filter { KittenBoard.belongs(thread, to: $0) }
            if owners.contains(where: \.usesInbox) {
                filing.insert(thread.id)
                reportOn(thread, failed: thread.status == .failed)
                continue
            }
            if let run = thread.lastRunID { notForInbox.insert(run) }
            // Saved for a kitten that just has no inbox, so turning it on later doesn't bring this up again. A thread
            // that matches no kitten could be one whose file can't be read right now, so it isn't written off.
            // shortcut: this grows by a short line per thread, prune it if that ever matters.
            if !owners.isEmpty {
                inbox.skip(thread)
                skipped = true
            }
        }
        if skipped { keepInbox() }
    }

    /// The run only counts as handled once this has sorted it and saved, so stopping at any point before that
    /// means it's filed on the next launch.
    func file(_ report: String?, of thread: AgentThread, failed: Bool, startedAnother next: String?) async {
        // It said nothing this time, so whatever's already waiting on you stays as it is.
        let saidNothing = report?.contains(where: { !$0.isWhitespace }) != true
        if saidNothing, !failed, inbox.entries.contains(where: { $0.threadID == thread.id }) {
            inbox.skip(thread)
            keepInbox()
            return
        }
        let sorted = await sort(report, of: thread, failed: failed)
        if let next, !failed, onlyPassedOn(sorted, report: report, of: thread) {
            passedOn(thread, to: next)
            inbox.skip(thread)
            keepInbox()
            return
        }
        // A reply can say it passed work on and name nowhere it went, and that doesn't get to lose a report.
        let lines = sorted.flatMap { $0.hasLines ? $0 : nil } ?? unsorted(report)
        if inbox.file(lines, from: thread, at: now(), id: { UUID().uuidString }) { nudgeInbox() }
        keepInbox()
        inboxChanged()
    }

    /// The model's call. With no answer from it, a thread the cat started whose report is one sentence and a link,
    /// because anything more may be asking you something, and a false alarm beats a lost report.
    private func onlyPassedOn(_ sorted: SortedReport?, report: String?, of thread: AgentThread) -> Bool {
        guard let sorted else {
            return dispatchers.contains(thread.id) && report.map(ReportDigest.isOneSentence) == true && report?.contains("?") == false
        }
        return sorted.passedOn && sorted.decision == nil && sorted.shipped == nil
    }

    /// A failure never goes near the model, so no report can call one shipped. `nil` means the model's answer didn't work out.
    private func sort(_ report: String?, of thread: AgentThread, failed: Bool) async -> SortedReport? {
        if failed { return SortedReport(decision: opening(of: report).map(CatWords.failedRow) ?? CatWords.failedWithoutReport) }
        guard let report, report.contains(where: { !$0.isWhitespace }) else {
            return SortedReport(decision: CatWords.finishedWithoutReport)
        }
        let prompt = summaryPrompt(Prompts.sortReport(report, title: thread.title), about: thread)
        let reply = await firstOf(seconds: Self.summaryTimeout) { [self] in await summarize(prompt) }
        return (reply ?? nil).flatMap(SortedReport.init(reply:))
    }

    /// It's a decision, because a false alarm beats a lost report.
    private func unsorted(_ report: String?) -> SortedReport {
        SortedReport(decision: opening(of: report) ?? CatWords.finishedWithoutReport)
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
        if !CatWords.inboxHeadline(inboxEntries).isEmpty { inboxNudge = true }
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
        case .clear(let kind):
            inbox.clear(kind)
            keepInbox()
            inboxChanged()
        }
    }

    private func openReply(to entry: InboxEntry) {
        guard entry.questionID == nil else { return }
        stage.hideInput()
        inboxReplyIsOpen = true
        boxesOpened += 1
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

    func reply(_ words: String, to entry: InboxEntry) {
        reply(words, toThread: entry.threadID, title: entry.threadTitle, marking: entry.id)
    }

    /// Takes no snapshot, so no caller can pass one, and doesn't go near the router, whose thread is what would carry the screen.
    /// A report from that thread that's waiting on you stops asking, unless it's told which one.
    func reply(_ words: String, toThread threadID: String, title: String, marking entryID: String? = nil) {
        let text = Prompts.forwarded(words: words, snapshot: nil, screenshotPath: nil, screenLeftOut: false)
        let entryID = entryID ?? inbox.entries.last { $0.threadID == threadID && $0.needsYou }?.id
        if let entryID {
            inbox.markReplied(entryID, at: now())
            keepInbox()
            inboxChanged()
        }
        say(CatWords.sentTo(title), threadID: threadID)
        forwardTask = Task {
            var heardBack = false
            do {
                for try await event in backend.forward(threadID: threadID, text: text, attachments: []) {
                    if case .started = event { continue }
                    heardBack = true
                }
            } catch {
                // Losing the connection partway through a turn doesn't mean your words didn't arrive.
                if heardBack { return }
                if let entryID {
                    inbox.markReplied(entryID, at: nil)
                    keepInbox()
                    inboxChanged()
                }
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
        channels.refresh()
        notifyNeedsYou()
        renderBubble()
    }
}
