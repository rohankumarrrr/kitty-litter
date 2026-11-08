@testable import ShadesContext
import XCTest

final class FrontWindowTests: XCTestCase {
    private let messages = CGRect(x: 526, y: 184, width: 900, height: 560)
    private let shades: pid_t = 1
    private let editor: pid_t = 2
    private let borders: pid_t = 3

    private func window(_ number: Int, of pid: pid_t, layer: Int = 0, _ frame: CGRect) -> [String: Any] {
        [
            kCGWindowNumber as String: number,
            kCGWindowOwnerPID as String: pid,
            kCGWindowLayer as String: layer,
            kCGWindowBounds as String: frame.dictionaryRepresentation,
        ]
    }

    private func isOnTop(_ above: [[String: Any]]) -> Bool {
        FrontWindow.isOnTop(1, among: above + [window(1, of: shades, messages)]) { $0 != self.borders }
    }

    func testAnAppsWindowOverAnyOfItPutsItBehind() {
        XCTAssertTrue(isOnTop([]))
        XCTAssertFalse(isOnTop([window(2, of: editor, messages.insetBy(dx: 300, dy: 100))]))
        XCTAssertFalse(isOnTop([window(2, of: editor, messages.offsetBy(dx: 880, dy: 0))]), "over its edge")
    }

    func testWhatsBesideItFloatsOverItOrIsDrawnByAToolLeavesItOnTop() {
        let beside = messages.offsetBy(dx: -messages.width - 1, dy: 0)
        XCTAssertTrue(isOnTop([
            window(4, of: shades, layer: 25, messages.insetBy(dx: 400, dy: 200)),
            window(3, of: borders, beside.insetBy(dx: -32, dy: -32)),
            window(2, of: editor, beside),
        ]))
    }

    func testAWindowTheListDoesntHaveIsntOnTop() {
        XCTAssertFalse(FrontWindow.isOnTop(1, among: []) { _ in true })
    }
}
