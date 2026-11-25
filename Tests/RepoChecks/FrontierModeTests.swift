import XCTest

final class FrontierModeTests: XCTestCase {
    func testAThreadTakesFrontiersModeOnlyThroughWhetherItCarriesYourScreen() throws {
        let reading = try NSRegularExpression(pattern: #"\.frontierMode\b(?!\.carrying\(screen:)"#)
        for file in try Repo.files(under: ["Sources"], endingIn: [".swift"]) where !file.hasPrefix("Sources/Shades/UI/") && !file.hasPrefix("Sources/ShadesCore/Settings") {
            for match in SwiftLexer(try Repo.read(file)).matches(of: reading, in: .code) {
                XCTFail("""
                \(file):\(match.line) reads Frontier's mode as it is. A thread that carries your screen has to run in a \
                mode that takes it, and full access never does. Start the thread with `startFrontier`, which picks \
                `settings.frontierMode.carrying(screen: carriesScreen(snapshot))`, so its mode and its screen come from \
                one place.
                """)
            }
        }
    }
}
