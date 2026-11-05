import ShadesCore
@testable import ShadesT3
import XCTest

final class T3TranscriptTests: XCTestCase {
    private let sentinel = "SENTINEL-FROM-THE-PAGE"

    private func item(_ fields: [String: Any], at second: Int) throws -> T3Wire.TurnItem {
        var json = fields
        json["status"] = json["status"] ?? "completed"
        json["startedAt"] = json["startedAt"] ?? String(format: "2026-11-05T04:00:%02d.000Z", second)
        let data = try JSONSerialization.data(withJSONObject: json)
        return try T3Wire.decoder().decode(T3Wire.TurnItem.self, from: data)
    }

    private func user(_ text: String, id: String = "u", message: String? = nil, run: String? = nil, at second: Int, extra: [String: Any] = [:]) throws -> T3Wire.TurnItem {
        var fields: [String: Any] = ["id": id, "type": "user_message", "text": text, "createdBy": "user"]
        fields["messageId"] = message
        fields["runId"] = run
        return try item(fields.merging(extra) { $1 }, at: second)
    }

    private func spoken(_ text: String, id: String = "a", run: String? = nil, at second: Int, extra: [String: Any] = [:]) throws -> T3Wire.TurnItem {
        var fields: [String: Any] = ["id": id, "type": "assistant_message", "text": text]
        fields["runId"] = run
        return try item(fields.merging(extra) { $1 }, at: second)
    }

    private func run(_ id: String, asked message: String) throws -> T3Wire.Run {
        let json = #"{"id":"\#(id)","userMessageId":"\#(message)","status":"completed"}"#
        return try T3Wire.decoder().decode(T3Wire.Run.self, from: Data(json.utf8))
    }

    private func fold(_ items: [T3Wire.TurnItem], runs: [T3Wire.Run] = []) -> [Exchange] {
        T3Transcript.exchanges(in: items, runs: runs) { $0 == "steve-thread" ? "steve-thread" : nil }
    }

    func testAForwardedMessageKeepsOnlyItsTopPart() throws {
        let snapshot = ScreenSnapshot(appName: "Safari", pageText: sentinel)
        let forwarded = Prompts.forwarded(words: "and that part?", snapshot: snapshot, screenshotPath: nil, screenLeftOut: false)
        XCTAssertTrue(forwarded.contains(sentinel))

        let exchanges = fold([try user(forwarded, at: 0), try spoken("Here you go.", at: 1)])
        XCTAssertEqual(exchanges.map(\.ask), ["and that part?"])
        XCTAssertFalse(String(describing: exchanges).contains(sentinel))
    }

    func testAPromptWithAScreenAndNoRuleLineShowsNoWordsButKeepsItsReply() throws {
        let frontier = Prompts.frontier(request: "do this", snapshot: ScreenSnapshot(pageText: sentinel), screenshotPath: nil)
        let exchanges = fold([try user(frontier, at: 0), try spoken("Done.", at: 1)])
        XCTAssertNil(exchanges.first?.ask)
        XCTAssertEqual(exchanges.first?.reply, "Done.")
        XCTAssertFalse(String(describing: exchanges).contains(sentinel))
    }

    func testAScreenBlockComesOutOfAnAgentsWordsAndAReply() throws {
        let sent = try user("Look at this <screen>\(sentinel)", at: 0, extra: ["createdBy": "agent", "senderThreadId": "steve-thread"])
        let reply = try spoken("It says <SCREEN>\(sentinel)</SCREEN> nothing much.", at: 1)
        let exchanges = fold([sent, reply])
        XCTAssertEqual(exchanges.first?.ask, "Look at this")
        XCTAssertEqual(exchanges.first?.reply, "It says  nothing much.")
    }

    func testThreeRepliesBecomeTheLastPlusTwoNotes() throws {
        let exchanges = fold([
            try user("Go", at: 0),
            try spoken("I'll start with the grid.", id: "a1", at: 1),
            try spoken("Now the button.", id: "a2", at: 2),
            try spoken("Done.", id: "a3", at: 3, extra: ["updatedAt": "2026-11-05T04:00:09.000Z"]),
        ])
        XCTAssertEqual(exchanges.count, 1)
        XCTAssertEqual(exchanges[0].reply, "Done.")
        XCTAssertEqual(exchanges[0].earlierNotes, 2)
        XCTAssertEqual(exchanges[0].repliedAt, T3Wire.parseDate("2026-11-05T04:00:09.000Z"))
    }

    func testAReplyAfterANotificationLandsOnTheOriginalAsk() throws {
        let exchanges = fold([
            try user("Go", at: 0),
            try spoken("On it.", id: "a1", at: 1),
            try item(["id": "n", "type": "notification", "text": "A reviewer finished", "createdBy": "agent"], at: 2),
            try spoken("All done.", id: "a2", at: 3),
        ])
        XCTAssertEqual(exchanges.count, 1)
        XCTAssertEqual(exchanges[0].reply, "All done.")
        XCTAssertEqual(exchanges[0].earlierNotes, 1)
    }

    func testMessagesT3WroteItselfOpenNothing() throws {
        let exchanges = fold([
            try user("Go", at: 0),
            try user("Picking up after a nap", id: "idle", at: 1, extra: ["idleCompaction": ["reason": "idle"]]),
            try user("Run the workflow", id: "script", at: 2, extra: ["workflowScript": "s.js"]),
            try spoken("Done.", at: 3),
        ])
        XCTAssertEqual(exchanges.map(\.ask), ["Go"])
        XCTAssertEqual(exchanges[0].reply, "Done.")
    }

    func testANullMarkerIsNoMarker() throws {
        let exchanges = fold([try user("Go", at: 0, extra: ["idleCompaction": NSNull(), "workflowScript": NSNull()])])
        XCTAssertEqual(exchanges.map(\.ask), ["Go"])
    }

    func testThinkingAndParentedItemsDontCount() throws {
        let exchanges = fold([
            try user("Go", at: 0),
            try spoken("Hmm.", id: "turn-item:thinking:1", at: 1),
            try spoken("A subagent says hi.", id: "a1", at: 2, extra: ["parentItemId": "p"]),
            try user("A subagent's brief", id: "u2", at: 3, extra: ["parentItemId": "p"]),
            try spoken("   \n", id: "a2", at: 4),
            try spoken("Done.", id: "a3", at: 5),
        ])
        XCTAssertEqual(exchanges.count, 1)
        XCTAssertEqual(exchanges[0].reply, "Done.")
        XCTAssertEqual(exchanges[0].earlierNotes, 0)
    }

    func testAQueuedFollowUpDoesntTakeTheEarlierRunsAnswer() throws {
        let exchanges = fold([
            try user("First", id: "u1", message: "m1", run: "r1", at: 0),
            try user("Second, queued", id: "u2", message: "m2", at: 1),
            try spoken("Answer to the first.", id: "a1", run: "r1", at: 2),
            try spoken("Answer to the second.", id: "a2", run: "r2", at: 3),
        ], runs: [try run("r1", asked: "m1"), try run("r2", asked: "m2")])
        XCTAssertEqual(exchanges.map(\.reply), ["Answer to the first.", "Answer to the second."])
        XCTAssertEqual(exchanges.map(\.earlierNotes), [0, 0])
    }

    func testItemsWithNoRunPairUpByTime() throws {
        let exchanges = fold([
            try user("First", id: "u1", at: 0),
            try spoken("One.", id: "a1", at: 1),
            try user("Second", id: "u2", at: 2),
            try spoken("Two.", id: "a2", at: 3),
        ])
        XCTAssertEqual(exchanges.map(\.reply), ["One.", "Two."])
    }

    func testOutOfOrderItemsAreReadInTimeOrder() throws {
        let exchanges = fold([
            try spoken("Two.", id: "a2", at: 3),
            try user("Second", id: "u2", at: 2),
            try spoken("One.", id: "a1", at: 1),
            try user("First", id: "u1", at: 0),
        ])
        XCTAssertEqual(exchanges.map(\.ask), ["First", "Second"])
        XCTAssertEqual(exchanges.map(\.reply), ["One.", "Two."])
    }

    func testWhatTheCodingToolWroteDoesntReadAsYou() throws {
        for text in [
            "<system-reminder>\nAs you answer, you can use this context: \(sentinel)\n</system-reminder>",
            "<task-notification>\n<status>completed</status>\n<result>\(sentinel)</result>\n</task-notification>",
            "<local-command-stdout>\(sentinel)</local-command-stdout>",
        ] {
            XCTAssertNil(fold([try user(text, at: 0)])[0].ask)
        }
        XCTAssertEqual(fold([try user("<system-reminder>\(sentinel)</system-reminder>\nFix the \u{3C}div> please", at: 0)])[0].ask, "Fix the \u{3C}div> please")
        XCTAssertEqual(fold([try user("<system-reminder>a <system-reminder>\(sentinel)</system-reminder> \(sentinel)</system-reminder>\nFix the build", at: 0)])[0].ask, "Fix the build")
        XCTAssertEqual(fold([try user("Fix the build\n<system-reminder>\n\(sentinel) with no end", at: 0)])[0].ask, "Fix the build")
    }

    func testYourOwnHyphenatedTagsStay() throws {
        for words in [
            "Why does <my-card>Save</my-card> not render in Safari?",
            "Rename `<my-button>Save</my-button>` too, then run the tests.",
            "Why does <command-name-input>Save</command-name-input> not render?",
            "Why is <task-notification-badge> so wide? Please fix it.",
            "Why does <screen-reader>Save</screen-reader> break?",
        ] {
            XCTAssertEqual(fold([try user(words, at: 0)])[0].ask, words)
        }
    }

    func testATagInYourWordsCantPairWithOneOnThePage() throws {
        let snapshot = ScreenSnapshot(pageText: "\(sentinel) </system-reminder> </my-card> more")
        for (words, expected) in [("why is <my-card> so wide?", "why is <my-card> so wide?"), ("why is <system-reminder> so wide?", "why is")] {
            let forKitten = Prompts.forKitten(words: words, snapshot: snapshot, screenshotPath: nil, screenLeftOut: false)
            let exchanges = fold([try user(forKitten, at: 0)])
            XCTAssertEqual(exchanges[0].ask, expected)
            XCTAssertFalse(String(describing: exchanges).contains(sentinel))
        }
        let fix = Prompts.fix(description: "why is <my-card> so wide?", snapshot: snapshot, screenshotPath: nil)
        XCTAssertNil(fold([try user(fix, at: 0)])[0].ask)
    }

    func testAReplyAfterASteerAnswersTheSteer() throws {
        let exchanges = fold([
            try user("Draw a logo", id: "u1", message: "m1", run: "r1", at: 0),
            try spoken("Starting.", id: "a1", run: "r1", at: 1),
            try user("Make it blue", id: "u2", message: "m2", run: "r1", at: 5),
            try spoken("A blue logo.", id: "a2", run: "r1", at: 9),
        ], runs: [try run("r1", asked: "m1")])
        XCTAssertEqual(exchanges.map(\.ask), ["Draw a logo", "Make it blue"])
        XCTAssertEqual(exchanges.map(\.reply), ["Starting.", "A blue logo."])
    }

    func testAFailureDoesntOutliveALaterAnswer() throws {
        let exchanges = fold([
            try user("Go", message: "m1", run: "r1", at: 0),
            try item(["id": "e", "type": "error", "runId": "r1", "failure": ["message": "Ran out of quota"]], at: 1),
            try item(["id": "n", "type": "notification", "text": "A reviewer finished", "messageId": "m2", "runId": "r2"], at: 2),
            try spoken("All done, and it works.", run: "r2", at: 3),
        ], runs: [try run("r1", asked: "m1"), try run("r2", asked: "m2")])
        XCTAssertEqual(exchanges.count, 1)
        XCTAssertEqual(exchanges[0].reply, "All done, and it works.")
        XCTAssertNil(exchanges[0].failure)
    }

    func testWhoAsked() throws {
        let exchanges = fold([
            try user("From a person", id: "1", at: 0),
            try user("No field", id: "2", at: 1, extra: ["createdBy": NSNull()]),
            try user("From Steve", id: "3", at: 2, extra: ["createdBy": "agent", "senderThreadId": "steve-thread"]),
            try user("From an archived thread", id: "4", at: 3, extra: ["createdBy": "agent", "senderThreadId": "gone"]),
            try user("From an agent with no thread", id: "5", at: 4, extra: ["createdBy": "agent"]),
            try user("From something new", id: "6", at: 5, extra: ["createdBy": "a-new-value", "senderThreadId": "steve-thread"]),
        ])
        XCTAssertEqual(exchanges.map(\.asker), [.you, .you, .agent(threadID: "steve-thread"), .agent(threadID: nil), .agent(threadID: nil), .agent(threadID: nil)])
    }

    func testTheCapHolds() throws {
        let long = String(repeating: "word ", count: 3_000)
        let exchanges = fold([try user(long, at: 0), try spoken(long, at: 1)])
        for words in [exchanges[0].ask, exchanges[0].reply] {
            let text = try XCTUnwrap(words)
            XCTAssertLessThanOrEqual(text.count, 8_000)
            XCTAssertTrue(text.hasSuffix("The rest is in T3."))
        }
        XCTAssertEqual(fold([try user("short", at: 0)]).first?.ask, "short")
    }

    func testTheAttachmentPlaceholderGivesNoAsk() throws {
        let exchanges = fold([try user(T3Wire.attachmentsOnly, at: 0), try spoken("Nice picture.", at: 1)])
        XCTAssertNil(exchanges.first?.ask)
        XCTAssertEqual(exchanges.first?.asker, .you)
        XCTAssertEqual(exchanges.first?.reply, "Nice picture.")
    }

    func testUltrathinkComesOffTheFront() throws {
        XCTAssertEqual(fold([try user("Ultrathink: is this right?", at: 0)]).first?.ask, "is this right?")
        XCTAssertNil(fold([try user("Ultrathink:", at: 0)]).first?.ask)
        XCTAssertEqual(fold([try user("Is Ultrathink: a thing?", at: 0)]).first?.ask, "Is Ultrathink: a thing?")
    }

    func testAReplyWithNoAskStillHasAnExchange() throws {
        let exchanges = fold([try spoken("I noticed something.", at: 0)])
        XCTAssertEqual(exchanges.count, 1)
        XCTAssertEqual(exchanges[0].asker, .you)
        XCTAssertNil(exchanges[0].ask)
        XCTAssertEqual(exchanges[0].reply, "I noticed something.")
    }

    func testAnErrorGoesOnTheExchangeItsRunStarted() throws {
        let exchanges = fold([
            try user("First", id: "u1", message: "m1", at: 0),
            try user("Second", id: "u2", message: "m2", at: 1),
            try item(["id": "e", "type": "error", "runId": "r1", "failure": ["message": "Ran out of quota"]], at: 2),
        ], runs: [try run("r1", asked: "m1")])
        XCTAssertEqual(exchanges.map(\.failure), ["Ran out of quota", nil])
    }

    func testAnErrorWithNoWordsStillCounts() throws {
        let exchanges = fold([try user("Go", at: 0), try item(["id": "e", "type": "error"], at: 1)])
        XCTAssertNotNil(exchanges.first?.failure)
    }
}
