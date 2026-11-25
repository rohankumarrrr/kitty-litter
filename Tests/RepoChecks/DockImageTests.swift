import XCTest

final class DockImageTests: XCTestCase {
    func testOnlyAFinishedLaunchSetsTheDockImage() throws {
        let hook = "func applicationDidFinishLaunching(_ notification: Notification) {"
        var setters: [String] = []
        for path in try Repo.files(under: ["Sources", "Tests"], endingIn: [".swift"]) where path != "Tests/RepoChecks/DockImageTests.swift" {
            var inHook = false
            for (number, line) in try Repo.read(path).split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                if code == hook { inHook = true } else if inHook, code == "}" { inHook = false }
                if code.contains("applicationIconImage =") {
                    setters.append(inHook && path == "Sources/Shades/App/AppDelegate.swift" ? "hook" : "\(path):\(number + 1)")
                }
            }
        }
        XCTAssertEqual(setters, ["hook"], """
        The Dock image is set only in AppDelegate's applicationDidFinishLaunching, since setting it before AppKit has \
        finished launching crashes the app, cat and all. Move the line there, and have a test go through that hook \
        instead of setting it itself.
        """)
    }
}
