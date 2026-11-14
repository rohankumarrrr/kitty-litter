@testable import Shades
import ShadesCore
import XCTest

/// Lockdown at its edges, each found by trying to break it: what shows on a shared screen, and what goes where.
@MainActor
final class LockdownEdgeTests: XCTestCase {
    private var stage: FakeStage!
    private var backend: FakeBackend!
    private var clock = Date(timeIntervalSince1970: 100_000)
    private var kittens: [Kitten] = []
    private var savedSettings: Settings?
    private var controller: AppController!
    private let builder = Kitten(name: "Builder", role: "Coding", covers: "the app being built", folder: "/k/builder", usesInbox: true)
    private let money = Kitten(name: "Money", role: "Bills", covers: "bills and subscriptions", folder: "/k/money", usesInbox: true)
    private let rules = Kitten(name: "Rules", role: "The system", covers: "the rules", folder: "/k/rules", seesScreen: false)
    private let screen = ScreenSnapshot(appName: "Editor", windowTitle: "invoice.swift", selectedText: "let total = 0")

    override func setUp() async throws {
        stage = FakeStage(log: Log())
        backend = FakeBackend()
        backend.projects = ["/k/builder": "project-builder", "/k/money": "project-money", "/k/rules": "project-rules", "/shades/router": "project-router"]
        kittens = [builder, money]
        controller = makeController()
    }

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
                routerFolder: { "/shades/router" }
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

    private func thread(_ id: String, title: String, of kitten: Kitten, status: AgentStatus = .running) -> AgentThread {
        AgentThread(id: id, title: title, projectTitle: kitten.name, status: status, model: "m", updatedAt: clock, runtimeMode: .auto, projectPath: kitten.folder, lastRunID: "run-1", lastRunEndedAt: clock)
    }

    // 1. Another kitten's inbox row shows in the bubble during Lockdown.
    func testInboxBubbleDuringLockdownNamesOnlyItsKitten() async {
        controller.lockdownPicked(builder)
        let rent = thread("m", title: "Rent is overdue", of: money)
        let page = thread("b", title: "Invoice page", of: builder)
        controller.threadsChanged([rent, page])
        backend.reports = ["m": "Rent is overdue. Pay it?", "b": "Built the invoice page."]
        // The sorting model reads Money's as a decision and Builder's as shipped.
        backend.replyTo = { prompt in
            if prompt.text.contains("Rent is overdue. Pay it?") { return [.finished(fullText: "DECISION: Pay the rent?")] }
            if prompt.text.contains("Built the invoice page.") { return [.finished(fullText: "SHIPPED: The invoice page.")] }
            return nil
        }
        var moneyDone = rent
        moneyDone.status = .completed
        moneyDone.lastRunID = "run-2"
        controller.threadsChanged([moneyDone, page])
        await settle()
        var builderDone = page
        builderDone.status = .completed
        builderDone.lastRunID = "run-2"
        controller.threadsChanged([moneyDone, builderDone])
        await settle()
        let shown = stage.bubbles.compactMap { bubble -> String? in
            if case .inbox(let words)? = bubble { return words }
            return nil
        }
        XCTAssertFalse(shown.contains { $0.contains("Money") || $0.contains("Rent") }, "another kitten's inbox row reached the bubble: \(shown)")
    }

    // 2. Its own approval doesn't come up once another kitten's has been held.
    func testItsOwnApprovalComesUpAfterAnotherKittensWasHeld() async {
        controller.lockdownPicked(builder)
        let theirs = ApprovalRequest(id: "a-m", threadID: "m", threadTitle: "Bills", kind: .command, summary: "pay", createdAt: clock)
        let ours = ApprovalRequest(id: "a-b", threadID: "b", threadTitle: "Page", kind: .command, summary: "npm test", createdAt: clock.addingTimeInterval(1))
        var other = thread("m", title: "Bills", of: money, status: .waitingForApproval)
        other.pendingApprovals = [theirs]
        let ownIdle = thread("b", title: "Page", of: builder)
        controller.threadsChanged([other, ownIdle])
        await settle()
        var own = thread("b", title: "Page", of: builder, status: .waitingForApproval)
        own.pendingApprovals = [ours]
        controller.threadsChanged([other, own])
        await settle()
        if case .approval(let request, _, _)? = stage.bubble {
            XCTAssertEqual(request.id, "a-b")
        } else {
            XCTFail("its own approval didn't come up by itself; bubble is \(String(describing: stage.bubble))")
        }
    }

    // 2b. The same, with no other kitten's approval waiting: it does come up.
    func testControlItsOwnApprovalAloneComesUp() async {
        controller.lockdownPicked(builder)
        let ours = ApprovalRequest(id: "a-b", threadID: "b", threadTitle: "Page", kind: .command, summary: "npm test", createdAt: clock.addingTimeInterval(1))
        var own = thread("b", title: "Page", of: builder, status: .waitingForApproval)
        own.pendingApprovals = [ours]
        controller.threadsChanged([own])
        await settle()
        if case .approval(let request, _, _)? = stage.bubble { XCTAssertEqual(request.id, "a-b") } else { XCTFail("control: \(String(describing: stage.bubble))") }
    }

    // 2c. Its own approval's counter counts another kitten's held one.
    func testItsOwnApprovalsCounterLeavesOutHeldOnes() async {
        controller.lockdownPicked(builder)
        let theirs = ApprovalRequest(id: "a-m", threadID: "m", threadTitle: "Bills", kind: .command, summary: "pay", createdAt: clock)
        let ours = ApprovalRequest(id: "a-b", threadID: "b", threadTitle: "Page", kind: .command, summary: "npm test", createdAt: clock.addingTimeInterval(1))
        var other = thread("m", title: "Bills", of: money, status: .waitingForApproval)
        other.pendingApprovals = [theirs]
        var own = thread("b", title: "Page", of: builder, status: .waitingForApproval)
        own.pendingApprovals = [ours]
        controller.threadsChanged([other, own])
        await settle()
        guard case .approval(let request, let position, let total)? = stage.bubble else { return XCTFail("\(String(describing: stage.bubble))") }
        XCTAssertEqual(request.id, "a-b")
        XCTAssertEqual("\(position) of \(total)", "1 of 1", "the bubble says there's another approval after this one")
        controller.bubbleAction(.approval(request, .accept))
        await settle()
    }

    // 3. Clicking the cat while only another kitten's approval waits opens nothing.
    func testClickingTheCatOpensTheAskBoxWhenOnlyAnotherKittensApprovalWaits() async {
        controller.lockdownPicked(builder)
        let theirs = ApprovalRequest(id: "a-m", threadID: "m", threadTitle: "Bills", kind: .command, summary: "pay", createdAt: clock)
        var other = thread("m", title: "Bills", of: money, status: .waitingForApproval)
        other.pendingApprovals = [theirs]
        controller.threadsChanged([other])
        await settle()
        controller.catClicked()
        await settle()
        XCTAssertNotNil(stage.input, "the click did nothing: no Ask box and no bubble")
    }

    // 4. Esc on the thinking bubble takes the ask back, but Lockdown sends it anyway.
    func testEscOnTheThinkingBubbleTakesTheAskBack() async {
        controller.ask("Never mind this", snapshot: screen)
        controller.bubbleDismissed(byClick: false)
        await settle()
        let withoutLockdown = backend.sent.count
        controller.lockdownPicked(builder)
        controller.ask("Never mind this", snapshot: screen)
        controller.bubbleDismissed(byClick: false)
        await settle()
        XCTAssertEqual(withoutLockdown, 0)
        XCTAssertEqual(backend.sent.count, 0, "an ask taken back with Esc still went to the kitten")
    }

    // 6. Full access turned off while the first ask's thread starts: the next ask sends the screen to that full-access thread.
    func testFullAccessThreadGetsNoScreenThroughTheStartedFallback() async {
        var full = controller.settings
        full.frontierMode = .fullAccess
        controller.settingsEdited(full)
        controller.lockdownPicked(builder)
        var release: CheckedContinuation<Void, Never>?
        let gate = Task { await withCheckedContinuation { release = $0 } }
        backend.heldBeforeStarted = gate
        controller.ask("Start the page", snapshot: screen)
        for _ in 0..<20 { await Task.yield() }
        await controller.replyTask?.value
        await controller.flow?.value
        // You turn full access off in Settings while T3 is still starting it.
        var auto = controller.settings
        auto.frontierMode = .auto
        controller.settingsEdited(auto)
        backend.heldBeforeStarted = nil
        release?.resume()
        await settle()
        controller.ask("Now the total", snapshot: screen)
        await settle()
        let second = backend.sent.last
        XCTAssertEqual(backend.sent.first?.prompt.runtimeMode, .fullAccess)
        XCTAssertEqual(second?.threadID, "thread-1")
        XCTAssertFalse(second?.prompt.text.contains("let total = 0") == true, "screen text reached a thread started with full access")
    }

    // 7. Restart with Lockdown on, ask before T3's list is in: the pinned thread is replaced.
    func testAnAskRightAfterARestartCarriesOnInThePinnedThread() async throws {
        controller.lockdownPicked(builder)
        controller.ask("Start the page", snapshot: nil)
        await settle()
        let pinned = controller.settings.lockdown?.thread
        controller = makeController(settings: try XCTUnwrap(savedSettings))
        // The app's own default (AppController.swift: `var threadListWait: TimeInterval = 2`), with T3's list not in yet.
        controller.threadListWait = 2
        let started = Date()
        controller.ask("Carry on", snapshot: nil)
        await settle()
        XCTAssertEqual(backend.sent.last?.mode, .forward)
        XCTAssertEqual(controller.settings.lockdown?.thread, pinned)
    }
}
