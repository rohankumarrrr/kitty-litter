import Foundation
import XCTest
@testable import ShadesCore

/// Ways a request tried to change more than its card said, from the review of this feature. Temporary folders only.
final class ChangeRequestAttackTests: XCTestCase {
    private var home: URL!
    private var files: SettingsFiles { SettingsFiles(home: home.path, kittenFolders: [kitten.path]) }
    private var kitten: URL { home.appendingPathComponent("kittens/clawde") }
    private var kittenSettings: URL { kitten.appendingPathComponent(".claude/settings.json") }
    private var worktree: URL { home.appendingPathComponent(".t3/worktrees/app/t3-1234") }

    private let deny = """
          "Read(~/.t3/userdata/**)",
          "Read(~/.t3/scratch/**)",
          "Read(~/.claude/projects/**/*.jsonl)",
          "Read(~/.codex/**)",
          "Read(~/Library/Application Support/shades/captures/**)",
          "Edit(~/.t3/userdata/**)",
          "Edit(.claude/**)",
          "mcp__t3-code__t3_thread_search",
          "mcp__t3-code__t3_thread_transfer",
          "mcp__t3-code__t3_queue"
    """
    private let rest = """
      "sandbox": {"enabled": true, "failIfUnavailable": true, "allowUnsandboxedCommands": false, "autoAllowBashIfSandboxed": false},
      "hooks": {"PostToolUse": [{"matcher": "mcp__t3-code__t3_thread_read", "hooks": [{"type": "command", "command": "python3 -I thread-read-filter.py"}]}]}
    """
    private var block: String { "{\n  \"permissions\": {\n    \"deny\": [\n\(deny)\n    ]\n  },\n\(rest)\n}\n" }

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("attack-\(UUID().uuidString)", isDirectory: true)
        for folder in [kitten.appendingPathComponent(".claude"), worktree.appendingPathComponent(".claude")] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try Data(block.utf8).write(to: kittenSettings)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func asked(_ object: [String: String]) throws -> ChangeRequest {
        let json = String(decoding: try JSONSerialization.data(withJSONObject: object, options: .sortedKeys), as: UTF8.self)
        return try XCTUnwrap(XCTUnwrap(ChangeRequests.all(in: "```shades-request\n\(json)\n```").first).get().change)
    }

    /// A deny moved under a dotted top-level key reads as the same facts, so its removal goes unreported.
    func testMovingADenyUnderADottedKeyIsReportedAsWidening() throws {
        let withExtra = block.replacingOccurrences(of: "\"mcp__t3-code__t3_queue\"\n", with: "\"mcp__t3-code__t3_queue\",\n      \"Bash(rm:*)\"\n")
        try Data(withExtra.utf8).write(to: kittenSettings)
        let checked = files.check(try asked([
            "file": kittenSettings.path,
            "replace": "\"mcp__t3-code__t3_queue\",\n      \"Bash(rm:*)\"\n    ]\n  },",
            "with": "\"mcp__t3-code__t3_queue\"\n    ]\n  },\n  \"permissions.deny\": [\"Bash(rm:*)\"],",
        ]))
        XCTAssertNil(checked.problem)
        try files.apply(checked)
        let written = try JSONSerialization.jsonObject(with: Data(contentsOf: kittenSettings)) as! [String: Any]
        let realDeny = (written["permissions"] as! [String: Any])["deny"] as! [String]
        XCTAssertFalse(realDeny.contains("Bash(rm:*)"), "Bash(rm:*) really is out of permissions.deny now")
        XCTAssertTrue(checked.isLoosening, "taking Bash(rm:*) out of permissions.deny widens what agents can do")
    }

    /// A guard hook moved under a dotted key the same way.
    func testMovingAHookUnderADottedKeyIsReportedAsWidening() throws {
        let guardHook = "\"PreToolUse\": [{\"matcher\": \"Bash\", \"hooks\": [{\"type\": \"command\", \"command\": \"guard.sh\"}]}], "
        let withHook = block.replacingOccurrences(of: "\"hooks\": {\"PostToolUse\"", with: "\"hooks\": {\(guardHook)\"PostToolUse\"")
        try Data(withHook.utf8).write(to: kittenSettings)
        let checked = files.check(try asked([
            "file": kittenSettings.path,
            "replace": "\"hooks\": {\(guardHook)",
            "with": "\"hooks.PreToolUse\": [{\"matcher\": \"Bash\", \"hooks\": [{\"type\": \"command\", \"command\": \"guard.sh\"}]}],\n  \"hooks\": {",
        ]))
        XCTAssertNil(checked.problem)
        XCTAssertTrue(checked.isLoosening, "the PreToolUse guard hook is gone from what Claude Code reads")
    }

    /// Claude Code can't read a settings.local.json with a trailing comma, so the block in settings.json holds. Fixing the
    /// comma makes its `sandbox.enabled: false` take over, and the card should say the block opens.
    func testFixingAnUnreadableLocalFileThatTurnsOffTheSandboxOpensTheBlock() throws {
        try Data(block.utf8).write(to: worktree.appendingPathComponent(".claude/settings.json"))
        let local = worktree.appendingPathComponent(".claude/settings.local.json")
        try Data("{\"sandbox\": {\"enabled\": false},}\n".utf8).write(to: local)
        XCTAssertThrowsError(try StrictJSON.validate(Data(contentsOf: local)), "Claude Code can't read it as it is")
        let checked = files.check(try asked(["file": local.path, "replace": "},}", "with": "}}"]))
        XCTAssertNil(checked.problem)
        XCTAssertEqual(checked.opensScreenBlock, ["sandbox.enabled"])
    }

    /// The other file is unreadable to Claude Code, yet counted, so it masks the change to settings.json.
    func testAnUnreadableLocalFileDoesntMaskTurningOffTheSandbox() throws {
        try Data("{\"sandbox\": {\"enabled\": true},}\n".utf8).write(to: kitten.appendingPathComponent(".claude/settings.local.json"))
        let checked = files.check(try asked(["file": kittenSettings.path, "replace": "{\"enabled\": true,", "with": "{\"enabled\": false,"]))
        XCTAssertNil(checked.problem)
        XCTAssertEqual(checked.opensScreenBlock, ["sandbox.enabled"])
    }

    /// Foundation keeps the first of a repeated key and Claude Code the last, so the file before is read wrongly.
    func testARepeatedKeyBeforeIsReadAsClaudeCodeReadsIt() throws {
        let trueLine = "  \"sandbox\": {\"enabled\": true, \"failIfUnavailable\": true, \"allowUnsandboxedCommands\": false, \"autoAllowBashIfSandboxed\": false},\n"
        let falseLine = trueLine.replacingOccurrences(of: "\"enabled\": true", with: "\"enabled\": false")
        let twice = block.replacingOccurrences(of: trueLine, with: falseLine + trueLine)
        try Data(twice.utf8).write(to: kittenSettings)
        XCTAssertEqual(ScreenBlock.gaps(in: Data(twice.utf8)), ["sandbox.enabled"], "Foundation reads the first")
        let checked = files.check(try asked(["file": kittenSettings.path, "replace": trueLine, "with": ""]))
        XCTAssertNil(checked.problem)
        XCTAssertEqual(checked.opensScreenBlock, ["sandbox.enabled"], "Claude Code read enabled: true before, and false after")
    }

    /// A hook in a list and the same hook written as a string are one fact.
    func testAHookTurnedIntoAStringIsReportedAsWidening() throws {
        let hook: [String: Any] = ["matcher": "Bash", "hooks": [["type": "command", "command": "guard.sh"]]]
        let object = String(decoding: try JSONSerialization.data(withJSONObject: hook, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
        let string = String(decoding: try JSONSerialization.data(withJSONObject: [object], options: [.withoutEscapingSlashes]), as: UTF8.self)
        let withHook = block.replacingOccurrences(of: "\"hooks\": {\"PostToolUse\"", with: "\"hooks\": {\"PreToolUse\": [\(object)], \"PostToolUse\"")
        try Data(withHook.utf8).write(to: kittenSettings)
        let checked = files.check(try asked(["file": kittenSettings.path, "replace": "\"PreToolUse\": [\(object)]", "with": "\"PreToolUse\": \(string)"]))
        XCTAssertNil(checked.problem)
        XCTAssertTrue(checked.isLoosening, "PreToolUse now holds a string, not a hook")
    }

    /// A `.claude` swapped for a link after the check but before the write sends the write through the link.
    func testALinkSwappedInDuringAllowIsNeverFollowed() throws {
        let mine = home.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: mine, withIntermediateDirectories: true)
        let own = "{\"mine\": true}\n"
        try Data(own.utf8).write(to: mine.appendingPathComponent("settings.json"))

        let padding = String(repeating: "x", count: 60_000)
        let real = "{\"n\": 0, \"pad\": \"\(padding)\"}\n"
        let claude = kitten.appendingPathComponent(".claude")
        let parked = kitten.appendingPathComponent(".claude-real")
        try Data(real.utf8).write(to: kittenSettings)

        let stop = ManagedAtomicFlag()
        let swapper = Thread {
            while !stop.isSet {
                guard rename(claude.path, parked.path) == 0 else { continue }
                symlink(mine.path, claude.path)
                usleep(300)
                unlink(claude.path)
                rename(parked.path, claude.path)
                usleep(UInt32.random(in: 50...600))
            }
        }
        swapper.start()
        defer {
            stop.set()
            Thread.sleep(forTimeInterval: 0.05)
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: claude.path)) != nil { unlink(claude.path) }
            if FileManager.default.fileExists(atPath: parked.path) { rename(parked.path, claude.path) }
        }

        var checkedOK = 0, hit = false
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, !hit {
            let checked = files.check(try asked(["file": kittenSettings.path, "replace": "{\"n\": 0,", "with": "{\"n\": 0,"]))
            guard checked.problem == nil else { continue }
            checkedOK += 1
            try? files.apply(checked)
            if let now = try? String(contentsOf: mine.appendingPathComponent("settings.json"), encoding: .utf8), now != own { hit = true }
        }
        XCTAssertGreaterThan(checkedOK, 0, "some tries got as far as Allow")
        XCTAssertFalse(hit, "the write went through a link to the folder standing in for ~/.claude")
    }
}

private final class ManagedAtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
}

