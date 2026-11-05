@testable import ShadesVoice
import XCTest

final class CleanupGuardTests: XCTestCase {
    private func assertAccepted(_ raw: String, _ cleaned: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(CleanupGuard.check(raw: raw, cleaned: cleaned), .accept, file: file, line: line)
    }

    private func assertRejected(_ raw: String, _ cleaned: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(CleanupGuard.check(raw: raw, cleaned: cleaned).isAccepted, "\(cleaned)", file: file, line: line)
    }

    func testAcceptsGoodCleanups() {
        assertAccepted("Um, so I think we should, uh, go with the blue one.", "So I think we should go with the blue one.")
        assertAccepted("Let's meet at three, no, actually four.", "Let's meet at 4.")
        assertAccepted("Send it to John, sorry, I mean Mike.", "Send it to Mike.")
        assertAccepted("The budget is five thousand dollars, no wait, six thousand dollars.", "The budget is $6,000.")
        assertAccepted("I think the answer is gonna be fine.", "I think the answer is going to be fine.")
        assertAccepted("Send it to rohan at example dot com.", "Send it to rohan@example.com.")
        assertAccepted("Push the branch to git hub.", "Push the branch to GitHub.")
        assertAccepted("Turn left on Main Street. Scratch that. Turn right on Main Street.", "Turn right on Main Street.")
        assertAccepted("Bullet point, fix the bug. Bullet point, update the docs.", "- Fix the bug\n- Update the docs")
    }

    func testRejectsAnAnswer() {
        assertRejected("What is the capital of France?", "The capital of France is Paris.")
        assertRejected("What's two plus two?", "Two plus two is four, which is a basic sum in arithmetic.")
        assertRejected("Write me a poem about cats.", "Soft paws upon the windowsill, a cat sits watching, calm and still.")
        assertRejected("Translate this into Spanish, please.", "Traduce esto al español, por favor.")
    }

    func testRejectsInventedContent() {
        assertRejected("Send the report on Friday.", "Send the report on Friday to Sarah in finance.")
        assertRejected(
            "The meeting went well and everyone agreed on the plan for next quarter.",
            "The meeting went well, the budget doubled, and everyone agreed to hire twelve engineers next quarter."
        )
    }

    func testRejectsDroppedContent() {
        assertRejected(
            "I spent the afternoon reading logs and the root cause is a slow query in the billing service.",
            "I spent the afternoon reading."
        )
        assertRejected("Please remember to call the bank before noon tomorrow.", "Please remember.")
    }

    func testRejectsEmptyOutputUnlessItWasAllFiller() {
        assertRejected("Send the report.", "")
        assertAccepted("Um, uh.", "")
    }

    func testRejectsRewriting() {
        assertRejected(
            "We should ship the release on Tuesday after the review.",
            "After the review on Tuesday, the release should be shipped by us."
        )
    }

    func testEditDistance() {
        XCTAssertEqual(CleanupGuard.editDistance("kitten", "sitting"), 3)
        XCTAssertEqual(CleanupGuard.editDistance("", "abc"), 3)
        XCTAssertEqual(CleanupGuard.editDistance("same", "same"), 0)
    }
}

/// A stand-in model that says whatever the test wants.
private final class CannedCleaner: TextCleaning {
    var reply: String?
    init(reply: String?) { self.reply = reply }
    func clean(_ raw: String) async -> String? { reply }
}

final class CleanupPipelineTests: XCTestCase {
    func testUsesTheModelWhenItBehaves() async {
        let pipeline = CleanupPipeline(model: CannedCleaner(reply: "Let's meet at 4."))
        let outcome = await pipeline.clean("Let's meet at three, no, actually four.")
        XCTAssertEqual(outcome.text, "Let's meet at 4.")
        XCTAssertEqual(outcome.source, .model)
        XCTAssertNil(outcome.rejection)
    }

    func testAnAnswerFromTheModelFallsBackToWhatWasSaid() async {
        let pipeline = CleanupPipeline(model: CannedCleaner(reply: "The capital of France is Paris."))
        let outcome = await pipeline.clean("What is the capital of France?")
        XCTAssertEqual(outcome.text, "What is the capital of France?")
        XCTAssertEqual(outcome.source, .rules)
        XCTAssertNotNil(outcome.rejection)
    }

    func testRulesTakeOverWithoutAModel() async {
        let pipeline = CleanupPipeline(model: nil)
        let outcome = await pipeline.clean("Um, let's meet at three, no, actually four.")
        XCTAssertEqual(outcome.text, "Let's meet at four.")
        XCTAssertEqual(outcome.source, .rules)
    }

    func testRulesTakeOverWhenTheModelGivesUp() async {
        let pipeline = CleanupPipeline(model: CannedCleaner(reply: nil))
        let outcome = await pipeline.clean("Um, sounds good.")
        XCTAssertEqual(outcome.text, "Sounds good.")
        XCTAssertEqual(outcome.source, .rules)
    }

    func testAllFillerIsNothing() async {
        let pipeline = CleanupPipeline(model: CannedCleaner(reply: "This should not be used."))
        let outcome = await pipeline.clean("Um, uh.")
        XCTAssertEqual(outcome.text, "")
    }

    func testEmptyIsNothing() async {
        let pipeline = CleanupPipeline(model: CannedCleaner(reply: "Hello there."))
        let outcome = await pipeline.clean("  ")
        XCTAssertEqual(outcome.text, "")
    }

    func testVocabularySpellingAppliesToEveryPath() async {
        let pipeline = CleanupPipeline(model: CannedCleaner(reply: "Push it to git hub."))
        pipeline.setVocabulary(["GitHub"])
        let outcome = await pipeline.clean("Push it to git hub.")
        XCTAssertEqual(outcome.text, "Push it to GitHub.")
    }

    func testFormattingRunsOnTheModelsText() async {
        let raw = "Bullet point, fix the bug. Bullet point, update the docs."
        let pipeline = CleanupPipeline(model: CannedCleaner(reply: raw))
        let outcome = await pipeline.clean(raw)
        XCTAssertEqual(outcome.text, "- Fix the bug\n- Update the docs")
    }
}

final class VocabularySpellingTests: XCTestCase {
    func testFixesCaseAndSpacing() {
        let spelling = VocabularySpelling(words: ["GitHub", "FluidAudio", "T3", "JSON"])
        XCTAssertEqual(spelling.apply(to: "push to github"), "push to GitHub")
        XCTAssertEqual(spelling.apply(to: "push to git hub now"), "push to GitHub now")
        XCTAssertEqual(spelling.apply(to: "it uses fluid audio"), "it uses FluidAudio")
        XCTAssertEqual(spelling.apply(to: "open t3 and t three"), "open T3 and T3")
        XCTAssertEqual(spelling.apply(to: "as json."), "as JSON.")
    }

    func testLeavesEverydayWordsAlone() {
        let spelling = VocabularySpelling(words: ["Pepper", "Swift"])
        XCTAssertEqual(spelling.apply(to: "add salt and pepper"), "add salt and pepper")
        XCTAssertEqual(spelling.apply(to: "a swift reply"), "a swift reply")
        XCTAssertEqual(spelling.apply(to: "Pepper pulls my notes"), "Pepper pulls my notes")
    }

    func testOnlyMatchesWholeWords() {
        let spelling = VocabularySpelling(words: ["T3"])
        XCTAssertEqual(spelling.apply(to: "st3p by st3p"), "st3p by st3p")
    }

    func testLowercaseWordsWithSpacesInside() {
        let spelling = VocabularySpelling(words: ["worktree"])
        XCTAssertEqual(spelling.apply(to: "in its own git work tree."), "in its own git worktree.")
    }
}

final class VocabularyGateTests: XCTestCase {
    private func everyday(_ word: String) -> Bool {
        ["plus", "the", "solar", "work", "tree", "route", "money"].contains(word.lowercased())
    }

    func testAllowsSpellingFixes() {
        XCTAssertTrue(VocabularyGate.allows(heard: "fluid audio", term: "FluidAudio", isEveryday: everyday))
        XCTAssertTrue(VocabularyGate.allows(heard: "work tree", term: "worktree", isEveryday: everyday))
        XCTAssertTrue(VocabularyGate.allows(heard: "copulet money", term: "Copper Money", isEveryday: everyday))
        XCTAssertTrue(VocabularyGate.allows(heard: "post-GAS", term: "Postgres", isEveryday: everyday))
    }

    func testAllowsMishearingsThatArentWords() {
        XCTAssertTrue(VocabularyGate.allows(heard: "E3", term: "T3", isEveryday: everyday))
        XCTAssertTrue(VocabularyGate.allows(heard: "postPAS", term: "Postgres", isEveryday: everyday))
    }

    func testRejectsOrdinaryWordsThatOnlySoundClose() {
        XCTAssertFalse(VocabularyGate.allows(heard: "2 plus", term: "Opus", isEveryday: everyday))
        XCTAssertFalse(VocabularyGate.allows(heard: "plus", term: "Opus", isEveryday: everyday))
        XCTAssertFalse(VocabularyGate.allows(heard: "the solar", term: "DiaSorin", isEveryday: everyday))
    }

    func testAppliesOnlyWhatPasses() {
        let result = VocabularyGate.apply(
            replacements: [(heard: "fluid audio", term: "FluidAudio"), (heard: "2 plus", term: "Opus")],
            to: "What's 2 plus 2 in fluid audio?",
            allowed: { self.everyday($0) == false && VocabularyGate.allows(heard: $0, term: $1, isEveryday: self.everyday) }
        )
        XCTAssertEqual(result, "What's 2 plus 2 in FluidAudio?")
    }
}
