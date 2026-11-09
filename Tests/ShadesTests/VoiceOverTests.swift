import AppKit
@testable import Shades
import ShadesCore
import XCTest

@MainActor
final class VoiceOverTests: XCTestCase {
    private let steve = Kitten(name: "Steve", role: "Professional", covers: "", folder: "/k/steve")
    private let at = Date(timeIntervalSince1970: 1_000_000)

    func testPressingTheCatWithVoiceOverDoesWhatAClickDoes() {
        let cat = CatController()
        var clicks = 0
        var menus: [NSPoint] = []
        cat.onClick = { clicks += 1 }
        cat.onMenu = { menus.append($0) }

        XCTAssertTrue(cat.view.accessibilityPerformPress())
        XCTAssertEqual(clicks, 1, "a click asks, so a press does too")
        XCTAssertTrue(cat.view.accessibilityPerformShowMenu())
        XCTAssertEqual(menus.count, 1, "the menu a right-click opens")
        XCTAssertTrue(menus.allSatisfy { cat.view.bounds.contains($0) }, "opened over the cat")
        XCTAssertEqual(clicks, 1)
    }

    func testTheCatIsNamedForWhatPressingItDoes() {
        let view = CatController().view
        XCTAssertEqual(view.accessibilityRole(), .button)
        XCTAssertEqual(view.accessibilityLabel(), "Ask Shades")
    }

    func testPressingAKittenWithVoiceOverOpensItsThread() {
        var opened: [String] = []
        let working = KittenRow(status: KittenStatus(kitten: steve, state: .working(sessions: 1), threadID: "t1"), renderer: CatRenderer())
        working.onPress = { opened.append($0) }
        XCTAssertTrue(working.accessibilityPerformPress())
        XCTAssertEqual(opened, ["t1"], "the same as clicking it")

        let new = KittenRow(status: KittenStatus(kitten: steve, state: .notSetUp), renderer: CatRenderer())
        new.onPress = { opened.append($0) }
        XCTAssertFalse(new.accessibilityPerformPress(), "a kitten with nothing to open is only words")
        XCTAssertEqual(opened, ["t1"])
    }

    func testVoiceOverHearsWhatTheBubbleShowsAndNothingMore() {
        let approval = ApprovalRequest(id: "r", threadID: "t", threadTitle: "Work", kind: .command, summary: "npm test", createdAt: at)
        let shown: [BubbleContent] = [
            .thinking(note: "Looking"),
            .reply(text: "Whole answer.", done: true, threadID: "t", note: "From Steve"),
            .line("Can't reach T3 Code", threadID: nil),
            .notice(caption: "Asking: Work", text: "Which one?", threadID: "t", asks: true),
            .approval(approval, position: 1, total: 2),
            .inbox("2 things while you were away"),
        ]
        for content in shown {
            let words = content.words()
            XCTAssertEqual(content.spoken, [words.caption, words.counter, words.heading, words.body].compactMap { $0 }.joined(separator: "\n"))
        }
        XCTAssertEqual(BubbleContent.approval(approval, position: 1, total: 2).spoken, "Work\n1 of 2\nWants to run this:\nnpm test")
        XCTAssertEqual(BubbleContent.thinking(note: nil).spoken, "Thinking", "without the dots that come and go")
        XCTAssertNil(BubbleContent.listening("half a sentence").spoken, "nothing while you talk, so the microphone doesn't hear it")
        XCTAssertNil(BubbleContent.reply(text: "Half", done: false, threadID: nil, note: nil).spoken, "an answer is read once it's whole")
    }

    /// Somewhere no screen reaches, so a window a test shows is never on yours.
    private let away = NSRect(x: -20_000, y: -20_000, width: 800, height: 600)

    func testTheBubbleSaysEachThingOnceAsItShows() {
        var said: [String] = []
        BubbleController.onAnnounce = { words, priority in said.append(priority == .high ? "at once: \(words)" : words) }
        defer { BubbleController.onAnnounce = nil }
        let bubble = BubbleController()
        bubble.anchor = { [away] in (NSRect(x: away.midX, y: away.minY, width: 64, height: 64), away) }
        defer { bubble.hide() }
        let approval = ApprovalRequest(id: "r", threadID: "t", threadTitle: "Work", kind: .command, summary: "ls", createdAt: at)
        let answer = BubbleContent.reply(text: "The answer.", done: true, threadID: nil, note: nil)

        bubble.show(.thinking(note: nil))
        bubble.show(.thinking(note: nil))
        bubble.show(.reply(text: "The ans", done: false, threadID: nil, note: nil))
        bubble.show(answer)
        bubble.show(.approval(approval, position: 1, total: 1))
        bubble.show(answer)
        XCTAssertEqual(said, ["Thinking", "The answer.", "at once: Work\nWants to run this:\nls"], "the answer coming back after the approval isn't read again")

        bubble.show(.thinking(note: nil))
        bubble.show(answer)
        bubble.show(.listening("half a sentence"))
        XCTAssertEqual(said.suffix(2), ["Thinking", "The answer."], "asking again starts afresh")
    }

    func testThePairingPictureIsNamed() throws {
        let pairing = PairingPanel()
        pairing.show(PhonePairingCard(address: "http://example.test", code: "123456"), centeredIn: away)
        defer { pairing.hide() }
        func images(in view: NSView) -> [NSImageView] { (view as? NSImageView).map { [$0] } ?? view.subviews.flatMap(images) }
        let picture = try XCTUnwrap(images(in: try XCTUnwrap(pairing.panel.contentView)).first)
        XCTAssertEqual(picture.accessibilityLabel(), "QR code to pair your phone")
    }

    func testCopyingFromTheBubbleSaysCopied() throws {
        var said: [String] = []
        BubbleController.onAnnounce = { words, _ in said.append(words) }
        defer { BubbleController.onAnnounce = nil }
        let view = BubbleView(frame: .zero)
        var copied: [String] = []
        view.onAction = { if case .copy(let text) = $0 { copied.append(text) } }
        _ = view.update(.reply(text: "Answer.", done: true, threadID: nil, note: nil), keepingWidth: false, limitHeight: 400)
        let copy = try XCTUnwrap(view.subviews.compactMap { $0 as? QuietButton }.first { $0.accessibilityLabel() == "Copy" })
        XCTAssertTrue(copy.accessibilityPerformPress())
        XCTAssertEqual(copied, ["Answer."])
        XCTAssertEqual(said, ["Copied"], "the button only flashes the word, so VoiceOver is told it")
    }

    func testOnlyWhatWaitsOnYouInterrupts() {
        let approval = ApprovalRequest(id: "r", threadID: "t", threadTitle: "Work", kind: .command, summary: "ls", createdAt: at)
        XCTAssertTrue(BubbleContent.approval(approval, position: 1, total: 1).isUrgent)
        XCTAssertTrue(BubbleContent.notice(caption: "Asking: Work", text: "Which one?", threadID: "t", asks: true).isUrgent)
        XCTAssertFalse(BubbleContent.notice(caption: "Steve", text: "Done.", threadID: "t").isUrgent)
        XCTAssertFalse(BubbleContent.reply(text: "Hi", done: true, threadID: nil, note: nil).isUrgent)
        XCTAssertFalse(BubbleContent.line("Copied", threadID: nil).isUrgent)
    }
}
