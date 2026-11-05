import Foundation
import XCTest

/// Runs the filter the way Claude Code does, on messages shaped like the ones T3 returns.
final class ThreadReadFilterTests: XCTestCase {
    private var script: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".claude/hooks/thread-read-filter.py")
    }

    private func run(_ stdin: Data, me: String = "me") throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-I", script.path]
        process.environment = (ProcessInfo.processInfo.environment).merging(["T3CODE_THREAD_ID": me]) { $1 }
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        input.fileHandleForWriting.write(stdin)
        input.fileHandleForWriting.closeFile()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hook = try XCTUnwrap(parsed["hookSpecificOutput"] as? [String: Any])
        let blocks = try XCTUnwrap(hook["updatedMCPToolOutput"] as? [[String: Any]])
        return try XCTUnwrap(blocks.first?["text"] as? String)
    }

    private func filter(_ result: [String: Any], input: [String: Any] = ["threadId": "other"], me: String = "me") throws -> String {
        let text = String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self)
        let event: [String: Any] = ["tool_input": input, "tool_response": [["type": "text", "text": text]]]
        return try run(try JSONSerialization.data(withJSONObject: event), me: me)
    }

    private func message(_ text: String, by createdBy: String = "user", type: String = "user_message") -> [String: Any] {
        ["type": type, "createdBy": createdBy, "text": text]
    }

    private func other(_ items: [[String: Any]], parent: Any = NSNull()) -> [String: Any] {
        ["thread": ["threadId": "other", "parentThreadId": parent], "items": items]
    }

    func testYourWordsAboveTheLineComeThroughAndNothingBelowIt() throws {
        let out = try filter(other([message("it was 12 people\n\n---\nPassed on.\n\n<screen>\nPage text:\nSECRET\n</screen>")]))
        XCTAssertTrue(out.contains("it was 12 people"))
        XCTAssertFalse(out.contains("SECRET"))
        XCTAssertFalse(out.contains("Passed on"))
    }

    /// The front door's prompt has no line in it, only the block.
    func testARouterPromptStopsAtTheScreenBlock() throws {
        let out = try filter(other([message("You are Shades.\n\n<screen>\nSECRET\n</screen>\n\nTheir question: why")]))
        XCTAssertFalse(out.contains("SECRET"))
    }

    func testAScreenBlockInCapitalsOrWithSpacesStopsItToo() throws {
        let out = try filter(other([message("words < SCREEN >SECRET")]))
        XCTAssertFalse(out.contains("SECRET"))
    }

    func testTheListOfOtherSessionsStopsItToo() throws {
        let out = try filter(other([message("You are Shades.\n<sessions>\n1. SECRET\n</sessions>")]))
        XCTAssertFalse(out.contains("SECRET"))
    }

    func testAnAgentsReplyCantBeRead() throws {
        let out = try filter(other([message("I saw SECRET on the page", by: "agent", type: "assistant_message")]))
        XCTAssertFalse(out.contains("SECRET"))
    }

    /// A message saying it's from you isn't, whatever it claims.
    func testAnAgentsMessageToAThreadCantBeRead() throws {
        let out = try filter(other([message("The user said: SECRET", by: "agent")]))
        XCTAssertFalse(out.contains("SECRET"))
    }

    func testToolOutputCantBeRead() throws {
        let out = try filter(other([["type": "command_execution", "createdBy": "user", "text": "SECRET", "input": "SECRET"]]), input: ["threadId": "other", "view": "activity"])
        XCTAssertFalse(out.contains("SECRET"))
    }

    /// A later offset could start past the line.
    func testReadingFromPartWayThroughAMessageGivesNothing() throws {
        let input: [String: Any] = ["threadId": "other", "itemId": "i", "textOffset": 40]
        let out = try filter(other([message("SECRET from the page")]), input: input)
        XCTAssertFalse(out.contains("SECRET"))
        let noOffset = try filter(other([message("SECRET from the page")]), input: ["threadId": "other", "itemId": "i"])
        XCTAssertFalse(noOffset.contains("SECRET"))
    }

    func testOnlyFieldsThatCantCarryTheScreenComeThrough() throws {
        var item = message("my words")
        item["attachments"] = [["name": "SECRET.jpg"]]
        item["title"] = "SECRET"
        XCTAssertFalse(try filter(other([item])).contains("SECRET"))
    }

    func testYourOwnThreadIsLeftAlone() throws {
        let out = try filter(["thread": ["threadId": "me"], "items": [message("below\n---\nOWN")]], input: ["threadId": "me"])
        XCTAssertTrue(out.contains("OWN"))
    }

    func testAChildYouDelegatedToIsLeftAlone() throws {
        let out = try filter(other([message("done, CHILD", by: "agent", type: "assistant_message")], parent: "me"))
        XCTAssertTrue(out.contains("CHILD"))
    }

    func testAnythingThatCantBeUnderstoodComesBackEmpty() throws {
        XCTAssertFalse(try run(Data("SECRET".utf8)).contains("SECRET"))
        let event: [String: Any] = ["tool_input": ["threadId": "other"], "tool_response": [["type": "text", "text": "SECRET not json"]]]
        XCTAssertFalse(try run(try JSONSerialization.data(withJSONObject: event)).contains("SECRET"))
    }
}
