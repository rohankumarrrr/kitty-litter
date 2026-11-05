import Foundation
import ShadesCore

/// Decides nothing itself: the quick agent picks where a message belongs, from a list this
/// builds. All it can pick is a number, and your own words are what get sent, so anything
/// a page manages to say to it can misdirect your message at worst.
extension AppController {
    static let rosterSize = 10
    /// A session this old has probably been forgotten about.
    static let rosterWindow: TimeInterval = 24 * 60 * 60
    /// Reading what sessions last said shouldn't hold up a question.
    static let rosterWait: TimeInterval = 1.5

    func waitForThreadList() async {
        let deadline = Date().addingTimeInterval(threadListWait)
        while !threadListArrived, Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    func rosterThreads(excluding current: String?) -> [AgentThread] {
        let at = now()
        return latestThreads
            .filter { $0.id != current && !hiddenThreads.contains($0.id) }
            .filter { $0.status.isActive || at.timeIntervalSince($0.updatedAt) < Self.rosterWindow }
            .sorted { a, b in
                if a.status.isActive != b.status.isActive { return a.status.isActive }
                return a.updatedAt > b.updatedAt
            }
            .prefix(Self.rosterSize)
            .map { $0 }
    }

    func briefs(for threads: [AgentThread]) async -> [SessionBrief] {
        let backend = self.backend
        let ids = threads.map(\.id)
        let reports = await firstOf(seconds: Self.rosterWait) { () -> [String: String] in
            await withTaskGroup(of: (String, String?).self) { group in
                for id in ids {
                    group.addTask { (id, await backend.finalReport(threadID: id)) }
                }
                var found: [String: String] = [:]
                for await (id, report) in group {
                    if let report { found[id] = report }
                }
                return found
            }
        } ?? [:]

        let at = now()
        return threads.enumerated().map { index, thread in
            SessionBrief(
                number: index + 1,
                title: thread.title,
                project: thread.projectTitle,
                status: CatWords.sessionStatus(thread, now: at),
                model: ModelNames.friendly(model: thread.model),
                lastSaid: reports[thread.id].map { ReportDigest.firstSentences(of: $0) }
            )
        }
    }

    /// Gives your words to a kitten, in a new thread in its project. T3 writes the title.
    func give(_ words: String, to kitten: Kitten, snapshot: ScreenSnapshot?) {
        // As with a session, a kitten with full access doesn't get to see text from a page.
        let seesScreen = kitten.seesScreen && settings.frontierMode != .fullAccess
        let shared = seesScreen ? snapshot : nil
        flow = Task {
            guard let projectID = await backend.projectID(atPath: kitten.project) else {
                say(CatWords.notSetUp(kitten))
                return
            }
            startFrontier(
                title: nil,
                text: Prompts.forKitten(
                    kitten,
                    words: words,
                    snapshot: shared,
                    screenshotPath: saveScreenshot(of: shared),
                    screenLeftOut: !seesScreen && snapshot != nil
                ),
                snapshot: shared,
                projectID: projectID,
                name: kitten.name
            )
        }
    }

    /// Passes your words to a session that already has the context. The session's reply comes
    /// back the usual way, as a notice when it finishes.
    func forward(_ words: String, to thread: AgentThread, snapshot: ScreenSnapshot?) {
        say(CatWords.sentTo(thread), threadID: thread.id)

        // Quick chats are left out of the thread list's news, so their replies are picked up here.
        let isQuick = watch.isQuick(thread.id)
        forwardTask = Task {
            // A session with full access can do anything, so text from a page doesn't get to reach it.
            // Neither does one working for a kitten that isn't meant to see it, or one that won't say.
            var seesScreen = thread.runtimeMode != nil && thread.runtimeMode != .fullAccess
            if seesScreen, snapshot != nil { seesScreen = await isClearOfScreenlessKittens(thread) }
            let shared = seesScreen ? snapshot : nil
            let text = Prompts.forwarded(
                words: words,
                snapshot: shared,
                screenshotPath: saveScreenshot(of: shared),
                screenLeftOut: !seesScreen && snapshot != nil
            )
            do {
                for try await event in backend.forward(threadID: thread.id, text: text, attachments: attachments(for: shared)) {
                    switch event {
                    case .finished where isQuick:
                        reportOn(thread, failed: false)
                    case .failed(let message) where isQuick:
                        say(message)
                    default:
                        break
                    }
                }
            } catch {
                say(CatWords.problem(error, while: .agents))
            }
        }
    }

    /// A kitten's work can be in any project and called anything, so this follows who started the
    /// thread. One that can't be traced doesn't count as clear, since the screen can't be taken back.
    private func isClearOfScreenlessKittens(_ thread: AgentThread) async -> Bool {
        let screenless = loadKittens().filter { !$0.seesScreen }
        if screenless.isEmpty { return true }
        if screenless.contains(where: { KittenBoard.belongs(thread, to: $0) }) { return false }
        let backend = self.backend
        let id = thread.id
        return await firstOf(seconds: Self.rosterWait) {
            await Self.traceIsClear(from: id, of: screenless, backend: backend)
        } ?? false
    }

    private nonisolated static func traceIsClear(from threadID: String, of screenless: [Kitten], backend: AgentBackend) async -> Bool {
        var next = threadID
        var seen: Set<String> = []
        while seen.insert(next).inserted {
            guard let origin = await backend.origin(of: next),
                  !screenless.contains(where: { KittenBoard.belongs(title: origin.title, projectPath: origin.projectPath, to: $0) })
            else { return false }
            switch origin.startedBy {
            case .person: return true
            case .thread(let starter): next = starter
            case .unknown: return false
            }
        }
        return false
    }
}
