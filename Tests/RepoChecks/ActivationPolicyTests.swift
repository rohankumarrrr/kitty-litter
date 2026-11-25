import XCTest

final class ActivationPolicyTests: XCTestCase {
    func testOnlyNeverInFrontMakesACopyThatIsntInstalledAnAppThatStaysBehind() throws {
        let keeper = "Sources/Shades/UI/NeverInFront.swift"
        var found: [String] = []
        for path in try Repo.files(under: ["Sources/Shades"], endingIn: [".swift"]) where path != keeper {
            for (number, line) in try Repo.read(path).split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where line.contains("setActivationPolicy(") && !line.contains("setActivationPolicy(.regular)") {
                found.append("\(path):\(number + 1)")
            }
        }
        XCTAssertEqual(found, [], """
        Only the installed app sets its own activation policy, to .regular. Every other copy, such as the demo, a flow \
        or the bench, calls NeverInFront.keep(app) instead, which starts it where macOS can't make it the active app \
        and hands back any activation at once, so it never takes the keys someone is typing.
        """)
    }
}
