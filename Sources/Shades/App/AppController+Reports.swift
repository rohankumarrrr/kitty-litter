import Foundation
import ShadesCore

/// Says how a session went in a few sentences, rather than only that it ended.
extension AppController {
    /// How long a summary can take before the report's own opening stands in for it.
    static let summaryTimeout: TimeInterval = 25

    func reportOn(_ thread: AgentThread, failed: Bool) {
        reportTask = Task {
            let report = await backend.finalReport(threadID: thread.id)
            if !failed, dispatchers.contains(thread.id), let next = report.flatMap(ReportDigest.linkedThreadID(in:)), next != thread.id {
                passedOn(thread, to: next)
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
        loadKittens().first { kitten in
            thread.projectTitle == kitten.name || thread.title.hasPrefix("\(kitten.name):")
        }
    }

    /// All this thread did was start another one, so that's where the work is now.
    private func passedOn(_ thread: AgentThread, to next: String) {
        dispatchers.insert(next)
        hiddenThreads.insert(thread.id)
        watch.markQuick(thread.id)
        Task { [backend] in try? await backend.settle(threadID: thread.id) }
        stage.showThreads(watch.rows(at: now()), status: watch.summary)
        let title = latestThreads.first { $0.id == next }?.title
        say(CatWords.passedOn(to: title), threadID: next)
    }

    func announce(_ question: AgentQuestion) {
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

        let prompt = AgentPrompt(
            title: String("Shades summary: \(thread.title)".prefix(80)),
            text: Prompts.summary(of: report, title: thread.title, failed: failed),
            model: settings.summaryModel,
            runtimeMode: .approvalRequired
        )
        let summary = await firstOf(seconds: Self.summaryTimeout) { [self] in await summarize(prompt) }
        return (summary ?? nil) ?? ReportDigest.firstSentences(of: report)
    }

    /// Runs out of sight and tidies up after itself. It only has words to write, so it isn't
    /// allowed to do anything else, and the report it's reading doesn't get a say in that.
    private func summarize(_ prompt: AgentPrompt) async -> String? {
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
