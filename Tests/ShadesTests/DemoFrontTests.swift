import AppKit
@testable import Shades
import XCTest

/// What a journey prints goes on public pull requests, so the demo says whether it's in front, never which app is.
@MainActor
final class DemoFrontTests: XCTestCase {
    func testTheDemoSaysWhetherItsInFrontButNeverNamesAnotherApp() throws {
        XCTAssertEqual(DemoDriver.front(.current), "The Kitty Litter")
        XCTAssertEqual(DemoDriver.front(nil), "nothing")

        let me = NSRunningApplication.current.processIdentifier
        let other = try XCTUnwrap(NSWorkspace.shared.runningApplications.first { $0.processIdentifier != me && $0.localizedName?.isEmpty == false })
        let words = DemoDriver.front(other)
        // Checked without putting either string in a failure message, which would name the app.
        XCTAssertTrue(words == "another app")
        XCTAssertFalse(words.contains(other.localizedName ?? ""))
    }
}
