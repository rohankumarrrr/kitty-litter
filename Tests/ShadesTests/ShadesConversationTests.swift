@testable import Shades
import ShadesCore
import XCTest

/// A talk with the cat in Messages: never writable, never a kitten's, never on the phone, and read once.
@MainActor
final class ShadesConversationTests: XCTestCase {
    private let at = Date(timeIntervalSince1970: 1_000_000)
    private let steve = Kitten(name: "Steve", role: "Professional", covers: "", folder: "/k/steve")

    private func talk(_ id: String = "r", title: String = "Which plan is cheapest here?", status: AgentStatus = .completed) -> AgentThread {
        AgentThread(id: id, title: title, projectTitle: "Shades router", status: status, model: "m", updatedAt: at, projectPath: "/shades/router")
    }

    private func said(_ ask: String, _ reply: String?) -> [Exchange] {
        [Exchange(id: "1", asker: .you, askedAt: at, ask: ask, reply: reply, repliedAt: reply == nil ? nil : at)]
    }

    private func makeController(backend: FakeBackend = FakeBackend(), stage: FakeStage? = nil) -> AppController {
        let log = Log()
        var settings = Settings()
        settings.quickModel = ModelChoice(provider: "claudeAgent", model: "claude-haiku-5-5", effort: "medium")
        settings.frontierModel = ModelChoice(provider: "claudeAgent", model: "claude-fable-5-1", effort: "high")
        settings.quickMode = .approvalRequired
        settings.frontierMode = .autoAcceptEdits
        let controller = AppController(
            dependencies: AppDependencies(
                backend: backend,
                context: FakeContext(log: log),
                voice: FakeVoice(),
                inserter: FakeInserter(),
                keys: FakeKeys(),
                settings: settings,
                saveSettings: { _ in },
                kittens: { [steve] in [steve] },
                routerFolder: { "/shades/router" }
            ),
            stage: stage ?? FakeStage(log: log),
            now: { [at] in at.addingTimeInterval(60) }
        )
        controller.threadListWait = 0
        controller.reportDelay = 0
        return controller
    }

    private func send(_ key: String, in book: ChannelBook) -> MessagesAction? {
        PhoneAsk(act: "send", key: key, text: "and the yearly price?", id: nil, value: nil, answers: nil, kind: nil).action(in: book, newTopic: { "topic" })?.action
    }

    /// T3 gives an assistant message's whole text so far, so a router turn that's still going is read half written.
    func testAReplyStillBeingWrittenReadsLikeTheBubble() {
        for partial in ["KITT", "SEND T", "REWR", "CORRECTION: 2\nKITTE", "It's the blue one.\nPOI"] {
            let built = ChannelBook.build(
                kittens: [steve], threads: [talk(status: .running)], transcripts: ["r": said("Where is it?", partial)],
                isReading: false, unreadable: 0, cantReachT3: false, withShades: ["r"]
            )
            let reply = built.shades.messages.last
            XCTAssertEqual(reply?.kind, .reply, partial)
            // What the bubble shows for the same text so far.
            var holdback = ReplyHoldback()
            let bubble = holdback.add(partial)
            XCTAssertEqual(reply?.text, bubble, "a half-written \(partial.debugDescription) isn't the cat's words")
        }
    }

    /// Being the router's used to be remembered only while the app ran, so after a restart a talk with the cat was
    /// work under Shades in Needs you, on the phone too, and opened writable.
    func testAfterARestartATalkWithTheCatIsntWorkOnThePhoneOrWritable() {
        let controller = makeController()
        let thread = talk()
        controller.threadsChanged([thread])
        XCTAssertTrue(controller.isWithShades(thread))
        let waiting = controller.waiting
        let built = ChannelBook.build(
            kittens: [], threads: [thread], transcripts: ["r": said("Which plan is cheapest here?", "Starter.")],
            isReading: false, unreadable: 0, cantReachT3: false, waiting: waiting, withShades: ["r"]
        )
        XCTAssertEqual(built.shades.messages.first?.text, "Which plan is cheapest here?")
        XCTAssertFalse(waiting.shadesWork.contains { $0.id == "r" }, "a talk with the cat isn't work")
        let needs = PhoneView(PhonePlace("needs", in: built), in: built, now: at)
        XCTAssertFalse(needs.rows.contains { $0.title == "Which plan is cheapest here?" }, "what you asked the cat stays off the phone")
        let opened = PhonePlace(PhonePlace.key(.thread("r", in: .everyone)), in: built)
        XCTAssertNil(opened.target, "it has no box")
        XCTAssertNil(send(opened.key, in: built), "and nothing goes into the router's thread")
    }

    /// A router thread's title is the first line of your question, and "Name: ..." makes a thread that kitten's.
    func testATalkTitledForAKittenIsntThatKittens() {
        let question = "Steve: which font did you pick for my site?"
        let thread = talk(title: question)
        let built = ChannelBook.build(
            kittens: [steve], threads: [thread], transcripts: ["r": said(question, "KITTEN: 1")],
            isReading: false, unreadable: 0, cantReachT3: false, isUnread: { $0.id == "r" }, withShades: ["r"]
        )
        XCTAssertEqual(built.shades.messages.first?.text, question, "it's in Shades")
        XCTAssertEqual(built.channel(.direct(steve))?.messages, [], "and not in Steve's DM")
        let done = PhoneView(PhonePlace("done", in: built), in: built, now: at)
        XCTAssertFalse(done.rows.contains { $0.open == PhonePlace.key(.thread("r", in: .direct(steve))) }, "it isn't in Steve's Done")
        XCTAssertNil(PhonePlace(PhonePlace.key(.thread("r", in: .direct(steve))), in: built).target, "it has no box")
        XCTAssertNil(send(PhonePlace.key(.thread("r", in: .direct(steve))), in: built), "and nothing goes into the router's thread")
        XCTAssertEqual(built.unread, [], "and Steve gets no dot for it")
    }

    private var books: [ChannelBook] = []

    /// A router thread titled "Name: ..." looked like that kitten's and the cat's, so it was read twice and the
    /// second read counted as one that couldn't be done.
    func testATalkTitledForAKittenIsReadOnce() async throws {
        let backend = FakeBackend()
        let question = "Steve: which font did you pick for my site?"
        let thread = talk(title: question)
        backend.listed = [thread]
        backend.said = ["r": said(question, "Inter, for the headings.")]
        let feed = ChannelFeed(backend: backend, kittens: { [steve] in [steve] }, gap: .milliseconds(20))
        feed.isWithShades = { $0.projectPath == "/shades/router" }
        books = []
        feed.onChange = { [unowned self] in self.books.append($0) }
        _ = feed.open(threads: [thread])
        for _ in 0..<400 {
            if books.contains(where: { !$0.isReading }) { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        feed.close()
        let read = try XCTUnwrap(books.first { !$0.isReading })
        XCTAssertEqual(read.shades.messages.first?.text, question)
        XCTAssertEqual(read.unreadable, 0, "read once, and nothing it couldn't read")
        XCTAssertFalse(ChannelRows.rows(.channel(.shades), in: read).contains(.note(CatWords.couldntRead(1))))
    }
}
