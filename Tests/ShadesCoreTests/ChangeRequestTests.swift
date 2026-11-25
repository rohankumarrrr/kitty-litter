import Foundation
import XCTest
@testable import ShadesCore

final class ChangeRequestTests: XCTestCase {
    private var home: URL!
    private var files: SettingsFiles { SettingsFiles(home: home.path, kittenFolders: [kitten.path]) }
    private var kitten: URL { home.appendingPathComponent("kittens/clawde") }
    private var kittenSettings: URL { kitten.appendingPathComponent(".claude/settings.json") }
    private var worktree: URL { home.appendingPathComponent(".t3/worktrees/app/t3-1234") }

    private let block = """
    {
      "permissions": {
        "deny": [
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
        ],
        "allow": [
          "Bash(swift test)"
        ]
      },
      "sandbox": {"enabled": true, "failIfUnavailable": true, "allowUnsandboxedCommands": false, "autoAllowBashIfSandboxed": false},
      "hooks": {"PostToolUse": [{"matcher": "mcp__t3-code__t3_thread_read", "hooks": [{"type": "command", "command": "python3 -I thread-read-filter.py"}]}]}
    }
    """

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("change-\(UUID().uuidString)", isDirectory: true)
        for folder in [kitten.appendingPathComponent(".claude"), home.appendingPathComponent("shades/.claude"), worktree.appendingPathComponent(".claude")] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try Data(block.utf8).write(to: kittenSettings)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func request(_ json: String, fence: String = "```") -> String {
        "Done with the rest. One thing I can't do:\n\n\(fence)shades-request\n\(json)\n\(fence)\n\nThat's all."
    }

    private func asked(_ json: String) throws -> ChangeRequest {
        try XCTUnwrap(XCTUnwrap(ChangeRequests.all(in: request(json)).first).get().change)
    }

    private func encoded(_ object: [String: String]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: object, options: .sortedKeys), as: UTF8.self)
    }

    func testAReplyAsksForExactlyWhatItsBlockSays() throws {
        let found = ChangeRequests.all(in: request(encoded(["file": "~/shades/.claude/settings.json", "replace": "a,\n]", "with": "a\n]", "why": "The comma\nbreaks the install."])))
        XCTAssertEqual(found.count, 1)
        let request = try XCTUnwrap(XCTUnwrap(found.first).get().change)
        XCTAssertEqual(request.file, "~/shades/.claude/settings.json")
        XCTAssertEqual(request.replace, "a,\n]")
        XCTAssertEqual(request.with, "a\n]")
        XCTAssertEqual(request.why, "The comma breaks the install.", "a reason is one line")
    }

    func testANewFileAndATildeFenceWork() throws {
        let found = ChangeRequests.all(in: request(encoded(["file": "/x/.claude/settings.local.json", "create": "{}"]), fence: "~~~~"))
        let request = try XCTUnwrap(XCTUnwrap(found.first).get().change)
        XCTAssertNil(request.replace)
        XCTAssertEqual(request.with, "{}")
    }

    func testOnlyAClosedBlockOfItsOwnCounts() {
        let quoted = "Here's the form:\n\n````markdown\n```shades-request\n{\"file\": \"x\", \"create\": \"{}\"}\n```\n````\n"
        XCTAssertTrue(ChangeRequests.all(in: quoted).isEmpty)
        XCTAssertTrue(ChangeRequests.all(in: "```shades-request\n{\"file\": \"x\", \"create\": \"{}\"}\n").isEmpty, "never closed")
        XCTAssertTrue(ChangeRequests.all(in: "```json\n{\"file\": \"x\", \"create\": \"{}\"}\n```").isEmpty)
        XCTAssertTrue(ChangeRequests.all(in: "Write a `shades-request` block.").isEmpty)
    }

    func testAnythingItCantDoExactlyIsAProblemNotAGuess() {
        let cases = [
            "not json",
            encoded(["file": "x"]),
            encoded(["file": "x", "replace": "a"]),
            encoded(["file": "x", "replace": "a", "with": "b", "create": "{}"]),
            encoded(["file": "x", "replace": "", "with": "b"]),
            encoded(["file": "x", "create": "{}", "mode": "0777"]),
            encoded(["file": "x", "replace": "\"deny\"", "with": "\"d\u{202E}yne\""]),
            encoded(["file": "x", "create": "{\"a\u{200B}\": 1}"]),
        ]
        for json in cases {
            guard case .failure(let problem)? = ChangeRequests.all(in: request(json)).first else { return XCTFail(json) }
            XCTAssertFalse(problem.reason.isEmpty, json)
        }
    }

    func testTheSorterSeesALineInPlaceOfEachBlock() {
        let reply = request(encoded(["file": "x", "create": "{}"])) + "\n\n```swift\nlet a = 1\n```"
        XCTAssertEqual(
            ChangeRequests.withoutBlocks(reply, saying: "(shown as a card)", withdrawn: "(taken back)"),
            "Done with the rest. One thing I can't do:\n\n(shown as a card)\n\nThat's all.\n\n```swift\nlet a = 1\n```"
        )
    }

    func testOnlyTheListedSettingsFilesCanChange() throws {
        let path = home.path
        XCTAssertEqual(try files.allowed("\(kitten.path)/.claude/settings.json").path, kittenSettings.path)
        XCTAssertEqual(try files.allowed("~/shades/.claude/settings.json").path, "\(path)/shades/.claude/settings.json")
        XCTAssertNoThrow(try files.allowed("\(worktree.path)/.claude/settings.local.json"))
        for refused in [
            "~/.claude/settings.json",
            "~/.claude/settings.local.json",
            "\(kitten.path)/.claude/settings.local.json",
            "\(kitten.path)/settings.json",
            "\(kitten.path)/.claude/hooks/filter.py",
            "~/shades/.claude/../../.claude/settings.json",
            "\(worktree.path)/.claude/settings.json",
            "~/.t3/worktrees/app/.claude/settings.local.json",
            "kittens/clawde/.claude/settings.json",
            "/etc/.claude/settings.json",
        ] {
            XCTAssertThrowsError(try files.allowed(refused), refused)
        }
    }

    func testALinkIsNeverFollowed() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        let mine = home.appendingPathComponent(".claude").path
        try Data("{}".utf8).write(to: URL(fileURLWithPath: "\(mine)/settings.json"))
        func refused(_ file: String, by checker: SettingsFiles? = nil, _ why: String) throws {
            let checked = (checker ?? files).check(try asked(encoded(["file": file, "replace": "{}", "with": "{\"model\": \"x\"}"])))
            XCTAssertNotNil(checked.problem, why)
            XCTAssertThrowsError(try (checker ?? files).apply(checked), why)
        }

        let claude = home.appendingPathComponent("shades/.claude")
        try manager.removeItem(at: claude)
        try manager.createSymbolicLink(atPath: claude.path, withDestinationPath: mine)
        try refused("~/shades/.claude/settings.json", "its .claude")

        try manager.removeItem(at: kittenSettings)
        try manager.createSymbolicLink(atPath: kittenSettings.path, withDestinationPath: "\(mine)/settings.json")
        try refused(kittenSettings.path, "the file")

        let project = home.appendingPathComponent(".t3/worktrees/linked")
        try manager.createSymbolicLink(atPath: project.path, withDestinationPath: home.path)
        try refused("\(project.path)/shades/.claude/settings.local.json", "a project folder")

        let folder = home.appendingPathComponent("kittens/linked")
        try manager.createSymbolicLink(atPath: folder.path, withDestinationPath: home.path)
        try refused("\(folder.path)/.claude/settings.json", by: SettingsFiles(home: home.path, kittenFolders: [folder.path]), "a kitten's folder")
        XCTAssertEqual(try String(contentsOfFile: "\(mine)/settings.json", encoding: .utf8), "{}", "your own settings are untouched")
    }

    func testFixingATrailingCommaBringsBackWhatTheFileAllows() throws {
        let comma = block.replacingOccurrences(of: "\"Bash(swift test)\"\n", with: "\"Bash(swift test)\",\n")
        try Data(comma.utf8).write(to: kittenSettings)
        let checked = files.check(try asked(encoded(["file": kittenSettings.path, "replace": "\"Bash(swift test)\",\n", "with": "\"Bash(swift test)\"\n"])))
        XCTAssertNil(checked.problem)
        XCTAssertTrue(checked.widens.contains("Adds `Bash(swift test)` to `permissions.allow`."), "\(checked.widens)")
        XCTAssertFalse(checked.widens.contains { $0.contains("permissions.deny") }, "a deny coming back only narrows")
        XCTAssertEqual(checked.opensScreenBlock, [], "it brings the block back, if anything")
        try files.apply(checked)
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: Data(contentsOf: kittenSettings)))
        XCTAssertEqual(try String(contentsOf: kittenSettings, encoding: .utf8), block)
    }

    func testWhatCantBeDoneExactlyIsAProblem() throws {
        let cases: [(json: [String: String], why: String)] = [
            (["file": kittenSettings.path, "replace": "nowhere", "with": "x"], "isn't in the file"),
            (["file": kittenSettings.path, "replace": "Read(", "with": "Read ("], "is in the file"),
            (["file": kittenSettings.path, "replace": "\"permissions\": {", "with": "\"permissions\": "], "valid JSON"),
            (["file": kittenSettings.path, "replace": "\"Bash(swift test)\"", "with": "\"Bash(swift test)\","], "valid JSON"),
            (["file": kittenSettings.path, "replace": "\"sandbox\":", "with": "// off for now\n\"sandbox\":"], "valid JSON"),
            (["file": kittenSettings.path, "replace": "\"sandbox\": {\"enabled\": true", "with": "\"sandbox\": {\"enabled\": true, \"enabled\": false"], "same key twice"),
            (["file": kittenSettings.path, "replace": "\"sandbox\"", "with": "\"sandbox\": {}, \"\\u0073andbox\""], "same key twice"),
            (["file": kittenSettings.path, "create": "{}"], "already there"),
            (["file": "\(worktree.path)/.claude/settings.local.json", "replace": "a", "with": "b"], "no file there"),
            (["file": "~/.claude/settings.json", "create": "{}"], "isn't one of"),
        ]
        for (json, why) in cases {
            let checked = files.check(try asked(encoded(json)))
            XCTAssertTrue(checked.problem?.contains(why) == true, "\(json): \(checked.problem ?? "no problem")")
            XCTAssertThrowsError(try files.apply(checked), "\(json)")
        }
        XCTAssertEqual(try String(contentsOf: kittenSettings, encoding: .utf8), block, "nothing was written")
    }

    func testAddingAnAllowWidensWhatAgentsCanDoAndAddingADenyDoesnt() throws {
        let allow = files.check(try asked(encoded(["file": kittenSettings.path, "replace": "\"Bash(swift test)\"", "with": "\"Bash(swift test)\", \"Bash(rm:*)\""])))
        XCTAssertEqual(allow.widens, ["Adds `Bash(rm:*)` to `permissions.allow`."])
        XCTAssertEqual(allow.opensScreenBlock, [])
        XCTAssertTrue(allow.isLoosening)

        let ticks = files.check(try asked(encoded(["file": kittenSettings.path, "replace": "\"Bash(swift test)\"", "with": "\"Bash(swift test)\", \"Bash(echo `id`)\""])))
        XCTAssertEqual(ticks.widens, ["Adds `` Bash(echo `id`) `` to `permissions.allow`."], "its own backticks can't close the code around it")

        let deny = files.check(try asked(encoded(["file": kittenSettings.path, "replace": "\"mcp__t3-code__t3_queue\"", "with": "\"mcp__t3-code__t3_queue\", \"WebFetch\""])))
        XCTAssertEqual(deny.widens, [])

        let sandbox = files.check(try asked(encoded(["file": kittenSettings.path, "replace": "\"allowUnsandboxedCommands\": false", "with": "\"allowUnsandboxedCommands\": true"])))
        XCTAssertEqual(sandbox.widens, ["Changes `sandbox.allowUnsandboxedCommands` from `false` to `true`."])
        XCTAssertEqual(sandbox.opensScreenBlock, ["sandbox.allowUnsandboxedCommands"])
    }

    func testTakingADenyOutOfAScreenBlockOpensIt() throws {
        let checked = files.check(try asked(encoded(["file": kittenSettings.path, "replace": "\"Read(~/.codex/**)\",\n", "with": ""])))
        XCTAssertNil(checked.problem)
        XCTAssertEqual(checked.opensScreenBlock, ["Read(~/.codex/**)"])
        XCTAssertEqual(checked.widens, ["Takes `Read(~/.codex/**)` out of `permissions.deny`."])
    }

    func testANewLocalFileIsWeighedWithTheFileItGoesOver() throws {
        let manager = FileManager.default
        try manager.copyItem(at: kittenSettings, to: worktree.appendingPathComponent(".claude/settings.json"))
        let local = "\(worktree.path)/.claude/settings.local.json"
        let off = files.check(try asked(encoded(["file": local, "create": "{\"sandbox\": {\"enabled\": false}}"])))
        XCTAssertNil(off.problem)
        XCTAssertEqual(off.opensScreenBlock, ["sandbox.enabled"])

        let device = files.check(try asked(encoded(["file": local, "create": "{\"permissions\": {\"allow\": [\"Bash(swift test)\", \"mcp__t3-code__device_open\"]}}"])))
        XCTAssertEqual(device.widens, ["Adds `mcp__t3-code__device_open` to `permissions.allow`."], "what settings.json already allows isn't new")
        XCTAssertEqual(device.opensScreenBlock, [])
    }

    func testANewWorktreeFileIsMadeWithItsFolder() throws {
        try FileManager.default.removeItem(at: worktree.appendingPathComponent(".claude"))
        let local = "\(worktree.path)/.claude/settings.local.json"
        let checked = files.check(try asked(encoded(["file": local, "create": "{\"permissions\": {\"allow\": []}}\n"])))
        XCTAssertNil(checked.problem)
        XCTAssertNil(checked.before)
        try files.apply(checked)
        XCTAssertEqual(try String(contentsOfFile: local, encoding: .utf8), "{\"permissions\": {\"allow\": []}}\n")
        XCTAssertThrowsError(try files.apply(checked), "it's there now, so a second Allow can't make it again")
    }

    func testAFileThatChangedSinceItWasShownIsLeftAlone() throws {
        let checked = files.check(try asked(encoded(["file": kittenSettings.path, "replace": "\"Bash(swift test)\"", "with": "\"Bash(swift test)\", \"Bash(ls)\""])))
        let meanwhile = block.replacingOccurrences(of: "\"enabled\": true", with: "\"enabled\": false")
        try Data(meanwhile.utf8).write(to: kittenSettings)
        XCTAssertThrowsError(try files.apply(checked)) { error in
            XCTAssertTrue((error as? ChangeRequests.Problem)?.reason.contains("changed after") == true)
        }
        XCTAssertEqual(try String(contentsOf: kittenSettings, encoding: .utf8), meanwhile)
    }

    func testOnlyJSONClaudeCodeWouldReadCounts() {
        for good in ["{}", "{\"a\": [1, -2.5e+3, true, false, null, \"\\u00e9\\n\"]}", " {\"a\": {\"b\": {}}} \n"] {
            XCTAssertNoThrow(try StrictJSON.validate(Data(good.utf8)), good)
        }
        for bad in ["{\"a\": 1,}", "{\"a\": [1,]}", "{\"a\": 1} // note", "{'a': 1}", "{\"a\": NaN}", "{\"a\": 01}", "{\"a\": \"\t\"}", "{\"a\": 1}}", "{\"a\" 1}", "[", ""] {
            XCTAssertThrowsError(try StrictJSON.validate(Data(bad.utf8)), bad) { XCTAssertEqual($0 as? StrictJSON.Failure, .invalid, bad) }
        }
        for twice in ["{\"a\": 1, \"a\": 2}", "{\"b\": {\"a\": 1, \"\\u0061\": 2}}"] {
            XCTAssertThrowsError(try StrictJSON.validate(Data(twice.utf8)), twice) { XCTAssertEqual($0 as? StrictJSON.Failure, .repeatedKey, twice) }
        }
        XCTAssertNoThrow(try StrictJSON.validate(Data("{\"a\": {\"a\": 1}, \"b\": [{\"a\": 1}, {\"a\": 2}]}".utf8)), "the same key in different objects is fine")
    }

    func testTheFileIsKeptWithATildeForHome() throws {
        let checked = files.check(try asked(encoded(["file": kittenSettings.path, "replace": "\"Bash(swift test)\"", "with": "\"Bash(ls)\""])))
        XCTAssertEqual(checked.file, "~/kittens/clawde/.claude/settings.json")
        XCTAssertEqual(files.current(checked), block)
        try files.apply(checked)
        XCTAssertTrue(try String(contentsOf: kittenSettings, encoding: .utf8).contains("Bash(ls)"))
        XCTAssertEqual(files.shown("/etc/hosts"), "/etc/hosts")
    }
}
