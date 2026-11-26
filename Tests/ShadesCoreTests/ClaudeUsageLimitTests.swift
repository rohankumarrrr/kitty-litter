import Foundation
import ShadesCore
import XCTest

final class ClaudeUsageLimitTests: XCTestCase {
    private func utc(_ iso: String) throws -> Date {
        try Date(iso, strategy: Date.ISO8601FormatStyle())
    }

    func testFallbackDefaultIsGemini4NeonOnHigh() throws {
        XCTAssertEqual(ModelChoice.fallback, ModelChoice(provider: "antigravity", model: "gemini-4-neon", effort: "high"))
        let saved = Data(#"{"quickModel":{"provider":"claudeAgent","model":"claude-opus-5-5","effort":"xhigh"}}"#.utf8)
        let decoded = try JSONDecoder().decode(Settings.self, from: saved)
        XCTAssertEqual(decoded.fallbackModel, .fallback)
    }

    func testParsesWeeklyLimitResetWithMonthDayAndTimeZone() throws {
        let now = try utc("2026-11-26T20:00:00Z")
        let parsed = ClaudeUsageLimit.parseReset(
            in: "You've hit your weekly limit · resets Dec 1 at 9pm (America/New_York)",
            relativeTo: now
        )
        XCTAssertEqual(parsed, try utc("2026-12-02T02:00:00Z"))
    }

    func testParsesTimeOnlyResetSameDayAndNextDay() throws {
        let afternoon = try utc("2026-11-26T20:00:00Z")
        let sameDay = ClaudeUsageLimit.parseReset(
            in: "You've hit your Fable limit · resets 9pm (America/New_York)",
            relativeTo: afternoon
        )
        XCTAssertEqual(sameDay, try utc("2026-11-27T02:00:00Z"))

        let lateNight = try utc("2026-11-27T03:00:00Z")
        let nextDay = ClaudeUsageLimit.parseReset(
            in: "You've hit your limit · resets 9pm (America/New_York)",
            relativeTo: lateNight
        )
        XCTAssertEqual(nextDay, try utc("2026-11-28T02:00:00Z"))
    }

    func testParsesYearRolloverMinutesAndISO() throws {
        let lateDecember = try utc("2026-12-28T12:00:00Z")
        XCTAssertEqual(
            ClaudeUsageLimit.parseReset(in: "resets Jan 2 at 9:30am (UTC)", relativeTo: lateDecember),
            try utc("2027-01-02T09:30:00Z")
        )
        XCTAssertEqual(
            ClaudeUsageLimit.parseReset(in: "resets 21:15 (UTC)", relativeTo: lateDecember),
            try utc("2026-12-28T21:15:00Z")
        )
        XCTAssertEqual(
            ClaudeUsageLimit.parseReset(in: "resets 2026-12-02T02:00:00.000Z", relativeTo: lateDecember),
            try utc("2026-12-02T02:00:00Z")
        )
    }

    func testEffectiveModelSwitchesOnlyClaudeModelsAndRevertsAtReset() throws {
        let before = try utc("2026-11-26T20:00:00Z")
        let reset = try utc("2026-12-02T02:00:00Z")
        var limit = ClaudeUsageLimit()
        XCTAssertTrue(limit.noteLimit(resetAt: reset, now: before))

        XCTAssertEqual(limit.effectiveModel(for: .quick, fallback: .fallback, at: before), .fallback)
        XCTAssertEqual(limit.effectiveModel(for: .frontier, fallback: .fallback, at: before), .fallback)
        XCTAssertEqual(limit.effectiveModel(for: .summary, fallback: .fallback, at: before), .summary)

        XCTAssertEqual(limit.effectiveModel(for: .quick, fallback: .fallback, at: reset), .quick)
        XCTAssertEqual(limit.effectiveModel(for: .frontier, fallback: .fallback, at: reset), .frontier)
        XCTAssertTrue(limit.clearIfReset(at: reset))
        XCTAssertNil(limit.resetAt)
    }

    func testNoteThreadsDetectsActiveClaudeLimitsAndIgnoresExpiredOnes() throws {
        let failedAt = try utc("2026-11-26T20:00:00Z")
        let resetAt = try utc("2026-12-02T02:00:00Z")
        let afterReset = try utc("2026-12-02T02:05:00Z")

        let structured = AgentThread(
            id: "t1",
            title: "Daily check",
            projectTitle: "William",
            status: .failed,
            model: "claude-opus-5-5",
            updatedAt: failedAt,
            provider: "claudeAgent",
            usageLimitResetAt: resetAt,
            lastError: "Claude API rate limit reached.",
            lastErrorClass: "usage_limit"
        )
        let textOnly = AgentThread(
            id: "t2",
            title: "Weekly",
            projectTitle: "Clawde",
            status: .failed,
            model: "claude-opus-5-5",
            updatedAt: failedAt,
            provider: "claudeAgent",
            lastError: "You've hit your weekly limit · resets Dec 1 at 9pm (America/New_York)"
        )
        let codex = AgentThread(
            id: "t3",
            title: "Other",
            projectTitle: "Other",
            status: .failed,
            model: "gpt-6.1-sol",
            updatedAt: failedAt,
            provider: "codex",
            usageLimitResetAt: resetAt
        )

        var fromStructured = ClaudeUsageLimit()
        XCTAssertTrue(fromStructured.noteThreads([codex, structured], now: failedAt))
        XCTAssertEqual(fromStructured.resetAt, resetAt)

        var fromText = ClaudeUsageLimit()
        XCTAssertTrue(fromText.noteThreads([textOnly], now: failedAt))
        XCTAssertEqual(fromText.resetAt, resetAt)

        var after = ClaudeUsageLimit()
        XCTAssertFalse(after.noteThreads([structured, textOnly], now: afterReset))
        XCTAssertNil(after.resetAt)
    }

    func testPersistsAndRemovesWhenCleared() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("claude-limit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("claude-fallback.json")
        let reset = try utc("2026-12-02T02:00:00Z")

        let active = ClaudeUsageLimit(resetAt: reset)
        try active.save(to: file)
        XCTAssertEqual(ClaudeUsageLimit.load(from: file), active)

        try ClaudeUsageLimit(resetAt: nil).save(to: file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(ClaudeUsageLimit.load(from: file), ClaudeUsageLimit())
    }
}
