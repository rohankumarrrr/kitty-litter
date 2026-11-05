import CoreGraphics
@testable import Shades
import ShadesCore
import XCTest

// Everything is faked here, so these run the real flows with no windows, agents or microphone.

private final class Log: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    func add(_ entry: String) {
        lock.lock()
        entries.append(entry)
        lock.unlock()
    }

    var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }
}

@MainActor
private final class FakeStage: CatStage {
    let log: Log
    var bubbles: [BubbleContent?] = []
    var input: InputRequest?
    var inputText: [String] = []
    var status: CatStatus = .none
    var busy = false
    var celebrated = 0
    var wentHome = 0
    var came = 0
    var ranTo: CGRect?
    var held: [String?] = []
    var threads: [AgentThread] = []
    var statusText = ""
    var copied: String?
    var arriveImmediately = true
    var pendingArrival: (() -> Void)?

    init(log: Log) { self.log = log }

    var bubble: BubbleContent? { bubbles.last ?? nil }

    func catWake() {}
    func catSay(_ word: String) {}
    func catHold(_ word: String?) { held.append(word) }
    func catStatus(_ status: CatStatus) { self.status = status }
    func catLevel(_ level: Float) {}
    func catAgentsBusy(_ busy: Bool) { self.busy = busy }
    func catCelebrate() { celebrated += 1 }
    func catPet() {}
    func catComeToYou(arrived: @escaping () -> Void) {
        came += 1
        if arriveImmediately { arrived() } else { pendingArrival = arrived }
    }
    func catRun(toRegion region: CGRect, arrived: @escaping () -> Void) {
        ranTo = region
        log.add("catRun")
        arrived()
    }
    func catGoHome() { wentHome += 1 }
    func showBubble(_ content: BubbleContent?) { bubbles.append(content) }
    var isInputVisible: Bool { input != nil }
    func showInput(_ request: InputRequest) {
        log.add("showInput")
        input = request
    }
    func setInputText(_ text: String) { inputText.append(text) }
    func submitInput(_ text: String) {
        let request = input
        input = nil
        request?.onSubmit(text)
    }
    func hideInput() {
        let request = input
        input = nil
        request?.onCancel()
    }
    func showThreads(_ threads: [AgentThread], status: String) {
        self.threads = threads
        statusText = status
    }
    func toggleDashboard() {}
    func showSettings(_ settings: Settings, onSave: @escaping (Settings) -> Void) {}
    func copyToPasteboard(_ text: String) { copied = text }

    /// What a person does: types into the panel and presses Return.
    func type(_ text: String) {
        submitInput(text)
    }
}

private final class FakeBackend: AgentBackend, @unchecked Sendable {
    enum Mode: String { case start, followUp, forward }
    struct Sent {
        var mode: Mode
        var threadID: String?
        var prompt: AgentPrompt
    }

    private let lock = NSLock()
    private var _sent: [Sent] = []
    private var _responses: [(String, ApprovalDecision)] = []
    private var _opened: [String] = []
    private var watcher: AsyncStream<[AgentThread]>.Continuation?
    var replies: [[AgentReplyEvent]] = []
    var reports: [String: String] = [:]
    var projects: [String: String] = [:]
    var settled: [String] = []
    var archived: [String] = []
    var failFollowUps = false
    var failResponses = false
    var connectError: Error?
    var streamError: Error?
    private var count = 0

    var sent: [Sent] { lock.withLock { _sent } }
    var responses: [(String, ApprovalDecision)] { lock.withLock { _responses } }
    var opened: [String] { lock.withLock { _opened } }

    func connect() async throws {
        if let connectError { throw connectError }
    }

    func start(_ prompt: AgentPrompt) -> AsyncThrowingStream<AgentReplyEvent, Error> {
        let id = lock.withLock { () -> Int in
            count += 1
            _sent.append(Sent(mode: .start, threadID: nil, prompt: prompt))
            return count
        }
        return play(threadID: "thread-\(id)")
    }

    func followUp(threadID: String, _ prompt: AgentPrompt) -> AsyncThrowingStream<AgentReplyEvent, Error> {
        lock.withLock { _sent.append(Sent(mode: .followUp, threadID: threadID, prompt: prompt)) }
        if failFollowUps {
            return AsyncThrowingStream { $0.finish(throwing: URLError(.badServerResponse)) }
        }
        return play(threadID: threadID)
    }

    private func play(threadID: String) -> AsyncThrowingStream<AgentReplyEvent, Error> {
        let events = lock.withLock { replies.isEmpty ? [AgentReplyEvent.finished(fullText: "Okay.")] : replies.removeFirst() }
        let error = streamError
        return AsyncThrowingStream { continuation in
            if let error {
                continuation.finish(throwing: error)
                return
            }
            continuation.yield(.started(threadID: threadID))
            events.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }

    func forward(threadID: String, text: String, attachments: [AgentAttachment]) -> AsyncThrowingStream<AgentReplyEvent, Error> {
        let prompt = AgentPrompt(text: text, attachments: attachments, model: .quick, runtimeMode: .auto)
        lock.withLock { _sent.append(Sent(mode: .forward, threadID: threadID, prompt: prompt)) }
        return play(threadID: threadID)
    }

    func watchThreads() -> AsyncStream<[AgentThread]> {
        AsyncStream { continuation in watcher = continuation }
    }

    func respond(to request: ApprovalRequest, with decision: ApprovalDecision) async throws {
        if failResponses { throw URLError(.notConnectedToInternet) }
        lock.withLock { _responses.append((request.id, decision)) }
    }

    func projectID(atPath path: String) async -> String? {
        projects[path]
    }

    func archive(threadID: String) async throws {
        archived.append(threadID)
    }

    func settle(threadID: String) async throws {
        settled.append(threadID)
    }

    func finalReport(threadID: String) async -> String? {
        reports[threadID]
    }

    func open(threadID: String) {
        lock.withLock { _opened.append(threadID) }
    }
}

private final class FakeContext: ScreenContextProviding, @unchecked Sendable {
    let log: Log
    var snapshotValue = ScreenSnapshot(appName: "Safari", windowTitle: "Pricing", screenshotJPEG: Data([1, 2, 3]))
    var region: CGRect? = CGRect(x: 100, y: 200, width: 50, height: 60)
    var saved = 0
    private(set) var options: [CaptureOptions] = []

    init(log: Log) { self.log = log }

    func snapshot(_ options: CaptureOptions) async throws -> ScreenSnapshot {
        log.add("snapshot")
        self.options.append(options)
        return snapshotValue
    }

    func pickRegion() async -> CGRect? {
        log.add("pickRegion")
        return region
    }

    func saveScreenshot(of snapshot: ScreenSnapshot) throws -> String? {
        saved += 1
        return snapshot.screenshotJPEG == nil ? nil : "/tmp/shot.jpg"
    }
}

private final class FakeVoice: VoiceEngine {
    let partials: AsyncStream<String>
    let levels: AsyncStream<Float>
    let partialsIn: AsyncStream<String>.Continuation
    private let levelsIn: AsyncStream<Float>.Continuation
    var transcript = Transcript(raw: "what is this", cleaned: "What is this?", audioSeconds: 1, latencySeconds: 0.1)
    var beginError: Error?
    var vocabulary: [String] = []
    var began = 0
    var cancelled = 0

    init() {
        (partials, partialsIn) = AsyncStream.makeStream(of: String.self)
        (levels, levelsIn) = AsyncStream.makeStream(of: Float.self)
    }

    func prepare() async throws {}
    func setVocabulary(_ words: [String]) { vocabulary = words }
    func begin() throws {
        if let beginError { throw beginError }
        began += 1
    }
    func end() async throws -> Transcript { transcript }
    func cancel() { cancelled += 1 }
}

private final class FakeInserter: TextInserting {
    var inserted: [String] = []
    func insert(_ text: String) async throws { inserted.append(text) }
}

private final class FakeKeys: KeyHoldMonitoring {
    var onPress: ((HoldKey) -> Void)?
    var onRelease: ((HoldKey) -> Void)?
    func start(keys: [HoldKey]) throws {}
    func stop() {}
}

private struct Friendly: LocalizedError {
    var errorDescription: String?
}

@MainActor
final class FlowTests: XCTestCase {
    private var log: Log!
    private var stage: FakeStage!
    private var backend: FakeBackend!
    private var context: FakeContext!
    private var voice: FakeVoice!
    private var inserter: FakeInserter!
    private var keys: FakeKeys!
    private var clock = Date(timeIntervalSince1970: 100_000)
    private var kittens: [Kitten] = []
    private var controller: AppController!
    private var settings: Settings {
        var settings = Settings()
        settings.quickModel = ModelChoice(provider: "codex", model: "gpt-6.1-sol", effort: "medium")
        settings.frontierModel = ModelChoice(provider: "claudeAgent", model: "claude-fable-5-1", effort: "high")
        settings.quickMode = .approvalRequired
        settings.frontierMode = .autoAcceptEdits
        return settings
    }

    override func setUp() async throws {
        log = Log()
        stage = FakeStage(log: log)
        backend = FakeBackend()
        context = FakeContext(log: log)
        voice = FakeVoice()
        inserter = FakeInserter()
        keys = FakeKeys()
        controller = AppController(
            dependencies: AppDependencies(
                backend: backend,
                context: context,
                voice: voice,
                inserter: inserter,
                keys: keys,
                settings: settings,
                saveSettings: { _ in },
                kittens: { [unowned self] in self.kittens }
            ),
            stage: stage,
            now: { [unowned self] in self.clock }
        )
        controller.threadListWait = 0
        controller.reportDelay = 0
    }

    private func settle() async {
        await controller.flow?.value
        await controller.replyTask?.value
        await controller.frontierTask?.value
        await controller.forwardTask?.value
        await controller.voiceTask?.value
        for _ in 0..<20 { await Task.yield() }
    }

    private func ask(_ question: String) async {
        await controller.beginAsk()
        stage.type(question)
        await settle()
    }

    private func request(_ id: String = "r1", thread: String = "w", kind: ApprovalKind = .command) -> ApprovalRequest {
        ApprovalRequest(id: id, threadID: thread, threadTitle: "Work", kind: kind, summary: "npm test", createdAt: Date(timeIntervalSince1970: 1))
    }

    // MARK: - Ask

    func testTheSnapshotComesBeforeThePanel() async {
        await controller.beginAsk()
        XCTAssertEqual(log.all, ["snapshot", "showInput"])
    }

    func testAskSendsTheQuickPromptWithTheScreenshot() async {
        backend.replies = [[.text(delta: "Hi."), .finished(fullText: "Hi.")]]
        await ask("what's this?")
        let sent = backend.sent[0]
        XCTAssertEqual(sent.mode, .start)
        XCTAssertEqual(sent.prompt.model, settings.quickModel)
        XCTAssertEqual(sent.prompt.runtimeMode, .approvalRequired)
        XCTAssertNil(sent.prompt.projectID)
        XCTAssertTrue(sent.prompt.text.contains("Their question: what's this?"))
        XCTAssertTrue(sent.prompt.text.contains("App: Safari"))
        XCTAssertEqual(sent.prompt.attachments.first?.data, Data([1, 2, 3]))
        XCTAssertEqual(sent.prompt.attachments.first?.mimeType, "image/jpeg")
        XCTAssertEqual(stage.bubble, .reply(text: "Hi.", done: true, threadID: "thread-1", note: nil))
    }

    func testShowsThinkingStraightAway() async {
        await controller.beginAsk()
        XCTAssertNil(stage.bubble)
        stage.type("hello?")
        XCTAssertEqual(stage.bubble, .thinking(note: nil))
        XCTAssertEqual(stage.status, .thinking)
        await settle()
        XCTAssertEqual(stage.status, .none)
    }

    func testFollowUpsReuseTheThreadForTenMinutes() async {
        await ask("one")
        clock.addTimeInterval(9 * 60)
        await ask("two")
        XCTAssertEqual(backend.sent[1].mode, .followUp)
        XCTAssertEqual(backend.sent[1].threadID, "thread-1")
        clock.addTimeInterval(10 * 60 + 5)
        await ask("three")
        XCTAssertEqual(backend.sent[2].mode, .start)
    }

    func testAGoneThreadQuietlyStartsFresh() async {
        await ask("one")
        backend.failFollowUps = true
        backend.replies = [[.text(delta: "Fresh."), .finished(fullText: "Fresh.")]]
        await ask("two")
        XCTAssertEqual(backend.sent.map(\.mode), [.start, .followUp, .start])
        XCTAssertEqual(stage.bubble, .reply(text: "Fresh.", done: true, threadID: "thread-2", note: nil))
    }

    // MARK: - Handing off

    func testAHandoffIsNeverShownAsAnAnswer() async {
        backend.replies = [
            [
                .text(delta: "HAND"), .text(delta: "OFF: Fix"), .text(delta: " the bug"),
                .finished(fullText: "HANDOFF: Fix the bug"),
            ],
            [.finished(fullText: "Done.")],
        ]
        await ask("fix it")
        for bubble in stage.bubbles {
            if case .reply? = bubble { XCTFail("a handoff was shown as a reply") }
        }
    }

    func testAHandoffStartsTheFrontierAgentByItself() async {
        backend.replies = [
            [.finished(fullText: "HANDOFF: Fix the bug")],
            [.finished(fullText: "Done.")],
        ]
        await ask("please fix it")

        XCTAssertEqual(backend.sent.count, 2)
        XCTAssertEqual(context.saved, 1)
        let sent = backend.sent[1]
        XCTAssertEqual(sent.mode, .start)
        XCTAssertEqual(sent.prompt.model, settings.frontierModel)
        XCTAssertEqual(sent.prompt.runtimeMode, .autoAcceptEdits)
        XCTAssertNil(sent.prompt.projectID)
        XCTAssertEqual(sent.prompt.title, "Fix the bug")
        XCTAssertTrue(sent.prompt.text.contains("Screenshot file: /tmp/shot.jpg"))
        XCTAssertTrue(sent.prompt.text.contains("Fix the bug"))
        XCTAssertTrue(sent.prompt.text.contains("please fix it"))
        XCTAssertEqual(sent.prompt.attachments.count, 1)
        XCTAssertTrue(stage.bubbles.contains(.line("Passing it to Fable...", threadID: nil)))
        XCTAssertEqual(stage.bubble, .line("Fable has this.", threadID: "thread-2"))
    }

    func testCancellingBeforeTheReplyStopsAHandoff() async {
        controller.ask("fix it", snapshot: nil)
        controller.bubbleDismissed(byClick: false)
        backend.replies = [[.finished(fullText: "HANDOFF: Fix the bug")]]
        await settle()
        XCTAssertLessThanOrEqual(backend.sent.count, 1)
    }

    // MARK: - Settling

    func testASimpleAnswerSettlesItsThread() async {
        backend.replies = [[.finished(fullText: "Red.")]]
        await ask("what colour?")
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(backend.settled, ["thread-1"])
        XCTAssertEqual(backend.archived, [])
    }

    func testANewThreadThatOnlyPassedWorkOnIsTidiedAway() async {
        backend.replies = [[.finished(fullText: "HANDOFF: Fix the bug")], [.finished(fullText: "Done.")]]
        await ask("fix it")
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(backend.archived, ["thread-1"])
        XCTAssertEqual(backend.settled, [])
    }

    func testAConversationThatLaterPassesWorkOnIsKept() async {
        backend.replies = [[.finished(fullText: "Red.")], [.finished(fullText: "HANDOFF: Fix the bug")], [.finished(fullText: "Done.")]]
        await ask("what colour?")
        await ask("now fix it")
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(backend.settled, ["thread-1", "thread-1"])
        XCTAssertEqual(backend.archived, [])
    }

    // MARK: - Routing

    private func session(_ id: String, _ title: String, status: AgentStatus = .completed, mode: RuntimeMode = .auto, age: TimeInterval = 60) -> AgentThread {
        AgentThread(id: id, title: title, projectTitle: nil, status: status, model: "claude-opus-5-5", updatedAt: clock.addingTimeInterval(-age), runtimeMode: mode)
    }

    /// What really happened: a follow-up to Opus's report went to the Sol chat, which had never seen it.
    func testAFollowUpAfterAHandoffGoesToTheSessionDoingTheWork() async {
        backend.replies = [
            [.finished(fullText: "HANDOFF: Review the video")],
            [.finished(fullText: "Done.")],
            [.finished(fullText: "SEND TO: 1")],
        ]
        await ask("what can I learn from this video?")

        backend.reports["thread-2"] = "The main lesson is verification."
        controller.threadsChanged([session("thread-2", "Review the video")])
        await ask("I don't mean just CareerPilot")

        let router = backend.sent[2].prompt.text
        XCTAssertTrue(router.contains("1. Review the video"))
        XCTAssertTrue(router.contains("Last said: The main lesson is verification."))

        let forwarded = backend.sent[3]
        XCTAssertEqual(forwarded.mode, .forward)
        XCTAssertEqual(forwarded.threadID, "thread-2")
        XCTAssertTrue(forwarded.prompt.text.hasPrefix("I don't mean just CareerPilot\n"))
        XCTAssertEqual(stage.bubble, .line("Sent that to Review the video.", threadID: "thread-2"))
        for bubble in stage.bubbles {
            if case .reply? = bubble { XCTFail("the routing decision was shown as an answer") }
        }
    }

    func testPassingOnIsNeverShownAsAnAnswerEvenWhileStreaming() async {
        controller.threadsChanged([session("w", "Work")])
        backend.replies = [[.text(delta: "SE"), .text(delta: "ND TO"), .text(delta: ": 1"), .finished(fullText: "SEND TO: 1")]]
        await ask("and that part?")
        for bubble in stage.bubbles {
            if case .reply? = bubble { XCTFail("the routing decision was shown as an answer") }
        }
        XCTAssertEqual(backend.sent.last?.mode, .forward)
    }

    func testASessionWithFullAccessGetsYourWordsButNotYourScreen() async {
        controller.threadsChanged([session("w", "Work", mode: .fullAccess)])
        backend.replies = [[.finished(fullText: "SEND TO: 1")]]
        await ask("and that part?")
        let forwarded = backend.sent[1].prompt
        XCTAssertTrue(forwarded.text.hasPrefix("and that part?"))
        XCTAssertTrue(forwarded.text.contains("left out"))
        XCTAssertFalse(forwarded.text.contains("<screen>"))
        XCTAssertTrue(forwarded.attachments.isEmpty)
        XCTAssertEqual(context.saved, 0)
    }

    func testAnOrdinarySessionSeesYourScreenToo() async {
        controller.threadsChanged([session("w", "Work")])
        backend.replies = [[.finished(fullText: "SEND TO: 1")]]
        await ask("and that part?")
        let forwarded = backend.sent[1].prompt
        XCTAssertTrue(forwarded.text.contains("<screen>"))
        XCTAssertEqual(forwarded.attachments.count, 1)
    }

    func testANumberThatIsntOnTheListSendsNothing() async {
        controller.threadsChanged([session("w", "Work")])
        backend.replies = [[.finished(fullText: "SEND TO: 7")]]
        await ask("and that part?")
        XCTAssertEqual(backend.sent.count, 1)
        XCTAssertEqual(stage.bubble, .line("I lost track of which session that was for. Try asking again?", threadID: nil))
    }

    func testTheRouterSeesRecentSessionsWithWhatsRunningFirst() async {
        controller.threadsChanged([
            session("old", "Old work", age: 2 * 24 * 60 * 60),
            session("done", "Finished work", age: 300),
            session("busy", "Running work", status: .running, age: 3000),
        ])
        await ask("hello")
        let router = backend.sent[0].prompt.text
        XCTAssertTrue(router.contains("1. Running work"))
        XCTAssertTrue(router.contains("2. Finished work"))
        XCTAssertFalse(router.contains("Old work"))
    }

    private let steve = Kitten(name: "Steve Pawsniak", role: "Professional", covers: "resumes and interviews", folder: "/k/steve")

    func testTheRouterKnowsTheKittens() async {
        kittens = [steve]
        await ask("hello")
        XCTAssertTrue(backend.sent[0].prompt.text.contains("1. Steve Pawsniak, Professional: resumes and interviews"))
    }

    func testAKittensAreaGoesToItWithYourWordsAndYourScreen() async {
        kittens = [steve]
        backend.projects["/k/steve"] = "project-steve"
        backend.replies = [[.finished(fullText: "KITTEN: 1")], [.finished(fullText: "Started.")]]
        await ask("I need a tailored resume for this job")
        await controller.frontierTask?.value

        XCTAssertEqual(backend.sent.count, 2)
        let given = backend.sent[1]
        XCTAssertEqual(given.mode, .start)
        XCTAssertEqual(given.prompt.projectID, "project-steve")
        XCTAssertNil(given.prompt.title, "T3 writes a better one")
        XCTAssertEqual(given.prompt.model, settings.frontierModel)
        XCTAssertTrue(given.prompt.text.hasPrefix("I need a tailored resume for this job\n"))
        XCTAssertTrue(given.prompt.text.contains("<screen>"))
        XCTAssertEqual(given.prompt.attachments.count, 1)
        XCTAssertTrue(stage.bubbles.contains(.line("Passing it to Steve Pawsniak...", threadID: nil)))
        XCTAssertEqual(stage.bubble, .line("Steve Pawsniak has this.", threadID: "thread-2"))
        for bubble in stage.bubbles {
            if case .reply? = bubble { XCTFail("the routing decision was shown as an answer") }
        }
    }

    func testAKittenThatIsntInT3SaysSo() async {
        kittens = [steve]
        backend.replies = [[.finished(fullText: "KITTEN: 1")]]
        await ask("I need a tailored resume")
        await controller.flow?.value
        XCTAssertEqual(backend.sent.count, 1)
        XCTAssertEqual(stage.bubble, .line("Steve Pawsniak isn't a T3 project yet. Add /k/steve in T3 and try again.", threadID: nil))
    }

    func testAKittensNumberThatIsntOnTheListGoesNowhere() async {
        kittens = [steve]
        backend.replies = [[.finished(fullText: "KITTEN: 4")]]
        await ask("I need a tailored resume")
        XCTAssertEqual(backend.sent.count, 1)
        XCTAssertEqual(stage.bubble, .line("I lost track of which session that was for. Try asking again?", threadID: nil))
    }

    func testAKittensReportSaysWhoItsFrom() async {
        kittens = [steve]
        backend.reports["w"] = "Your resume is ready."
        var work = AgentThread(id: "w", title: "Tailor resume", projectTitle: "Steve Pawsniak", status: .running, model: "m", updatedAt: clock)
        controller.threadsChanged([work])
        work.status = .completed
        controller.threadsChanged([work])
        await controller.reportTask?.value
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(stage.bubble, .notice(caption: "Steve Pawsniak: Tailor resume", text: "Your resume is ready.", threadID: "w"))
    }

    func testAQuestionRightAfterLaunchWaitsForTheSessions() async {
        controller.threadListWait = 2
        let asking = Task { await ask("and that part?") }
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(backend.sent.isEmpty, "the list hasn't arrived yet")
        controller.threadsChanged([session("w", "Work")])
        await asking.value
        XCTAssertTrue(backend.sent[0].prompt.text.contains("1. Work"))
    }

    func testTheRouterDoesntListTheChatItsIn() async {
        backend.replies = [[.finished(fullText: "Red.")], [.finished(fullText: "Blue.")]]
        await ask("what colour?")
        controller.threadsChanged([session("thread-1", "What colour?")])
        await ask("and now?")
        XCTAssertFalse(backend.sent[1].prompt.text.contains("1. What colour?"))
    }

    func testAnAgentThatOnlyStartedAnotherSessionStepsAside() async {
        backend.replies = [[.finished(fullText: "HANDOFF: Fix the bug")], [.finished(fullText: "Started.")]]
        await ask("fix it")

        var opus = session("thread-2", "Fix the bug", status: .running)
        let worker = session("worker", "Fix the login bug", status: .running)
        controller.threadsChanged([opus, worker])
        backend.reports["thread-2"] = "The change went to a new thread, <t3-thread://v2/env/worker>, in a worktree."
        opus.status = .completed
        controller.threadsChanged([opus, worker])
        await controller.reportTask?.value
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(stage.bubble, .line("Work's started in a new session: Fix the login bug.", threadID: "worker"))
        XCTAssertTrue(backend.settled.contains("thread-2"))
        XCTAssertEqual(backend.sent.count, 2, "no summary for a thread that only passed work on")

        backend.replies = [[.finished(fullText: "Okay.")]]
        await ask("how's it going?")
        let router = backend.sent[2].prompt.text
        XCTAssertTrue(router.contains("1. Fix the login bug"))
        XCTAssertFalse(router.contains("Fix the bug ("))
    }

    func testLoadingTheEarsDoesntTalkOverAnything() async {
        controller.say("On it.", seconds: nil)
        controller.fetchingEars(0.1)
        clock = clock.addingTimeInterval(5)
        controller.fetchingEars(0.5)
        XCTAssertEqual(stage.bubble, .line("On it.", threadID: nil))
    }

    func testAQuestionOverSeveralLinesKeepsThemButTitlesWithTheFirst() async {
        backend.replies = [[.finished(fullText: "Red.")]]
        await ask("first line\nsecond line")
        XCTAssertEqual(backend.sent[0].prompt.title, "first line")
        XCTAssertTrue(backend.sent[0].prompt.text.contains("first line\nsecond line"))
    }

    func testAFailedTurnDoesntSettle() async {
        backend.replies = [[.failed(message: "Nope")]]
        await ask("what colour?")
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(backend.settled, [])
    }

    // MARK: - Session reports

    private func finishWork(report: String?, summary: [AgentReplyEvent]? = nil, status: AgentStatus = .completed) async {
        backend.reports["w"] = report
        if let summary { backend.replies = [summary] }
        var work = thread(.running)
        work.id = "w"
        work.title = "Work"
        controller.threadsChanged([work])
        work.status = status
        controller.threadsChanged([work])
        await controller.reportTask?.value
        for _ in 0..<20 { await Task.yield() }
    }

    func testAThreadThatPicksUpAgainIsntReportedAsDone() async {
        controller.reportDelay = 0.05
        backend.reports["w"] = "A reviewer's looking at it."
        var work = session("w", "Work", status: .running)
        controller.threadsChanged([work])
        work.status = .completed
        controller.threadsChanged([work])
        work.status = .running
        controller.threadsChanged([work])
        await controller.reportTask?.value
        XCTAssertNil(stage.bubble)
        XCTAssertEqual(backend.sent.count, 0)
    }

    func testAShortReportIsPassedOnAsItIs() async {
        await finishWork(report: "Fixed the login bug. The tests pass.")
        XCTAssertEqual(stage.bubble, .notice(caption: "Done: Work", text: "Fixed the login bug. The tests pass.", threadID: "w"))
        XCTAssertEqual(backend.sent.count, 0)
    }

    func testALongReportGetsSummedUpOutOfSight() async {
        let report = "## Result\n\n" + String(repeating: "A long sentence about the work. ", count: 30)
        await finishWork(report: report, summary: [.started(threadID: "s"), .finished(fullText: " It went well. Please review the PR.\n")])

        XCTAssertEqual(stage.bubble, .notice(caption: "Done: Work", text: "It went well. Please review the PR.", threadID: "w"))
        let sent = backend.sent[0]
        XCTAssertEqual(sent.prompt.model, settings.summaryModel)
        XCTAssertEqual(sent.prompt.runtimeMode, .approvalRequired)
        XCTAssertTrue(sent.prompt.text.contains("<report>"))
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(backend.archived, ["s"])
    }

    func testAFailedSummaryFallsBackToTheReportsOpening() async {
        let report = "Fixed the bug, and the tests pass. " + String(repeating: "More detail follows here. ", count: 30)
        await finishWork(report: report, summary: [.failed(message: "Nope")])
        guard case .notice(_, let text, _)? = stage.bubble else { return XCTFail("no notice") }
        XCTAssertTrue(text.hasPrefix("Fixed the bug, and the tests pass."))
        XCTAssertLessThan(text.count, 200)
    }

    func testAFailureSaysSoAndNoReportStillSaysSomething() async {
        await finishWork(report: nil, status: .failed)
        XCTAssertEqual(stage.bubble, .notice(caption: "Hit a snag: Work", text: "It stopped before it could say why.", threadID: "w"))
    }

    func testASummaryCantAskForAnything() async {
        let request = ApprovalRequest(id: "r", threadID: "s", threadTitle: "Shades summary", kind: .command, summary: "Run: rm -rf /", createdAt: Date())
        let report = String(repeating: "A long sentence about the work. ", count: 30)
        await finishWork(report: report, summary: [.started(threadID: "s"), .needsApproval(request), .finished(fullText: "Fine.")])
        XCTAssertEqual(backend.responses.map(\.1), [.decline])
        for bubble in stage.bubbles {
            if case .approval? = bubble { XCTFail("a summary's request was shown") }
        }
    }

    func testNoticesWaitTheirTurn() async {
        await finishWork(report: "First.")
        var other = thread(.running)
        other.id = "o"
        other.title = "Other"
        backend.reports["o"] = "Second."
        controller.threadsChanged([other])
        other.status = .completed
        controller.threadsChanged([other])
        await controller.reportTask?.value
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(stage.bubble, .notice(caption: "Done: Work", text: "First.", threadID: "w"))
        controller.bubbleDismissed(byClick: true)
        XCTAssertEqual(stage.bubble, .notice(caption: "Done: Other", text: "Second.", threadID: "o"))
        controller.bubbleDismissed(byClick: false)
        XCTAssertNil(stage.bubble)
    }

    func testAQuestionShowsItsOptionsAndWaitsForAnAnswer() async {
        var work = thread(.running)
        work.id = "w"
        work.title = "Work"
        controller.threadsChanged([work])

        // The thread stops first, and the words follow a moment later.
        work.status = .waitingForAnswer
        controller.threadsChanged([work])
        XCTAssertNil(stage.bubble)

        work.pendingQuestion = AgentQuestion(id: "q", threadID: "w", threadTitle: "Work", text: "Which one?", options: ["A (Recommended)", "B"], moreCount: 1)
        controller.threadsChanged([work])
        let expected = BubbleContent.notice(
            caption: "Asking: Work",
            text: "Which one?\n\n• A (Recommended)\n• B\n\nAnd 1 more question.",
            threadID: "w"
        )
        XCTAssertEqual(stage.bubble, expected)

        // Only once, and a stray click doesn't lose it.
        controller.threadsChanged([work])
        controller.bubbleDismissed(byClick: true)
        XCTAssertEqual(stage.bubble, expected)

        work.pendingQuestion = nil
        work.status = .running
        controller.threadsChanged([work])
        XCTAssertNil(stage.bubble)
    }

    // MARK: - Fix

    func testFixPicksThenLooksThenAsks() async {
        await controller.beginFix()
        XCTAssertEqual(log.all, ["pickRegion", "catRun", "snapshot", "showInput"])
        XCTAssertEqual(context.options.last?.focusRegion, context.region)
        XCTAssertEqual(stage.ranTo, context.region)
    }

    func testFixWithNothingSaidIsFine() async {
        await controller.beginFix()
        XCTAssertEqual(stage.input?.allowsEmpty, true)
        stage.type("")
        await settle()
        let sent = backend.sent[0]
        XCTAssertEqual(sent.prompt.model, settings.frontierModel)
        XCTAssertEqual(sent.prompt.runtimeMode, .autoAcceptEdits)
        XCTAssertNil(sent.prompt.projectID)
        XCTAssertTrue(sent.prompt.text.contains("red rectangle"))
        XCTAssertTrue(sent.prompt.text.contains("didn't describe it"))
        XCTAssertTrue(sent.prompt.text.contains("Screenshot file: /tmp/shot.jpg"))
        XCTAssertEqual(context.saved, 1)
    }

    func testFixPassesAlongWhatYouSaid() async {
        await controller.beginFix()
        stage.type("the logo is squashed")
        await settle()
        XCTAssertTrue(backend.sent[0].prompt.text.contains("What they said about it: the logo is squashed"))
        XCTAssertEqual(backend.sent[0].prompt.title, "Fix: the logo is squashed")
    }

    func testCancellingThePickDoesNothing() async {
        context.region = nil
        await controller.beginFix()
        XCTAssertEqual(log.all, ["pickRegion"])
        XCTAssertNil(stage.input)
    }

    func testCancellingTheDescriptionSendsTheCatHome() async {
        await controller.beginFix()
        stage.hideInput()
        await settle()
        XCTAssertEqual(stage.wentHome, 1)
        XCTAssertTrue(backend.sent.isEmpty)
    }

    func testFixOnAPrivateAppNeedsWords() async {
        context.snapshotValue = ScreenSnapshot(isPrivate: true)
        await controller.beginFix()
        XCTAssertEqual(stage.input?.allowsEmpty, false)
        XCTAssertEqual(stage.input?.caption, CatWords.privateApp)
        stage.type("it's broken")
        await settle()
        XCTAssertTrue(backend.sent[0].prompt.attachments.isEmpty)
        XCTAssertEqual(context.saved, 0, "nothing's saved from a private app")
    }

    func testSayingTheDescriptionSendsIt() async {
        controller.start()
        await controller.beginFix()
        keys.onPress?(settings.talkKey)
        await settle()
        keys.onRelease?(settings.talkKey)
        await drainMainQueue()
        await settle()
        XCTAssertNil(stage.input)
        XCTAssertTrue(backend.sent[0].prompt.text.contains("What is this?"))
    }

    // MARK: - Talk

    func testTalkingGoesThroughAskWithNoPanel() async {
        controller.start()
        await drainMainQueue()
        log = Log()
        keys.onPress?(settings.talkKey)
        await drainMainQueue()
        XCTAssertEqual(stage.status, .listening)
        XCTAssertEqual(stage.bubble, .listening(""))
        XCTAssertEqual(voice.began, 1)
        voice.partialsIn.yield("what is")
        await settle()
        XCTAssertEqual(stage.bubble, .listening("what is"))

        keys.onRelease?(settings.talkKey)
        await drainMainQueue()
        await settle()
        XCTAssertNil(stage.input, "no panel")
        XCTAssertTrue(backend.sent[0].prompt.text.contains("Their question: What is this?"))
        XCTAssertEqual(backend.sent[0].prompt.model, settings.quickModel)
        XCTAssertEqual(backend.sent[0].prompt.attachments.count, 1, "the snapshot from key down")
        XCTAssertEqual(stage.status, .none)
    }

    func testAPartialArrivingAfterReleaseDoesntComeBack() async {
        controller.start()
        keys.onPress?(settings.talkKey)
        await drainMainQueue()
        keys.onRelease?(settings.talkKey)
        await drainMainQueue()
        voice.partialsIn.yield("late")
        await settle()
        for bubble in stage.bubbles {
            XCTAssertNotEqual(bubble, .listening("late"))
        }
    }

    func testTheSnapshotIsTakenWhenTheKeyGoesDown() async {
        controller.start()
        await drainMainQueue()
        keys.onPress?(settings.talkKey)
        await drainMainQueue()
        await settle()
        XCTAssertEqual(context.options.count, 1)
        keys.onRelease?(settings.talkKey)
        await drainMainQueue()
        await settle()
        XCTAssertEqual(context.options.count, 1, "not again on release")
    }

    func testEscWhileHoldingForgetsIt() async {
        controller.start()
        keys.onPress?(settings.talkKey)
        await drainMainQueue()
        controller.bubbleDismissed(byClick: false)
        XCTAssertEqual(voice.cancelled, 1)
        XCTAssertNil(stage.bubble)
        keys.onRelease?(settings.talkKey)
        await drainMainQueue()
        await settle()
        XCTAssertTrue(backend.sent.isEmpty)
    }

    func testHeardNothing() async {
        controller.start()
        voice.transcript = Transcript(raw: "", cleaned: "  ", audioSeconds: 0.1, latencySeconds: 0)
        keys.onPress?(settings.talkKey)
        await drainMainQueue()
        keys.onRelease?(settings.talkKey)
        await drainMainQueue()
        await settle()
        XCTAssertTrue(backend.sent.isEmpty)
        XCTAssertEqual(stage.bubble, .line(CatWords.didntCatch, threadID: nil))
    }

    // MARK: - Dictate

    func testDictationGoesOnlyToTheCursor() async {
        controller.start()
        keys.onPress?(settings.dictateKey)
        await drainMainQueue()
        XCTAssertEqual(stage.status, .listening)
        XCTAssertEqual(stage.held.last, CatWords.listening)
        XCTAssertNil(stage.bubble, "nothing that could get in the way")

        keys.onRelease?(settings.dictateKey)
        await drainMainQueue()
        await settle()
        XCTAssertEqual(inserter.inserted, ["What is this?"])
        XCTAssertTrue(backend.sent.isEmpty, "nothing goes to any agent")
        XCTAssertEqual(context.options.count, 0, "and the screen isn't looked at")
        XCTAssertEqual(stage.held.last, .some(nil))
        XCTAssertEqual(stage.status, .none)
    }

    // MARK: - Privacy

    func testAPrivateAppIsntSentButStillGetsAnAnswer() async {
        context.snapshotValue = ScreenSnapshot(isPrivate: true)
        backend.replies = [[.text(delta: "Sure."), .finished(fullText: "Sure.")]]
        await controller.beginAsk()
        XCTAssertEqual(stage.input?.caption, CatWords.privateApp)
        stage.type("what do I do?")
        await settle()
        let sent = backend.sent[0]
        XCTAssertTrue(sent.prompt.attachments.isEmpty)
        XCTAssertTrue(sent.prompt.text.contains("Hidden"))
        XCTAssertEqual(stage.bubble, .reply(text: "Sure.", done: true, threadID: "thread-1", note: CatWords.privateApp))
    }

    // MARK: - Problems

    func testNoT3GetsOneShortLine() async {
        backend.connectError = Friendly(errorDescription: "T3 Code isn't running. Open it and try again.")
        controller.start()
        await settle()
        XCTAssertEqual(stage.bubble, .line("T3 Code isn't running. Open it and try again.", threadID: nil))
        XCTAssertEqual(stage.statusText, CatWords.cantReachT3)
    }

    func testAFailedTurnGetsOneShortLine() async {
        backend.streamError = Friendly(errorDescription: "Lost the connection to T3 Code.")
        await ask("hello")
        XCTAssertEqual(stage.bubble, .line("Lost the connection to T3 Code.", threadID: nil))
    }

    func testAMissingPermissionShowsWhenAsking() async {
        context.snapshotValue = ScreenSnapshot(appName: "Safari")
        await controller.beginAsk()
        XCTAssertEqual(stage.input?.caption, CatWords.needsScreenRecording)
    }

    func testAModelStillDownloadingGetsOneShortLine() async {
        controller.start()
        voice.beginError = Friendly(errorDescription: "Still getting my ears on. Give me a moment.")
        keys.onPress?(settings.talkKey)
        await drainMainQueue()
        XCTAssertEqual(stage.bubble, .line("Still getting my ears on. Give me a moment.", threadID: nil))
        XCTAssertNotEqual(stage.status, .listening)
    }

    // MARK: - Approvals

    private func thread(_ status: AgentStatus, approvals: [ApprovalRequest] = []) -> AgentThread {
        AgentThread(id: "w", title: "Work", projectTitle: "site", status: status, model: "m", updatedAt: clock, pendingApprovals: approvals)
    }

    func testTheCatComesOverThenAsks() async {
        stage.arriveImmediately = false
        controller.threadsChanged([thread(.waitingForApproval, approvals: [request()])])
        XCTAssertEqual(stage.came, 1)
        XCTAssertNil(stage.bubble, "not until it's there")
        XCTAssertEqual(stage.status, .attention)
        stage.pendingArrival?()
        XCTAssertEqual(stage.bubble, .approval(request(), position: 1, total: 1))
    }

    func testAnswersGoBackAndTheCatGoesHome() async {
        controller.threadsChanged([thread(.waitingForApproval, approvals: [request()])])
        controller.bubbleAction(.approval(request(), .accept))
        await settle()
        XCTAssertEqual(backend.responses.first?.0, "r1")
        XCTAssertEqual(backend.responses.first?.1, .accept)
        XCTAssertEqual(stage.wentHome, 1)
        XCTAssertNil(stage.bubble)
    }

    func testSeveralQueueUpInOrder() async {
        let a = request("a")
        var b = request("b")
        b.createdAt = Date(timeIntervalSince1970: 2)
        controller.threadsChanged([thread(.waitingForApproval, approvals: [a, b])])
        XCTAssertEqual(stage.came, 1, "only runs over once")
        XCTAssertEqual(stage.bubble, .approval(a, position: 1, total: 2))
        controller.bubbleAction(.approval(a, .decline))
        XCTAssertEqual(stage.bubble, .approval(b, position: 2, total: 2))
        XCTAssertEqual(stage.wentHome, 0)
        controller.bubbleAction(.approval(b, .acceptForSession))
        await settle()
        XCTAssertEqual(stage.wentHome, 1)
    }

    func testAClickElsewhereCantLoseAnApproval() async {
        controller.threadsChanged([thread(.waitingForApproval, approvals: [request()])])
        controller.bubbleDismissed(byClick: true)
        XCTAssertEqual(stage.bubble, .approval(request(), position: 1, total: 1))
        XCTAssertTrue(backend.responses.isEmpty)
    }

    func testEscHidesAnApprovalWithoutAnsweringItAndClickingTheCatBringsItBack() async {
        controller.threadsChanged([thread(.waitingForApproval, approvals: [request()])])
        controller.bubbleDismissed(byClick: false)
        XCTAssertNil(stage.bubble)
        XCTAssertTrue(backend.responses.isEmpty)
        XCTAssertEqual(stage.status, .attention, "the light stays on")
        controller.catClicked()
        XCTAssertEqual(stage.bubble, .approval(request(), position: 1, total: 1))
    }

    func testAnApprovalThatFailsToSendComesBack() async {
        backend.failResponses = true
        controller.threadsChanged([thread(.waitingForApproval, approvals: [request()])])
        controller.bubbleAction(.approval(request(), .accept))
        await settle()
        XCTAssertEqual(stage.bubble, .approval(request(), position: 1, total: 1))
    }

    func testApprovalsFromAReplyStreamAreAskedToo() async {
        backend.replies = [[.needsApproval(request()), .text(delta: "Hi."), .finished(fullText: "Hi.")]]
        await ask("hello")
        XCTAssertEqual(stage.came, 1)
        XCTAssertEqual(stage.bubble, .approval(request(), position: 1, total: 1))
    }

    func testTheReplyIsStillThereAfterAnApproval() async {
        backend.replies = [[.text(delta: "Hi."), .finished(fullText: "Hi.")]]
        await ask("hello")
        controller.threadsChanged([thread(.waitingForApproval, approvals: [request()])])
        controller.bubbleAction(.approval(request(), .decline))
        await settle()
        XCTAssertEqual(stage.bubble, .reply(text: "Hi.", done: true, threadID: "thread-1", note: nil))
    }

    // MARK: - Mood

    func testAwakeWhileWorkingAndCelebratesWhenDone() async {
        controller.threadsChanged([thread(.running)])
        XCTAssertTrue(stage.busy)
        XCTAssertEqual(stage.statusText, "1 agent working")
        controller.threadsChanged([thread(.completed)])
        XCTAssertFalse(stage.busy)
        XCTAssertEqual(stage.celebrated, 1)
        await controller.reportTask?.value
        XCTAssertEqual(stage.bubble, .notice(caption: "Done: Work", text: "It's finished, but didn't leave a report.", threadID: "w"))
        XCTAssertEqual(stage.statusText, "Napping")
    }

    func testAQuickAnswerIsntACelebration() async {
        backend.replies = [[.finished(fullText: "Hi.")]]
        await ask("hello")
        var quick = thread(.running)
        quick.id = "thread-1"
        controller.threadsChanged([quick])
        XCTAssertFalse(stage.busy)
        quick.status = .completed
        controller.threadsChanged([quick])
        XCTAssertEqual(stage.celebrated, 0)
    }

    func testProjectNamesBecomeVocabulary() async {
        controller.threadsChanged([thread(.running)])
        XCTAssertEqual(voice.vocabulary, ["site"])
    }

    // MARK: - The bubble

    func testAThinkingBubbleSurvivesAClickElsewhereButNotEsc() async {
        await controller.beginAsk()
        stage.type("hello?")
        controller.bubbleDismissed(byClick: true)
        XCTAssertEqual(stage.bubble, .thinking(note: nil))
        controller.bubbleDismissed(byClick: false)
        XCTAssertNil(stage.bubble)
        await settle()
        XCTAssertNil(stage.bubble, "the late answer stays gone")
    }

    func testARepliesDismissOnAClickElsewhere() async {
        backend.replies = [[.text(delta: "Hi."), .finished(fullText: "Hi.")]]
        await ask("hello")
        controller.bubbleDismissed(byClick: true)
        XCTAssertNil(stage.bubble)
    }

    func testOpenInT3AndCopy() async {
        controller.bubbleAction(.open(threadID: "t"))
        XCTAssertEqual(backend.opened, ["t"])
        controller.bubbleAction(.copy("some text"))
        XCTAssertEqual(stage.copied, "some text")
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
