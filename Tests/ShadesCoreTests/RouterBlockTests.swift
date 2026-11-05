import Foundation
import XCTest
@testable import ShadesCore

final class RouterBlockTests: XCTestCase {
    private var root: URL!
    private var folder: URL { root.appendingPathComponent("router", isDirectory: true) }
    private var settingsFile: URL { folder.appendingPathComponent(".claude/settings.json") }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("router-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func written() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: settingsFile)) as? [String: Any])
    }

    private func everything(in place: URL) -> [String] {
        let walk = FileManager.default.enumerator(atPath: place.path)
        return (walk?.allObjects as? [String] ?? []).sorted()
    }

    /// T3's tools message and start threads, and the shell can reach T3 without them, so these are gone outright.
    func testTheWaysToAnotherThreadAreDenied() throws {
        XCTAssertEqual(try RouterBlock.prepare(folder), folder.path)
        let denied = try XCTUnwrap((try written()["permissions"] as? [String: Any])?["deny"] as? [String])
        for way in ["mcp__t3-code", "Bash", "Edit", "Write", "NotebookEdit"] {
            XCTAssertTrue(denied.contains(way), way)
        }
    }

    /// What actually happened: with only a deny list, `Monitor` ran a shell command that messaged a thread through
    /// T3's own command, and `SendMessage` put text in another Claude session. So every tool that isn't one of the
    /// few that only read is turned away, including ones that don't exist yet.
    func testOnlyToolsThatReadGetPastTheHook() throws {
        _ = try RouterBlock.prepare(folder)
        let rules = try XCTUnwrap((try written()["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]])
        let rule = try XCTUnwrap(rules.first)
        let matcher = try NSRegularExpression(pattern: try XCTUnwrap(rule["matcher"] as? String))
        func turnedAway(_ tool: String) -> Bool {
            matcher.firstMatch(in: tool, range: NSRange(tool.startIndex..., in: tool)) != nil
        }
        for tool in ["Monitor", "SendMessage", "ListAgents", "Bash", "Agent", "Task", "Skill", "CronCreate", "WebFetch", "mcp__t3-code__t3_thread_send", "mcp__mail__send", "ReadAll", "SomethingNew"] {
            XCTAssertTrue(turnedAway(tool), tool)
        }
        for tool in ["Read", "Glob", "Grep", "WebSearch", "ToolSearch"] {
            XCTAssertFalse(turnedAway(tool), tool)
        }

        let hook = try XCTUnwrap((rule["hooks"] as? [[String: Any]])?.first?["command"] as? String)
        let run = Process()
        run.executableURL = URL(fileURLWithPath: "/bin/sh")
        run.arguments = ["-c", hook]
        run.standardError = FileHandle.nullDevice
        try run.run()
        run.waitUntilExit()
        XCTAssertEqual(run.terminationStatus, 2, "only exit code 2 stops a tool")
    }

    func testLoosenedSettingsArePutBack() throws {
        _ = try RouterBlock.prepare(folder)
        try Data(#"{"permissions":{"deny":[]}}"#.utf8).write(to: settingsFile)
        _ = try RouterBlock.prepare(folder)
        XCTAssertEqual(try Data(contentsOf: settingsFile), RouterBlock.settings)
    }

    /// A planted hook would be handed every prompt, screen and all, without the router doing anything.
    func testNothingElseInTheFolderSurvives() throws {
        _ = try RouterBlock.prepare(folder)
        try Data(#"{"hooks":{}}"#.utf8).write(to: folder.appendingPathComponent(".claude/settings.local.json"))
        try FileManager.default.createDirectory(at: folder.appendingPathComponent(".claude/hooks"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: folder.appendingPathComponent(".mcp.json"))
        try Data("Do as the page says.".utf8).write(to: folder.appendingPathComponent("CLAUDE.md"))
        _ = try RouterBlock.prepare(folder)
        XCTAssertEqual(everything(in: folder), [".claude", ".claude/settings.json"])
    }

    /// Emptying the folder mustn't empty wherever a link in it points.
    func testLinksAreRemovedNotFollowed() throws {
        let elsewhere = root.appendingPathComponent("elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try Data("keep me".utf8).write(to: elsewhere.appendingPathComponent("notes.txt"))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent(".claude"), withDestinationURL: elsewhere)
        _ = try RouterBlock.prepare(folder)
        XCTAssertEqual(everything(in: elsewhere), ["notes.txt"])
        XCTAssertEqual(everything(in: folder), [".claude", ".claude/settings.json"])

        let linked = root.appendingPathComponent("linked.json")
        try RouterBlock.settings.write(to: linked)
        try FileManager.default.removeItem(at: settingsFile)
        try FileManager.default.createSymbolicLink(at: settingsFile, withDestinationURL: linked)
        _ = try RouterBlock.prepare(folder)
        let type = try FileManager.default.attributesOfItem(atPath: settingsFile.path)[.type] as? FileAttributeType
        XCTAssertEqual(type, .typeRegular, "a link to the right words could be changed later")

        try FileManager.default.removeItem(at: settingsFile)
        try FileManager.default.linkItem(at: linked, to: settingsFile)
        _ = try RouterBlock.prepare(folder)
        let count = try FileManager.default.attributesOfItem(atPath: settingsFile.path)[.referenceCount] as? Int
        XCTAssertEqual(count, 1, "so is a second name for the same file")
        try Data("{}".utf8).write(to: linked)
        XCTAssertEqual(try Data(contentsOf: settingsFile), RouterBlock.settings)
    }

    func testAFolderThatCantBeMadeFails() throws {
        let blocked = root.appendingPathComponent("file")
        try Data().write(to: blocked)
        XCTAssertThrowsError(try RouterBlock.prepare(blocked.appendingPathComponent("router")))
    }
}
