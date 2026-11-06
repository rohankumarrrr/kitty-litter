import Foundation
import ShadesCore

/// Why the router won't run, other than T3's own errors.
enum FrontDoorProblem: LocalizedError, Equatable {
    case notClaude, noFolder

    var errorDescription: String? {
        switch self {
        case .notClaude: return CatWords.frontDoorNotClaude
        case .noFolder: return CatWords.frontDoorNoFolder
        }
    }
}

/// Decides nothing itself: the quick agent picks where a message belongs, from a list this
/// builds. All it can pick is a number, and your own words are what get sent, so anything
/// a page manages to say to it can misdirect your message at worst. A correction is the same:
/// the router names a kitten, and what goes is your whole message, as you said it.
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

    func rosterThreads(excluding current: String?, only isOffered: (AgentThread) -> Bool = { _ in true }) -> [AgentThread] {
        let at = now()
        // Neither router conversation lists the other, since the Ask box's can hold your screen and Messages' never may.
        return latestThreads
            .filter { $0.id != current && !hiddenThreads.contains($0.id) && !watch.isQuick($0.id) && isOffered($0) }
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

    /// Says your words have gone. If they point at a screen the agent won't get, you need to act
    /// on that, so it's a notice that goes first and waits to be read, not a line that can be lost.
    /// `asked` is `questionsAsked` when they were sent, since asking another takes the warning back. Says which notice it was.
    @discardableResult
    func sayPassedOn(_ said: String, threadID: String, missesScreen: Bool, asked: Int, followUp: Bool = false) -> Int? {
        guard missesScreen, asked == questionsAsked else {
            say(said, threadID: threadID)
            return nil
        }
        line = nil
        post(caption: said, text: CatWords.sendTheLink, threadID: threadID, first: true)
        if let index = notices.firstIndex(where: { $0.id == lineCounter }) { notices[index].followUp = followUp }
        return lineCounter
    }

    /// Whether the agent gets anything of your screen to go on. A private app's is only a note that it's hidden.
    func carriesScreen(_ shared: ScreenSnapshot?) -> Bool {
        shared.map { !$0.isPrivate } ?? false
    }

    /// The work your words started in that thread went wrong, so there's nothing left to warn about. Other threads'
    /// warnings stand, and so do follow-ups', which only their own turns take back. `run` is the run that failed, if known.
    func dropScreenWarning(for threadID: String?, run: String? = nil) {
        notices.removeAll { $0.text == CatWords.sendTheLink && $0.threadID == threadID && !$0.followUp && (run == nil || $0.after != run) }
        renderBubble()
    }

    /// The list can show a failure it never saw running, such as one from while the connection was down.
    func dropScreenWarnings(forFailuresIn threads: [AgentThread]) {
        let failed = Dictionary(threads.filter { $0.status == .failed }.map { ($0.id, $0.lastRunID) }, uniquingKeysWith: { first, _ in first })
        let before = notices.count
        notices.removeAll { notice in
            guard notice.text == CatWords.sendTheLink, !notice.followUp, let id = notice.threadID, let run = failed[id] else { return false }
            return notice.after == nil || (run != nil && notice.after != run)
        }
        if notices.count != before { renderBubble() }
    }

    /// The warning goes with the work, so it's taken back if that fails, even if it already has. A run the thread
    /// had already finished well isn't the work.
    func moveScreenWarnings(from threadID: String, to next: String) {
        let known = latestThreads.first { $0.id == next }
        let finishedWell = known.map { !$0.status.isActive && $0.status != .failed } == true
        for index in notices.indices where notices[index].text == CatWords.sendTheLink && notices[index].threadID == threadID {
            notices[index].threadID = next
            notices[index].after = finishedWell ? known?.lastRunID : nil
            notices[index].followUp = false
        }
        dropScreenWarnings(forFailuresIn: known.map { [$0] } ?? [])
    }

    /// Only that one, since another send's warning for the same thread can still stand.
    func takeBackNotice(_ id: Int) {
        notices.removeAll { $0.id == id }
        renderBubble()
    }

    /// The router's own project, where it can't pass on what it's seen. Asked before every turn, since a follow-up
    /// runs on whatever its folder says by then. Only Claude Code reads that folder, so no other model gets to be
    /// the router, and the turn runs on the `model` checked here. If this throws, the router doesn't run.
    func routerProjectID(for model: ModelChoice) async throws -> String {
        guard model.provider == "claudeAgent" else { throw FrontDoorProblem.notClaude }
        guard let folder = routerFolder() else { throw FrontDoorProblem.noFolder }
        if let id = await backend.projectID(atPath: folder) { return id }
        do {
            return try await backend.addProject(atPath: folder, title: "Shades router")
        } catch {
            // T3 turns away a second project at the same folder, which another question may have just added.
            if let id = await backend.projectID(atPath: folder) { return id }
            throw error
        }
    }

    /// Gives your words to a kitten, in a new thread in its workspace. T3 writes the title.
    /// `onStarted` hears the new thread, or `nil` if there isn't one.
    /// `asked` is `questionsAsked` when you sent them, if that was before now.
    func give(_ words: String, to kitten: Kitten, snapshot: ScreenSnapshot?, as errand: Errand = .work, asked: Int? = nil, onStarted: ((String?) -> Void)? = nil) {
        // As with a session, a kitten with full access doesn't get to see text from a page. Nor does
        // one whose thread would count as a kitten's that isn't meant to see it, in a project they share.
        let sharesWithScreenless = loadKittens().contains {
            !$0.seesScreen && KittenBoard.belongs(title: "", projectPath: kitten.workspace, to: $0)
        }
        let seesScreen = kitten.seesScreen && settings.frontierMode != .fullAccess && !sharesWithScreenless
        // Your words alone would only make sense with the file, so nothing goes, except a correction in them,
        // which the owner gets on its own.
        if !seesScreen, snapshot?.droppedName != nil {
            onStarted?(nil)
            say(CatWords.cantTakeFiles(kitten.name))
            if errand == .correction { give(words, to: kitten, snapshot: nil, as: .correctionCopy) }
            return
        }
        let shared = seesScreen ? snapshot : nil
        // A copy of a correction goes beside your message, which already warns.
        let missesScreen = errand != .correctionCopy && !carriesScreen(shared) && ScreenWords.pointAtScreen(words)
        let asked = asked ?? questionsAsked
        flow = Task {
            guard let projectID = await backend.projectID(atPath: kitten.workspace) else {
                onStarted?(nil)
                tell(CatWords.notSetUp(kitten), as: errand)
                return
            }
            startFrontier(
                title: nil,
                text: Prompts.forKitten(
                    kitten,
                    words: words,
                    snapshot: shared,
                    screenshotPath: saveScreenshot(of: shared),
                    screenLeftOut: !seesScreen && snapshot != nil,
                    correction: errand != .work
                ),
                snapshot: shared,
                projectID: projectID,
                name: kitten.name,
                as: errand,
                missesScreen: missesScreen,
                asked: asked,
                onStarted: onStarted
            )
        }
    }

    /// Passes your words to a session that already has the context. The session's reply comes
    /// back the usual way, as a notice when it finishes.
    /// `refused` hears if it couldn't take what you dropped, so nothing went.
    func forward(
        _ words: String,
        to thread: AgentThread,
        snapshot: ScreenSnapshot?,
        correction: Bool = false,
        asked: Int? = nil,
        refused: (() -> Void)? = nil
    ) {
        // Quick chats are left out of the thread list's news, so their replies are picked up here.
        let isQuick = watch.isQuick(thread.id)
        let asked = asked ?? questionsAsked
        forwardTask = Task {
            // A session with full access can do anything, so text from a page doesn't get to reach it.
            // Neither does one working for a kitten that isn't meant to see it, or one that won't say.
            var seesScreen = thread.runtimeMode != nil && thread.runtimeMode != .fullAccess
            if seesScreen, snapshot != nil { seesScreen = await isClearOfScreenlessKittens(thread) }
            guard seesScreen || snapshot?.droppedName == nil else {
                say(CatWords.cantTakeFiles(thread.title))
                refused?()
                return
            }
            // What it says about a correction has to reach you, even if it starts threads elsewhere. It's marked as it
            // goes, so a restart while it waits behind a busy run can't lose that, and unmarked below if it never got there.
            if correction {
                correctionSends.start(thread.id, wasDispatcher: dispatchers.contains(thread.id), wasCorrected: inbox.wasCorrected(thread.id))
                dispatchers.remove(thread.id)
                noteCorrection(in: thread.id)
            }
            say(CatWords.sentTo(thread), threadID: thread.id)
            let shared = seesScreen ? snapshot : nil
            let text = Prompts.forwarded(
                words: words,
                snapshot: shared,
                screenshotPath: saveScreenshot(of: shared),
                screenLeftOut: !seesScreen && snapshot != nil,
                correction: correction
            )
            let missesScreen = !carriesScreen(shared) && ScreenWords.pointAtScreen(words, isFollowUp: true)
            var warning: Int?
            var heardBack = false
            var reached = true
            do {
                for try await event in backend.forward(threadID: thread.id, text: text, attachments: attachments(for: shared)) {
                    if case .started = event {
                        if missesScreen {
                            warning = sayPassedOn(CatWords.sentTo(thread), threadID: thread.id, missesScreen: true, asked: asked, followUp: true)
                        }
                        continue
                    }
                    heardBack = true
                    switch event {
                    case .finished where isQuick:
                        reportOn(thread, failed: false)
                    case .failed(let message):
                        if let warning { takeBackNotice(warning) }
                        if isQuick { say(message) }
                    default:
                        break
                    }
                }
            } catch {
                // T3 says it's started before it sends, so only hearing back means your words got there.
                // After that, losing the connection doesn't take them back, the same as with a new thread.
                if !heardBack, let warning { takeBackNotice(warning) }
                reached = heardBack
                say(CatWords.problem(error, while: .agents))
            }
            if correction, let before = correctionSends.end(thread.id, reached: reached) {
                if before.wasDispatcher { dispatchers.insert(thread.id) }
                if !before.wasCorrected { forgetCorrection(in: thread.id) }
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
