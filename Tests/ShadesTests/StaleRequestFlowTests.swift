import Foundation
@testable import Shades
import ShadesCore
import TestSupport
import XCTest

@MainActor
final class StaleRequestFlowTests: XCTestCase {
    private var home: URL!
    private var backend: FakeBackend!
    private var stage: FakeStage!
    private var controller: AppController!
    private var kittens: [Kitten] = []
    private var savedInbox: Inbox?
    private let clock = Date(timeIntervalSince1970: 100_000)

    private var clawde: Kitten { Kitten(name: "Clawde", role: "The system", covers: "", folder: home.appendingPathComponent("kittens/clawde").path, seesScreen: false, usesInbox: true) }
    private var steve: Kitten { Kitten(name: "Steve", role: "Professional", covers: "", folder: home.appendingPathComponent("kittens/steve").path) }
    private var clawdeFile: String { "\(clawde.folder)/.claude/settings.json" }
    private var steveFile: String { "\(steve.folder)/.claude/settings.json" }
    private let listed = "{\n  \"permissions\": {\n    \"allow\": [\n      \"Bash(swift build)\",\n      \"Bash(curl *)\",\n      \"Bash(swift test)\"\n    ]\n  }\n}\n"

    override func setUp() async throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("stale-flow-\(UUID().uuidString)", isDirectory: true)
        for kitten in [clawde, steve] {
            try FileManager.default.createDirectory(atPath: "\(kitten.folder)/.claude", withIntermediateDirectories: true)
        }
        try Data(listed.utf8).write(to: URL(fileURLWithPath: clawdeFile))
        try Data("{\"a\": {}}".utf8).write(to: URL(fileURLWithPath: steveFile))
        kittens = [clawde, steve]
        backend = FakeBackend()
        backend.replyTo = { prompt in
            if prompt.text.contains("asked for a change to a settings file") { return [.finished(fullText: "I'd allow it.")] }
            if prompt.text.hasPrefix("Below is the final report") { return [.finished(fullText: "NOTE: Done.")] }
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
                notify: { _ in },
                withdrawNotifications: { _ in }
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

    private func block(_ json: [String: String]) -> String {
        "```shades-request\n" + String(decoding: try! JSONSerialization.data(withJSONObject: json, options: .sortedKeys), as: UTF8.self) + "\n```"
    }

    private func thread(_ id: String, of kitten: Kitten, run: String, status: AgentStatus) -> AgentThread {
        AgentThread(id: id, title: "\(kitten.name): Tidy permissions", projectTitle: nil, status: status, model: "m", updatedAt: clock, projectPath: kitten.folder, lastRunID: run, lastRunEndedAt: clock)
    }

    private var clawdeContents: String { (try? String(contentsOfFile: clawdeFile, encoding: .utf8)) ?? "" }

    func testAllowingOneCardLeavesAnotherCardsRemovalAskingWhileTheRuleIsStillThere() async throws {
        let addLs = ["file": clawdeFile, "replace": "      \"Bash(swift build)\",\n", "with": "      \"Bash(swift build)\",\n      \"Bash(ls)\",\n", "why": "It lists folders."]
        let dropCurl = ["file": clawdeFile, "replace": "      \"Bash(swift build)\",\n      \"Bash(curl *)\",\n", "with": "      \"Bash(swift build)\",\n", "why": "Curl can reach anywhere."]
        backend.reports["w"] = "Two changes.\n\n\(block(addLs))\n\n\(block(dropCurl))"
        controller.threadsChanged([thread("w", of: clawde, run: "run-1", status: .completed)])
        await until { controller.filing.isEmpty }
        let cards = controller.inbox.entries.filter { $0.change != nil }
        XCTAssertEqual(cards.count, 2)
        let add = try XCTUnwrap(cards.first { $0.change?.with.contains("Bash(ls)") == true })
        let drop = try XCTUnwrap(cards.first { $0.change?.why == "Curl can reach anywhere." })
        XCTAssertNil(drop.change?.problem)

        controller.inboxAction(.allow(id: add.id))
        await controller.forwardTask?.value

        XCTAssertTrue(clawdeContents.contains("\"Bash(curl *)\""), "curl is still allowed")
        let told = backend.sentApartFromLooks.filter { $0.mode == .forward }.map(\.prompt.text)
        let left = try XCTUnwrap(controller.inbox.entries.first { $0.id == drop.id }, "the card asking to take curl out doesn't go by itself, since curl is still in the file")
        XCTAssertNotNil(left.change?.problem, "and it can't be allowed against a file it wasn't shown")
        XCTAssertEqual(told.count, 1, "only the allowed card's kitten hears anything")
    }

    func testAWithdrawThatArrivesWhileTheEarlierRequestIsBeingLookedIntoStillTakesItBack() async throws {
        backend.holdTurn = "A kitten, one of the user's AI agents, asked for a change"
        let ask = ["file": steveFile, "replace": "\"a\": {}", "with": "\"a\": {\"allow\": [\"Bash(ls)\"]}", "why": "It lists folders."]

        controller.threadsChanged([thread("s", of: steve, run: "run-1", status: .running)])
        backend.reports["s"] = "Needs one setting.\n\n\(block(ask))"
        controller.threadsChanged([thread("s", of: steve, run: "run-1", status: .completed)])
        await until { backend.sent.contains(where: { $0.prompt.title?.hasPrefix(AppController.reviewTitle) == true }) }
        XCTAssertTrue(backend.sent.contains { $0.prompt.title?.hasPrefix(AppController.reviewTitle) == true }, "the first request is being looked into")

        controller.threadsChanged([thread("s", of: steve, run: "run-2", status: .running)])
        backend.reports["s"] = "Found another way.\n\n\(block(["withdraw": steveFile]))"
        controller.threadsChanged([thread("s", of: steve, run: "run-2", status: .completed)])
        await until { backend.sent.filter { $0.prompt.text.hasPrefix("Below is the final report") }.count == 2 }
        XCTAssertTrue(controller.inbox.entries.filter { $0.change != nil }.isEmpty, "no card yet")

        backend.releaseHeld()
        await controller.changeFiling["s"]?.value
        XCTAssertTrue(controller.inbox.entries.filter { $0.change != nil }.isEmpty, "Steve took the request back in its next run, so no card should be waiting")
    }

    func testAWithdrawFromAKittenWithoutAnInboxTakesItsFiledCardAway() async throws {
        let ask = ["file": steveFile, "replace": "\"a\": {}", "with": "\"a\": {\"allow\": [\"Bash(ls)\"]}", "why": "It lists folders."]
        controller.threadsChanged([thread("s", of: steve, run: "run-1", status: .running)])
        backend.reports["s"] = "Needs one setting.\n\n\(block(ask))"
        controller.threadsChanged([thread("s", of: steve, run: "run-1", status: .completed)])
        await until { !controller.inbox.entries.filter({ $0.change != nil }).isEmpty }
        XCTAssertEqual(controller.inbox.entries.filter { $0.change != nil }.count, 1)

        controller.threadsChanged([thread("s", of: steve, run: "run-2", status: .running)])
        backend.reports["s"] = "Found another way.\n\n\(block(["withdraw": steveFile]))"
        controller.threadsChanged([thread("s", of: steve, run: "run-2", status: .completed)])
        await until { controller.inbox.entries.filter({ $0.change != nil }).isEmpty }
        XCTAssertTrue(controller.inbox.entries.filter { $0.change != nil }.isEmpty)
    }

    private func decisionReplies() {
        backend.replyTo = { prompt in
            if prompt.text.hasPrefix("Below is the final report") { return [.finished(fullText: "DECISION: Merge pull request #3? Its tests pass.")] }
            if prompt.text.contains("finished some work and needs something from the user") {
                return [.finished(fullText: "ASK: Merge pull request #3.\nRECOMMEND: I'd allow it.")]
            }
            return nil
        }
    }

    private let withdrawAndDecide = "Pull request #3 is ready. Should I merge it?\n\n```shades-request\n{\"withdraw\": \"Send the invite.\"}\n```"

    func testAWithdrawOnlyReportStillHasItsDecisionReadInTheInbox() async throws {
        decisionReplies()
        backend.reports["w"] = withdrawAndDecide
        controller.threadsChanged([thread("w", of: clawde, run: "run-1", status: .completed)])
        await until { controller.filing.isEmpty }
        await until { controller.inbox.entries.contains(where: { $0.ask != nil }) }
        XCTAssertTrue(controller.inbox.entries.contains { $0.ask?.ask == "Merge pull request #3." })
    }

    func testAWithdrawOnlyReportStillHasItsDecisionReadForAKittenWithoutAnInbox() async throws {
        decisionReplies()
        controller.threadsChanged([thread("s", of: steve, run: "run-1", status: .running)])
        backend.reports["s"] = withdrawAndDecide
        controller.threadsChanged([thread("s", of: steve, run: "run-1", status: .completed)])
        await until { controller.inbox.entries.contains(where: { $0.kind == .decision }) }
        await controller.reportTask?.value
        await until { controller.inbox.entries.contains(where: { $0.ask != nil }) }
        XCTAssertTrue(controller.inbox.entries.contains { $0.ask?.ask == "Merge pull request #3." }, "a withdraw makes no card, so the decision should still be read, as it is in the inbox")
    }

    func testACardKeepsItsAllowWhenItsKittenIsMissingFromOneThreadList() async throws {
        let addLs = ["file": clawdeFile, "replace": "      \"Bash(swift build)\",\n", "with": "      \"Bash(swift build)\",\n      \"Bash(ls)\",\n", "why": "It lists folders."]
        backend.reports["w"] = "One change.\n\n\(block(addLs))"
        controller.threadsChanged([thread("w", of: clawde, run: "run-1", status: .completed)])
        await until { controller.filing.isEmpty }
        let card = try XCTUnwrap(controller.inbox.entries.first { $0.change != nil })
        XCTAssertNil(card.change?.problem)

        kittens = [steve]
        controller.threadsChanged([thread("w", of: clawde, run: "run-1", status: .completed)])
        kittens = [clawde, steve]
        controller.threadsChanged([thread("w", of: clawde, run: "run-1", status: .completed)])

        XCTAssertEqual(clawdeContents, listed, "the file never changed")
        let after = try XCTUnwrap(controller.inbox.entries.first { $0.id == card.id })
        XCTAssertNil(after.change?.problem, "it still offers Allow")
        controller.inboxAction(.allow(id: card.id))
        await controller.forwardTask?.value
        XCTAssertTrue(clawdeContents.contains("\"Bash(ls)\""), "the file is byte for byte what the card was shown against, so Allow should still make it")
    }
}
