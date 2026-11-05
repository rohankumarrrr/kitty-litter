import Foundation
import XCTest
@testable import ShadesCore

/// Repros for the review. Real prompts through the real hook, and real settings through the real check.
final class ReproBlockTests: XCTestCase {
    private var repo: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func hook(_ text: String) throws -> String {
        let result: [String: Any] = ["thread": ["threadId": "other", "parentThreadId": NSNull()], "items": [["type": "user_message", "createdBy": "user", "text": text]]]
        let inner = String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self)
        let event: [String: Any] = ["tool_input": ["threadId": "other"], "tool_response": [["type": "text", "text": inner]]]
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-I", repo.appendingPathComponent(".claude/hooks/thread-read-filter.py").path]
        process.environment = ProcessInfo.processInfo.environment.merging(["T3CODE_THREAD_ID": "me"]) { $1 }
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        input.fileHandleForWriting.write(try JSONSerialization.data(withJSONObject: event))
        input.fileHandleForWriting.closeFile()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hook = try XCTUnwrap(parsed["hookSpecificOutput"] as? [String: Any])
        let blocks = try XCTUnwrap(hook["updatedMCPToolOutput"] as? [[String: Any]])
        let body = try XCTUnwrap(blocks.first?["text"] as? String)
        let filtered = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        let items = try XCTUnwrap(filtered["items"] as? [[String: Any]])
        return items.first?["text"] as? String ?? "(no item)"
    }

    private let snapshot = ScreenSnapshot(appName: "Generic App", windowTitle: "GENERIC-WINDOW", pageText: "GENERIC-PAGE")

    func testShowWhatEachRealPromptLeavesBehind() throws {
        let cases: [(String, String)] = [
            ("forwarded", Prompts.forwarded(words: "MY-WORDS", snapshot: snapshot, screenshotPath: "/x.jpg", screenLeftOut: false)),
            ("forKitten", Prompts.forKitten(words: "MY-WORDS", snapshot: snapshot, screenshotPath: "/x.jpg", screenLeftOut: false)),
            ("quick", Prompts.quick(question: "MY-WORDS", snapshot: snapshot)),
            ("frontier", Prompts.frontier(request: "ROUTER-READING\n\nTheir own words: MY-WORDS", snapshot: snapshot, screenshotPath: "/x.jpg")),
            ("fix", Prompts.fix(description: "MY-WORDS", snapshot: snapshot, screenshotPath: "/x.jpg")),
            ("summary", Prompts.summary(of: "Generic report. The page said GENERIC-PAGE.", title: "GENERIC-TITLE", failed: false)),
        ]
        for (name, prompt) in cases {
            let kept = try hook(prompt)
            print("REPRO \(name): keptMyWords=\(kept.contains("MY-WORDS")) keptPage=\(kept.contains("GENERIC-PAGE")) keptChars=\(kept.count) of \(prompt.count)")
        }
    }

    func testAReportQuotingThePageStaysOutOfASummaryThreadsWords() throws {
        let kept = try hook(Prompts.summary(of: "Generic report. The page said GENERIC-PAGE.", title: "Generic", failed: false))
        print("REPRO summary kept: \(kept)")
        XCTAssertFalse(kept.contains("GENERIC-PAGE"))
    }

    func testACorrectionMentioningTheTagKeepsAllItsWords() throws {
        let words = "the <screen> block is wrong, do not ship this"
        let kept = try hook(Prompts.forwarded(words: words, snapshot: nil, screenshotPath: nil, screenLeftOut: false))
        print("REPRO tag kept: \(kept)")
        XCTAssertEqual(kept, words)
    }

    func testACorrectionWithALineOfDashesKeepsAllItsWords() throws {
        let words = "first part\n---\nsecond part: do not ship this"
        let kept = try hook(Prompts.forwarded(words: words, snapshot: nil, screenshotPath: nil, screenLeftOut: false))
        print("REPRO dashes kept: \(kept)")
        XCTAssertEqual(kept, words)
    }

    func testARoutersPromptKeepsTheQuestion() throws {
        let kept = try hook(Prompts.quick(question: "MY-WORDS", snapshot: snapshot))
        XCTAssertTrue(kept.contains("MY-WORDS"))
    }

    func testAHandoffKeepsTheirWords() throws {
        let kept = try hook(Prompts.frontier(request: "ROUTER\n\nTheir own words: MY-WORDS", snapshot: snapshot, screenshotPath: nil))
        XCTAssertTrue(kept.contains("MY-WORDS"))
    }

    // MARK: Settings that pass the check

    private func repoSettings(changing change: (inout [String: Any]) -> Void) throws -> Data {
        var parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: repo.appendingPathComponent(".claude/settings.json"))) as? [String: Any])
        change(&parsed)
        return try JSONSerialization.data(withJSONObject: parsed)
    }

    func testEveryWayOfDisarmingTheBlockIsAGap() throws {
        let cases: [(String, (inout [String: Any]) -> Void)] = [
            ("disableAllHooks", { $0["disableAllHooks"] = true }),
            ("excludedCommands *", { settings in
                var sandbox = settings["sandbox"] as! [String: Any]
                sandbox["excludedCommands"] = ["*"]
                settings["sandbox"] = sandbox
            }),
            ("filesystem.allowRead", { settings in
                var sandbox = settings["sandbox"] as! [String: Any]
                sandbox["filesystem"] = ["allowRead": ["~/.t3/userdata", "~/.t3/scratch", "~/Library/Application Support/shades/captures"]]
                settings["sandbox"] = sandbox
            }),
            ("network allowAllUnixSockets and any domain", { settings in
                var sandbox = settings["sandbox"] as! [String: Any]
                sandbox["network"] = ["allowAllUnixSockets": true, "allowLocalBinding": true, "allowedDomains": ["*"]]
                settings["sandbox"] = sandbox
            }),
            ("a hook that only names the filter", { settings in
                settings["hooks"] = ["PostToolUse": [["matcher": "mcp__t3-code__t3_thread_read", "hooks": [["type": "command", "command": "true # thread-read-filter"]]]]]
            }),
        ]
        var passed: [String] = []
        for (name, change) in cases {
            let gaps = ScreenBlock.gaps(in: try repoSettings(changing: change))
            print("REPRO gaps with \(name): \(gaps)")
            if gaps.isEmpty { passed.append(name) }
        }
        XCTAssertEqual(passed, [])
    }
}
