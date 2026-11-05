import Foundation
import XCTest
@testable import ShadesCore

final class RouterBlockTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("router-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func denied() throws -> [String] {
        let data = try Data(contentsOf: folder.appendingPathComponent(".claude/settings.json"))
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap((parsed["permissions"] as? [String: Any])?["deny"] as? [String])
    }

    /// Each of these was a way for a router to pass on what it saw: T3's tools message and start threads,
    /// the shell can reach T3 without them, and a written file can loosen these settings or land in a kitten's folder.
    func testTheRouterCantReachAnotherThread() throws {
        XCTAssertEqual(try RouterBlock.prepare(folder), folder.path)
        let denied = try denied()
        for way in ["mcp__t3-code", "Bash", "Edit", "Write", "NotebookEdit"] {
            XCTAssertTrue(denied.contains(way), way)
        }
    }

    func testLoosenedSettingsArePutBack() throws {
        _ = try RouterBlock.prepare(folder)
        try Data(#"{"permissions":{"deny":[]}}"#.utf8).write(to: folder.appendingPathComponent(".claude/settings.json"))
        _ = try RouterBlock.prepare(folder)
        XCTAssertTrue(try denied().contains("mcp__t3-code"))
    }

    func testAFolderThatCantBeWrittenFails() throws {
        try Data().write(to: folder)
        XCTAssertThrowsError(try RouterBlock.prepare(folder))
    }
}
