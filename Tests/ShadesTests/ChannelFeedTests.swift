@testable import Shades
import ShadesCore
import XCTest

private final class FeedBackend: AgentBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var _threads: [AgentThread]? = []
    private var _words: [String: [Exchange]] = [:]
    private var _failing: Set<String> = []
    private var _listings = 0
    private var _reads: [String] = []
    private var _reading = 0
    private var _mostAtOnce = 0
    private var _gates: [CheckedContinuation<Void, Never>] = []
    private var _holdsReads = false
    private var _readDuration: Duration = .zero

    var threads: [AgentThread]? {
        get { lock.withLock { _threads } }
        set { lock.withLock { _threads = newValue } }
    }
    var failing: Set<String> {
        get { lock.withLock { _failing } }
        set { lock.withLock { _failing = newValue } }
    }
    var holdsReads: Bool {
        get { lock.withLock { _holdsReads } }
        set { lock.withLock { _holdsReads = newValue } }
    }
    var readDuration: Duration {
        get { lock.withLock { _readDuration } }
        set { lock.withLock { _readDuration = newValue } }
    }
    var listings: Int { lock.withLock { _listings } }
    var reads: [String] { lock.withLock { _reads } }
    var mostAtOnce: Int { lock.withLock { _mostAtOnce } }
    var heldReads: Int { lock.withLock { _gates.count } }

    func say(_ words: String, in threadID: String) {
        let exchange = Exchange(id: "\(threadID):\(words)", asker: .you, askedAt: Date(timeIntervalSince1970: 1), ask: words)
        lock.withLock { _words[threadID] = [exchange] }
    }

    func releaseReads() {
        let gates = lock.withLock {
            let gates = _gates
            _gates = []
            _holdsReads = false
            return gates
        }
        gates.forEach { $0.resume() }
    }

    func allThreads() async -> [AgentThread]? {
        lock.withLock {
            _listings += 1
            return _threads
        }
    }

    func exchanges(threadID: String) async -> [Exchange]? {
        let duration = lock.withLock {
            _reads.append(threadID)
            _reading += 1
            _mostAtOnce = max(_mostAtOnce, _reading)
            return _readDuration
        }
        if duration > .zero { try? await Task.sleep(for: duration) }
        await withCheckedContinuation { continuation in
            let held = lock.withLock {
                if _holdsReads { _gates.append(continuation) }
                return _holdsReads
            }
            if !held { continuation.resume() }
        }
        return lock.withLock {
            _reading -= 1
            return _failing.contains(threadID) ? nil : _words[threadID, default: []]
        }
    }

    // Channels only ever reads, so anything that would send or change something stops the tests.
    func connect() async throws { fatalError("Channels never connects by itself") }
    func start(_ prompt: AgentPrompt) -> AsyncThrowingStream<AgentReplyEvent, Error> { fatalError("Channels never sends") }
    func followUp(threadID: String, _ prompt: AgentPrompt) -> AsyncThrowingStream<AgentReplyEvent, Error> { fatalError("Channels never sends") }
    func forward(threadID: String, text: String, attachments: [AgentAttachment]) -> AsyncThrowingStream<AgentReplyEvent, Error> { fatalError("Channels never sends") }
    func watchThreads() -> AsyncStream<[AgentThread]> { fatalError("Channels is told about changes") }
    func respond(to request: ApprovalRequest, with decision: ApprovalDecision) async throws { fatalError("Channels never answers") }
    func archive(threadID: String) async throws { fatalError("Channels never archives") }
    func settle(threadID: String) async throws { fatalError("Channels never settles") }
    func open(threadID: String) { fatalError("The window opens threads, not the feed") }
}

@MainActor
final class ChannelFeedTests: XCTestCase {
    private let steve = Kitten(name: "Steve", role: "Professional", covers: "", folder: "/k/steve")
    private var backend: FeedBackend!
    private var feed: ChannelFeed!
    private var books: [ChannelBook] = []
    private let start = Date(timeIntervalSince1970: 1_000)

    override func setUp() async throws {
        backend = FeedBackend()
        books = []
        makeFeed(gap: .milliseconds(20))
    }

    override func tearDown() async throws {
        feed.close()
    }

    private func makeFeed(gap: Duration) {
        feed = ChannelFeed(backend: backend, kittens: { [steve] in [steve] }, gap: gap)
        feed.onChange = { [unowned self] in self.books.append($0) }
    }

    private func thread(_ id: String, project: String? = "Steve", age: TimeInterval = 0, status: AgentStatus = .completed) -> AgentThread {
        AgentThread(id: id, title: "Work", projectTitle: project, status: status, model: "m", updatedAt: start.addingTimeInterval(-age))
    }

    private func moved(_ thread: AgentThread, by seconds: TimeInterval) -> AgentThread {
        var thread = thread
        thread.updatedAt = thread.updatedAt.addingTimeInterval(seconds)
        return thread
    }

    private func eventually(_ what: String = "it didn't happen", _ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<400 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail(what, file: file, line: line)
    }

    /// Long enough for anything that was going to happen to have happened.
    private func holdOn() async {
        try? await Task.sleep(for: .milliseconds(120))
    }

    private var latest: ChannelBook? { books.last }

    private func words(in book: ChannelBook?) -> [String?] {
        (book?.channel(.direct(steve))?.messages ?? []).map(\.text)
    }

    private func openAndRead() async {
        _ = feed.open(threads: [])
        await eventually { self.latest?.isReading == false }
    }

    func testNothingIsReadWhileClosed() async {
        backend.threads = [thread("a")]
        feed.threadsChanged([thread("a")])
        await holdOn()
        XCTAssertEqual(backend.listings, 0)
        XCTAssertEqual(backend.reads, [])
        XCTAssertEqual(books, [])

        await openAndRead()
        feed.close()
        let listings = backend.listings
        feed.threadsChanged([moved(thread("a"), by: 5)])
        await holdOn()
        XCTAssertEqual(backend.listings, listings)
        XCTAssertEqual(feed.threadsHeld, 0)
    }

    func testOpeningReturnsAtOnceAndStillReading() {
        backend.holdsReads = true
        let book = feed.open(threads: [thread("a")])
        XCTAssertTrue(book.isReading)
        XCTAssertEqual(book.directs.map(\.messages), [[]])
        XCTAssertEqual(book.issues.first?.threads.map(\.id), ["a"], "what's open is known before any words are")
        backend.releaseReads()
    }

    func testTheLiveListShowsBeforeTheFirstReadLands() async {
        backend.holdsReads = true
        backend.threads = [thread("a")]
        _ = feed.open(threads: [])
        feed.threadsChanged([thread("a", status: .running)])
        XCTAssertEqual(latest?.issues.first?.threads.map(\.status), [.running])
        XCTAssertEqual(latest?.isReading, true)
        await eventually { self.backend.heldReads == 1 }
        backend.releaseReads()
    }

    func testOpeningReadsEachOwnedThreadOnceAndLeavesTheRest() async {
        backend.threads = [thread("mine"), thread("also-mine", project: "site"), thread("not-mine", project: "Pepper")]
        backend.threads?[1].title = "Steve: Fix the site"
        await openAndRead()
        await holdOn()
        XCTAssertEqual(Set(backend.reads), ["mine", "also-mine"])
        XCTAssertEqual(backend.reads.count, 2)
    }

    func testOpeningTwiceChangesNothing() async {
        backend.threads = [thread("a")]
        backend.say("Hello", in: "a")
        await openAndRead()
        let book = feed.open(threads: [])
        XCTAssertEqual(book, latest)
        await holdOn()
        XCTAssertEqual(backend.listings, 1)
    }

    func testOnlyAMovedThreadIsReadAgain() async {
        let a = thread("a")
        let b = thread("b")
        backend.threads = [a, b]
        await openAndRead()

        backend.threads = [a, moved(b, by: 5)]
        backend.say("New words", in: "b")
        feed.threadsChanged([a])
        await eventually { self.words(in: self.latest).contains("New words") }
        XCTAssertEqual(backend.reads.filter { $0 == "a" }.count, 1)
        XCTAssertEqual(backend.reads.filter { $0 == "b" }.count, 2)
    }

    func testAFlurryOfUpdatesMakesOneMoreReadPass() async {
        makeFeed(gap: .milliseconds(150))
        let a = thread("a")
        backend.threads = [a]
        await openAndRead()
        let listings = backend.listings

        for second in 1...20 {
            let next = moved(a, by: TimeInterval(second))
            backend.threads = [next]
            feed.threadsChanged([next])
            await Task.yield()
        }
        await eventually { self.backend.reads.count == 2 }
        await holdOn()
        XCTAssertEqual(backend.listings, listings + 1)
        XCTAssertEqual(backend.reads, ["a", "a"])
    }

    func testAChangeAfterTheLoopHasStoppedStillGetsRead() async {
        let a = thread("a")
        backend.threads = [a]
        await openAndRead()
        await holdOn()

        backend.threads = [moved(a, by: 5)]
        feed.threadsChanged([a])
        await eventually { self.backend.reads.count == 2 }
    }

    func testAFailedReadKeepsTheOldWordsAndRecovers() async {
        let a = thread("a")
        backend.threads = [a]
        backend.say("Old words", in: "a")
        await openAndRead()
        XCTAssertEqual(words(in: latest), ["Old words"])

        backend.failing = ["a"]
        backend.say("New words", in: "a")
        backend.threads = [moved(a, by: 5)]
        feed.threadsChanged([a])
        await eventually { self.latest?.unreadable == 1 }
        XCTAssertEqual(words(in: latest), ["Old words"])

        backend.failing = []
        await eventually { self.latest?.unreadable == 0 }
        XCTAssertEqual(words(in: latest), ["New words"])
    }

    func testLosingT3KeepsTheOldWordsAndRecovers() async {
        let a = thread("a")
        backend.threads = [a]
        backend.say("Old words", in: "a")
        await openAndRead()

        backend.threads = nil
        feed.threadsChanged([a])
        await eventually { self.latest?.cantReachT3 == true }
        XCTAssertEqual(words(in: latest), ["Old words"])

        backend.threads = [moved(a, by: 5)]
        backend.say("New words", in: "a")
        await eventually { self.latest?.cantReachT3 == false }
        XCTAssertEqual(words(in: latest), ["New words"])
    }

    func testAReadLandingAfterCloseIsDropped() async {
        backend.threads = [thread("a")]
        backend.say("Too late", in: "a")
        backend.holdsReads = true
        _ = feed.open(threads: [])
        await eventually { self.backend.heldReads == 1 }

        feed.close()
        backend.releaseReads()
        await holdOn()
        XCTAssertEqual(books.filter { !$0.isReading }, [])
        XCTAssertEqual(feed.threadsHeld, 0)
    }

    func testClosingForgetsTheWords() async {
        backend.threads = [thread("a")]
        backend.say("Hello", in: "a")
        await openAndRead()
        XCTAssertEqual(feed.threadsHeld, 1)

        feed.close()
        XCTAssertEqual(feed.threadsHeld, 0)
        backend.holdsReads = true
        XCTAssertEqual(words(in: feed.open(threads: [])), [], "opening again starts from nothing")
        backend.releaseReads()
    }

    func testNeverMoreThanFourAtOnce() async {
        backend.threads = (0..<12).map { thread("t\($0)") }
        backend.readDuration = .milliseconds(10)
        await openAndRead()
        XCTAssertEqual(backend.reads.count, 12)
        XCTAssertEqual(backend.mostAtOnce, 4)
    }

    func testOnlyTheNewestSixtyAreRead() async {
        backend.threads = (0..<70).map { thread("t\($0)", age: TimeInterval($0)) }
        await openAndRead()
        XCTAssertEqual(Set(backend.reads), Set((0..<60).map { "t\($0)" }))
    }

    func testTheFirstBatchIsOneSwap() async {
        backend.threads = (0..<8).map { thread("t\($0)") }
        for index in 0..<8 { backend.say("Words", in: "t\(index)") }
        await openAndRead()
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(words(in: latest).count, 8)
    }

    func testABookThatHasntChangedIsntPublishedAgain() async {
        let a = thread("a")
        backend.threads = [a]
        await openAndRead()
        let count = books.count
        feed.threadsChanged([a])
        await holdOn()
        XCTAssertEqual(books.count, count)
    }
}
