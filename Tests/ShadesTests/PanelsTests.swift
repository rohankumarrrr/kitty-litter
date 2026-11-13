import AppKit
@testable import Shades
import ShadesCore
import UserNotifications
import XCTest

/// The kittens view, the pairing code and the notifications, held to how a Mac does the same things.
@MainActor
final class PanelsTests: XCTestCase {
    private let steve = Kitten(name: "Steve Pawsniak", role: "Professional", covers: "jobs", folder: "/k/steve")
    private let cali = Kitten(name: "Cali", role: "Scheduling", covers: "time", folder: "/k/cali", planned: true)
    private let away = NSRect(x: -20_000, y: -20_000, width: 800, height: 600)

    private func elements(in view: NSView) -> [NSView] {
        (view.isAccessibilityElement() ? [view] : []) + view.subviews.flatMap(elements)
    }

    func testTheKittensNotSetUpAreAGroupOfTheirOwnAndEveryKittenOpens() throws {
        let panel = KittenPanel()
        panel.anchor = { (NSRect(x: self.away.midX, y: self.away.minY, width: 64, height: 64), self.away) }
        defer { panel.hide() }
        panel.show([KittenStatus(kitten: steve, state: .idle), KittenStatus(kitten: cali, state: .notSetUp)])
        let found = elements(in: try XCTUnwrap(panel.panel.contentView)).map { "\($0.accessibilityRole()?.rawValue ?? ""): \($0.accessibilityLabel() ?? "")" }
        XCTAssertEqual(found, [
            "AXStaticText: Kittens",
            "AXButton: Steve Pawsniak, Professional, Idle",
            "AXStaticText: Not set up yet",
            "AXButton: Cali, Scheduling, Not set up yet",
        ], "small capitals over each group, and an idle kitten with nothing to open still opens")
    }

    func testAKittensStateIsInOpalsStatusColoursNeverGreyOrOrange() {
        XCTAssertEqual(KittenRow.color(for: .working(sessions: 2)), Opal.lilac, "the glint its cat wears while it works")
        XCTAssertEqual(KittenRow.color(for: .needsYou), Opal.errorText)
        XCTAssertEqual(KittenRow.color(for: .idle), Opal.good, "not a bare grey square")
        XCTAssertNil(KittenRow.color(for: .notSetUp), "its group says so")
    }

    func testEscClosesThePairingCodeAndItStopsWorking() {
        let stage = AppStage()
        var closed = 0
        stage.pairing.onClose = { closed += 1 }
        stage.showPairing(PhonePairingCard(address: "http://example.test", code: "ABCD-2345"))
        XCTAssertTrue(stage.pairing.isVisible)
        stage.escapePressed()
        XCTAssertFalse(stage.pairing.isVisible, "Escape closes what floats")
        XCTAssertEqual(closed, 1, "the same as Cancel, so the code stops working")
    }

    func testTheCodeSaysCancelSinceClosingItStopsThePairing() throws {
        let pairing = PairingPanel()
        pairing.show(PhonePairingCard(address: "http://example.test", code: "ABCD-2345"), centeredIn: away)
        defer { pairing.hide() }
        let buttons = elements(in: try XCTUnwrap(pairing.panel.contentView)).compactMap { $0 as? QuietButton }
        XCTAssertEqual(buttons.map { $0.accessibilityLabel() ?? "" }, ["Cancel"])
    }

    func testANotificationSaysWhoInItsTitleAndWhatInItsBody() {
        let steves = NeedsYouNotifications.content(NeedsYouAlert(id: "r1", kind: .approval, who: "Steve Pawsniak", threadID: "t1"))
        XCTAssertEqual(steves.title, "Steve Pawsniak", "as Messages and Slack name who it's from")
        XCTAssertEqual(steves.body, "Needs an approval")
        XCTAssertEqual(steves.threadIdentifier, "t1", "grouped by thread in Notification Center")
        XCTAssertEqual(steves.userInfo["thread"] as? String, "t1")

        let nobodys = NeedsYouNotifications.content(NeedsYouAlert(id: "q1", kind: .question, who: nil, threadID: "t2"))
        XCTAssertEqual(nobodys.title, "", "macOS titles it with the app's name")
        XCTAssertEqual(nobodys.body, "An agent has a question")
    }
}
