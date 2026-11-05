import Foundation
import ShadesCore

/// Something that ended, waiting a moment in case anything else does too.
struct FinishedWork {
    let thread: AgentThread
    let failed: Bool
    let report: String?
}

/// Says how a session went in a few sentences, rather than only that it ended.
extension AppController {
    /// How long a summary can take before the report's own opening stands in for it.
    static let summaryTimeout: TimeInterval = 25

    func reportOn(_ thread: AgentThread, failed: Bool) {
        guard reporting.insert(thread.id).inserted else {
            // It ended again during the wait, and if the wait comes to nothing this is what's left to tell.
            endedMeanwhile[thread.id] = failed
            return
        }
        followedUp.remove(thread.id)
        reportTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(reportDelay * 1_000_000_000))
            if isStillGoing(thread.id) { return giveUpReport(on: thread) }

            let report = await backend.finalReport(threadID: thread.id)
            // It may have picked up again, or been given more to do, while that was being read.
            if isStillGoing(thread.id) { return giveUpReport(on: thread) }
            let next = failed ? nil : await threadPassedOnTo(in: report, from: thread)
            if isStillGoing(thread.id) { return giveUpReport(on: thread) }

            told.insert(thread.id)
            reporting.remove(thread.id)
            endedMeanwhile[thread.id] = nil
            if let next {
                passedOn(thread, to: next)
                return
            }
            workEnded(in: thread.id, failed: failed)
            tell(FinishedWork(thread: thread, failed: failed, report: report))
        }
    }

    private func giveUpReport(on thread: AgentThread) {
        reporting.remove(thread.id)
        guard let failed = endedMeanwhile.removeValue(forKey: thread.id) else { return }
        reportOn(latestThreads.first { $0.id == thread.id } ?? thread, failed: failed)
    }

    private func isStillGoing(_ thread: String) -> Bool {
        followedUp.contains(thread) || latestThreads.first { $0.id == thread }?.status.isActive == true
    }

    /// A report is an agent's own words, and can mention any thread. One only counts as where the work
    /// went if T3 says this thread started it and it's going now, so a link can't hide or settle anything.
    private func threadPassedOnTo(in report: String?, from thread: AgentThread) async -> String? {
        guard dispatchers.contains(thread.id) || kitten(of: thread) != nil,
              let next = report.flatMap(ReportDigest.linkedThreadID(in:)),
              next != thread.id,
              latestThreads.first(where: { $0.id == next })?.status.isActive == true,
              await backend.origin(of: next)?.startedBy == .thread(thread.id)
        else { return nil }
        return next
    }

    /// The first one to finish starts the wait, and everything that finished by the end of it goes in one go.
    private func tell(_ work: FinishedWork) {
        finishing.append(work)
        guard finishing.count == 1 else { return }
        digestTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(digestWindow * 1_000_000_000))
            let finished = finishing
            finishing = []
            if finished.count == 1, let only = finished.first {
                let words = await words(for: only.report, of: only.thread, failed: only.failed)
                post(caption: caption(for: only), text: words, threadID: only.thread.id)
            } else {
                post(caption: CatWords.digestCaption(finished.count), text: finished.map(digestEntry).joined(separator: "\n\n"), threadID: nil)
            }
        }
    }

    private func caption(for work: FinishedWork) -> String {
        work.failed ? CatWords.failedCaption(work.thread) : CatWords.finishedCaption(work.thread, kitten: kitten(of: work.thread))
    }

    private func digestEntry(_ work: FinishedWork) -> String {
        let said = work.report.map { ReportDigest.firstSentences(of: $0, count: 1) } ?? ""
        let words = said.isEmpty ? (work.failed ? CatWords.failedWithoutReport : CatWords.finishedWithoutReport) : said
        return "\(caption(for: work))\n\(words)"
    }

    /// Which kitten a thread belongs to. What the app saw for itself comes first, then the folder it's
    /// in, and last the name it starts with, which is the only one of these an agent can choose.
    func kitten(of thread: AgentThread) -> Kitten? {
        let everyone = loadKittens()
        return everyone.first { threadOwners[thread.id] == $0.id }
            ?? everyone.first { KittenBoard.belongs(title: "", projectPath: thread.projectPath, to: $0) }
            ?? everyone.first { KittenBoard.belongs(thread, to: $0) }
    }

    /// All this thread did was start another one, so that's where the work is now.
    private func passedOn(_ thread: AgentThread, to next: String) {
        dispatchers.insert(next)
        hiddenThreads.insert(thread.id)
        watch.markQuick(thread.id)
        threadOwners[next] = kitten(of: thread)?.id
        movedTo[thread.id] = next
        for owner in listOwners(of: thread.id) {
            try? updateList(of: owner) { $0.moveWork(from: thread.id, to: next, at: now()) }
            tend(owner)
        }
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
    /// An offer can sit for as long as you like, so everything else goes ahead of it.
    func post(caption: String, text: String, threadID: String?, questionID: String? = nil, offer: Offer? = nil) {
        lineCounter += 1
        let notice = Notice(id: lineCounter, caption: caption, text: text, threadID: threadID, questionID: questionID, offer: offer)
        let firstOffer = offer == nil ? notices.firstIndex { $0.offer != nil } : nil
        notices.insert(notice, at: firstOffer ?? notices.endIndex)
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
