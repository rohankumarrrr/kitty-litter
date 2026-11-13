import AppKit
@testable import Shades
import XCTest

@MainActor
final class MenuBarTests: XCTestCase {
    private func item(_ title: String, in bar: MenuBar) throws -> NSMenuItem {
        try XCTUnwrap(bar.shownItems.first { $0.title == title }, "no item [\(title)]")
    }

    func testTheMenuOnlyOffersAShortcutTheAppHolds() throws {
        let bar = MenuBar()
        bar.held = [.ask, .messages]
        let ask = try item("Ask…", in: bar)
        XCTAssertEqual(ask.keyEquivalent, " ")
        XCTAssertEqual(ask.keyEquivalentModifierMask, .option)
        let messages = try item(CatWords.appName, in: bar)
        XCTAssertEqual(messages.keyEquivalent, "b")
        XCTAssertEqual(messages.keyEquivalentModifierMask, [.control, .command])
        XCTAssertEqual(try item("Fix What I'm Looking At", in: bar).keyEquivalent, "", "another app has ⌃⌥F, so pressing it wouldn't do this")
    }

    func testTheMenuKeepsCountsAndTipsOutOfItsTitles() throws {
        let bar = MenuBar()
        bar.messagesSummary = { "1 needs you" }
        XCTAssertEqual(try item(CatWords.appName, in: bar).badge?.stringValue, "1 needs you")
        XCTAssertEqual(try item("Kittens", in: bar).toolTip, "Or Shift-click the cat")
        XCTAssertFalse(bar.shownItems.contains { $0.title.contains("...") }, "an ellipsis is one character")
    }

    func testSettingsAndQuitEndTheMenuOnTheirOwn() throws {
        let bar = MenuBar()
        let items = bar.shownItems
        let settings = try XCTUnwrap(items.firstIndex { $0.title == "Settings…" })
        XCTAssertTrue(items[settings - 1].isSeparatorItem, "Do Not Disturb isn't in with them")
        XCTAssertEqual(items[settings + 1].title, "Quit \(CatWords.appName)")
        XCTAssertEqual(settings + 2, items.count)
    }
}
