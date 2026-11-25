import AppKit
@testable import Shades
import XCTest

@MainActor
final class DemoFrontTests: XCTestCase {
    func testTheDemoSaysWhetherItsInFrontButNeverNamesAnotherApp() throws {
        XCTAssertEqual(DemoDriver.front(.current), "The Kitty Litter")
        XCTAssertEqual(DemoDriver.front(nil), "nothing")

        let me = NSRunningApplication.current.processIdentifier
        let other = try XCTUnwrap(NSWorkspace.shared.runningApplications.first { $0.processIdentifier != me && $0.localizedName?.isEmpty == false })
        let words = DemoDriver.front(other)
        // Outside the repo: XCTAssertEqual prints both values when it fails, which would name the app.
        XCTAssertTrue(words == "another app")
        XCTAssertFalse(words.contains(other.localizedName ?? ""))
    }
}
