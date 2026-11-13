@testable import Shades
import ShadesCore
import XCTest

/// Each channel's notifications: muted, or everything, only what needs you, or nothing, on the Mac and on the phone,
/// all asked by the one gate Do Not Disturb uses.
@MainActor
final class ChannelNotificationsTests: XCTestCase {
    private var stage: FakeStage!
    private var backend: FakeBackend!
    private var clock = Date(timeIntervalSince1970: 100_000)
    private var kittens: [Kitten] = []
    private var savedSettings: Settings?
    private var notified: [NeedsYouAlert] = []
    private var controller: AppController!
    private let clawde = Kitten(name: "Clawde", role: "The system", covers: "the app", folder: "/k/clawde", seesScreen: false, usesInbox: true)
    private let steve = Kitten(name: "Steve", role: "Careers", covers: "jobs", folder: "/k/steve")
    private let pepper = Kitten(name: "Pepper", role: "Finance", covers: "money", folder: "/k/pepper")

    override func setUp() async throws {
        stage = FakeStage(log: Log())
        backend = FakeBackend()
        var settings = Settings()
        settings.quickMode = .approvalRequired
        settings.notifyFinished = true
        controller = AppController(
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
                inbox: Inbox(since: .distantPast),
                saveInbox: { _ in },
                notify: { [unowned self] in self.notified.append($0) }
            ),
            stage: stage,
            now: { [unowned self] in self.clock }
        )
        controller.threadListWait = 0
        controller.reportDelay = 0
    }

    private func set(_ kitten: Kitten, _ notifications: ChannelNotifications) {
        controller.messagesAction(.notifications(.of(kitten), notifications))
    }

    private func work(_ id: String, of kitten: Kitten, status: AgentStatus = .completed) -> AgentThread {
        AgentThread(id: id, title: "\(kitten.name): Work", projectTitle: nil, status: status, model: "m", updatedAt: clock, projectPath: kitten.folder, lastRunID: "run-\(id)", lastRunEndedAt: clock)
    }

    private func asking(_ id: String, of kitten: Kitten) -> AgentThread {
        var thread = work("w-\(id)", of: kitten, status: .waitingForApproval)
        thread.pendingApprovals = [ApprovalRequest(id: id, threadID: thread.id, threadTitle: thread.title, kind: .command, summary: "npm test", createdAt: clock)]
        return thread
    }

    private func finish(_ thread: AgentThread, report: String, sorted: String? = nil) async {
        backend.reports[thread.id] = report
        if let sorted { backend.replies.append([.finished(fullText: sorted)]) }
        var running = thread
        running.status = .running
        controller.threadsChanged([running])
        controller.threadsChanged([thread])
        for _ in 0..<50 {
            await controller.reportTask?.value
            await controller.replyTask?.value
            await Task.yield()
        }
    }

    func testAMutedChannelPopsUpNothingAndKeepsNothingForLater() async {
        kittens = [steve]
        set(steve, ChannelNotifications(muted: true))
        XCTAssertEqual(savedSettings?.channelNotifications, ["kitten:/k/steve": ChannelNotifications(muted: true)])

        await finish(work("s", of: steve), report: "Your resume is ready.", sorted: "DECISION: Send it?")
        XCTAssertNil(stage.bubble)
        XCTAssertTrue(notified.isEmpty)
        XCTAssertEqual(controller.inboxEntries.filter(\.needsYou).map(\.text), ["Send it?"], "what it needs from you still waits in Activity")

        controller.threadsChanged([asking("r1", of: steve)])
        XCTAssertEqual(stage.came, 0)
        XCTAssertNil(stage.bubble)
        XCTAssertTrue(notified.isEmpty)
        XCTAssertEqual(controller.approvals.pending.map(\.id), ["r1"], "it still waits in Messages")
        XCTAssertTrue(controller.away.isEmpty, "muting isn't Do Not Disturb, so there's nothing to catch up on")
    }

    func testOnlyWhenItNeedsYouLetsApprovalsAndDecisionsThroughButNotAFinish() async {
        kittens = [clawde, steve]
        set(steve, ChannelNotifications(mac: .needsYou))
        set(clawde, ChannelNotifications(mac: .needsYou))

        await finish(work("s", of: steve), report: "Your resume is ready.")
        XCTAssertNil(stage.bubble)
        XCTAssertTrue(notified.isEmpty)

        await finish(work("c", of: clawde), report: "Merged.", sorted: "SHIPPED: The fix is live.")
        XCTAssertTrue(notified.isEmpty)
        XCTAssertFalse(controller.inboxNudge)
        XCTAssertEqual(controller.inbox.entries.map(\.text), ["The fix is live."], "it's still filed")

        await finish(work("d", of: clawde), report: "Ready.", sorted: "DECISION: Ship it?")
        XCTAssertEqual(notified.map(\.kind), [.decision])

        controller.threadsChanged([asking("r1", of: steve)])
        XCTAssertEqual(notified.map(\.kind), [.decision, .approval])
        XCTAssertEqual(stage.came, 1, "the cat comes to ask")
    }

    func testAKittenWithoutAnInboxStillSaysWhenItNeedsYouToDoSomething() async {
        kittens = [pepper]
        let report = "Merged the pull request. The sandbox can't write settings, so you need to run `git pull` in your checkout yourself."
        await finish(work("p", of: pepper), report: report, sorted: "SHIPPED: The pull request is merged.\nDECISION: Run git pull in your checkout yourself.")

        XCTAssertTrue(backend.sent.last?.prompt.text.contains("decide or do themselves") == true, "it was sorted, not summed up")
        XCTAssertEqual(controller.inboxEntries.filter(\.needsYou).map(\.text), ["Run git pull in your checkout yourself."])
        XCTAssertEqual(notified.map(\.kind), [.decision], "the decision's notification, and no second one for finishing")
        XCTAssertEqual(notified.map(\.who), ["Pepper"])
        guard case .notice(_, let words, "p", _)? = stage.bubble else { return XCTFail("the bubble still says how it went") }
        XCTAssertEqual(words, "The pull request is merged. Run git pull in your checkout yourself.")

        await finish(work("q", of: pepper), report: "All tidy.", sorted: "NOTE: Nothing else to do.")
        XCTAssertEqual(notified.map(\.kind), [.decision, .finished], "a report that asks nothing only finishes")
        XCTAssertEqual(controller.inboxEntries.map(\.threadID), ["p"], "and nothing else of it is filed")
    }

    func testOtherChannelsAndTheCatsOwnLinesAreUntouched() async {
        kittens = [steve, pepper]
        set(steve, ChannelNotifications(mac: .nothing, phone: .nothing))
        controller.shortcutTaken("⌃⌘B")
        XCTAssertEqual(stage.bubble, .line(CatWords.shortcutTaken("⌃⌘B"), threadID: nil))

        await finish(work("p", of: pepper), report: "The budget's done.")
        XCTAssertEqual(notified.map(\.who), ["Pepper"])
    }

    func testDoNotDisturbOnlyKeepsWhatTheChannelWouldHaveSaid() async {
        kittens = [steve, pepper]
        set(steve, ChannelNotifications(muted: true))
        controller.doNotDisturbPressed()
        await finish(work("s", of: steve), report: "Your resume is ready.")
        await finish(work("p", of: pepper), report: "The budget's done.")
        XCTAssertEqual(controller.away, [.thread("p")])
    }

    func testTheMenuMutesKeepingEachLevelAndPickingALevelUnmutes() throws {
        let menu = NotificationsMenu()
        let current = ChannelNotifications(mac: .needsYou, phone: .nothing)
        let items = menu.items(current, phone: true)
        XCTAssertEqual(items.map { $0.isSeparatorItem ? "---" : "\($0.state == .on ? "* " : "")\($0.title)" }, [
            "Mute",
            "---", "On this Mac", "Everything", "* Only when it needs you", "Nothing",
            "---", "On your phone", "Everything", "Only when it needs you", "* Nothing",
        ])
        let muted = try XCTUnwrap(items[0].representedObject as? ChannelNotifications)
        XCTAssertEqual(muted, ChannelNotifications(mac: .needsYou, phone: .nothing, muted: true))

        let mutedItems = menu.items(muted, phone: true)
        XCTAssertEqual(mutedItems[0].state, .on)
        XCTAssertEqual(mutedItems[0].representedObject as? ChannelNotifications, current, "unmuting brings back what each was")
        XCTAssertEqual(mutedItems[8].representedObject as? ChannelNotifications, ChannelNotifications(mac: .needsYou, phone: .everything))

        XCTAssertEqual(menu.items(current, phone: false).map(\.title), ["Mute", "", "On this Mac", "Everything", "Only when it needs you", "Nothing"], "no phone, no phone to set")
    }

    func testOnlyAChangedChannelIsSaved() {
        var settings = Settings()
        settings.setNotifications(ChannelNotifications(phone: .needsYou), for: "general")
        XCTAssertEqual(settings.notifications(for: "general"), ChannelNotifications(phone: .needsYou))
        settings.setNotifications(ChannelNotifications(), for: "general")
        XCTAssertEqual(settings.channelNotifications, [:])
        XCTAssertEqual(settings.notifications(for: "general"), ChannelNotifications())
    }
}
