import Foundation
import XCTest
@testable import ShadesCore

final class ScreenBlockTests: XCTestCase {
    private var repo: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func settings(removing path: [String]) throws -> Data {
        var parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: repo.appendingPathComponent(".claude/settings.json"))) as? [String: Any])
        func removed(_ object: [String: Any], _ keys: ArraySlice<String>) -> [String: Any] {
            var object = object
            guard let key = keys.first else { return object }
            if keys.count == 1 { object[key] = nil } else if let inner = object[key] as? [String: Any] { object[key] = removed(inner, keys.dropFirst()) }
            return object
        }
        parsed = removed(parsed, path[...])
        return try JSONSerialization.data(withJSONObject: parsed)
    }

    /// Threads working on this repo run under these settings, wherever the agent that started them came from.
    func testThisRepoHasTheBlock() throws {
        let data = try Data(contentsOf: repo.appendingPathComponent(".claude/settings.json"))
        XCTAssertEqual(ScreenBlock.gaps(in: data), [])
    }

    func testNoSettingsAreAGap() {
        XCTAssertEqual(ScreenBlock.gaps(in: nil), ["settings"])
        XCTAssertEqual(ScreenBlock.gaps(in: Data("not json".utf8)), ["settings"])
    }

    func testTheSandboxBeingOffIsAGap() throws {
        XCTAssertTrue(ScreenBlock.gaps(in: try settings(removing: ["sandbox", "enabled"])).contains("sandbox.enabled"))
    }

    /// The tool has a flag for running outside the sandbox, and it's on unless turned off.
    func testAWayOutOfTheSandboxIsAGap() throws {
        XCTAssertTrue(ScreenBlock.gaps(in: try settings(removing: ["sandbox", "allowUnsandboxedCommands"])).contains("sandbox.allowUnsandboxedCommands"))
    }

    /// Left to its default, turning the sandbox on would stop asking before commands run.
    func testAutoApprovalIsAGap() throws {
        XCTAssertTrue(ScreenBlock.gaps(in: try settings(removing: ["sandbox", "autoAllowBashIfSandboxed"])).contains("sandbox.autoAllowBashIfSandboxed"))
    }

    func testEveryPlaceScreenTextRestsIsDenied() throws {
        var parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: try settings(removing: [])) as? [String: Any])
        var permissions = try XCTUnwrap(parsed["permissions"] as? [String: Any])
        var deny = try XCTUnwrap(permissions["deny"] as? [String])
        deny.removeAll { $0.contains("attachments") || $0.contains(".t3/userdata") }
        permissions["deny"] = deny
        parsed["permissions"] = permissions
        let gaps = ScreenBlock.gaps(in: try JSONSerialization.data(withJSONObject: parsed))
        XCTAssertTrue(gaps.contains("Read(~/.t3/userdata/**)"))
    }

    /// `mv` carried a file out of T3's attachments folder when reading it was denied.
    func testMovingFilesOutOfT3sFolderIsDenied() throws {
        var parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: try settings(removing: [])) as? [String: Any])
        var permissions = try XCTUnwrap(parsed["permissions"] as? [String: Any])
        permissions["deny"] = try XCTUnwrap(permissions["deny"] as? [String]).filter { $0 != "Edit(~/.t3/userdata/**)" }
        parsed["permissions"] = permissions
        XCTAssertTrue(ScreenBlock.gaps(in: try JSONSerialization.data(withJSONObject: parsed)).contains("Edit(~/.t3/userdata/**)"))
    }

    func testTheThreadReadFilterIsNeeded() throws {
        let gaps = ScreenBlock.gaps(in: try settings(removing: ["hooks"]))
        XCTAssertTrue(gaps.contains("thread read filter"))
    }
}
