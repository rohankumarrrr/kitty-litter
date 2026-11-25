import XCTest

final class PrivateOutputTests: XCTestCase {
    static let printsWhereAnyoneCanRead = ["Sources/Shades/Demo", "Sources/Probes", "Sources/Shades/App/DevFlags.swift"]
    static let namesWhatsOnYourScreen = ["localizedName", "bundleIdentifier", "kCGWindowOwnerName", "kCGWindowName"]

    func testWhatTheDemoAndProbesPrintNeverNamesAnotherApp() throws {
        let pattern = try NSRegularExpression(pattern: Self.namesWhatsOnYourScreen.map(NSRegularExpression.escapedPattern).joined(separator: "|"))
        for file in try Repo.files(under: Self.printsWhereAnyoneCanRead, endingIn: [".swift"]) {
            for match in SwiftLexer(try Repo.read(file)).matches(of: pattern, in: .code) {
                XCTFail("""
                \(file):\(match.line) reads \(match.text). What the demo and the probes print goes on public pull \
                requests, so it never names the app in front or its windows. Print `DemoDriver.front(_:)`, which says \
                only "The Kitty Litter" or "another app", or a process ID or a yes or no.
                """)
            }
        }
    }
}
