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

    /// Gives your words to a kitten. A new thread in its folder already knows what it needs to,
    /// and T3 writes the title, so nothing here has to explain anything to it.
    func give(_ words: String, to kitten: Kitten, snapshot: ScreenSnapshot?) {
        // As with a session, a kitten with full access doesn't get to see text from a page.
        let seesScreen = kitten.seesScreen && settings.frontierMode != .fullAccess
        let shared = seesScreen ? snapshot : nil
        flow = Task {
            guard let projectID = await backend.projectID(atPath: kitten.folder) else {
                say(CatWords.notSetUp(kitten))
                return
            }
            startFrontier(
                title: nil,
                text: Prompts.forKitten(
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
        // A session with full access can do anything, so text from a page doesn't get to reach it.
        // Neither does one belonging to a kitten that isn't meant to see it.
        let owner = loadKittens().first { KittenBoard.belongs(thread, to: $0) }
        let seesScreen = thread.runtimeMode != .fullAccess && owner?.seesScreen != false
        let shared = seesScreen ? snapshot : nil
        let text = Prompts.forwarded(
            words: words,
            snapshot: shared,
            screenshotPath: saveScreenshot(of: shared),
            screenLeftOut: !seesScreen && snapshot != nil
        )
        say(CatWords.sentTo(thread), threadID: thread.id)

        // Quick chats are left out of the thread list's news, so their replies are picked up here.
        let isQuick = watch.isQuick(thread.id)
        forwardTask = Task {
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
}
