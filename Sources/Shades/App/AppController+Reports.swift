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
            if !failed, dispatchers.contains(thread.id), let link {
                passedOn(thread, to: link)
                return
            }
            let words = await words(for: report, of: thread, failed: failed)
            post(
                caption: failed ? CatWords.failedCaption(thread) : CatWords.finishedCaption(thread, kitten: kitten(of: thread)),
                text: words,
                threadID: thread.id
            )
        }
    }

    /// Which kitten a thread belongs to, by the project it's in or the name it starts with.
    private func kitten(of thread: AgentThread) -> Kitten? {
        loadKittens().first { KittenBoard.belongs(thread, to: $0) }
    }

    /// All this thread did was start another one, so that's where the work is now.
    func passedOn(_ thread: AgentThread, to next: String) {
        dispatchers.insert(next)
        // Work that came from Everyone keeps answering there from wherever it moves, and what it said before stays.
        if let since = messagesThreads[thread.id] { messagesThreads[next] = min(since, messagesThreads[next] ?? since) }
        hiddenThreads.insert(thread.id)
        watch.markQuick(thread.id)
        Task { [backend] in try? await backend.settle(threadID: thread.id) }
        stage.showThreads(watch.rows(at: now()), status: watch.summary)
        let title = latestThreads.first { $0.id == next }?.title
        say(CatWords.passedOn(to: title), threadID: next)
    }

    func announce(_ question: AgentQuestion) {
        if let thread = latestThreads.first(where: { $0.pendingQuestion?.id == question.id }), goesToInbox(thread) {
            nudgeInbox()
            renderBubble()
            return
        }
        post(
            caption: CatWords.questionCaption(question),
            text: CatWords.question(question),
            threadID: question.threadID,
            questionID: question.id
        )
    }

    private func words(for report: String?, of thread: AgentThread, failed: Bool) async -> String {
        guard let report, report.contains(where: { !$0.isWhitespace }) else {
            return failed ? CatWords.failedWithoutReport : CatWords.finishedWithoutReport
        }
        if ReportDigest.isShort(report) { return report.trimmingCharacters(in: .whitespacesAndNewlines) }

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

    /// Notices wait their turn behind each other and anything more urgent, so none get lost.
    func post(caption: String, text: String, threadID: String?, questionID: String? = nil) {
        lineCounter += 1
        notices.append(Notice(id: lineCounter, caption: caption, text: text, threadID: threadID, questionID: questionID))
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
