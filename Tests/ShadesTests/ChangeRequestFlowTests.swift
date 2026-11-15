import Foundation
@testable import Shades
import ShadesCore
import XCTest

/// A kitten asks for a settings change it can't make, Shades looks into it, and only your Allow makes it, through the
/// app's own controller with a fake T3 that records everything sent.
@MainActor
final class ChangeRequestFlowTests: XCTestCase {
    private var home: URL!
    private var backend: FakeBackend!
    private var stage: FakeStage!
    private var controller: AppController!
    private var kittens: [Kitten] = []
    private var notified: [NeedsYouAlert] = []
    private var withdrawn: [String] = []
    private var savedInbox: Inbox?
    private let clock = Date(timeIntervalSince1970: 100_000)

    private var clawde: Kitten { Kitten(name: "Clawde", role: "The system", covers: "", folder: home.appendingPathComponent("kittens/clawde").path, seesScreen: false, usesInbox: true) }
    private var steve: Kitten { Kitten(name: "Steve", role: "Professional", covers: "", folder: home.appendingPathComponent("kittens/steve").path) }
    private var settingsFile: String { "\(clawde.folder)/.claude/settings.json" }
    private let original = "{\n  \"permissions\": {\n    \"allow\": [\n      \"Bash(swift test)\",\n    ]\n  }\n}\n"
    private let review = "I'd allow it. It only takes out a stray comma."

    override func setUp() async throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("change-flow-\(UUID().uuidString)", isDirectory: true)
        for kitten in [clawde, steve] {
            try FileManager.default.createDirectory(atPath: "\(kitten.folder)/.claude", withIntermediateDirectories: true)
        }
        try Data(original.utf8).write(to: URL(fileURLWithPath: settingsFile))
        try Data("{}".utf8).write(to: URL(fileURLWithPath: "\(steve.folder)/.claude/settings.json"))
        kittens = [clawde, steve]
        backend = FakeBackend()
        backend.replyTo = { [review] prompt in
            if prompt.text.contains("asked for a change to a settings file") { return [.finished(fullText: review)] }
            if prompt.text.hasPrefix("Below is the final report") { return [.finished(fullText: "NOTE: Fixed the rest.")] }
            return nil
        }
        stage = FakeStage(log: Log())
        var settings = Settings()
        settings.quickModel = ModelChoice(provider: "claudeAgent", model: "claude-haiku-5-5", effort: "medium")
        controller = AppController(
            dependencies: AppDependencies(
                backend: backend,
                context: FakeContext(log: Log()),
                voice: FakeVoice(),
                inserter: FakeInserter(),
                keys: FakeKeys(),
                settings: settings,
                saveSettings: { _ in },
                kittens: { [unowned self] in self.kittens },
                home: home.path,
                routerFolder: { "/shades/router" },
                inbox: Inbox(since: .distantPast),
                saveInbox: { [unowned self] in self.savedInbox = $0 },
                notify: { [unowned self] in self.notified.append($0) },
                withdrawNotifications: { [unowned self] in self.withdrawn += $0 }
            ),
            stage: stage,
            now: { [unowned self] in self.clock }
        )
        controller.threadListWait = 0
        controller.reportDelay = 0
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func reply(asking json: [String: String]) -> String {
        let block = String(decoding: try! JSONSerialization.data(withJSONObject: json, options: .sortedKeys), as: UTF8.self)
        return "Fixed the rest.\n\n```shades-request\n\(block)\n```"
    }

    private var commaFix: [String: String] {
        ["file": settingsFile, "replace": "\"Bash(swift test)\",\n", "with": "\"Bash(swift test)\"\n", "why": "The comma stops the install."]
    }

    private func thread(_ id: String, of kitten: Kitten, status: AgentStatus = .completed) -> AgentThread {
        AgentThread(id: id, title: "\(kitten.name): Fix the install", projectTitle: nil, status: status, model: "m", updatedAt: clock, projectPath: kitten.folder, lastRunID: "run-\(id)", lastRunEndedAt: clock)
    }

    /// An inbox kitten's run is filed by itself, with its requests saved alongside.
    private func finishClawde(_ report: String) async throws -> InboxEntry {
        backend.reports["w"] = report
        controller.threadsChanged([thread("w", of: clawde)])
        for _ in 0..<50 where !controller.filing.isEmpty {
            await controller.reportTask?.value
            await Task.yield()
        }
        return try XCTUnwrap(controller.inbox.entries.first { $0.change != nil })
    }

    private func settle() async {
        await controller.forwardTask?.value
        for _ in 0..<20 { await Task.yield() }
    }

    private var contents: String { (try? String(contentsOfFile: settingsFile, encoding: .utf8)) ?? "" }

    func testAllowMakesExactlyTheChangeTheCardShowedAndTheKittenHearsItWasntYourWords() async throws {
        let entry = try await finishClawde(reply(asking: commaFix))
        let change = try XCTUnwrap(entry.change)
        XCTAssertNil(change.problem)
        XCTAssertEqual(change.widens, ["Adds `Bash(swift test)` to `permissions.allow`."], "Claude Code can't read the file with its comma, so fixing it brings that back")
        XCTAssertEqual(change.review, review)
        XCTAssertTrue(entry.needsYou)
        XCTAssertEqual(savedInbox?.entries.first { $0.id == entry.id }, entry, "saved with the run, so a restart keeps it")
        XCTAssertTrue(notified.contains { $0.id == entry.id && $0.kind == .decision }, "it comes as a notification")
        XCTAssertTrue(CatWords.changeCard(change, by: "Clawde").contains("```\n- \"Bash(swift test)\",\n+ \"Bash(swift test)\"\n```"))

        let looked = try XCTUnwrap(backend.sent.first { $0.prompt.title?.hasPrefix(AppController.reviewTitle) == true })
        XCTAssertEqual(looked.prompt.projectID, "project-router", "it runs where no tool that acts, sends or reads a file works")
        XCTAssertEqual(looked.prompt.runtimeMode, .approvalRequired)
        XCTAssertFalse(looked.prompt.text.contains("<screen>"))
        let sorter = try XCTUnwrap(backend.sent.first { $0.prompt.text.hasPrefix("Below is the final report") })
        XCTAssertTrue(sorter.prompt.text.contains(Prompts.changeCardLine))
        XCTAssertFalse(sorter.prompt.text.contains(ChangeRequests.fence), "the sorter only hears there's a card")

        controller.inboxAction(.allow(id: entry.id))
        await settle()
        XCTAssertEqual(contents, original.replacingOccurrences(of: "\"Bash(swift test)\",\n", with: "\"Bash(swift test)\"\n"))
        XCTAssertFalse(controller.inbox.entries.contains { $0.id == entry.id })
        XCTAssertTrue(withdrawn.contains(entry.id))
        let told = try XCTUnwrap(backend.sent.last)
        XCTAssertEqual(told.mode, .forward)
        XCTAssertEqual(told.threadID, "w")
        XCTAssertEqual(told.behavior, .queue)
        XCTAssertTrue(told.prompt.text.contains("pressed Allow"))
        XCTAssertNil(Prompts.ownWords(in: told.prompt.text), "nothing The Kitty Litter sends can pass for your words")
    }

    func testDenyChangesNothingAndTellsTheKittenNo() async throws {
        let entry = try await finishClawde(reply(asking: commaFix))
        controller.inboxAction(.deny(id: entry.id))
        await settle()
        XCTAssertEqual(contents, original)
        XCTAssertFalse(controller.inbox.entries.contains { $0.id == entry.id })
        let told = try XCTUnwrap(backend.sent.last)
        XCTAssertEqual(told.threadID, "w")
        XCTAssertTrue(told.prompt.text.contains("pressed Deny"))
        XCTAssertNil(Prompts.ownWords(in: told.prompt.text))
    }

    /// The card showed the change against the file as it was, so a file that's changed since is left alone.
    func testAFileThatChangedSinceIsLeftAloneAndBothYouAndTheKittenHearWhy() async throws {
        let entry = try await finishClawde(reply(asking: commaFix))
        let meanwhile = original.replacingOccurrences(of: "allow", with: "deny")
        try Data(meanwhile.utf8).write(to: URL(fileURLWithPath: settingsFile))
        controller.inboxAction(.allow(id: entry.id))
        await settle()
        XCTAssertEqual(contents, meanwhile)
        XCTAssertTrue(backend.sent.last?.prompt.text.contains("couldn't make it") == true)
        XCTAssertTrue(stage.bubbles.contains { if case .line(let text, _)? = $0 { text.hasPrefix("I couldn't make that change.") } else { false } })
    }

    func testARequestThatCantBeDoneOnlyTakesDenyWhichSaysWhy() async throws {
        let entry = try await finishClawde(reply(asking: ["file": "~/.claude/settings.json", "create": "{}"]))
        let change = try XCTUnwrap(entry.change)
        XCTAssertNotNil(change.problem)
        XCTAssertNil(change.review, "nothing to look into")
        XCTAssertFalse(backend.sent.contains { $0.prompt.title?.hasPrefix(AppController.reviewTitle) == true })
        controller.inboxAction(.allow(id: entry.id))
        await settle()
        XCTAssertTrue(controller.inbox.entries.contains { $0.id == entry.id }, "Allow does nothing")
        controller.inboxAction(.deny(id: entry.id))
        await settle()
        XCTAssertTrue(backend.sent.last?.prompt.text.contains("isn't one of the settings files") == true)
    }

    /// A kitten without an inbox has its run said in the bubble, and what it asks for still waits in Activity.
    func testAKittenWithoutAnInboxStillGetsItsCardAndTheBubbleSkipsTheBlock() async throws {
        let steveFile = "\(steve.folder)/.claude/settings.json"
        var work = thread("s", of: steve, status: .running)
        controller.threadsChanged([work])
        backend.reports["s"] = reply(asking: ["file": steveFile, "replace": "{}", "with": "{\"permissions\": {\"allow\": [\"Bash(rm:*)\"]}}"])
        work.status = .completed
        controller.threadsChanged([work])
        await controller.reportTask?.value
        for _ in 0..<100 where !controller.inbox.entries.contains(where: { $0.change != nil }) { await Task.yield() }
        let change = try XCTUnwrap(controller.inbox.entries.first { $0.change != nil }?.change)
        XCTAssertEqual(change.widens, ["Adds `Bash(rm:*)` to `permissions.allow`."])
        XCTAssertTrue(CatWords.changeCard(change, by: "Steve").hasPrefix("**This widens what agents can do.**"), "said first")
        XCTAssertFalse(stage.bubbles.contains { "\($0)".contains(ChangeRequests.fence) })
    }

    /// T3 can leave out run IDs, and two cards from one thread still each make only their own change.
    func testAllowMakesThePressedCardsChangeEvenWithoutRunIDs() async throws {
        let steveFile = "\(steve.folder)/.claude/settings.json"
        let asks = ["{\"permissions\": {\"allow\": [\"Bash(rm:*)\"]}}", "{\"permissions\": {\"deny\": [\"WebFetch\"]}}"]
        for (index, with) in asks.enumerated() {
            var work = AgentThread(id: "s", title: "Steve: Work", projectTitle: nil, status: .running, model: "m", updatedAt: clock, projectPath: steve.folder)
            controller.threadsChanged([work])
            backend.reports["s"] = reply(asking: ["file": steveFile, "replace": "{}", "with": with])
            work.status = .completed
            controller.threadsChanged([work])
            await controller.reportTask?.value
            for _ in 0..<200 where controller.inbox.entries.filter({ $0.change != nil }).count <= index { await Task.yield() }
        }
        let cards = controller.inbox.entries.filter { $0.change != nil }
        XCTAssertEqual(cards.map(\.change?.with), asks)
        XCTAssertEqual(Set(cards.map(\.id)).count, 2, "each card is its own")
        controller.inboxAction(.allow(id: cards[1].id))
        await settle()
        XCTAssertEqual(try String(contentsOfFile: steveFile, encoding: .utf8), asks[1])
        XCTAssertEqual(controller.inbox.entries.filter { $0.change != nil }.map(\.id), [cards[0].id])
    }

    /// Two kittens can ask for the same change. It's one card, and both hear what you decided.
    func testEveryThreadThatAskedForTheSameChangeHearsWhatYouDecided() async throws {
        var asking = thread("s", of: steve, status: .running)
        controller.threadsChanged([asking])
        backend.reports["s"] = reply(asking: commaFix)
        asking.status = .completed
        controller.threadsChanged([asking])
        await controller.reportTask?.value
        for _ in 0..<200 where !controller.inbox.entries.contains(where: { $0.change != nil }) { await Task.yield() }
        backend.reports["w"] = reply(asking: commaFix)
        controller.threadsChanged([asking, thread("w", of: clawde)])
        for _ in 0..<50 where !controller.filing.isEmpty {
            await controller.reportTask?.value
            await Task.yield()
        }
        let cards = controller.inbox.entries.filter { $0.change != nil }
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?.change?.alsoAskedIn, ["w"])
        controller.inboxAction(.deny(id: try XCTUnwrap(cards.first).id))
        await settle()
        XCTAssertEqual(backend.sent.filter { $0.mode == .forward }.map(\.threadID), ["s", "w"])
        XCTAssertTrue(backend.sent.filter { $0.mode == .forward }.allSatisfy { Prompts.ownWords(in: $0.prompt.text) == nil })
    }

    /// It runs in the router's folder, where every other thread is a talk with the cat, and the app could stop before it ends.
    func testALeftoverLookAtAChangeIsTidiedAwayAndIsntATalk() async {
        let leftover = AgentThread(id: "r", title: "\(AppController.reviewTitle) ~/kittens/clawde/.claude/settings.json", projectTitle: "Shades router", status: .completed, model: "m", updatedAt: clock, projectPath: "/shades/router")
        let talk = AgentThread(id: "t", title: "What's on my calendar?", projectTitle: "Shades router", status: .completed, model: "m", updatedAt: clock, projectPath: "/shades/router")
        XCTAssertFalse(controller.isWithShades(leftover))
        XCTAssertTrue(controller.isWithShades(talk))
        controller.threadsChanged([leftover, talk])
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(controller.hiddenThreads.contains("r"))
        XCTAssertEqual(backend.archived, ["r"])
    }

    func testAnUnlistedThreadsRequestIsntACard() async throws {
        kittens = []
        backend.reports["w"] = reply(asking: commaFix)
        var work = thread("w", of: clawde, status: .running)
        controller.threadsChanged([work])
        work.status = .completed
        controller.threadsChanged([work])
        await controller.reportTask?.value
        for _ in 0..<20 { await Task.yield() }
        XCTAssertFalse(controller.inbox.entries.contains { $0.change != nil }, "only a kitten's reply can ask")
    }
}
