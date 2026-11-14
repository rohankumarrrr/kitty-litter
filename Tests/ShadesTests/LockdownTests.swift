@testable import Shades
import ShadesCore
import XCTest

/// Lockdown: every ask goes straight to one kitten, with no router, its screen as that kitten may have it, and carries on
/// in one thread. Nothing else pops up until it's off, and then it all comes in one catch-up.
@MainActor
final class LockdownTests: XCTestCase {
    private var stage: FakeStage!
    private var backend: FakeBackend!
    private var clock = Date(timeIntervalSince1970: 100_000)
    private var kittens: [Kitten] = []
    private var savedSettings: Settings?
    private var notified: [NeedsYouAlert] = []
    private var reported: [String?] = []
    private var controller: AppController!
    private let builder = Kitten(name: "Builder", role: "Coding", covers: "the app being built", folder: "/k/builder")
    private let money = Kitten(name: "Money", role: "Bills", covers: "bills and subscriptions", folder: "/k/money")
    private let rules = Kitten(name: "Rules", role: "The system", covers: "the rules", folder: "/k/rules", seesScreen: false)
    private let screen = ScreenSnapshot(appName: "Editor", windowTitle: "invoice.swift", selectedText: "let total = 0")

    override func setUp() async throws {
        stage = FakeStage(log: Log())
        backend = FakeBackend()
        backend.projects = ["/k/builder": "project-builder", "/k/money": "project-money", "/k/rules": "project-rules", "/shades/router": "project-router"]
        kittens = [builder, money, rules]
        controller = makeController()
    }

    /// The app as it comes up: a new one of these, with what the last one saved, is a restart.
    private func makeController(settings: Settings = Settings()) -> AppController {
        var settings = settings
        settings.quickMode = .approvalRequired
        let controller = AppController(
            dependencies: AppDependencies(
                backend: backend,
                context: FakeContext(log: Log()),
                voice: FakeVoice(),
                inserter: FakeInserter(),
                keys: FakeKeys(),
                settings: settings,
                saveSettings: { [unowned self] in self.savedSettings = $0 },
                kittens: { [unowned self] in self.kittens },
                routerFolder: { "/shades/router" },
                reportHealth: { [unowned self] _, lockdown in self.reported.append(lockdown) },
                notify: { [unowned self] in self.notified.append($0) }
            ),
            stage: stage,
            now: { [unowned self] in self.clock }
        )
        controller.threadListWait = 0
        controller.reportDelay = 0
        return controller
    }

    private func settle() async {
        for _ in 0..<50 {
            await controller.replyTask?.value
            await controller.lockdownTurn?.value
            await controller.flow?.value
            await controller.frontierTask?.value
            await controller.forwardTask?.value
            await controller.messagesTurn?.value
            await controller.reportTask?.value
            await Task.yield()
        }
    }

    private func thread(_ id: String, of kitten: Kitten, status: AgentStatus = .running) -> AgentThread {
        AgentThread(id: id, title: "Work", projectTitle: kitten.name, status: status, model: "m", updatedAt: clock, runtimeMode: .auto, projectPath: kitten.folder, lastRunID: "run-1", lastRunEndedAt: clock)
    }

    private func ask(_ words: String) async {
        controller.ask(words, snapshot: screen)
        await settle()
    }

    // MARK: - Every ask goes to the kitten

    func testAnAskGoesStraightToTheKittenWithItsScreenMarkedAndNoRouter() async {
        controller.lockdownPicked(builder)
        await ask("Add subscriptions to the invoice page")
        XCTAssertEqual(backend.sent.count, 1, "no router turn first")
        let sent = backend.sent[0]
        XCTAssertEqual(sent.mode, .start)
        XCTAssertEqual(sent.prompt.projectID, "project-builder", "not the money kitten, whatever the words say")
        XCTAssertTrue(sent.prompt.text.hasPrefix("Add subscriptions to the invoice page"))
        XCTAssertTrue(sent.prompt.text.contains("<screen>"))
        XCTAssertTrue(sent.prompt.text.contains("let total = 0"))
        XCTAssertEqual(controller.settings.lockdown?.thread, "thread-1")
    }

    func testLaterAsksCarryOnInItsThreadAsRepliesWhileItWorksSays() async {
        controller.lockdownPicked(builder)
        await ask("Start the page")
        controller.threadsChanged([thread("thread-1", of: builder)])
        await ask("Now the total")
        XCTAssertEqual(backend.sent.map(\.mode), [.start, .forward])
        XCTAssertEqual(backend.sent[1].threadID, "thread-1")
        XCTAssertEqual(backend.sent[1].behavior, .steer)
        XCTAssertTrue(backend.sent[1].prompt.text.contains("<screen>"))

        var queued = controller.settings
        queued.followUpBehavior = .queue
        controller.settingsEdited(queued)
        await ask("And tests")
        XCTAssertEqual(backend.sent[2].threadID, "thread-1")
        XCTAssertEqual(backend.sent[2].behavior, .queue)
    }

    func testTwoQuickAsksStartOneThread() async {
        controller.lockdownPicked(builder)
        controller.threadsChanged([])
        controller.ask("One", snapshot: nil)
        await settle()
        controller.threadsChanged([thread("thread-1", of: builder)])
        controller.ask("Two", snapshot: nil)
        await settle()
        XCTAssertEqual(backend.sent.filter { $0.mode == .start }.count, 1)
    }

    func testTheNextAskCarriesOnInANewThreadBeforeT3ListsItWithoutTheScreenUntilItsModeIsKnown() async {
        controller.lockdownPicked(builder)
        await ask("Start the page")
        await ask("Now the total")
        XCTAssertEqual(backend.sent.map(\.mode), [.start, .forward])
        XCTAssertEqual(backend.sent[1].threadID, "thread-1")
        XCTAssertFalse(backend.sent[1].prompt.text.contains("let total = 0"), "its mode could have changed since it started")
        XCTAssertTrue(stage.bubbles.contains(.line(CatWords.sentTo("Builder"), threadID: "thread-1")), "it says where, by the kitten's name")
    }

    func testAKittenThatDoesntSeeTheScreenGetsNoneOfItInItsNextAskEither() async {
        controller.lockdownPicked(rules)
        await ask("Look at this")
        await ask("And this")
        XCTAssertEqual(backend.sent.map(\.mode), [.start, .forward])
        XCTAssertFalse(backend.sent[1].prompt.text.contains("let total = 0"))
        XCTAssertTrue(backend.sent[1].prompt.attachments.isEmpty)
    }

    func testAKittenThatDoesntSeeTheScreenGetsNoneOfIt() async {
        controller.lockdownPicked(rules)
        await ask("Look at this")
        XCTAssertEqual(backend.sent.count, 1)
        XCTAssertFalse(backend.sent[0].prompt.text.contains("let total = 0"))
        XCTAssertFalse(backend.sent[0].prompt.text.contains("<screen>"))
        XCTAssertTrue(backend.sent[0].prompt.attachments.isEmpty)
    }

    func testStartANewThreadMeansTheNextAskStartsOne() async {
        controller.lockdownPicked(builder)
        await ask("First")
        controller.threadsChanged([thread("thread-1", of: builder)])
        controller.lockdownNewThread()
        await ask("Second")
        XCTAssertEqual(backend.sent.map(\.mode), [.start, .start])
        XCTAssertEqual(controller.settings.lockdown?.thread, "thread-2")
    }

    func testWhatYouSayToTheCatInMessagesGoesToTheKitten() async {
        controller.lockdownPicked(builder)
        controller.messagesAction(.send("Add a header", to: .router, shownIn: .shades))
        await settle()
        XCTAssertEqual(backend.sent.count, 1)
        XCTAssertEqual(backend.sent[0].prompt.projectID, "project-builder")
        XCTAssertFalse(backend.sent[0].prompt.text.contains("<screen>"), "Messages never takes your screen")
    }

    func testTypingInAnotherKittensChannelStillGoesThere() async {
        controller.lockdownPicked(builder)
        controller.messagesAction(.startTopic("Pay the bill", with: money, id: "topic-1"))
        await settle()
        XCTAssertEqual(backend.sent.map(\.prompt.projectID), ["project-money"])
    }

    func testFixGoesToTheKitten() async {
        controller.lockdownPicked(builder)
        controller.sendFix("", snapshot: screen)
        await settle()
        XCTAssertEqual(backend.sent.count, 1)
        XCTAssertEqual(backend.sent[0].prompt.projectID, "project-builder")
        XCTAssertTrue(backend.sent[0].prompt.text.hasPrefix(CatWords.fixThis))
    }

    func testItSurvivesARestartAndCarriesOnInTheSameThread() async throws {
        controller.lockdownPicked(builder)
        await ask("Start the page")
        controller = makeController(settings: try XCTUnwrap(savedSettings))
        controller.threadsChanged([thread("thread-1", of: builder)])
        await ask("Carry on")
        XCTAssertEqual(backend.sent.last?.mode, .forward)
        XCTAssertEqual(backend.sent.last?.threadID, "thread-1")
    }

    func testOffTheRouterIsBack() async {
        controller.lockdownPicked(builder)
        controller.lockdownPicked(builder)
        XCTAssertNil(controller.settings.lockdown)
        await ask("Hello")
        XCTAssertEqual(backend.sent.first?.prompt.projectID, "project-router")
    }

    func testAKittenThatsGoneHoldsTheAskRatherThanRoutingIt() async {
        controller.lockdownPicked(builder)
        kittens = [money]
        await ask("Hello")
        XCTAssertTrue(backend.sent.isEmpty)
        XCTAssertEqual(stage.bubble, .line(CatWords.lockdownKittenGone, threadID: nil))
    }

    // MARK: - Only that kitten comes through

    func testOnlyItsKittensWorkPopsUpAndTheRestWaitsForOneCatchUp() async {
        controller.lockdownPicked(builder)
        let other = thread("m", of: money)
        let own = thread("b", of: builder)
        controller.threadsChanged([other, own])
        backend.reports = ["m": "Paid.", "b": "Built."]
        var done = [other, own]
        done[0].status = .completed
        done[1].status = .completed
        done[0].lastRunID = "run-2"
        done[1].lastRunID = "run-2"
        controller.threadsChanged(done)
        await settle()
        XCTAssertEqual(controller.away, [.thread("m")], "the money kitten's report waits")
        XCTAssertEqual(stage.bubble, .notice(caption: "Builder: Work", text: "Built.", threadID: "b", asks: false), "its own still comes")

        controller.lockdownPicked(builder)
        XCTAssertTrue(controller.catchingUp)
        controller.bubbleDismissed(byClick: false)
        if case .inbox = stage.bubble {} else { XCTFail("one catch-up once it's off, not \(String(describing: stage.bubble))") }
    }

    func testAnotherKittensApprovalWaitsAndItsOwnIsAsked() async {
        controller.lockdownPicked(builder)
        let theirs = ApprovalRequest(id: "a-m", threadID: "m", threadTitle: "Bills", kind: .command, summary: "pay", createdAt: clock)
        let ours = ApprovalRequest(id: "a-b", threadID: "b", threadTitle: "Page", kind: .command, summary: "npm test", createdAt: clock.addingTimeInterval(1))
        var other = thread("m", of: money, status: .waitingForApproval)
        other.pendingApprovals = [theirs]
        var own = thread("b", of: builder, status: .waitingForApproval)
        own.pendingApprovals = [ours]
        controller.threadsChanged([other, own])
        await settle()
        XCTAssertTrue(controller.away.contains(.approval("a-m")))
        XCTAssertFalse(controller.away.contains(.approval("a-b")))
        controller.catClicked()
        if case .approval(let request, _, _) = stage.bubble {
            XCTAssertEqual(request.id, "a-b", "the money kitten's never shows")
        } else {
            XCTFail("its own approval is asked, not \(String(describing: stage.bubble))")
        }
    }

    func testTheCatsOwnLinesWait() {
        controller.lockdownPicked(builder)
        XCTAssertFalse(controller.mayPopUp(.line("Something finished")))
        XCTAssertEqual(controller.away, [.line("Something finished")])
    }

    // MARK: - Checking it

    func testHealthSaysWhichKittenItsOnFor() async {
        controller.lockdownPicked(builder)
        await settle()
        await controller.healthTask?.value
        XCTAssertEqual(reported.last, "Builder")
        controller.lockdownPicked(builder)
        await controller.healthTask?.value
        XCTAssertEqual(reported.last, .some(nil))
    }

    func testTheSelfCheckSaysWhenItsKittenIsGone() {
        var facts = HealthFacts()
        facts.lockdownKittenGone = true
        XCTAssertEqual(HealthCheck.findings(from: facts).first { $0.check == "lockdown" }?.ok, false)
        XCTAssertNil(HealthCheck.findings(from: HealthFacts()).first { $0.check == "lockdown" })
    }
}
