@testable import Shades
import ShadesContext
import ShadesCore
import TestSupport
import XCTest

@MainActor
final class ClaudeFallbackTests: XCTestCase {
    private var log: Log!
    private var stage: FakeStage!
    private var backend: FakeBackend!
    private var clock = Date(timeIntervalSince1970: 1_795_723_200)
    private var savedLimits: [ClaudeUsageLimit] = []
    private var controller: AppController!

    override func setUp() async throws {
        log = Log()
        stage = FakeStage(log: log)
        backend = FakeBackend()
        var settings = Settings()
        settings.quickModel = .quick
        settings.frontierModel = .frontier
        settings.quickMode = .approvalRequired
        settings.frontierMode = .autoAcceptEdits
        controller = AppController(
            dependencies: AppDependencies(
                backend: backend,
                context: FakeContext(log: log),
                voice: FakeVoice(),
                inserter: FakeInserter(),
                keys: FakeKeys(),
                settings: settings,
                saveSettings: { _ in },
                kittens: { [] },
                systemFacts: { HealthFacts() },
                fileExists: { _ in true },
                screenBlockGaps: { _ in [] },
                routerFolder: { "/shades/router" },
                kittensCheckSummary: { nil },
                saveClaudeLimit: { [unowned self] in self.savedLimits.append($0) }
            ),
            stage: stage,
            now: { [unowned self] in self.clock }
        )
        controller.start()
    }

    private var started: [AgentPrompt] {
        backend.sent.filter { $0.mode == .start }.map(\.prompt)
    }

    func testGeminiFriendlyName() {
        XCTAssertEqual(ModelNames.friendly(.fallback), "Gemini 4 Neon")
        XCTAssertEqual(ModelNames.friendly(model: "gemini-4-neon"), "Gemini 4 Neon")
    }

    func testThreadListLimitActivatesOptionCFallbackAndRevertsAtReset() async throws {
        let resetAt = clock.addingTimeInterval(3600)
        controller.threadsChanged([
            AgentThread(
                id: "failed-claude",
                title: "Blocked",
                projectTitle: "Shades",
                status: .failed,
                model: "claude-opus-5-5",
                updatedAt: clock,
                provider: "claudeAgent",
                usageLimitResetAt: resetAt,
                lastError: "Claude API rate limit reached.",
                lastErrorClass: "usage_limit"
            )
        ])
        await until { self.controller.claudeLimit.resetAt == resetAt }
        XCTAssertEqual(savedLimits.last?.resetAt, resetAt)

        backend.replies = [
            [.finished(fullText: "HANDOFF: Fix the build")],
            [.finished(fullText: "Done.")]
        ]
        controller.askPressed()
        await until { self.stage.isInputVisible }
        stage.submitInput("Fix the build")
        await until { self.started.count == 2 }

        XCTAssertEqual(started[0].model, .fallback)
        XCTAssertEqual(started[0].projectID, backend.projects["/shades/router"])
        XCTAssertEqual(started[1].model, .fallback)
        XCTAssertEqual(controller.frontierName, "Gemini 4 Neon")

        let findings = await controller.runHealthCheck()
        let report = HealthCheck.report(findings, pid: 1, version: "1", at: clock)
        XCTAssertTrue(report.ok)
        XCTAssertEqual(findings.first { $0.check == "front door" }?.ok, true)
        let advice = try XCTUnwrap(findings.first { $0.check == HealthCheck.claudeFallback })
        XCTAssertTrue(advice.advice)
        XCTAssertTrue(advice.problem?.contains("Gemini 4 Neon") == true)

        clock = resetAt.addingTimeInterval(1)
        backend.replies = [
            [.finished(fullText: "HANDOFF: Check again")],
            [.finished(fullText: "All good.")]
        ]
        controller.askPressed()
        await until { self.stage.isInputVisible }
        stage.submitInput("Check again")
        await until { self.started.count == 4 }

        XCTAssertEqual(started[2].model, .quick)
        XCTAssertEqual(started[3].model, .frontier)
        XCTAssertEqual(controller.frontierName, "Opus")
        XCTAssertNil(controller.claudeLimit.resetAt)

        let afterFindings = await controller.runHealthCheck()
        XCTAssertNil(afterFindings.first { $0.check == HealthCheck.claudeFallback })
    }

    func testQuickTurnUsageLimitRetriesImmediatelyOnNeon() async {
        let resetAt = clock.addingTimeInterval(7200)
        controller.threadsChanged([])
        await until { self.controller.threadListArrived }

        backend.replies = [
            [
                .text(delta: "You've hit your weekly limit · resets Dec 1 at 9pm (America/New_York)"),
                .usageLimited(message: "Claude API rate limit reached.", resetAt: resetAt)
            ],
            [.finished(fullText: "Here is your answer.")]
        ]
        controller.askPressed()
        await until { self.stage.isInputVisible }
        stage.submitInput("What is 2 + 2?")
        await until {
            if case .reply(let text, true, _, _, _) = self.stage.bubble { return text == "Here is your answer." }
            return false
        }

        XCTAssertEqual(started.map(\.model), [.quick, .fallback])
        XCTAssertEqual(controller.claudeLimit.resetAt, resetAt)
        await until { self.backend.archived.contains("thread-1") }
    }

    func testFrontierUsageLimitRetriesImmediatelyOnNeon() async {
        let resetAt = clock.addingTimeInterval(7200)
        controller.threadsChanged([])
        await until { self.controller.threadListArrived }

        backend.replies = [
            [.usageLimited(message: "Claude API rate limit reached.", resetAt: resetAt)],
            [.finished(fullText: "Finished on Neon.")]
        ]
        controller.startFrontier(title: "Ship it", text: "Ship it", snapshot: nil)
        await until { self.started.count == 2 }

        XCTAssertEqual(started.map(\.model), [.frontier, .fallback])
        XCTAssertEqual(controller.claudeLimit.resetAt, resetAt)
        await until { self.backend.archived.contains("thread-1") }
    }
}
