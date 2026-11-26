import Foundation
import ShadesCore

extension AppController {
    static let summaryTimeout: TimeInterval = 25
    private static let summaryTitle = "Shades summary:"

    func reportOn(_ thread: AgentThread, failed: Bool) {
        reportTask = Task {
            var unread = false
            defer {
                filing.remove(thread.id)
                if !unread { fileOwedReports() }
            }
            try? await Task.sleep(nanoseconds: UInt64(reportDelay * 1_000_000_000))
            let current = latestThreads.first { $0.id == thread.id } ?? thread
            if current.status.isActive && !current.turnEnded { return }

            let toInbox = filing.contains(thread.id)
            let done = !current.turnEnded
            let wasRead = toInbox ? nil : readRuns[thread.id].flatMap { $0.run == current.lastRunID ? $0.done : nil }
            if wasRead == true || wasRead == false && !done { return }
            if !toInbox, let run = current.lastRunID { readRuns[thread.id] = (run, done) }
            let firstRead = wasRead == nil
            let report: String?
            var readFailed = false
            do {
                report = try await backend.report(threadID: thread.id, run: toInbox ? current.lastRunID : nil)
            } catch {
                unread = toInbox
                if toInbox { return }
                report = nil
                readFailed = true
            }
            let heardBy: ReportAudience = readFailed ? .you : await audience(of: current)
            var handedOver = heardBy == .nobody
            if case .thread(let asker) = heardBy {
                handedOver = toInbox || firstRead ? await tell(asker, about: current, report: report) : true
            }
            if handedOver {
                if toInbox || firstRead, current.status != .failed, let report { fileChangeRequests(in: report, of: current) }
                if toInbox {
                    inbox.skip(current)
                    keepInbox()
                }
                return
            }
            let link = report.flatMap(ReportDigest.linkedThreadID(in:)).flatMap { $0 == thread.id ? nil : $0 }
            if toInbox {
                await file(report, of: current, failed: current.status == .failed, startedAnother: link)
                return
            }
            if !failed, firstRead, let report { fileChangeRequests(in: report, of: current) }
            if !failed, firstRead, dispatchers.contains(thread.id), !inbox.wasCorrected(thread.id), let link {
                passedOn(thread, to: link)
                return
            }
            let kitten = kitten(of: thread)
            let readable = readable(report)
            var sorted: SortedReport?
            if !failed, firstRead, kitten != nil, let readable, readable.contains(where: { !$0.isWhitespace }) {
                sorted = await self.sorted(readable, of: current)
            }
            if let decision = sorted?.decision { flag(decision, of: current, report: report) }
            guard done, mayPopUp(.thread(thread.id)) else { return }
            let words = await words(for: readable, of: thread, failed: failed, sorted: sorted)
            post(
                caption: failed ? CatWords.failedCaption(thread) : CatWords.finishedCaption(thread, kitten: kitten),
                text: words,
                threadID: thread.id,
                unasked: true
            )
            if !failed, sorted?.decision == nil { notifyFinished(thread, by: kitten) }
        }
    }

    func kitten(of thread: AgentThread) -> Kitten? {
        loadKittens().first { KittenBoard.belongs(thread, to: $0) }
    }

    func kittenColor(ofThread id: String) -> UInt32? {
        latestThreads.first { $0.id == id }.flatMap(kitten(of:)).flatMap(ChannelSpeakerLook.color(of:))
    }

    enum ReportAudience: Equatable {
        case you, nobody
        case thread(String)
    }

    func audience(of thread: AgentThread) async -> ReportAudience {
        guard kitten(of: thread) != nil, !isForYou(thread.id) else { return .you }
        let said = await backend.exchanges(threadID: thread.id) ?? []
        guard let run = thread.lastRunID, let opener = said.first(where: { $0.opensRun == run }) else {
            return await owner(of: thread, said: said)
        }
        if opener.isTheKittyLittersOwnNote {
            guard let from = opener.passesOnReportOf else { return .you }
            if await writer(from, to: thread) != .itsOwnWorker {
                switch await firstContact(between: thread.id, and: from, ours: said) {
                case .ours?: break
                case .theirs?: return .nobody
                case nil: return .you
                }
            }
            let heardBy = await owner(of: thread, said: said)
            return heardBy == .thread(from) ? .nobody : heardBy
        }
        switch opener.asker {
        case .you, .schedule:
            return .you
        case .agent(let sender?) where sender != thread.id:
            switch await writer(sender, to: thread) {
            case .itsOwnWorker:
                return await owner(of: thread, said: said)
            case .untraced:
                return .you
            case .another:
                switch await firstContact(between: thread.id, and: sender, ours: said) {
                case .ours?: return await owner(of: thread, said: said)
                case nil: return .you
                case .theirs?:
                    guard !isForYou(sender), await isClearOfScreenlessKittens(threadID: sender) else { return .you }
                    return .thread(sender)
                }
            }
        default:
            return await owner(of: thread, said: said)
        }
    }

    private func owner(of thread: AgentThread, said: [Exchange]) async -> ReportAudience {
        if said.contains(where: { $0.asker == .you && !$0.isTheKittyLittersOwnNote }) { return .you }
        return await ownLauncher(of: thread).map(ReportAudience.thread) ?? .you
    }

    private enum Contact {
        case ours, theirs
    }

    private func firstContact(between us: String, and them: String, ours: [Exchange]) async -> Contact? {
        guard let theirs = await backend.exchanges(threadID: them) else { return nil }
        let from = { (sender: String, said: [Exchange]) in
            said.first { $0.asker == .agent(threadID: sender) || $0.passesOnReportOf == sender }?.askedAt ?? .distantFuture
        }
        return from(us, theirs) < from(them, ours) ? .ours : .theirs
    }

    private enum Writer {
        case itsOwnWorker, another, untraced
    }

    private func writer(_ sender: String, to thread: AgentThread) async -> Writer {
        var next = sender
        var seen: Set<String> = []
        while seen.insert(next).inserted {
            switch await starter(ofThread: next) {
            case .thread(thread.id)?: return .itsOwnWorker
            case .thread(let launcher)?: next = launcher
            case .person?: return .another
            case .unknown?, nil: return next == sender ? .untraced : .another
            }
        }
        return .another
    }

    private func starter(ofThread id: String) async -> ThreadOrigin.Starter? {
        if let known = launchers[id] { return .thread(known) }
        let starter = await backend.origin(of: id)?.startedBy
        if case .thread(let launcher)? = starter { launchers[id] = launcher }
        return starter
    }

    private func ownLauncher(of thread: AgentThread) async -> String? {
        await launcher(of: thread).flatMap { isForYou($0) ? nil : $0 }
    }

    private func isForYou(_ threadID: String) -> Bool {
        dispatchers.contains(threadID) || inbox.wasStartedForYou(threadID)
    }

    func launcher(of thread: AgentThread) async -> String? {
        guard thread.startedByAgent else { return nil }
        if let known = launchers[thread.id] { return known }
        guard case .thread(let launcher)? = await backend.origin(of: thread.id)?.startedBy else { return nil }
        launchers[thread.id] = launcher
        return launcher
    }

    func starter(of thread: AgentThread) -> WaitingVisit.Starter {
        guard thread.startedByAgent else { return .you }
        if dispatchers.contains(thread.id) || inbox.wasStartedForYou(thread.id) { return .passedOn }
        return launchers[thread.id] == nil ? .unknown : .agent
    }

    private func tell(_ asker: String, about thread: AgentThread, report: String?) async -> Bool {
        if thread.isDelegated { return true }
        if let started = thread.lastRunStartedAt, let said = await backend.exchanges(threadID: asker),
           said.contains(where: { $0.asker == .agent(threadID: thread.id) && $0.askedAt >= started }) {
            return true
        }
        guard relayLimit.allows(thread.id, asker, at: now()) else { return false }
        inbox.appWillWrite(to: asker, at: now())
        do {
            try await backend.deliver(threadID: asker, text: Prompts.launchedReport(readable(report), of: thread))
            relayLimit.record(thread.id, asker, at: now())
            return true
        } catch {
            inbox.appDidntWrite(to: asker)
            return false
        }
    }

    func passedOn(_ thread: AgentThread, to next: String) {
        dispatchers.insert(next)
        inbox.startedForYou(next, at: now())
        moveScreenWarnings(from: thread.id, to: next)
        if let since = messagesThreads[thread.id] { messagesThreads[next] = min(since, messagesThreads[next] ?? since) }
        if let since = catsWork[thread.id] { catsWork[next] = min(since, catsWork[next] ?? since) }
        hiddenThreads.insert(thread.id)
        watch.markQuick(thread.id)
        Task { [backend] in try? await backend.settle(threadID: thread.id) }
        stage.showStatus(watch.summary, needsYou: watch.needsYouCount > 0)
        let title = latestThreads.first { $0.id == next }?.title
        say(CatWords.passedOn(to: title), threadID: next, fades: true, unasked: true)
    }

    func announce(_ question: AgentQuestion) {
        if let thread = latestThreads.first(where: { $0.pendingQuestion?.id == question.id }), goesToInbox(thread) {
            nudgeInbox(about: [.question(question.id)])
            renderBubble()
            return
        }
        post(
            caption: CatWords.questionCaption(question),
            text: CatWords.question(question),
            threadID: question.threadID,
            questionID: question.id,
            unasked: true
        )
    }

    private func words(for report: String?, of thread: AgentThread, failed: Bool, sorted: SortedReport?) async -> String {
        guard let report, report.contains(where: { !$0.isWhitespace }) else {
            return failed ? CatWords.failedWithoutReport : CatWords.finishedWithoutReport
        }
        if ReportDigest.isShort(report) { return report.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let sorted, sorted.hasLines { return [sorted.shipped, sorted.note, sorted.decision].compactMap { $0 }.joined(separator: " ") }

        let prompt = summaryPrompt(Prompts.summary(of: report, title: thread.title, failed: failed), about: thread)
        let summary = await firstOf(seconds: Self.summaryTimeout) { [self] in await summarize(prompt) }
        return (summary ?? nil) ?? ReportDigest.firstSentences(of: report)
    }

    func summaryPrompt(_ text: String, about thread: AgentThread) -> AgentPrompt {
        AgentPrompt(
            title: String("\(Self.summaryTitle) \(thread.title)".prefix(80)),
            text: text,
            model: settings.summaryModel,
            runtimeMode: .approvalRequired
        )
    }

    func tidyLeftoverSummaries(_ threads: [AgentThread]) {
        let leftover = { (thread: AgentThread) in
            thread.title.hasPrefix(Self.summaryTitle) && thread.projectPath == nil
                || thread.title.hasPrefix(Self.reviewTitle) && self.inRouterFolder(thread)
        }
        for thread in threads where leftover(thread) {
            if hiddenThreads.insert(thread.id).inserted {
                watch.markQuick(thread.id)
                leftoverSummaries.insert(thread.id)
            }
            guard leftoverSummaries.contains(thread.id) else { continue }
            for request in thread.pendingApprovals {
                Task { [backend] in try? await backend.respond(to: request, with: .decline) }
            }
            if !thread.status.isActive, thread.status != .idle {
                leftoverSummaries.remove(thread.id)
                Task { [backend] in try? await backend.archive(threadID: thread.id) }
            }
        }
    }

    func summarize(_ prompt: AgentPrompt, retryingFallback: Bool = false) async -> String? {
        var threadID: String?
        var text: String?
        var streamed = ""
        var usageLimit: (message: String, resetAt: Date?)?
        do {
            for try await event in backend.start(prompt) {
                switch event {
                case .started(let id):
                    threadID = id
                    watch.markQuick(id)
                    hiddenThreads.insert(id)
                case .needsApproval(let request):
                    try? await backend.respond(to: request, with: .decline)
                case .finished(let fullText):
                    text = fullText
                case .text(let delta):
                    streamed += delta
                case .usageLimited(let message, let resetAt):
                    let detected = ClaudeUsageLimit.detect(errorClass: "usage_limit", message: message, text: streamed, resetAt: resetAt, reference: now())
                    usageLimit = (message, detected?.resetAt ?? resetAt)
                case .failed(let message):
                    if prompt.model.isClaude, let detected = ClaudeUsageLimit.detect(message: message, text: streamed, reference: now()) {
                        usageLimit = (message, detected.resetAt)
                    }
                }
            }
        } catch {
            text = nil
        }
        if let threadID {
            Task { [backend] in try? await backend.archive(threadID: threadID) }
        }
        if let usageLimit, prompt.model.isClaude, !retryingFallback {
            noteClaudeUsageLimit(resetAt: usageLimit.resetAt, message: usageLimit.message, text: streamed)
            let fallback = settings.fallbackModel
            if fallback != prompt.model, claudeLimit.isActive(at: now()) {
                var retried = prompt
                retried.model = fallback
                return await summarize(retried, retryingFallback: true)
            }
        }
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    func post(caption: String, text: String, threadID: String?, questionID: String? = nil, first: Bool = false, unasked: Bool = false) {
        if unasked, !mayPopUp(missed(question: questionID, thread: threadID, text: text)) { return }
        lineCounter += 1
        notices.insert(Notice(id: lineCounter, caption: caption, text: text, threadID: threadID, questionID: questionID), at: first ? 0 : notices.count)
        renderBubble()
    }

    func dropAnsweredQuestions(_ threads: [AgentThread]) {
        let open = Set(threads.compactMap { $0.pendingQuestion?.id })
        let before = notices.count
        notices.removeAll { notice in notice.questionID.map { !open.contains($0) } ?? false }
        if notices.count != before { renderBubble() }
    }
}
