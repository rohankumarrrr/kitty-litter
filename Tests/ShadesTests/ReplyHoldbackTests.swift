@testable import Shades
import ShadesCore
import XCTest

final class ReplyHoldbackTests: XCTestCase {
    func testARouteIsHeldBackAndReadAtTheEnd() {
        var holdback = ReplyHoldback()
        XCTAssertNil(holdback.add("SE"))
        XCTAssertNil(holdback.add("ND TO: 2"))
        XCTAssertEqual(holdback.finish(fullText: "SEND TO: 2"), .route(session: 2))
    }

    func testAnAnswerThatStartsTheSameWayIsStillAnAnswer() {
        var holdback = ReplyHoldback()
        XCTAssertNil(holdback.add("S"))
        XCTAssertEqual(holdback.add("o you could"), "So you could")
    }

    func testARouteToNowhereIsNothingWorthReading() {
        XCTAssertEqual(ReplyHoldback().finish(fullText: "SEND TO: the second one"), .answer(""))
    }

    func testARealAnswerShowsFromItsFirstLetter() {
        var holdback = ReplyHoldback()
        XCTAssertEqual(holdback.add("That's"), "That's")
        XCTAssertEqual(holdback.add(" a button."), "That's a button.")
        XCTAssertEqual(holdback.finish(fullText: "That's a button."), .answer("That's a button."))
    }

    func testAWordThatStartsLikeTheMarkerOnlyWaitsUntilItCant() {
        var holdback = ReplyHoldback()
        XCTAssertNil(holdback.add("H"))
        XCTAssertEqual(holdback.add("ello"), "Hello")
    }

    func testALongerNearMissIsStillReleased() {
        var holdback = ReplyHoldback()
        XCTAssertNil(holdback.add("HAND"))
        XCTAssertNil(holdback.add("OFF"))
        XCTAssertEqual(holdback.add(" is a word"), "HANDOFF is a word")
    }

    func testAHandoffNeverShows() {
        var holdback = ReplyHoldback()
        for piece in ["HAN", "DOFF", ":", " Fix", " the", " bug"] {
            XCTAssertNil(holdback.add(piece))
        }
        XCTAssertEqual(holdback.finish(fullText: "HANDOFF: Fix the bug"), .handoff(task: "Fix the bug"))
    }

    func testAHandoffAfterLeadingSpaceNeverShows() {
        var holdback = ReplyHoldback()
        XCTAssertNil(holdback.add("\n  "))
        XCTAssertNil(holdback.add("HANDOFF: go"))
        XCTAssertEqual(holdback.finish(fullText: nil), .handoff(task: "go"))
    }

    func testLeadingSpaceIsDroppedFromAnswers() {
        var holdback = ReplyHoldback()
        XCTAssertNil(holdback.add("\n"))
        XCTAssertEqual(holdback.add("Sure."), "Sure.")
    }

    func testAShortReplyThatStaysAmbiguousStillArrives() {
        var holdback = ReplyHoldback()
        XCTAssertNil(holdback.add("H"))
        XCTAssertEqual(holdback.finish(fullText: "H"), .answer("H"))
    }

    func testTheMarkerAloneIsNothing() {
        var holdback = ReplyHoldback()
        XCTAssertNil(holdback.add("HANDOFF:"))
        XCTAssertEqual(holdback.finish(fullText: "HANDOFF:"), .answer(""))
    }

    func testTheFullTextIsTheOneThatCounts() {
        var holdback = ReplyHoldback()
        XCTAssertEqual(holdback.add("Part"), "Part")
        XCTAssertEqual(holdback.finish(fullText: "Part of it, and the rest."), .answer("Part of it, and the rest."))
    }

    func testAMarkerMidReplyIsJustWords() {
        var holdback = ReplyHoldback()
        XCTAssertEqual(holdback.add("Sure. HANDOFF: no"), "Sure. HANDOFF: no")
        XCTAssertEqual(holdback.finish(fullText: "Sure. HANDOFF: no"), .answer("Sure. HANDOFF: no"))
    }
}
