@testable import ShadesVoice
import XCTest

final class RuleCleanerTests: XCTestCase {
    private let cleaner = RuleCleaner()

    private func assertCleans(_ raw: String, to expected: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(cleaner.tidy(raw), expected, file: file, line: line)
    }

    // MARK: - Fillers

    func testRemovesFillerWords() {
        assertCleans("Um, so I think we should, uh, go with the blue one.", to: "So I think we should go with the blue one.")
        assertCleans("Let's, um, do it.", to: "Let's do it.")
        assertCleans("Hmm, let me think. Um, yeah, okay.", to: "Let me think. Yeah, okay.")
    }

    func testRemovesYouKnowWhenSetOff() {
        assertCleans("You know, I was thinking about it.", to: "I was thinking about it.")
        assertCleans("The test is flaky, you know, on the build server.", to: "The test is flaky on the build server.")
    }

    func testKeepsRealYouKnow() {
        assertCleans("Do you know the answer?", to: "Do you know the answer?")
        assertCleans("Let me know if you know, please.", to: "Let me know if you know, please.")
    }

    func testRemovesLikeOnlyWhenSetOff() {
        assertCleans("Can you, like, update the timeline?", to: "Can you update the timeline?")
        assertCleans("I like how the app feels like a native Mac app.", to: "I like how the app feels like a native Mac app.")
    }

    func testOnlyFillersBecomesEmpty() {
        XCTAssertEqual(cleaner.tidy("Um, uh."), "")
        XCTAssertTrue(RuleCleaner.isOnlyFillers("Um."))
        XCTAssertFalse(RuleCleaner.isOnlyFillers("Um, okay."))
    }

    // MARK: - Stutters

    func testCollapsesStutters() {
        assertCleans("The, the problem is here.", to: "The problem is here.")
        assertCleans("I, I, I don't think so.", to: "I don't think so.")
        assertCleans("We should we should ship it.", to: "We should ship it.")
    }

    func testKeepsRealRepeats() {
        assertCleans("I know that that works.", to: "I know that that works.")
        assertCleans("It's very very good.", to: "It's very very good.")
        assertCleans("Call five five five.", to: "Call five five five.")
    }

    // MARK: - Corrections

    func testReplacesCorrectedValue() {
        assertCleans("Let's meet at three, no, actually four.", to: "Let's meet at four.")
        assertCleans("Send it to John, sorry, I mean Mike.", to: "Send it to Mike.")
        assertCleans("We should ship it on Tuesday, actually, make that Wednesday.", to: "We should ship it on Wednesday.")
        assertCleans("Book a table for four, no, five people on Friday.", to: "Book a table for five people on Friday.")
        assertCleans("The budget is five thousand dollars, no wait, six thousand dollars.", to: "The budget is six thousand dollars.")
        assertCleans("Open the settings page, no, I mean the profile page.", to: "Open the profile page.")
        assertCleans("I'll be there at nine, or rather nine thirty.", to: "I'll be there at nine thirty.")
    }

    func testScratchThatDropsTheClauseBefore() {
        assertCleans("Turn left on Main Street. Scratch that. Turn right on Main Street.", to: "Turn right on Main Street.")
    }

    func testLeavesWordsThatOnlyLookLikeCorrections() {
        assertCleans("Actually, the new design is great.", to: "Actually, the new design is great.")
        assertCleans("I mean it when I say this matters a lot.", to: "I mean it when I say this matters a lot.")
        assertCleans("No, I don't think we should keep it.", to: "No, I don't think we should keep it.")
        assertCleans("I actually like it.", to: "I actually like it.")
        assertCleans("The build is green. No, I don't think so.", to: "The build is green. No, I don't think so.")
    }

    func testLeavesCorrectionsItCantLineUp() {
        // Unsure which words "blue" replaces, so nothing is lost.
        assertCleans("The red one, no wait, blue.", to: "The red one, no wait, blue.")
    }

    // MARK: - Edges

    func testAddsCapitalAndFullStop() {
        assertCleans("sounds good", to: "Sounds good.")
        assertCleans("what time is it", to: "What time is it?")
        assertCleans("i think i'm done", to: "I think I'm done.")
    }

    func testEmptyStaysEmpty() {
        XCTAssertEqual(cleaner.tidy(""), "")
        XCTAssertEqual(cleaner.tidy("   "), "")
    }
}

final class SpokenFormattingTests: XCTestCase {
    func testBulletPoints() {
        XCTAssertEqual(
            SpokenFormatting.apply(to: "Bullet point, fix the login bug. Bullet point, update the docs. Bullet point, ship the release."),
            "- Fix the login bug\n- Update the docs\n- Ship the release"
        )
    }

    func testNumberedSteps() {
        XCTAssertEqual(
            SpokenFormatting.apply(to: "Here are the next steps. Number one, fix the login bug. Number two, update the docs."),
            "Here are the next steps:\n1. Fix the login bug\n2. Update the docs"
        )
    }

    func testOrdinals() {
        XCTAssertEqual(
            SpokenFormatting.apply(to: "To set it up, first, install the app. Second, grant permissions. Third, restart it."),
            "To set it up:\n1. Install the app\n2. Grant permissions\n3. Restart it"
        )
    }

    func testOrdinaryOrdinalsStayInTheSentence() {
        let text = "The first thing is the second part of the third plan."
        XCTAssertEqual(SpokenFormatting.apply(to: text), text)
    }

    func testNumberInSentenceIsNotAList() {
        let text = "Call number one before number two."
        XCTAssertNotEqual(SpokenFormatting.apply(to: text), "")
        let single = "We are number one this year."
        XCTAssertEqual(SpokenFormatting.apply(to: single), single)
    }

    func testNewLineCommand() {
        XCTAssertEqual(SpokenFormatting.apply(to: "Hi team, new line, the build is green."), "Hi team,\nThe build is green.")
        XCTAssertEqual(SpokenFormatting.apply(to: "First part. New paragraph. Second part."), "First part.\n\nSecond part.")
    }

    func testNewLineInASentenceStays() {
        let text = "Add a new line to the config file before you save it."
        XCTAssertEqual(SpokenFormatting.apply(to: text), text)
    }

    func testListLinesLoseTheirFullStops() {
        XCTAssertEqual(SpokenFormatting.tidyListLines("Steps:\n1. Install it.\n2. Run it."), "Steps:\n1. Install it\n2. Run it")
        XCTAssertEqual(SpokenFormatting.tidyListLines("- One.\n- Two."), "- One\n- Two")
        XCTAssertEqual(SpokenFormatting.tidyListLines("A sentence.\nAnother one."), "A sentence.\nAnother one.")
        XCTAssertEqual(SpokenFormatting.tidyListLines("No newline."), "No newline.")
    }

    func testSpokenEndMarks() {
        XCTAssertEqual(SpokenFormatting.apply(to: "Is it done question mark"), "Is it done?")
        XCTAssertEqual(SpokenFormatting.apply(to: "We won exclamation point"), "We won!")
        let text = "It ends with a question mark and a full stop in the middle."
        XCTAssertEqual(SpokenFormatting.apply(to: text), text)
    }
}
