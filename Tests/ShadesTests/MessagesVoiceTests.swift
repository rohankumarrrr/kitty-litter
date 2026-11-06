import AppKit
@testable import Shades
import ShadesCore
import XCTest

/// Talking into Messages' box, where the box holds still while you speak.
@MainActor
final class MessagesVoiceTests: XCTestCase {
    private let steve = Kitten(name: "Steve", role: "Professional", covers: "", folder: "/k/steve")
    private let pepper = Kitten(name: "Pepper", role: "Finance", covers: "", folder: "/k/pepper")
    private let at = Date(timeIntervalSince1970: 1_000_000)

    private func controller(stage: FakeStage, voice: VoiceEngine) -> AppController {
        AppController(dependencies: AppDependencies(
            backend: FakeBackend(),
            context: FakeContext(log: stage.log),
            voice: voice,
            inserter: FakeInserter(),
            keys: FakeKeys(),
            settings: Settings(),
            saveSettings: { _ in },
            kittens: { [] }
        ), stage: stage)
    }

    private func thread(_ id: String, kitten: Kitten) -> AgentThread {
        AgentThread(id: id, title: "Work", projectTitle: kitten.name, status: .completed, model: "m", updatedAt: at, projectPath: kitten.folder)
    }

    private func book(questions: [AgentQuestion] = [], between: Bool = false) -> ChannelBook {
        let exchange = Exchange(id: "e", asker: between ? .agent(threadID: "p") : .you, askedAt: at, ask: "Choose a font", reply: "Ready", repliedAt: at)
        return ChannelBook.build(
            kittens: [steve, pepper],
            threads: [thread("t", kitten: steve), thread("p", kitten: pepper)],
            transcripts: ["t": [exchange], "p": []],
            isReading: false,
            unreadable: 0,
            cantReachT3: false,
            waiting: Waiting(questions: questions, owners: Dictionary(uniqueKeysWithValues: questions.map { ($0.id, steve.id) }))
        )
    }

    private func subviews(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(subviews)
    }

    func testCancellingWhileItsStillWorkingOutWhatYouSaidLetsTheBoxGoAtOnce() async {
        let stage = FakeStage(log: Log())
        stage.isMessagesBoxTyping = true
        let voice = HeldVoice()
        let controller = controller(stage: stage, voice: voice)
        controller.talkDown()
        XCTAssertTrue(stage.messagesBoxHeld)

        let finishing = Task { await controller.talkUp() }
        while voice.pending == nil { await Task.yield() }
        controller.cancelListening()
        XCTAssertFalse(stage.messagesBoxHeld)

        voice.pending?.resume(returning: Transcript(raw: "never mind", cleaned: "Never mind.", audioSeconds: 1, latencySeconds: 0.1))
        await finishing.value
        XCTAssertEqual(stage.sentInMessages, [], "what you cancelled isn't sent when it's worked out")
        XCTAssertFalse(stage.log.all.contains("snapshot"), "and it doesn't turn into asking the cat")
    }

    func testEveryWayOfStoppingLetsTheBoxGo() async {
        for exit in ["cancel", "begin error", "end error", "empty", "focus lost", "closed"] {
            let stage = FakeStage(log: Log())
            stage.isMessagesBoxTyping = true
            let voice = FakeVoice()
            if exit == "begin error" { voice.beginError = URLError(.cannotConnectToHost) }
            if exit == "end error" { voice.endError = URLError(.cannotConnectToHost) }
            if exit == "empty" { voice.transcript = Transcript(raw: "", cleaned: "", audioSeconds: 1, latencySeconds: 0.1) }
            let controller = controller(stage: stage, voice: voice)
            controller.talkDown()
            switch exit {
            case "cancel": controller.cancelListening()
            case "begin error": break
            default:
                if exit == "focus lost" { stage.isMessagesBoxTyping = false }
                if exit == "closed" { controller.channelsClosed() }
                await controller.talkUp()
            }
            XCTAssertFalse(stage.messagesBoxHeld, exit)
            XCTAssertTrue(stage.sentInMessages.isEmpty, exit)
            XCTAssertFalse(stage.log.all.contains("snapshot"), exit)
        }
    }

    func testWhatYouSaidForOnePartOfAQuestionDoesntAnswerTheNext() throws {
        let question = AgentQuestion(id: "q", threadID: "t", threadTitle: "Work", text: "Which month?", form: AnswerForm(parts: [
            AnswerForm.Part(key: "month", text: "Which month?", options: ["January"], values: ["jan"], takesOwnWords: true),
            AnswerForm.Part(key: "currency", text: "Which currency?", options: ["USD"], values: ["usd"], takesOwnWords: true),
        ]))
        let view = ChannelsView(frame: NSRect(x: 0, y: 0, width: 820, height: 560))
        var sent: [MessagesAction] = []
        view.pane.onAction = { sent.append($0) }
        view.show(book(questions: [question]))
        view.select(.thread("t", in: .direct(steve)))
        view.pane.startSpeaking()

        let january = try XCTUnwrap(subviews(of: view).compactMap { $0 as? QuietButton }.first { $0.accessibilityLabel() == "January" })
        XCTAssertTrue(january.accessibilityPerformPress())
        view.pane.spoke("February")
        XCTAssertTrue(sent.isEmpty, "February was said for the month, not the currency")
        XCTAssertEqual(view.pane.composer.textView.string, "February")
    }

    func testABoxThatGoesAwayAfterYouStopTalkingLeavesNoGap() throws {
        let view = ChannelsView(frame: NSRect(x: 0, y: 0, width: 820, height: 560))
        view.show(ChannelBook.build(kittens: [steve, pepper], threads: [thread("t", kitten: steve), thread("p", kitten: pepper)], transcripts: [:], isReading: true, unreadable: 0, cantReachT3: false))
        view.select(.thread("t", in: .direct(steve)))
        view.pane.startSpeaking()
        view.show(book(between: true))
        XCTAssertNotNil(view.pane.composer.target, "held while you talk")

        view.pane.stopSpeaking()
        view.layoutSubtreeIfNeeded()
        XCTAssertNil(view.pane.composer.target, "a thread between kittens is only read")
        let scroll = try XCTUnwrap(view.pane.subviews.compactMap { $0 as? QuietScrollView }.first)
        XCTAssertEqual(scroll.frame.maxY, view.pane.bounds.height, accuracy: 1)
    }
}

/// Holds on to working out what was said until the test lets it go.
private final class HeldVoice: VoiceEngine {
    let partials = AsyncStream<String> { $0.finish() }
    let levels = AsyncStream<Float> { $0.finish() }
    var pending: CheckedContinuation<Transcript, Error>?

    func prepare() async throws {}
    func setVocabulary(_ words: [String]) {}
    func begin() throws {}
    func end() async throws -> Transcript {
        try await withCheckedThrowingContinuation { pending = $0 }
    }
    func cancel() {}
}
