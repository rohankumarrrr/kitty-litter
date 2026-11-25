import ShadesCore
import XCTest

final class RuntimeModeTests: XCTestCase {
    func testAThreadCarryingYourScreenAlwaysRunsInAModeThatTakesItAndOneWithoutKeepsItsMode() {
        for mode in RuntimeMode.allCases {
            XCTAssertTrue(mode.carrying(screen: true).takesScreen, "\(mode)")
            XCTAssertEqual(mode.carrying(screen: false), mode, "\(mode)")
        }
        XCTAssertEqual(RuntimeMode.fullAccess.carrying(screen: true), .auto)
        XCTAssertEqual(RuntimeMode.approvalRequired.carrying(screen: true), .approvalRequired, "a stricter mode stays as it is")
        XCTAssertFalse(RuntimeMode.fullAccess.takesScreen)
    }
}
