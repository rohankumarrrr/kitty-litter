@testable import Shades
import ShadesCore
import XCTest

final class ReplyHoldbackTests: XCTestCase {
    func testAKittenIsHeldBackAndReadAtTheEnd() {
        var holdback = ReplyHoldback()
        XCTAssertNil(holdback.add("KIT"))
        XCTAssertNil(holdback.add("TEN: 1"))
        XCTAssertEqual(holdback.finish(fullText: "KITTEN: 1"), .kitten(number: 1))
        XCTAssertEqual(ReplyHoldback().finish(fullText: "KITTEN: Steve"), .answer(""))
    }

    func testARewriteIsHeldBackAndReadAtTheEnd() {
        var holdback = ReplyHoldback()
        XCTAssertNil(holdback.add("REW"))
        XCTAssertNil(holdback.add("RITE:\nShorter."))
        XCTAssertEqual(holdback.finish(fullText: "REWRITE:\nShorter.\n\nStill short."), .rewrite("Shorter.\n\nStill short."))
        XCTAssertEqual(ReplyHoldback().finish(fullText: "REWRITE: "), .answer(""))
        XCTAssertEqual(ReplyHoldback().finish(fullText: "Rewrite it yourself."), .answer("Rewrite it yourself."))
    }

    func testACorrectionIsHeldBackAndTheRestIsStillRead() {
        var holdback = ReplyHoldback()
        for piece in ["COR", "RECTION: 1", "\n", "CORRECTION: 3\nSE", "ND TO: 2"] {
            XCTAssertNil(holdback.add(piece))
        }
        XCTAssertEqual(holdback.read(fullText: nil), .init(corrections: [1, 3], outcome: .route(session: 2)))
    }

    func testAnAnswerAfterACorrectionShowsWithoutIt() {
        var holdback = ReplyHoldback()
        XCTAssertNil(holdback.add("CORRECTION: 1\n"))
        XCTAssertEqual(holdback.add("Red"), "Red")
        XCTAssertEqual(holdback.add("."), "Red.")
        XCTAssertEqual(holdback.read(fullText: "CORRECTION: 1\nRed."), .init(corrections: [1], outcome: .answer("Red.")))
    }

    func testACorrectionOnItsOwnIsNothingToShow() {
        XCTAssertEqual(ReplyHoldback().read(fullText: "CORRECTION: 2"), .init(corrections: [2], outcome: .answer("")))
    }

    /// A marker with nothing usable after it meant the rest for somewhere, so it isn't an answer of nothing.
    func testAMarkerThatGoesNowhereBesideACorrectionIsntNothing() {
        for rest in ["KITTEN: Penny", "SEND TO: Work", "HANDOFF:", "REWRITE: "] {
            XCTAssertTrue(ReplyHoldback().read(fullText: "CORRECTION: 1\n\(rest)").wentNowhere, rest)
        }
        XCTAssertFalse(ReplyHoldback().read(fullText: "CORRECTION: 1").wentNowhere)
    }

    func testACorrectionThatDoesntSayANumberNeverShows() {
        var holdback = ReplyHoldback()
        XCTAssertNil(holdback.add("CORRECTION: it was 12 people"))
        XCTAssertEqual(holdback.read(fullText: nil), .init(corrections: [0], outcome: .answer("")))
        XCTAssertEqual(ReplyHoldback().read(fullText: "CORRECTION: Steve\nSEND TO: 2"), .init(corrections: [0], outcome: .route(session: 2)))
    }

    func testACorrectionLineInsideAnAnswerIsJustWords() {
        var holdback = ReplyHoldback()
        XCTAssertEqual(holdback.add("Red.\nCORRECTION: 1"), "Red.\nCORRECTION: 1")
        XCTAssertEqual(holdback.read(fullText: nil), .init(corrections: [], outcome: .answer("Red.\nCORRECTION: 1")))
    }

    func testAWordThatStartsLikeACorrectionIsStillAnAnswer() {
        var holdback = ReplyHoldback()
        XCTAssertNil(holdback.add("CORRECTION"))
        XCTAssertEqual(holdback.add(" fluid is a thing"), "CORRECTION fluid is a thing")
    }

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

    func testWhereToPointNeverShowsEvenHalfWritten() {
        var holdback = ReplyHoldback()
        XCTAssertEqual(holdback.add("Top right."), "Top right.")
        XCTAssertEqual(holdback.add("\nP"), "Top right.")
        XCTAssertEqual(holdback.add("OINT: "), "Top right.")
        XCTAssertEqual(holdback.add("2"), "Top right.")
        XCTAssertEqual(holdback.finish(fullText: "Top right.\nPOINT: 2"), .answer("Top right.", point: .element(2)))
    }

    func testWhereToPointStaysHiddenWhenANewLineFollowsIt() {
        var holdback = ReplyHoldback()
        XCTAssertEqual(holdback.add("Top right."), "Top right.")
        XCTAssertEqual(holdback.add("\nPOINT: 2"), "Top right.")
        XCTAssertEqual(holdback.add("\n"), "Top right.")
        XCTAssertEqual(holdback.finish(fullText: "Top right.\nPOINT: 2\n"), .answer("Top right.", point: .element(2)))
    }

    func testALineThatOnlyStartsLikeItShows() {
        var holdback = ReplyHoldback()
        XCTAssertEqual(holdback.add("Top right.\nP"), "Top right.")
        XCTAssertEqual(holdback.add("ress it."), "Top right.\nPress it.")
    }

    func testAReplyThatOnlyPointsHasNoWords() {
        var holdback = ReplyHoldback()
        XCTAssertEqual(holdback.add("POINT: 1"), "")
        XCTAssertEqual(holdback.finish(fullText: "POINT: 1"), .answer("", point: .element(1)))
    }
}
