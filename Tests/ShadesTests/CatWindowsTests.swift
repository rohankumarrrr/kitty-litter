import AppKit
@testable import Shades
import ShadesContext
import ShadesCore
import XCTest

/// The cat's own windows beside macOS's: a card on the desktop like its widgets, an alert's buttons, and a popover that
/// comes and goes.
@MainActor
final class CatWindowsTests: XCTestCase {
    /// Somewhere no screen reaches, so a window a test shows is never on yours.
    private let away = NSRect(x: -20_000, y: -20_000, width: 800, height: 600)
    private let request = ApprovalRequest(id: "r", threadID: "steve-1", threadTitle: "Tidy up", kind: .command, summary: "npm test", createdAt: Date(timeIntervalSince1970: 1_000_000))
    private let motion = Motion.forced

    override func tearDown() {
        Motion.forced = motion
        super.tearDown()
    }

    private func buttons(_ view: BubbleView) -> [QuietButton] {
        view.subviews.compactMap { $0 as? QuietButton }.sorted { $0.frame.minX < $1.frame.minX }
    }

    private func bubble() -> BubbleController {
        let bubble = BubbleController()
        bubble.anchor = { [away] in (NSRect(x: away.midX, y: away.minY, width: 64, height: 64), away) }
        return bubble
    }

    /// Every bubble was lit the same, whoever was speaking, where each card on the desktop is lit in its own hue.
    func testTheBubbleIsLitByWhoeverIsSpeaking() {
        let view = BubbleView(frame: .zero)
        view.kittenColor = { $0 == "steve-1" ? Opal.kittens[6] : nil }
        _ = view.update(.approval(request, position: 1, total: 1), keepingWidth: false, limitHeight: 600)
        XCTAssertEqual(view.look, .card(.of(Opal.kittens[6])), "a kitten asking is lit in its colour")
        _ = view.update(.notice(caption: "Steve", text: "Done.", threadID: "steve-1"), keepingWidth: false, limitHeight: 600)
        XCTAssertEqual(view.look, .card(.of(Opal.kittens[6])), "and telling you how it went")
        _ = view.update(.reply(text: "The answer.", done: true, threadID: "steve-1", note: nil), keepingWidth: false, limitHeight: 600)
        XCTAssertEqual(view.look, .card(.shades), "an answer is Shades' own, whichever thread it opens")
        _ = view.update(.notice(caption: "Opus", text: "Done.", threadID: "frontier"), keepingWidth: false, limitHeight: 600)
        XCTAssertEqual(view.look, .card(.shades), "a thread no kitten owns is lit in Shades' hue")
    }

    /// Allow sat in the middle, and Allow for this session at the right, where a macOS alert puts what you most likely want.
    func testAnApprovalsAllowIsItsOnePrimaryAtTheRightAndAllowingMoreSitsApart() throws {
        let view = BubbleView(frame: .zero)
        _ = view.update(.approval(request, position: 1, total: 1), keepingWidth: false, limitHeight: 600)
        let row = buttons(view)
        XCTAssertEqual(row.map { $0.accessibilityLabel() }, ["Allow for this session", "Deny", "Allow"])
        XCTAssertEqual(row.filter { $0.style == .filled }.map { $0.accessibilityLabel() }, ["Allow"], "one primary")
        XCTAssertEqual(try XCTUnwrap(row.last).frame.maxX, view.body.maxX - 18, accuracy: 1, "at the right edge")
        XCTAssertGreaterThan(row[1].frame.minX - row[0].frame.maxX, 2 * (row[2].frame.minX - row[1].frame.maxX), "allowing more sits apart")
    }

    /// A rewrite's Replace was quiet and first, though putting it in place is why you asked for it.
    func testAnAnswersButtonsSitAtTheRightWithAtMostOnePrimary() throws {
        let view = BubbleView(frame: .zero)
        _ = view.update(.reply(text: "Shorter.", done: true, threadID: "t", note: nil, canReplace: true), keepingWidth: false, limitHeight: 600)
        XCTAssertEqual(buttons(view).map { $0.accessibilityLabel() }, ["Copy", "Open in T3", "Replace"])
        XCTAssertEqual(buttons(view).map(\.style), [.text, .plain, .filled], "Replace is what you most likely want")
        XCTAssertEqual(try XCTUnwrap(buttons(view).last).frame.maxX, view.body.maxX - 18, accuracy: 1)

        _ = view.update(.reply(text: "The answer.", done: true, threadID: "t", note: nil), keepingWidth: false, limitHeight: 600)
        XCTAssertEqual(buttons(view).map { $0.accessibilityLabel() }, ["Copy", "Open in T3"])
        XCTAssertFalse(buttons(view).contains { $0.style == .filled }, "an answer leans you toward nothing")
        XCTAssertEqual(try XCTUnwrap(buttons(view).last).frame.maxX, view.body.maxX - 18, accuracy: 1)
    }

    /// "Thinking." grew to the bubble's full width a moment after it showed, as its dots were drawn again.
    func testABubbleKeepsToItsWordsWidthWhenItsDrawnAgain() {
        let view = BubbleView(frame: .zero)
        let first = view.update(.thinking(note: nil), keepingWidth: false, limitHeight: 600)
        view.advanceThinking()
        let again = view.update(.thinking(note: nil), keepingWidth: true, limitHeight: 600)
        XCTAssertLessThan(first.width, 200)
        XCTAssertEqual(again.width, first.width)
    }

    /// The bubble popped in and vanished, where a popover or a notification comes and goes.
    func testTheBubbleFadesInAndOutUnlessReduceMotionIsOn() {
        Motion.forced = false
        let bubble = bubble()
        bubble.show(.line("Hello.", threadID: nil))
        XCTAssertTrue(bubble.panel.isVisible)
        XCTAssertLessThan(bubble.panel.alphaValue, 1, "fading in")
        bubble.hide()
        XCTAssertFalse(bubble.isVisible, "gone as far as anything else can tell")
        XCTAssertTrue(bubble.panel.isVisible, "while it fades out")
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        XCTAssertFalse(bubble.panel.isVisible)

        Motion.forced = true
        bubble.show(.line("Hello.", threadID: nil))
        XCTAssertEqual(bubble.panel.alphaValue, 1, "there at once with Reduce Motion on")
        bubble.hide()
        XCTAssertFalse(bubble.panel.isVisible, "and gone at once")
    }

    /// The pill came and went at once, as the bubble did.
    func testThePillFadesInAndOutUnlessReduceMotionIsOn() {
        Motion.forced = false
        let pill = SayPill()
        let cat = NSRect(x: away.midX, y: away.minY, width: 64, height: 64)
        pill.say("Purr", over: cat, in: away, seconds: nil)
        XCTAssertLessThan(pill.panel.alphaValue, 1)
        pill.hide()
        XCTAssertFalse(pill.isVisible)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        XCTAssertFalse(pill.panel.isVisible)

        Motion.forced = true
        pill.say("Purr", over: cat, in: away, seconds: nil)
        XCTAssertEqual(pill.panel.alphaValue, 1)
        pill.hide()
        XCTAssertFalse(pill.panel.isVisible)
    }

    /// Esc put an approval away, and a click already on its way could still land on Allow while it went.
    func testABubbleOnItsWayOutTakesNoClicks() throws {
        Motion.forced = false
        let bubble = bubble()
        var answers: [ApprovalDecision] = []
        bubble.view.onAction = { if case .approval(_, let decision) = $0 { answers.append(decision) } }
        func clickAllow() throws {
            bubble.view.setButtonsArmed(true)
            let allow = try XCTUnwrap(bubble.view.subviews.compactMap { $0 as? QuietButton }.first { $0.accessibilityLabel() == "Allow" })
            let point = allow.convert(NSPoint(x: allow.bounds.midX, y: allow.bounds.midY), to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: bubble.panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
                bubble.panel.sendEvent(event)
            }
        }
        bubble.show(.approval(request, position: 1, total: 1))
        try clickAllow()
        XCTAssertEqual(answers, [.accept], "a click while it's up allows")
        bubble.hide()
        try clickAllow()
        XCTAssertEqual(answers, [.accept], "and none while it goes")
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    }

    /// An error asking you to turn something on in System Settings had no way there.
    func testAnErrorThatNeedsASettingOffersToOpenIt() throws {
        let view = BubbleView(frame: .zero)
        var actions: [BubbleAction] = []
        view.onAction = { actions.append($0) }
        _ = view.update(.line("Copied", threadID: nil), keepingWidth: false, limitHeight: 600)
        XCTAssertTrue(buttons(view).isEmpty)
        _ = view.update(.line(CatWords.needsMicrophone, threadID: nil), keepingWidth: true, limitHeight: 600)
        let open = try XCTUnwrap(buttons(view).first { $0.accessibilityLabel() == "Open System Settings" })
        XCTAssertTrue(open.accessibilityPerformPress())
        XCTAssertEqual(actions, [.settings(.microphone)], "the Microphone page")
        _ = view.update(.line(CatWords.needsInputMonitoring, threadID: nil), keepingWidth: true, limitHeight: 600)
        XCTAssertTrue(try XCTUnwrap(buttons(view).first).accessibilityPerformPress())
        XCTAssertEqual(actions.last, .settings(.inputMonitoring))
    }

    /// Redo's ⇧⌘Z did nothing in the Ask box, though ⌘Z undid.
    func testTheBoxesRedoAsWellAsUndo() throws {
        func keys(_ modifiers: NSEvent.ModifierFlags, _ key: String) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: 6))
        }
        XCTAssertEqual(QuietPanel.editAction(for: try keys(.command, "z")), Selector(("undo:")))
        XCTAssertEqual(QuietPanel.editAction(for: try keys([.command, .shift], "Z")), Selector(("redo:")))
        XCTAssertNil(QuietPanel.editAction(for: try keys([.command, .option], "z")))
        XCTAssertNil(QuietPanel.editAction(for: try keys([.command, .shift], "C")))
    }
}
