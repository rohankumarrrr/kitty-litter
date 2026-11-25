import Foundation
import ShadesCore

extension AppController {
    private static let kittenRecheck: TimeInterval = 60

    func goesToInbox(_ thread: AgentThread) -> Bool {
        thread.lastRunID != nil && !hiddenThreads.contains(thread.id) && loadKittens().contains { $0.usesInbox && KittenBoard.belongs(thread, to: $0) }
    }

    func fileOwedReports() {
        if now().timeIntervalSince(notForInboxSince) > Self.kittenRecheck {
            notForInbox = []
            notForInboxSince = now()
        }
        let candidates = watch.threads.filter { thread in
            inbox.owes(thread) && !filing.contains(thread.id) && !hiddenThreads.contains(thread.id)
                && !notForInbox.contains(thread.lastRunID ?? "")
        }
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
            if !owners.isEmpty {
                inbox.skip(thread)
                skipped = true
            }
        }
        if skipped { keepInbox() }
    }

    func file(_ report: String?, of thread: AgentThread, failed: Bool, startedAnother next: String?) async {
        let saidNothing = report?.contains(where: { !$0.isWhitespace }) != true
        if saidNothing, !failed {
            inbox.skip(thread)
            keepInbox()
            return
        }
        async let asked = failed ? [] : changeRequests(in: report, of: thread)
        let readable = readable(report)
        let sorted = await sort(readable, of: thread, failed: failed)
        let changes = await asked
        if !failed { withdrawRequests(in: report, of: thread) }
        if let next, !failed, changes.isEmpty, onlyPassedOn(sorted, report: readable, of: thread) {
            passedOn(thread, to: next)
            inbox.skip(thread)
            keepInbox()
            return
        }
        let lines = sorted.flatMap { $0.hasLines ? $0 : nil } ?? unsorted(readable)
        let owed = inbox.owes(thread)
        let starter = starter(of: thread)
        if inbox.file(lines, from: thread, startedBy: starter, at: now(), id: { UUID().uuidString }) { nudgeInbox(about: [.thread(thread.id)]) }
        changes.forEach { inbox.ask($0, startedBy: starter, held: thread.turnEnded, title: title(ofThread:)) }
        inbox.follow(latestThreads, at: now())
        keepInbox()
        inboxChanged()
        if owed, lines.decision == nil, !thread.turnEnded { notifyFinished(thread, by: kitten(of: thread)) }
        if !failed, changes.isEmpty, readable?.contains(where: { !$0.isWhitespace }) == true, let decision = sorted?.decision,
           let row = inbox.entries.last(where: { $0.threadID == thread.id && $0.kind == .decision && !$0.isStanding }) {
            readDecision(row.id, decision: decision, of: thread)
        }
    }

    private func onlyPassedOn(_ sorted: SortedReport?, report: String?, of thread: AgentThread) -> Bool {
        if inbox.wasCorrected(thread.id) { return false }
        guard let sorted else {
            return dispatchers.contains(thread.id) && report.map(ReportDigest.isOneSentence) == true && report?.contains("?") == false
        }
        return sorted.passedOn && sorted.decision == nil && sorted.shipped == nil
    }

    private func sort(_ report: String?, of thread: AgentThread, failed: Bool) async -> SortedReport? {
        if failed { return SortedReport(decision: opening(of: report).map(CatWords.failedRow) ?? CatWords.failedWithoutReport) }
        guard let report, report.contains(where: { !$0.isWhitespace }) else { return nil }
        if let sorted = await sorted(report, of: thread) { return sorted }
        return await sorted(report, of: thread)
    }

    func sorted(_ report: String, of thread: AgentThread) async -> SortedReport? {
        let prompt = summaryPrompt(Prompts.sortReport(report, of: thread), about: thread)
        let reply = await firstOf(seconds: Self.summaryTimeout) { [self] in await summarize(prompt) }
        return (reply ?? nil).flatMap(SortedReport.init(reply:))
    }

    func flag(_ decision: String, of thread: AgentThread, report: String?) {
        let id = UUID().uuidString
        inbox.flag(decision, from: thread, startedBy: starter(of: thread), at: now(), id: id)
        keepInbox()
        inboxChanged()
        if ChangeRequests.cards(in: report ?? "").isEmpty { readDecision(id, decision: decision, of: thread) }
    }

    private func unsorted(_ report: String?) -> SortedReport {
        SortedReport(note: opening(of: report), isOpening: true)
    }

    private func opening(of report: String?) -> String? {
        report.map { ReportDigest.firstSentences(of: $0) }.flatMap { $0.isEmpty ? nil : $0 }
    }

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

    func startInbox() {
        keepInbox()
        showNeedsYouCount()
        let news = inboxEntries.filter { $0.needsYou || $0.kind == .shipped }
        if !news.isEmpty { nudgeInbox(about: news.map { .thread($0.threadID) }) }
        renderBubble()
    }

    func nudgeInbox(about missed: [Missed]) {
        guard missed.map({ mayPopUp($0) }).contains(true) else { return }
        if stage.isChannelsOpen {
            nudgeOnClose = true
        } else {
            inboxNudge = true
        }
    }

    var inboxBubbleWords: String {
        let kittens = loadKittens()
        let owners = KittenBoard.Owners(kittens)
        return CatWords.inboxBubble(inboxEntries.filter { !lockdownHolds(.thread($0.threadID)) }) { entry in
            let thread = latestThreads.first { $0.id == entry.threadID }
            return (thread.flatMap(owners.of) ?? kittens.first { KittenBoard.belongs(title: entry.threadTitle, projectPath: nil, to: $0) })?.name
        }
    }

    var messagesMenuLine: String? {
        CatWords.inboxSummary(inboxEntries)
    }

    func showNeedsYouCount() {
        stage.showNeedsYou(inboxEntries.filter(\.needsYou).count)
    }

    func inboxAction(_ action: InboxAction) {
        switch action {
        case .open(let threadID):
            openThread(threadID)
        case .done(let id):
            inbox.remove(id, because: .done, at: now())
            keepInbox()
            inboxChanged()
        case .ignore(let id):
            inbox.remove(id, because: .ignored, at: now())
            keepInbox()
            inboxChanged()
        case .clear(let kind):
            inbox.clear(kind, at: now())
            keepInbox()
            inboxChanged()
        case .allow(let id):
            allow(id)
        case .deny(let id):
            deny(id)
        }
    }

    func reply(_ words: String, toThread threadID: String, marking report: String? = nil, echoID: String, behavior: FollowUpBehavior) {
        let text = Prompts.forwarded(words: words, snapshot: nil, screenshotPath: nil, screenLeftOut: false)
        let own = inbox.entries.filter { $0.threadID == threadID && !$0.isStanding }
        let entryID = (own.first { $0.id == report } ?? own.last(where: \.needsYou) ?? own.last)?.id
        if let entryID {
            inbox.markReplied(entryID, at: now())
            keepInbox()
            inboxChanged()
        }
        forwardTask = Task {
            var heardBack = false
            do {
                for try await event in backend.forward(threadID: threadID, text: text, attachments: [], behavior: behavior) {
                    if case .started = event { continue }
                    heardBack = true
                }
            } catch {
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

    func inboxChanged() {
        channels.refresh()
        notifyNeedsYou()
        renderBubble()
    }
}
