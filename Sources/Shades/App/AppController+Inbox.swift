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
        let owed = inbox.owes(thread)
        if inbox.file(lines, from: thread, at: now(), id: { UUID().uuidString }) { nudgeInbox(about: [.thread(thread.id)]) }
        keepInbox()
        inboxChanged()
        if owed, lines.decision == nil { notifyFinished(thread, by: kitten(of: thread)) }
    }

    /// Never for a thread given a correction. Otherwise the model's call, and with no answer from it, a thread the cat started whose report is one sentence and a link,
    /// because anything more may be asking you something, and a false alarm beats a lost report.
    private func onlyPassedOn(_ sorted: SortedReport?, report: String?, of thread: AgentThread) -> Bool {
        if inbox.wasCorrected(thread.id) { return false }
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

    /// What's saved, plus any question a thread has stopped to ask, for the cat's nudge. A question goes away by
    /// itself once it's answered, so it's never saved.
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
        let news = inboxEntries.filter { $0.needsYou || $0.kind == .shipped }
        if !news.isEmpty { nudgeInbox(about: news.map { .thread($0.threadID) }) }
        renderBubble()
    }

    /// Says there's something new, unless Messages is open. Being open isn't the same as having looked, since it can
    /// sit behind your work, so the bubble comes once it's closed. Every one asks, so Do Not Disturb keeps them all.
    func nudgeInbox(about missed: [Missed]) {
        guard missed.map({ mayPopUp($0) }).contains(true) else { return }
        if stage.isChannelsVisible {
            nudgeOnClose = true
        } else {
            inboxNudge = true
        }
    }

    /// What the menu says next to Messages. What needs you comes first, since that's what it's for.
    var messagesMenuLine: String? {
        CatWords.inboxSummary(inboxEntries)
    }

    func inboxAction(_ action: InboxAction) {
        switch action {
        case .open(let threadID):
            backend.open(threadID: threadID)
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

    /// Takes no snapshot, so no caller can pass one, and doesn't go near the router, whose thread is what would carry the screen.
    /// The report you replied to, if you picked one, stops asking and gets the answer. Otherwise that thread's report
    /// waiting on you does, or failing that its latest one. `echoID` is what Messages shows of your words meanwhile.
    func reply(_ words: String, toThread threadID: String, title: String, marking report: String? = nil, echoID: String) {
        let text = Prompts.forwarded(words: words, snapshot: nil, screenshotPath: nil, screenLeftOut: false)
        let own = inbox.entries.filter { $0.threadID == threadID }
        let entryID = (own.first { $0.id == report } ?? own.last(where: \.needsYou) ?? own.last)?.id
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
                let problem = CatWords.problem(error, while: .agents)
                channels.failed(echoID, because: problem)
                say(problem)
            }
        }
    }

    /// Kept with the inbox, so a report about it can't be taken for only passing work on, even after a restart.
    func noteCorrection(in threadID: String) {
        inbox.noteCorrection(in: threadID)
        keepInbox()
    }

    func forgetCorrection(in threadID: String) {
        inbox.forgetCorrection(in: threadID)
        keepInbox()
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
        channels.refresh()
        notifyNeedsYou()
        renderBubble()
    }
}
