import Foundation
import ShadesCore

/// Says how a session went in a few sentences, rather than only that it ended.
extension AppController {
    /// How long a summary can take before the report's own opening stands in for it.
    static let summaryTimeout: TimeInterval = 25
    private static let summaryTitle = "Shades summary:"

    func reportOn(_ thread: AgentThread, failed: Bool) {
        reportTask = Task {
            // A run that ended while this one was being read gets its turn here.
            defer {
                filing.remove(thread.id)
                fileOwedReports()
            }
            try? await Task.sleep(nanoseconds: UInt64(reportDelay * 1_000_000_000))
            let current = latestThreads.first { $0.id == thread.id } ?? thread
            if current.status.isActive { return }

            let toInbox = goesToInbox(current)
            let report = await backend.finalReport(threadID: thread.id, run: toInbox ? current.lastRunID : nil)
            let next = dispatchers.contains(thread.id) ? report.flatMap(ReportDigest.linkedThreadID(in:)) : nil
            let startedAnother = !failed && next != thread.id ? next : nil
            if toInbox {
                await file(report, of: current, failed: current.status == .failed, startedAnother: startedAnother)
                return
            }
            if let startedAnother {
                passedOn(thread, to: startedAnother)
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
        for thread in threads where thread.title.hasPrefix(Self.summaryTitle) {
            if hiddenThreads.insert(thread.id).inserted {
                watch.markQuick(thread.id)
                leftoverSummaries.insert(thread.id)
            }
            guard leftoverSummaries.contains(thread.id) else { continue }
            for request in thread.pendingApprovals {
                Task { [backend] in try? await backend.respond(to: request, with: .decline) }
            }
            if !thread.status.isActive {
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
