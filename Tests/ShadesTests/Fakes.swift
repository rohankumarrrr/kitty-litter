import CoreGraphics
@testable import Shades
import ShadesCore
import XCTest

// The app's parts, faked, so tests run the real flows with no windows, agents or microphone.

final class Log: @unchecked Sendable {
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
final class FakeStage: CatStage {
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
    var statusText = ""
    var statusNeedsYou = false
    var kittens: [KittenStatus]?
    var isKittensVisible: Bool { kittens != nil }
    var channelsShown: [ChannelBook] = []
    var channelsUpdated: [ChannelBook] = []
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
    func showStatus(_ status: String, needsYou: Bool) {
        statusText = status
        statusNeedsYou = needsYou
    }
    func showKittens(_ statuses: [KittenStatus]) { kittens = statuses }
    func hideKittens() { kittens = nil }
    var isChannelsVisible = false
    var selections: [ChannelSelection?] = []
    func showChannels(_ book: ChannelBook, selecting selection: ChannelSelection?) {
        channelsShown.append(book)
        selections.append(selection)
        isChannelsVisible = true
    }
    func updateChannels(_ book: ChannelBook) { channelsUpdated.append(book) }
    func hideChannels() { isChannelsVisible = false }
    var isMessagesBoxTyping = false
    var sentInMessages: [String] = []
    var messagesBoxHeld = false
    func holdMessagesBox() { messagesBoxHeld = true }
    func sendInMessages(_ text: String) {
        sentInMessages.append(text)
        messagesBoxHeld = false
    }
    func releaseMessagesBox() { messagesBoxHeld = false }
    func showSettings(_ settings: Settings, onSave: @escaping (Settings) -> Void) {}
    func copyToPasteboard(_ text: String) { copied = text }

    /// What a person does: types into the panel and presses Return.
    func type(_ text: String) {
        submitInput(text)
    }
}

final class FakeBackend: AgentBackend, @unchecked Sendable {
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
    /// The router's reply to a question, whatever order things start in.
    var routerSays: [String: String] = [:]
    /// Chooses by what was sent, for turns that overlap. Falls back on `replies`.
    var replyTo: ((AgentPrompt) -> [AgentReplyEvent]?)?
    /// Holds a reply open partway, until this ends, then plays `afterHeld`.
    var held: Task<Void, Never>?
    var afterHeld: [AgentReplyEvent] = []
    /// Holds back `.started` until this ends, the way a real follow-up does while it uploads the screenshot.
    var heldBeforeStarted: Task<Void, Never>?
    /// A follow-up that fails only once this ends, as a thread that's gone does after the upload.
    var failFollowUpsAfter: Task<Void, Never>?
    /// Holds back finding a kitten's project, the way a real lookup takes a trip to T3. Kittens' folders are all
    /// in /k, and the router's own lookup isn't held, since the router has to run first.
    var heldProject: Task<Void, Never>?
    var reports: [String: String] = [:]
    var projects: [String: String] = [:]
    private var _settled: [String] = []
    private var _archived: [String] = []
    var settled: [String] { lock.withLock { _settled } }
    var archived: [String] { lock.withLock { _archived } }
    var failFollowUps = false
    var failResponses = false
    var origins: [String: ThreadOrigin] = [:]
    var untraceable: Set<String> = []
    /// New threads start, and then never finish.
    var holdStarts = false
    var whileReadingAReport: (() async -> Void)?
    var whileFindingAProject: (() async -> Void)?
    var connectError: Error?
    var streamError: Error?
    var forwardError: Error?
    var droppedAfterReply: Error?
    var runReports: [String: String] = [:]
    var silentRuns: Set<String> = []
    var readFails = false
    var addedProjects: [String] = []
    var addProjectError: Error?
    private var count = 0

    var sent: [Sent] { lock.withLock { _sent } }
    var responses: [(String, ApprovalDecision)] { lock.withLock { _responses } }
    var opened: [String] { lock.withLock { _opened } }

    func connect() async throws {
        if let connectError { throw connectError }
    }

    func start(_ prompt: AgentPrompt) -> AsyncThrowingStream<AgentReplyEvent, Error> {
        // The router sees your screen, so wherever it's started from, it can only start where it can't pass that on.
        if prompt.text.hasPrefix("You are Shades,") { XCTAssertEqual(prompt.projectID, "project-router") }
        let id = lock.withLock { () -> Int in
            count += 1
            _sent.append(Sent(mode: .start, threadID: nil, prompt: prompt))
            return count
        }
        if holdStarts { return AsyncThrowingStream { $0.yield(.started(threadID: "thread-\(id)")) } }
        if let holdTurn, prompt.text.hasPrefix(holdTurn) { return heldTurn(threadID: "thread-\(id)") }
        return play(threadID: "thread-\(id)", prompt: prompt)
    }

    func followUp(threadID: String, _ prompt: AgentPrompt) -> AsyncThrowingStream<AgentReplyEvent, Error> {
        lock.withLock { _sent.append(Sent(mode: .followUp, threadID: threadID, prompt: prompt)) }
        if failFollowUps {
            return AsyncThrowingStream { $0.finish(throwing: URLError(.badServerResponse)) }
        }
        if let failFollowUpsAfter {
            return AsyncThrowingStream { continuation in
                Task {
                    await failFollowUpsAfter.value
                    continuation.finish(throwing: URLError(.badServerResponse))
                }
            }
        }
        return play(threadID: threadID, prompt: prompt)
    }

    /// The router's turn for this question starts, then waits for `releaseHeld()`.
    var holdQuestion: String?
    /// A new thread's first turn, or a follow-up, whose text starts with this starts, then waits for `releaseHeld()`.
    var holdTurn: String?
    private var heldTurns: [() -> Void] = []
    func releaseHeld() {
        let waiting = lock.withLock { () -> [() -> Void] in
            defer { heldTurns = [] }
            return heldTurns
        }
        waiting.forEach { $0() }
    }

    private func heldTurn(threadID: String) -> AsyncThrowingStream<AgentReplyEvent, Error> {
        let events = lock.withLock { replies.isEmpty ? [AgentReplyEvent.finished(fullText: "Okay.")] : replies.removeFirst() }
        return AsyncThrowingStream { continuation in
            continuation.yield(.started(threadID: threadID))
            lock.withLock {
                heldTurns.append {
                    events.forEach { continuation.yield($0) }
                    continuation.finish()
                }
            }
        }
    }

    /// What Messages reads: every thread, and what was said in each.
    var listed: [AgentThread]?
    var said: [String: [Exchange]] = [:]
    func allThreads() async -> [AgentThread]? { listed }
    func exchanges(threadID: String) async -> [Exchange]? { said[threadID] }

    private func play(threadID: String, prompt: AgentPrompt) -> AsyncThrowingStream<AgentReplyEvent, Error> {
        let routed = routerSays.first { prompt.text.contains("Their question: \($0.key)") }?.value
        let chosen = routed.map { [AgentReplyEvent.finished(fullText: $0)] } ?? replyTo?(prompt)
        let events = chosen ?? lock.withLock { replies.isEmpty ? [AgentReplyEvent.finished(fullText: "Okay.")] : replies.removeFirst() }
        if let holdQuestion, prompt.text.contains("Their question: \(holdQuestion)") {
            return AsyncThrowingStream { continuation in
                continuation.yield(.started(threadID: threadID))
                lock.withLock {
                    heldTurns.append {
                        events.forEach { continuation.yield($0) }
                        continuation.finish()
                    }
                }
            }
        }
        let error = streamError
        let dropped = droppedAfterReply
        let held = self.held
        let afterHeld = self.afterHeld
        let heldBeforeStarted = self.heldBeforeStarted
        return AsyncThrowingStream { continuation in
            if let error {
                continuation.finish(throwing: error)
                return
            }
            if let heldBeforeStarted {
                Task {
                    await heldBeforeStarted.value
                    continuation.yield(.started(threadID: threadID))
                    events.forEach { continuation.yield($0) }
                    if let held {
                        await held.value
                        afterHeld.forEach { continuation.yield($0) }
                    }
                    continuation.finish()
                }
                return
            }
            continuation.yield(.started(threadID: threadID))
            events.forEach { continuation.yield($0) }
            guard let held else {
                continuation.finish(throwing: dropped)
                return
            }
            Task {
                await held.value
                afterHeld.forEach { continuation.yield($0) }
                continuation.finish(throwing: dropped)
            }
        }
    }

    func forward(threadID: String, text: String, attachments: [AgentAttachment]) -> AsyncThrowingStream<AgentReplyEvent, Error> {
        if let forwardError {
            return AsyncThrowingStream { $0.finish(throwing: forwardError) }
        }
        let prompt = AgentPrompt(text: text, attachments: attachments, model: .quick, runtimeMode: .auto)
        lock.withLock { _sent.append(Sent(mode: .forward, threadID: threadID, prompt: prompt)) }
        if let holdTurn, text.hasPrefix(holdTurn) { return heldTurn(threadID: threadID) }
        return play(threadID: threadID, prompt: prompt)
    }

    func watchThreads() -> AsyncStream<[AgentThread]> {
        AsyncStream { continuation in watcher = continuation }
    }

    func respond(to request: ApprovalRequest, with decision: ApprovalDecision) async throws {
        if failResponses { throw URLError(.notConnectedToInternet) }
        lock.withLock { _responses.append((request.id, decision)) }
    }

    private var _answers: [(String, [String])] = []
    var answers: [(String, [String])] { lock.withLock { _answers } }

    func answer(_ question: AgentQuestion, with answers: [String]) async throws {
        if failResponses { throw URLError(.notConnectedToInternet) }
        lock.withLock { _answers.append((question.id, answers)) }
    }

    // These run off the main actor, and more than one at once when turns overlap, so what they share is locked.
    func projectID(atPath path: String) async -> String? {
        let happening = lock.withLock { () -> (() async -> Void)? in
            defer { whileFindingAProject = nil }
            return whileFindingAProject
        }
        await happening?()
        if let held = lock.withLock({ heldProject }), path.hasPrefix("/k/") { await held.value }
        return lock.withLock { projects[path] }
    }

    func addProject(atPath path: String, title: String) async throws -> String {
        if let addProjectError { throw addProjectError }
        lock.withLock {
            addedProjects.append(path)
            projects[path] = "project-router"
        }
        return "project-router"
    }

    func archive(threadID: String) async throws {
        lock.withLock { _archived.append(threadID) }
    }

    func settle(threadID: String) async throws {
        lock.withLock { _settled.append(threadID) }
    }

    func report(threadID: String, run: String?) async throws -> String? {
        let happening = lock.withLock { () -> (() async -> Void)? in
            defer { whileReadingAReport = nil }
            return whileReadingAReport
        }
        await happening?()
        let found = lock.withLock { () -> (fails: Bool, report: String?) in
            if readFails { return (true, nil) }
            if let run, silentRuns.contains(run) { return (false, nil) }
            if let run, let said = runReports[run] { return (false, said) }
            return (false, reports[threadID])
        }
        if found.fails { throw URLError(.networkConnectionLost) }
        return found.report
    }

    func origin(of threadID: String) async -> ThreadOrigin? {
        if untraceable.contains(threadID) { return nil }
        return origins[threadID] ?? ThreadOrigin(title: "Work", projectPath: nil, startedBy: .person)
    }

    func open(threadID: String) {
        lock.withLock { _opened.append(threadID) }
    }
}

final class FakeContext: ScreenContextProviding, @unchecked Sendable {
    static let savedPath = "/tmp/shot.jpg"
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
        return snapshot.screenshotJPEG == nil ? nil : Self.savedPath
    }
}

final class FakeVoice: VoiceEngine {
    var endError: Error?
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
    func end() async throws -> Transcript {
        if let endError { throw endError }
        return transcript
    }
    func cancel() { cancelled += 1 }
}

final class FakeInserter: TextInserting {
    var inserted: [String] = []
    var replaced: [(original: String, bundleID: String?, text: String)] = []
    var replaces = true
    func insert(_ text: String) async throws { inserted.append(text) }
    func replaceSelection(_ original: String, in bundleID: String?, with text: String) async -> Bool {
        replaced.append((original, bundleID, text))
        return replaces
    }
}

final class FakeKeys: KeyHoldMonitoring {
    var onPress: ((HoldKey) -> Void)?
    var onRelease: ((HoldKey) -> Void)?
    func start(keys: [HoldKey]) throws {}
    func stop() {}
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
