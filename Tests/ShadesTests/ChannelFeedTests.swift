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

    func set(_ exchanges: [Exchange], in threadID: String) {
        lock.withLock { _words[threadID] = exchanges }
    }

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
        AgentThread(id: id, title: "Work", projectTitle: project, status: status, model: "m", updatedAt: start.addingTimeInterval(-age), projectPath: project.map { "/k/\($0.lowercased())" })
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
        XCTAssertEqual(feed.threadsHeld, 1, "what's been read stays for next time")
    }

    func testOpeningReturnsAtOnceAndStillReading() {
        backend.holdsReads = true
        let book = feed.open(threads: [thread("a", status: .running)])
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
        makeFeed(gap: .seconds(60))
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

    func testAReadLandingAfterCloseIsKeptForNextTime() async {
        backend.threads = [thread("a")]
        backend.say("Worth keeping", in: "a")
        backend.holdsReads = true
        _ = feed.open(threads: [])
        await eventually { self.backend.heldReads == 1 }

        feed.close()
        backend.releaseReads()
        await eventually { self.feed.threadsHeld == 1 }
        XCTAssertEqual(words(in: feed.open(threads: [])), ["Worth keeping"])
    }

    func testOpeningAgainShowsWhatWasReadAtOnceThenReadsOnlyWhatMoved() async {
        let quiet = thread("quiet", age: 10)
        let busy = thread("busy")
        backend.threads = [quiet, busy]
        backend.say("Old news", in: "quiet")
        backend.say("Working on it", in: "busy")
        await openAndRead()
        feed.close()

        backend.threads = [quiet, moved(busy, by: 5)]
        backend.say("Done", in: "busy")
        let reads = backend.reads.count
        let reopened = feed.open(threads: [])
        XCTAssertFalse(reopened.isReading, "nothing waits behind a loading note once anything's known")
        XCTAssertEqual(Set(words(in: reopened)), ["Old news", "Working on it"])
        await eventually { Set(self.words(in: self.latest)) == ["Old news", "Done"] }
        XCTAssertEqual(Array(backend.reads.dropFirst(reads)), ["busy"])
    }

    func testOpeningCutsTheWaitBetweenPassesShort() async {
        makeFeed(gap: .seconds(30))
        let first = thread("a")
        backend.threads = [first]
        backend.say("Before", in: "a")
        await openAndRead()
        feed.close()

        backend.threads = [moved(first, by: 1)]
        backend.say("After", in: "a")
        _ = feed.open(threads: [])
        await eventually { self.words(in: self.latest) == ["After"] }
    }

    func testWarmingReadsOnceBeforeAnyoneLooks() async {
        let first = thread("a")
        backend.threads = [first]
        backend.say("Ready", in: "a")
        feed.warm(threads: [first])
        await eventually { self.feed.threadsHeld == 1 }
        await holdOn()
        XCTAssertEqual(backend.listings, 1, "it reads once, and not again until someone looks")

        let book = feed.open(threads: [])
        XCTAssertFalse(book.isReading)
        XCTAssertEqual(words(in: book), ["Ready"])
    }

    func testReadingAheadTakesOneThreadAtATime() async {
        backend.threads = (0..<8).map { thread("t\($0)", age: TimeInterval($0)) }
        backend.readDuration = .milliseconds(10)
        feed.warm(threads: [])
        await eventually { self.feed.threadsHeld == 8 }
        XCTAssertEqual(backend.mostAtOnce, 1, "with nobody looking, T3 keeps room for everything else")
    }

    func testWhatsOnTheScreenIsReadFirst() async {
        let pepper = Kitten(name: "Pepper", role: "Finance", covers: "", folder: "/k/pepper")
        feed = ChannelFeed(backend: backend, kittens: { [steve] in [steve, pepper] }, gap: .milliseconds(20))
        feed.onChange = { [unowned self] in self.books.append($0) }
        feed.lookingAt = .channel(.direct(pepper))
        backend.threads = (0..<12).map { thread("steve-\($0)", age: TimeInterval($0)) } + [thread("pepper", project: "Pepper", age: 100)]
        await openAndRead()
        // Four go at once, so only which four is certain, not their order.
        XCTAssertTrue(backend.reads.prefix(4).contains("pepper"), "\(backend.reads)")
        XCTAssertFalse(backend.reads.prefix(4).contains("steve-11"), "then the newest: \(backend.reads)")
    }

    func testReadsShowAsTheyLand() async {
        backend.threads = (0..<8).map { thread("t\($0)", age: TimeInterval($0)) }
        for index in 0..<8 { backend.say("Words \(index)", in: "t\(index)") }
        backend.readDuration = .milliseconds(200)
        _ = feed.open(threads: [])
        await eventually { !self.words(in: self.latest).isEmpty }
        XCTAssertEqual(latest?.isReading, true, "the first words show before the pass is over")
        await eventually { self.latest?.isReading == false }
        XCTAssertEqual(words(in: latest).count, 8)
    }

    func testANewThreadStillBeingReadDoesntLookCutShort() async {
        backend.threads = [thread("a", age: 10)]
        backend.say("First", in: "a")
        await openAndRead()
        feed.close()

        backend.threads = [thread("a", age: 10), thread("b")]
        backend.say("Second", in: "b")
        backend.holdsReads = true
        _ = feed.open(threads: [])
        await eventually { self.backend.heldReads == 1 }
        feed.refresh()
        XCTAssertEqual(latest?.channel(.direct(steve))?.isCut, false)
        backend.releaseReads()
        await eventually { self.words(in: self.latest) == ["First", "Second"] }
    }

    func testNeverMoreThanFourAtOnce() async {
        backend.threads = (0..<12).map { thread("t\($0)") }
        backend.readDuration = .milliseconds(10)
        await openAndRead()
        XCTAssertEqual(backend.reads.count, 12)
        XCTAssertEqual(backend.mostAtOnce, 4)
    }

    func testEachKittensNewestThreadsAreRead() async {
        let pepper = Kitten(name: "Pepper", role: "Finance", covers: "", folder: "/k/pepper")
        feed = ChannelFeed(backend: backend, kittens: { [steve] in [steve, pepper] }, gap: .milliseconds(20))
        feed.onChange = { [unowned self] in self.books.append($0) }
        backend.threads = (0..<70).map { thread("t\($0)", age: TimeInterval($0)) } + [thread("quiet", project: "Pepper", age: 500)]
        await openAndRead()
        XCTAssertEqual(Set(backend.reads), Set((0..<30).map { "t\($0)" } + ["quiet"]))
    }

    func testClosingMidPassFinishesThatPassAndStops() async {
        backend.threads = (0..<12).map { thread("t\($0)", age: TimeInterval($0)) }
        backend.holdsReads = true
        _ = feed.open(threads: [])
        await eventually { self.backend.heldReads == 4 }
        feed.close()
        backend.releaseReads()
        await eventually { self.feed.threadsHeld == 12 }
        let listings = backend.listings
        feed.threadsChanged([])
        await holdOn()
        XCTAssertEqual(backend.listings, listings)
    }

    func testAnIdleWindowNoticesT3HasGone() async {
        backend.threads = [thread("t")]
        backend.say("Hello", in: "t")
        await openAndRead()
        backend.threads = nil
        await eventually("nothing told it, so it has to look") { self.latest?.cantReachT3 == true }
        XCTAssertEqual(words(in: latest), ["Hello"])
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

    // MARK: - Messages

    func testOnlyThreadsWhoseWordsHaveBeenReadCountAsSeen() async {
        backend.holdsReads = true
        backend.threads = [thread("a")]
        _ = feed.open(threads: [thread("a")])
        await eventually { self.backend.heldReads == 1 }
        XCTAssertEqual(feed.threads(in: .channel(.direct(steve))), [], "nothing's on the screen while it's still reading")

        backend.releaseReads()
        await eventually { self.latest?.isReading == false }
        XCTAssertEqual(feed.threads(in: .channel(.direct(steve))).map(\.id), ["a"])
        XCTAssertEqual(feed.threads(in: .channel(.everyone)).map(\.id), ["a"])
        XCTAssertEqual(feed.threads(in: .needsYou), [])
    }

    func testWorkEveryoneHandedOutsideAnyKittenIsReadToo() async {
        let work = thread("w", project: nil)
        backend.threads = [work]
        backend.say("Find a cheaper flight", in: "w")
        feed.alsoInEveryone = { ["w": Date(timeIntervalSince1970: 0)] }
        await openAndRead()
        XCTAssertEqual(backend.reads, ["w"])

        let other = thread("other", project: nil)
        backend.threads = [work, other]
        feed.alsoInEveryone = { [:] }
        feed.threadsChanged([work, other])
        await holdOn()
        XCTAssertFalse(backend.reads.contains("other"), "anything else outside a kitten stays unread")
    }

    func testANewTopicLearnsItsThreadOrThatItDidntStart() async {
        await openAndRead()
        let echo = ChannelMessage(exchangeID: "sent-1", kind: .ask, speaker: .you, text: "Draft a letter", at: start, threadID: "", threadTitle: "")
        feed.sent(echo, in: .direct(steve))
        feed.started("sent-1", in: "new", title: "Draft a letter")
        XCTAssertEqual(latest?.channel(.direct(steve))?.messages.last?.threadID, "new")

        feed.sent(ChannelMessage(exchangeID: "sent-2", kind: .ask, speaker: .you, text: "Another", at: start, threadID: "", threadTitle: ""), in: .direct(steve))
        feed.started("sent-2", in: nil, title: "Another")
        XCTAssertEqual(latest?.channel(.direct(steve))?.messages.last?.failure, "That didn't start. Try again?")
    }
}

// MARK: - Messages, review round 2

extension ChannelFeedTests {
    func testAThreadOnItsOwnOnlyCountsAsReadIfItsWordsAreShown() async throws {
        let work = thread("work")
        backend.threads = [work, thread("other")]
        backend.set([Exchange(id: "between", asker: .agent(threadID: nil), askedAt: start, ask: "Another agent's request", reply: "An unseen answer", repliedAt: start)], in: work.id)
        backend.say("Other", in: "other")
        await openAndRead()
        XCTAssertEqual(feed.threads(in: .thread(work.id, in: .direct(steve))).map(\.id), [], "its words are only between agents, so its DM shows none")
        XCTAssertEqual(feed.threads(in: .thread("other", in: .direct(steve))).map(\.id), ["other"], "and only that thread")
    }
}

extension ChannelFeedTests {
    func testAThreadOnItsOwnDoesntCountAsReadWhileItsLatestAnswerIsOnlyBetweenKittens() async throws {
        let pepper = Kitten(name: "Pepper", role: "Finance", covers: "", folder: "/k/pepper")
        feed = ChannelFeed(backend: backend, kittens: { [steve] in [steve, pepper] }, gap: .milliseconds(20))
        feed.onChange = { [unowned self] in self.books.append($0) }
        let work = thread("work")
        let plans = AgentThread(id: "p", title: "Plans", projectTitle: "Pepper", status: .completed, model: "m", updatedAt: start, projectPath: "/k/pepper")
        backend.threads = [work, plans]
        backend.set([
            Exchange(id: "mine", asker: .you, askedAt: start.addingTimeInterval(-100), ask: "Draft the budget", reply: "Drafted.", repliedAt: start.addingTimeInterval(-90)),
            Exchange(id: "theirs", asker: .agent(threadID: "p"), askedAt: start.addingTimeInterval(-10), ask: "Change the totals?", reply: "Changed the totals.", repliedAt: start),
        ], in: work.id)
        backend.set([], in: "p")
        await openAndRead()
        let book = try XCTUnwrap(latest)
        XCTAssertTrue(book.channel(.direct(steve))?.messages.contains { $0.threadID == "work" } == true, "its older words are in the DM")
        XCTAssertEqual(feed.threads(in: .thread("work", in: .direct(steve))).map(\.id), [], "but its latest answer isn't, so it isn't read")
    }
}

// MARK: - Talking to the cat

extension ChannelFeedTests {
    func testTheCatsOwnThreadsAreReadToo() async {
        let talk = AgentThread(id: "r", title: "Which plan?", projectTitle: "Shades router", status: .completed, model: "m", updatedAt: start, projectPath: "/shades/router")
        feed.isWithShades = { $0.projectPath == "/shades/router" }
        backend.threads = [talk, thread("other", project: nil)]
        backend.say("Which plan?", in: "r")
        await openAndRead()
        XCTAssertEqual(backend.reads, ["r"], "and nothing else outside a kitten")
        XCTAssertEqual(latest?.shades.messages.first?.text, "Which plan?")
    }
}

extension ChannelFeedTests {
    func testLiveTestsOfTheCatDontUseUpWhatsReadOfIt() async {
        let real = AgentThread(id: "real-router", title: "A real question", projectTitle: "Shades router", status: .completed, model: "m", updatedAt: start, projectPath: "/shades/router")
        let tests = (1...30).map { index in
            AgentThread(id: "test-\(index)", title: "Shades test: \(index)", projectTitle: "Shades router", status: .completed, model: "m", updatedAt: start.addingTimeInterval(TimeInterval(index)), projectPath: "/shades/router")
        }
        feed.isWithShades = { $0.projectPath == "/shades/router" }
        backend.threads = tests + [real]
        backend.say("A real question", in: real.id)
        await openAndRead()
        XCTAssertTrue(backend.reads.contains(real.id), "30 newer live tests crowded out the real talk")
        XCTAssertEqual(latest?.shades.messages.compactMap(\.text), ["A real question"])
    }

    func testATalkWithTheCatNeverCountsAsReadAnywhereElse() async {
        let router = AgentThread(id: "router", title: "Steve: What's here?", projectTitle: "Shades router", status: .completed, model: "m", updatedAt: start, projectPath: "/shades/router")
        feed.isWithShades = { $0.projectPath == "/shades/router" }
        backend.threads = [router]
        backend.say("What's here?", in: router.id)
        await openAndRead()
        XCTAssertEqual(feed.threads(in: .channel(.everyone)).map(\.id), [], "Everyone doesn't show it")
        XCTAssertEqual(feed.threads(in: .channel(.direct(steve))).map(\.id), [], "nor does Steve's DM, whatever its title says")
    }
}
