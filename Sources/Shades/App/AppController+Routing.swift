import Foundation
import ShadesCore

enum FrontDoorProblem: LocalizedError, Equatable {
    case notClaude, noFolder

    var errorDescription: String? {
        switch self {
        case .notClaude: return CatWords.frontDoorNotClaude
        case .noFolder: return CatWords.frontDoorNoFolder
        }
    }
}

extension AppController {
    static let rosterSize = 10
    static let rosterWindow: TimeInterval = 24 * 60 * 60
    static let rosterWait: TimeInterval = 1.5

    func waitForThreadList() async {
        let deadline = Date().addingTimeInterval(threadListWait)
        while !threadListArrived, Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    func rosterThreads(excluding current: String?, only isOffered: (AgentThread) -> Bool = { _ in true }) -> [AgentThread] {
        let at = now()
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

    @discardableResult
    func sayPassedOn(_ said: String, threadID: String, missesScreen: Bool, asked: Int, followUp: Bool = false) -> Int? {
        guard missesScreen, asked == questionsAsked else {
            say(said, threadID: threadID, fades: true)
            return nil
        }
        line = nil
        post(caption: said, text: CatWords.sendTheLink, threadID: threadID, first: true)
        if let index = notices.firstIndex(where: { $0.id == lineCounter }) { notices[index].followUp = followUp }
        return lineCounter
    }

    func carriesScreen(_ shared: ScreenSnapshot?) -> Bool {
        shared.map { !$0.isPrivate } ?? false
    }

    func dropScreenWarning(for threadID: String?, run: String? = nil) {
        notices.removeAll { $0.text == CatWords.sendTheLink && $0.threadID == threadID && !$0.followUp && (run == nil || $0.after != run) }
        renderBubble()
    }

    func dropScreenWarnings(forFailuresIn threads: [AgentThread]) {
        let failed = Dictionary(threads.filter { $0.status == .failed }.map { ($0.id, $0.lastRunID) }, uniquingKeysWith: { first, _ in first })
        let before = notices.count
        notices.removeAll { notice in
            guard notice.text == CatWords.sendTheLink, !notice.followUp, let id = notice.threadID, let run = failed[id] else { return false }
            return notice.after == nil || (run != nil && notice.after != run)
        }
        if notices.count != before { renderBubble() }
    }

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

    func takeBackNotice(_ id: Int) {
        notices.removeAll { $0.id == id }
        renderBubble()
    }

    // Outside the repo: only Claude Code reads the router folder's settings, so no other provider can be the router.
    func routerProjectID(for model: ModelChoice) async throws -> String {
        guard model.provider == "claudeAgent" else { throw FrontDoorProblem.notClaude }
        guard let folder = routerFolder() else { throw FrontDoorProblem.noFolder }
        if let id = await backend.projectID(atPath: folder) { return id }
        do {
            return try await backend.addProject(atPath: folder, title: "Shades router")
        } catch {
            // Outside the repo: T3 turns away a second project at the same folder, which another question may have just added.
            if let id = await backend.projectID(atPath: folder) { return id }
            throw error
        }
    }

    func give(_ words: String, to kitten: Kitten, snapshot: ScreenSnapshot?, as errand: Errand = .work, youPicked: Bool = false, asked: Int? = nil, onStarted: ((String?) -> Void)? = nil, refused: (() -> Void)? = nil) {
        let seesScreen = mayHaveScreen(kitten)
        if !seesScreen, snapshot?.isDropped == true {
            if let refused { refused() } else { onStarted?(nil) }
            say(CatWords.cantTakeFiles(kitten.name))
            if errand == .correction { give(words, to: kitten, snapshot: nil, as: .correctionCopy) }
            return
        }
        let shared = seesScreen ? snapshot : nil
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
                youPicked: youPicked,
                missesScreen: missesScreen,
                asked: asked,
                onStarted: onStarted
            )
        }
    }

    func mayHaveScreen(_ kitten: Kitten) -> Bool {
        let sharesWithScreenless = loadKittens().contains {
            !$0.seesScreen && KittenBoard.belongs(title: "", projectPath: kitten.workspace, to: $0)
        }
        return kitten.seesScreen && settings.frontierMode != .fullAccess && !sharesWithScreenless
    }

    static func mayHaveScreen(_ mode: RuntimeMode?) -> Bool {
        mode != nil && mode != .fullAccess
    }

    func takesFiles(_ target: MessageTarget) -> Bool {
        guard target.takesFiles else { return false }
        switch target {
        case .router:
            guard settings.lockdown != nil else { return settings.quickMode != .fullAccess }
            guard let kitten = lockedDownKitten else { return false }
            if let id = settings.lockdown?.thread { return latestThreads.first { $0.id == id }.map(takesFiles) ?? false }
            return mayHaveScreen(kitten)
        case .newThread(let kitten):
            return mayHaveScreen(kitten)
        case .thread(let id, _, _):
            return (latestThreads.first { $0.id == id } ?? channels.listed(id)).map(takesFiles) ?? false
        case .starting, .question:
            return false
        }
    }

    private func takesFiles(_ thread: AgentThread) -> Bool {
        Self.mayHaveScreen(thread.runtimeMode) && !loadKittens().contains { !$0.seesScreen && KittenBoard.belongs(thread, to: $0) }
    }

    func forward(
        _ words: String,
        to thread: AgentThread,
        snapshot: ScreenSnapshot?,
        correction: Bool = false,
        youPicked: Bool = false,
        behavior: FollowUpBehavior = .queue,
        asked: Int? = nil,
        refused: (() -> Void)? = nil,
        unheard: ((String) -> Void)? = nil
    ) {
        let isQuick = watch.isQuick(thread.id)
        let asked = asked ?? questionsAsked
        forwardTask = Task {
            var seesScreen = Self.mayHaveScreen(thread.runtimeMode)
            if seesScreen, snapshot != nil { seesScreen = await isClearOfScreenlessKittens(thread) }
            guard seesScreen || snapshot?.isDropped != true else {
                say(CatWords.cantTakeFiles(thread.title))
                refused?()
                return
            }
            if correction {
                correctionSends.start(thread.id, wasDispatcher: dispatchers.contains(thread.id), wasCorrected: inbox.wasCorrected(thread.id))
                dispatchers.remove(thread.id)
                noteCorrection(in: thread.id)
            }
            if !youPicked { say(CatWords.sentTo(thread), threadID: thread.id, fades: true) }
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
                for try await event in backend.forward(threadID: thread.id, text: text, attachments: attachments(for: shared), behavior: behavior) {
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
                        if isQuick { say(message, unasked: true) }
                    default:
                        break
                    }
                }
            } catch {
                if !heardBack, let warning { takeBackNotice(warning) }
                reached = heardBack
                let problem = CatWords.problem(error, while: .agents)
                if !heardBack { unheard?(problem) }
                say(problem, unasked: heardBack)
            }
            if correction, let before = correctionSends.end(thread.id, reached: reached) {
                if before.wasDispatcher { dispatchers.insert(thread.id) }
                if !before.wasCorrected { forgetCorrection(in: thread.id) }
            }
        }
    }

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
