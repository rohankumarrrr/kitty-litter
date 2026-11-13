import AppKit
@testable import Shades
import ShadesCore
import XCTest

/// The mic in the Ask box and in The Kitty Litter's box.
@MainActor
final class MicTests: XCTestCase {
    func testVoiceOverCanPressTheMicAndHearsWhetherItsListening() {
        let composer = ChannelComposer(frame: NSRect(x: 0, y: 0, width: 600, height: 120))
        var pressed = 0
        composer.onMic = { pressed += 1 }
        XCTAssertEqual(composer.mic.accessibilityRole(), .button)
        XCTAssertEqual(composer.mic.accessibilityLabel(), "Speak")
        XCTAssertTrue(composer.mic.accessibilityPerformPress())
        XCTAssertEqual(pressed, 1)

        composer.mic.showListening(true)
        XCTAssertEqual(composer.mic.accessibilityLabel(), "Done speaking", "pressing it now finishes")
        XCTAssertTrue(composer.mic.isLit)
        composer.mic.showListening(false)
        XCTAssertEqual(composer.mic.accessibilityLabel(), "Speak")
    }

    func testEscWhileTheMicHearsYouForgetsWhatYouSaidAndLeavesThePaneOpen() {
        let composer = ChannelComposer(frame: NSRect(x: 0, y: 0, width: 600, height: 120))
        var stopped = 0, escaped = 0
        composer.onStopListening = { stopped += 1 }
        composer.onEscape = { escaped += 1 }
        composer.mic.showListening(true)
        _ = composer.textView(composer.textView, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        XCTAssertEqual(stopped, 1)
        XCTAssertEqual(escaped, 0)

        composer.mic.showListening(false)
        _ = composer.textView(composer.textView, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        XCTAssertEqual(escaped, 1, "otherwise Esc does what it always does")
    }

    func testTheMicNamesTheTalkKey() {
        XCTAssertEqual(CatWords.speakTip(talkKey: .rightOption), "Speak instead of typing, or hold Right Option")
        XCTAssertEqual(CatWords.speakTip(talkKey: .off), "Speak instead of typing")
    }

    func testTheMicsWordsDontRunUnderIt() {
        let composer = ChannelComposer(frame: NSRect(x: 0, y: 0, width: 600, height: 120))
        composer.show(.router, in: .general)
        composer.layoutSubtreeIfNeeded()
        let words = composer.textView.enclosingScrollView!.frame
        XCTAssertLessThanOrEqual(words.maxX, composer.mic.frame.minX, "the text stops before the mic")
        XCTAssertTrue(composer.bounds.contains(composer.mic.frame))
    }
}
