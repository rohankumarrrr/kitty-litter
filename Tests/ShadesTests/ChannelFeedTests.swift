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
    private var _named: [String] = []
    private var _searches: [String] = []

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
    /// What T3's search names, whatever it's asked.
    var named: [String] {
        get { lock.withLock { _named } }
        set { lock.withLock { _named = newValue } }
    }
    var searches: [String] { lock.withLock { _searches } }
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

    func threads(matching words: String) async -> [String]? {
        lock.withLock {
            _searches.append(words)
            return _named
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
    func open(threadID: String) async throws { fatalError("The window opens threads, not the feed") }
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
        guard let book else { return [] }
        return book.threads(in: .of(steve)).flatMap { book.threads[$0]?.messages.map(\.text) ?? [] }
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
        XCTAssertEqual(book.channel(.of(steve))?.posts, [])
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
        feed.lookingAt = .channel(.of(pepper))
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
        XCTAssertEqual(latest?.channel(.of(steve))?.isCut, false)
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
        backend.threads = [thread("a"), thread("quiet", age: 5)]
        backend.say("Tidy it", in: "a")
        _ = feed.open(threads: [thread("a")])
        await eventually { self.backend.heldReads == 2 }
        XCTAssertEqual(feed.threads(in: .channel(.of(steve))), [], "nothing's on the screen while it's still reading")

        backend.releaseReads()
        await eventually { self.latest?.isReading == false }
        XCTAssertEqual(feed.threads(in: .channel(.of(steve))).map(\.id), ["a", "quiet"], "its parent is all it's said, so the channel shows it all, and one that's said nothing has nothing left to see")
        XCTAssertEqual(feed.threads(in: .thread("a", in: .threads)).map(\.id), ["a"], "and so does its pane")
        XCTAssertEqual(feed.threads(in: .channel(.shades)).map(\.id), [], "it doesn't live with the cat")
        XCTAssertEqual(feed.threads(in: .activity), [])
        XCTAssertEqual(feed.threads(in: .threads), [], "a line of a reply isn't all of it")
    }

    func testWorkEveryoneHandedOutsideAnyKittenIsReadToo() async {
        let work = thread("w", project: nil)
        backend.threads = [work]
        backend.say("Find a cheaper flight", in: "w")
        feed.messagesThreads = { ["w": Date(timeIntervalSince1970: 0)] }
        await openAndRead()
        XCTAssertEqual(backend.reads, ["w"])

        let other = thread("other", project: nil)
        backend.threads = [work, other]
        feed.messagesThreads = { [:] }
        feed.threadsChanged([work, other])
        await holdOn()
        XCTAssertFalse(backend.reads.contains("other"), "anything else outside a kitten stays unread")
    }

    func testANewTopicLearnsItsThreadOrThatItDidntStart() async {
        await openAndRead()
        let echo = ChannelMessage(exchangeID: "sent-1", kind: .ask, speaker: .you, text: "Draft a letter", at: start, threadID: "", threadTitle: "")
        feed.sent(echo, in: .of(steve), startsThread: true)
        XCTAssertEqual(latest?.threads["sent-1"]?.isStarting, true)
        feed.started("sent-1", in: "new", title: "Draft a letter")
        XCTAssertEqual(latest?.threads["new"]?.parent.text, "Draft a letter")
        XCTAssertEqual(latest?.started["sent-1"], "new")

        feed.sent(ChannelMessage(exchangeID: "sent-2", kind: .ask, speaker: .you, text: "Another", at: start, threadID: "", threadTitle: ""), in: .of(steve), startsThread: true)
        feed.started("sent-2", in: nil, title: "Another")
        XCTAssertEqual(latest?.threads["sent-2"]?.parent.failure, "That didn't start. Try again?")

        feed.sent(ChannelMessage(exchangeID: "sent-3", kind: .ask, speaker: .you, text: "To the cat", at: start, threadID: "", threadTitle: ""), in: .shades)
        feed.started("sent-3", in: nil)
        XCTAssertEqual(latest?.channel(.shades)?.posts.count, 1, "anything else stays where you said it")
        XCTAssertNil(latest?.threads["sent-3"])
    }

    func testALongThreadKeepsTheExchangeThatStartedIt() async {
        backend.threads = [thread("a")]
        backend.set((0..<250).map { Exchange(id: "e\($0)", asker: .you, askedAt: start.addingTimeInterval(TimeInterval($0)), ask: $0 == 0 ? "Start here" : "More \($0)") }, in: "a")
        await openAndRead()
        let thread = latest?.threads["a"]
        XCTAssertEqual(thread?.parent.text, "Start here")
        XCTAssertEqual(thread?.replies.count, ChannelBook.keptExchanges - 1)
        XCTAssertEqual(thread?.replies.first?.text, "More 51", "then the newest")
        XCTAssertEqual(thread?.isCut, true)
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
        XCTAssertEqual(feed.threads(in: .channel(.of(steve))).map(\.id), ["other"], "the channel only shows work's parent, not its answer")
        XCTAssertEqual(feed.threads(in: .thread(work.id, in: .channel(.of(steve)))).map(\.id).sorted(), ["other", "work"], "its pane shows every reply")
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
        XCTAssertEqual(book.threads["work"]?.latest.text, "Changed the totals.", "Pepper's ask is a reply in Steve's thread")
        XCTAssertEqual(feed.threads(in: .channel(.of(steve))).map(\.id), [], "its channel shows only its parent, so it isn't read")
        XCTAssertEqual(feed.threads(in: .thread("work", in: .channel(.of(steve)))).map(\.id), ["work"], "but its pane shows its latest reply")
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
        XCTAssertEqual(latest?.threads["r"]?.parent.text, "Which plan?")
        XCTAssertEqual(latest?.channel(.shades)?.posts, [.thread("r")])
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
        XCTAssertEqual(latest?.channel(.shades)?.posts, [.thread(real.id)])
    }

    func testATalkWithTheCatNeverCountsAsReadAnywhereElse() async {
        let router = AgentThread(id: "router", title: "Steve: What's here?", projectTitle: "Shades router", status: .completed, model: "m", updatedAt: start, projectPath: "/shades/router")
        feed.isWithShades = { $0.projectPath == "/shades/router" }
        backend.threads = [router]
        backend.say("What's here?", in: router.id)
        await openAndRead()
        XCTAssertEqual(feed.threads(in: .channel(.shades)).map(\.id), [], "the cat's channel doesn't count it")
        XCTAssertEqual(feed.threads(in: .channel(.of(steve))).map(\.id), [], "nor does Steve's channel, whatever its title says")
        XCTAssertEqual(feed.threads(in: .thread(router.id, in: .channel(.shades))).map(\.id), [], "and its own pane doesn't count for a kitten's runs")
    }
}

extension ChannelFeedTests {
    func testAReplyAlsoSentToTheChannelLetsTheChannelCountItsThreadAsRead() async {
        backend.threads = [thread("work")]
        backend.set([
            Exchange(id: "first", asker: .you, askedAt: start.addingTimeInterval(-100), ask: "Draft the budget", reply: "Drafted.", repliedAt: start.addingTimeInterval(-90)),
            Exchange(id: "second", asker: .you, askedAt: start.addingTimeInterval(-10), ask: "Change the totals"),
        ], in: "work")
        await openAndRead()
        XCTAssertEqual(feed.threads(in: .channel(.of(steve))).map(\.id), [])
        feed.sent(ChannelMessage(exchangeID: "sent-1", kind: .ask, speaker: .you, text: "Change the totals", at: start.addingTimeInterval(-10), threadID: "work", threadTitle: ""), in: .of(steve), alsoSent: true)
        XCTAssertEqual(feed.threads(in: .channel(.of(steve))).map(\.id), ["work"], "its latest is in the channel too")
    }
}

// MARK: - Delivery

extension ChannelFeedTests {
    func testYourWordsShowAsSendingUntilT3HasThem() async {
        let work = thread("a")
        backend.threads = [work]
        let first = Exchange(id: "e1", asker: .you, askedAt: start, ask: "Tidy the page")
        backend.set([first], in: "a")
        await openAndRead()
        feed.sent(ChannelMessage(exchangeID: "sent-1", kind: .ask, speaker: .you, text: "Shorter", at: start, threadID: "a", threadTitle: "", isSending: true), in: .of(steve), isReply: true)
        XCTAssertEqual(latest?.threads["a"]?.latest.isSending, true, "on its way")

        backend.set([first, Exchange(id: "e2", asker: .you, askedAt: start, ask: "Shorter")], in: "a")
        backend.threads = [moved(work, by: 1)]
        feed.threadsChanged(backend.threads ?? [])
        await eventually { self.latest?.threads["a"]?.latest.exchangeID == "e2" }
        XCTAssertEqual(latest?.threads["a"]?.latest.isSending, false, "delivered, once T3 echoes it")
        XCTAssertEqual(latest?.threads["a"]?.replies.count, 1, "and only once")
    }

    func testWordsThatWentNowhereCanGoAgainAsTheSameMessage() async {
        await openAndRead()
        let echo = ChannelMessage(exchangeID: "sent-1", kind: .ask, speaker: .you, text: "Shorter", at: start, threadID: "a", threadTitle: "", isSending: true)
        feed.sent(echo, in: .of(steve), isReply: true, target: .thread(id: "a", title: "Work"))
        XCTAssertNil(feed.toTryAgain("sent-1"), "nothing to try again while it's on its way")

        feed.failed("sent-1", because: "I can't reach T3 Code. Open it and try again.")
        let failed = latest?.threads["a"]?.latest
        XCTAssertEqual(failed?.failure, "I can't reach T3 Code. Open it and try again.")
        XCTAssertEqual(failed?.isSending, false)
        XCTAssertEqual(failed?.canTryAgain, true)
        XCTAssertEqual(feed.toTryAgain("sent-1")?.target, .thread(id: "a", title: "Work"), "where it was going")

        feed.sent(echo, in: .of(steve), isReply: true, target: .thread(id: "a", title: "Work"))
        XCTAssertEqual(latest?.threads["a"]?.messages.map(\.exchangeID), ["sent-1"], "trying again takes its place")
        XCTAssertEqual(latest?.threads["a"]?.latest.isSending, true)
        XCTAssertNil(latest?.threads["a"]?.latest.failure)
    }

    func testOnlyWordsYouSentCanGoAgain() {
        var failed = ChannelMessage(exchangeID: "x", kind: .ask, speaker: .you, text: "Shorter", at: start, threadID: "a", threadTitle: "", failure: "Not sent")
        XCTAssertTrue(failed.canTryAgain)
        failed.files = [ChannelFile(name: "plan.pdf")]
        XCTAssertFalse(failed.canTryAgain, "a file isn't kept, and what stops one going is still there next time")
        let theirs = ChannelMessage(exchangeID: "x", kind: .reply, speaker: .kitten(steve.id), text: nil, at: start, threadID: "a", threadTitle: "", failure: "Ran out of quota")
        XCTAssertFalse(theirs.canTryAgain, "a kitten's failed turn is its own")
    }
}

extension ChannelFeedTests {
    /// Only each kitten's newest 30 were ever read, so anything older could only be found in T3.
    func testScrollingBackToTheTopOfAChannelLoadsItsOlderThreadsAPageAtATime() async {
        backend.threads = (0..<70).map { thread("t\($0)", age: TimeInterval($0)) }
        for index in 0..<70 { backend.say("Ask \(index)", in: "t\(index)") }
        await openAndRead()
        XCTAssertEqual(latest?.threads(in: .of(steve)).count, 30)
        XCTAssertEqual(ChannelRows.rows(.channel(.of(steve)), in: latest!).first, .older(isLoading: false))

        backend.holdsReads = true
        feed.older(in: .of(steve))
        XCTAssertEqual(ChannelRows.rows(.channel(.of(steve)), in: latest!).first, .older(isLoading: true))
        let reads = backend.reads.count
        feed.older(in: .of(steve))
        await eventually { self.backend.heldReads > 0 }
        backend.releaseReads()
        await eventually { self.latest?.channel(.of(steve))?.isLoadingOlder == false }
        XCTAssertEqual(Set(backend.reads.dropFirst(reads)), Set((30..<60).map { "t\($0)" }), "one page, however often it's asked for meanwhile")
        XCTAssertEqual(latest?.threads(in: .of(steve)).count, 60)

        feed.older(in: .of(steve))
        await eventually { self.latest?.threads(in: .of(steve)).count == 70 }
        XCTAssertEqual(latest?.channel(.of(steve))?.isCut, false, "and once there's nothing older, nothing more to load")
    }

    func testSearchFindsWhatLoadOlderRead() async {
        backend.threads = (0..<35).map { thread("t\($0)", age: TimeInterval($0)) }
        for index in 0..<35 { backend.say(index == 34 ? "Where did the coupon box go?" : "Ask \(index)", in: "t\(index)") }
        await openAndRead()
        XCTAssertTrue(MessageSearch.find("coupon", in: latest!, limit: 8).found.isEmpty, "Messages hasn't read that far back")
        feed.older(in: .of(steve))
        await eventually { self.latest?.threads(in: .of(steve)).count == 35 }
        XCTAssertEqual(MessageSearch.find("coupon", in: latest!, limit: 8).found.map(\.message.threadID), ["t34"])
    }

    func testSearchAsksT3AndReadsOnlyTheThreadsItNamesThatMessagesShows() async {
        backend.threads = (0..<35).map { thread("t\($0)", age: TimeInterval($0)) } + [thread("elsewhere", project: "Elsewhere")]
        for index in 0..<35 { backend.say("Ask \(index)", in: "t\(index)") }
        backend.say("Where did the coupon box go?", in: "t34")
        backend.say("The coupon box is in the footer.", in: "elsewhere")
        await openAndRead()
        let read = backend.reads.count
        // T3 matches what was sent, screen and all, so a thread it names can have none of the words Messages shows.
        backend.named = ["elsewhere", "t34", "t33", "t0"]
        backend.holdsReads = true
        feed.find("coupon")
        await eventually { self.latest?.searchingT3 == "coupon" }
        await eventually { self.backend.heldReads > 0 }
        backend.releaseReads()
        await eventually { self.latest?.searchingT3 == nil }

        XCTAssertEqual(backend.searches, ["coupon"])
        XCTAssertEqual(Set(backend.reads.dropFirst(read)), ["t34", "t33"], "only threads Messages shows and hasn't read, never someone else's")
        XCTAssertEqual(MessageSearch.find("coupon", in: latest!, limit: 8).found.map(\.message.threadID), ["t34"], "what shows is only what Messages itself read")
        XCTAssertNil(latest?.threads["elsewhere"])

        feed.threadsChanged(backend.threads!)
        await holdOn()
        XCTAssertNotNil(latest?.threads["t34"], "what Search found stays read")
        XCTAssertEqual(MessageSearch.find("coupon", in: latest!, limit: 8).found.count, 1)
    }

    func testOnlyTheLatestWordsAreAskedAboutAndNoneStopsLooking() async {
        backend.threads = [thread("t0")]
        backend.say("Ask", in: "t0")
        await openAndRead()
        backend.holdsReads = true
        backend.named = ["t1"]
        feed.find("co")
        feed.find("")
        XCTAssertNil(latest?.searchingT3, "clearing the box stops it looking")
        feed.find("x")
        XCTAssertNil(latest?.searchingT3, "one letter isn't asked about")
        backend.releaseReads()
    }

    func testTheCatsDMLoadsOlderTalksToo() async {
        feed.isWithShades = { $0.projectPath == "/shades/router" }
        backend.threads = (0..<35).map { index in
            AgentThread(id: "r\(index)", title: "Question \(index)", projectTitle: "Shades router", status: .completed, model: "m", updatedAt: start.addingTimeInterval(-TimeInterval(index)), projectPath: "/shades/router")
        }
        for index in 0..<35 { backend.say("Question \(index)", in: "r\(index)") }
        await openAndRead()
        XCTAssertEqual(latest?.threads(in: .shades).count, 30)
        XCTAssertEqual(latest?.channel(.shades)?.isCut, true)
        feed.older(in: .shades)
        await eventually { self.latest?.threads(in: .shades).count == 35 }
    }

    /// Everything Messages started was read in #general, whoever's it was. Now a kitten's is among its newest, and the
    /// cat's own is among the cat's.
    func testWorkMessagesStartedIsReadWithWhoeverHasIt() async {
        backend.threads = (0..<30).map { thread("t\($0)", age: TimeInterval($0)) } + [thread("from-messages", age: 500), thread("cats", project: nil, age: 500)]
        for thread in backend.threads! { backend.say("Ask", in: thread.id) }
        feed.messagesThreads = { ["from-messages": Date(timeIntervalSince1970: 0), "cats": Date(timeIntervalSince1970: 0)] }
        await openAndRead()
        XCTAssertTrue(backend.reads.contains("cats"))
        XCTAssertEqual(latest?.threads(in: .shades), ["cats"])
        XCTAssertFalse(backend.reads.contains("from-messages"), "older than Steve's newest 30")
        XCTAssertEqual(latest?.channel(.of(steve))?.isCut, true, "so it loads as you scroll back to it")
        feed.older(in: .of(steve))
        await eventually { self.latest?.threads(in: .of(steve)).contains("from-messages") == true }
    }

    func testAReplyAlsoSentToTheChannelIsHandedOverToKeepOnceT3HasIt() async {
        var kept: [String: ChannelBook.HeardAlsoSent] = [:]
        feed.keepAlsoSent = { kept.merge($0) { first, _ in first } }
        backend.threads = [thread("work")]
        backend.set([Exchange(id: "first", asker: .you, askedAt: start.addingTimeInterval(-100), ask: "Draft the budget")], in: "work")
        await openAndRead()
        feed.sent(ChannelMessage(exchangeID: "sent-1", kind: .ask, speaker: .you, text: "Change the totals", at: start.addingTimeInterval(-10), threadID: "work", threadTitle: ""), in: .of(steve), alsoSent: true)
        XCTAssertEqual(kept, [:], "words T3 doesn't have yet are never kept")

        backend.set([
            Exchange(id: "first", asker: .you, askedAt: start.addingTimeInterval(-100), ask: "Draft the budget"),
            Exchange(id: "second", asker: .you, askedAt: start.addingTimeInterval(-10), ask: "Change the totals"),
        ], in: "work")
        backend.threads = [moved(thread("work"), by: 5)]
        feed.threadsChanged(backend.threads!)
        await eventually { kept == ["second:ask": .init(thread: "work", channel: .of(steve))] }
    }
}

extension ChannelFeedTests {
    func testAThreadThatCantBeReadElsewhereLeavesLoadOlderWhereThereAreOlderThreads() async {
        backend.threads = (0..<40).map { thread("t\($0)", age: TimeInterval($0)) } + [thread("broken", project: nil)]
        for index in 0..<40 { backend.say("Ask \(index)", in: "t\(index)") }
        backend.failing = ["broken"]
        feed.messagesThreads = { ["broken": Date(timeIntervalSince1970: 0)] }
        await openAndRead()
        await holdOn()
        XCTAssertEqual(ChannelRows.rows(.channel(.of(steve)), in: latest!).first, .older(isLoading: false), "Steve's channel still has 10 older threads to load")
        XCTAssertEqual(latest?.channel(.shades)?.isCut, false, "and the one that couldn't be read isn't older, just unread")
    }
}
