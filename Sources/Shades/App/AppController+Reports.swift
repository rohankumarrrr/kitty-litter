import Foundation
import ShadesCore

/// Says how a session went in a few sentences, rather than only that it ended.
extension AppController {
    /// How long a summary can take before the report's own opening stands in for it.
    static let summaryTimeout: TimeInterval = 25
    private static let summaryTitle = "Shades summary:"

    func reportOn(_ thread: AgentThread, failed: Bool) {
        reportTask = Task {
            var unread = false
            // A run that ended while this one was being read gets its turn here.
            defer {
                filing.remove(thread.id)
                if !unread { fileOwedReports() }
            }
            try? await Task.sleep(nanoseconds: UInt64(reportDelay * 1_000_000_000))
            let current = latestThreads.first { $0.id == thread.id } ?? thread
            if current.status.isActive { return }

            // Settled when this started, so a kitten's file changing partway can't leave a report with nowhere to go.
            let toInbox = filing.contains(thread.id)
            let report: String?
            do {
                report = try await backend.report(threadID: thread.id, run: toInbox ? current.lastRunID : nil)
            } catch {
                // It's still owed, and the next list tries again. Not being able to read it doesn't mean it said nothing.
                unread = toInbox
                if toInbox { return }
                report = nil
            }
            let link = report.flatMap(ReportDigest.linkedThreadID(in:)).flatMap { $0 == thread.id ? nil : $0 }
            if toInbox {
                await file(report, of: current, failed: current.status == .failed, startedAnother: link)
                return
            }
            // A thread given a correction says how it went, even if it was passed work before that.
            if !failed, dispatchers.contains(thread.id), !inbox.wasCorrected(thread.id), let link {
                passedOn(thread, to: link)
                return
            }
            // A kitten's report is sorted rather than summed up, so what it needs from you reaches you even when the
            // bubble won't show, the same as one with an inbox.
            let kitten = kitten(of: thread)
            var sorted: SortedReport?
            if !failed, kitten != nil, let report, report.contains(where: { !$0.isWhitespace }) {
                sorted = await self.sorted(report, of: thread)
            }
            if let decision = sorted?.decision { flag(decision, of: current) }
            // Held by Do Not Disturb, it's read again from the thread, so there's nothing to sum up.
            guard mayPopUp(.thread(thread.id)) else { return }
            let words = await words(for: report, of: thread, failed: failed, sorted: sorted)
            post(
                caption: failed ? CatWords.failedCaption(thread) : CatWords.finishedCaption(thread, kitten: kitten),
                text: words,
                threadID: thread.id,
                unasked: true
            )
            // A decision has its own notification.
            if !failed, sorted?.decision == nil { notifyFinished(thread, by: kitten) }
        }
    }

    /// Which kitten a thread belongs to, by the project it's in or the name it starts with.
    func kitten(of thread: AgentThread) -> Kitten? {
        loadKittens().first { KittenBoard.belongs(thread, to: $0) }
    }

    /// The colour of the kitten a thread belongs to, which lights the bubble while it speaks.
    func kittenColor(ofThread id: String) -> UInt32? {
        latestThreads.first { $0.id == id }.flatMap(kitten(of:)).flatMap(ChannelSpeakerLook.color(of:))
    }

    /// All this thread did was start another one, so that's where the work is now.
    func passedOn(_ thread: AgentThread, to next: String) {
        dispatchers.insert(next)
        moveScreenWarnings(from: thread.id, to: next)
        // Work Messages started keeps showing from wherever it moves, and what it said before stays.
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

    /// A summary still running when the app last stopped carries on without it, and it's reading
    /// a report just the same. So nothing it says or asks for gets through, and it's tidied up as usual.
    func tidyLeftoverSummaries(_ threads: [AgentThread]) {
        // They're never in a project, which keeps a thread of yours in one with a title like that out of this.
        for thread in threads where thread.title.hasPrefix(Self.summaryTitle) && thread.projectPath == nil {
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

    /// Runs out of sight and tidies up after itself. It only has words to write, so it isn't
    /// allowed to do anything else, and the report it's reading doesn't get a say in that.
    func summarize(_ prompt: AgentPrompt) async -> String? {
        var threadID: String?
        var text: String?
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
                case .text, .failed:
                    break
                }
            }
        } catch {
            text = nil
        }
        if let threadID {
            Task { [backend] in try? await backend.archive(threadID: threadID) }
        }
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    /// Notices wait their turn behind each other and anything more urgent, so none get lost. One that's `unasked` comes
    /// by itself, so Do Not Disturb holds it.
    func post(caption: String, text: String, threadID: String?, questionID: String? = nil, first: Bool = false, unasked: Bool = false) {
        if unasked, !mayPopUp(missed(question: questionID, thread: threadID, text: text)) { return }
        lineCounter += 1
        notices.insert(Notice(id: lineCounter, caption: caption, text: text, threadID: threadID, questionID: questionID), at: first ? 0 : notices.count)
        renderBubble()
    }

    /// A question that's been answered has nothing left to say.
    func dropAnsweredQuestions(_ threads: [AgentThread]) {
        let open = Set(threads.compactMap { $0.pendingQuestion?.id })
        let before = notices.count
        notices.removeAll { notice in notice.questionID.map { !open.contains($0) } ?? false }
        if notices.count != before { renderBubble() }
    }
}
