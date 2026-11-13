import AppKit
@testable import Shades
import ShadesCore
import XCTest

/// The quiet buttons and checkbox: Tab reaches them only with Full Keyboard Access on and only in a window that already
/// has the keyboard, Space presses them, and pressing always shows. Each test calls what the key or click calls on the
/// control itself, never a made-up press posted to the system, since that would land on whatever's really on the desktop.
@MainActor
final class QuietControlsTests: XCTestCase {
    /// A window that says it has the keyboard or doesn't, since a test can't make a real one key.
    private final class Window: NSWindow {
        var key = false
        override var isKeyWindow: Bool { key }
    }

    private func window(with views: NSView...) -> Window {
        let window = Window(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        var x: CGFloat = 10
        for view in views {
            view.frame.origin = NSPoint(x: x, y: 10)
            x = view.frame.maxX + 10
            window.contentView?.addSubview(view)
        }
        return window
    }

    private func key(_ characters: String, _ type: NSEvent.EventType = .keyDown) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: characters == " " ? 49 : 36)!
    }

    private var mouseDown: NSEvent {
        NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 1, y: 1), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    private var mouseEntered: NSEvent {
        NSEvent.enterExitEvent(with: .mouseEntered, location: NSPoint(x: 1, y: 1), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
    }

    override func tearDown() async throws {
        QuietFocus.fullKeyboardAccess = { NSApplication.shared.isFullKeyboardAccessEnabled }
    }

    func testTabReachesAQuietControlOnlyWithFullKeyboardAccessInAWindowThatAlreadyHasTheKeyboard() {
        let button = QuietButton("Theme ▾")
        let checkbox = QuietCheckbox()
        checkbox.title = "Also send to #general"
        checkbox.sizeToFit()
        let window = window(with: button, checkbox)

        QuietFocus.fullKeyboardAccess = { true }
        window.key = true
        XCTAssertTrue(button.canBecomeKeyView)
        XCTAssertTrue(button.acceptsFirstResponder)
        XCTAssertTrue(checkbox.canBecomeKeyView)
        XCTAssertTrue(checkbox.acceptsFirstResponder)

        button.isHidden = true
        XCTAssertFalse(button.canBecomeKeyView, "Tab skips one that isn't showing, such as one folded under a message's More")
        button.isHidden = false

        window.key = false
        XCTAssertFalse(button.canBecomeKeyView, "focus never comes to a panel that isn't already key")
        XCTAssertFalse(button.acceptsFirstResponder)
        XCTAssertFalse(checkbox.canBecomeKeyView)
        XCTAssertFalse(checkbox.acceptsFirstResponder)

        QuietFocus.fullKeyboardAccess = { false }
        window.key = true
        XCTAssertFalse(button.canBecomeKeyView, "with keyboard navigation off it's as quiet as it always was")
        XCTAssertFalse(button.acceptsFirstResponder)
        XCTAssertFalse(checkbox.canBecomeKeyView)
        XCTAssertFalse(checkbox.acceptsFirstResponder)
    }

    func testTabStepsFromOneQuietControlToTheNext() {
        let pair = QuietButton("Pair a phone…", style: .text)
        let done = QuietButton("Done", style: .filled)
        let window = window(with: pair, done)
        QuietFocus.fullKeyboardAccess = { true }
        window.key = true

        window.recalculateKeyViewLoop()
        window.makeFirstResponder(pair)
        window.selectNextKeyView(nil)
        XCTAssertTrue(window.firstResponder === done)
        window.selectPreviousKeyView(nil)
        XCTAssertTrue(window.firstResponder === pair)
    }

    func testSpacePressesAFocusedButtonOnceItsLetGo() {
        var presses = 0
        let button = QuietButton("Allow") { presses += 1 }
        let window = window(with: button)
        QuietFocus.fullKeyboardAccess = { true }
        window.key = true
        window.makeFirstResponder(button)

        button.keyDown(with: key(" "))
        XCTAssertEqual(presses, 0, "it shows pressed while Space is down")
        button.keyUp(with: key(" ", .keyUp))
        XCTAssertEqual(presses, 1)

        button.isArmed = false
        button.keyDown(with: key(" "))
        button.keyUp(with: key(" ", .keyUp))
        XCTAssertEqual(presses, 1, "a disarmed one ignores Space too")
    }

    func testSpaceTicksAFocusedCheckbox() {
        var ticks: [Bool] = []
        let checkbox = QuietCheckbox()
        checkbox.title = "Also send to #general"
        checkbox.onChange = { ticks.append($0) }
        let window = window(with: checkbox)
        QuietFocus.fullKeyboardAccess = { true }
        window.key = true
        window.makeFirstResponder(checkbox)

        checkbox.keyDown(with: key(" "))
        XCTAssertTrue(checkbox.isOn)
        checkbox.keyDown(with: key(" "))
        XCTAssertEqual(ticks, [true, false])
    }

    func testAFocusedButtonDrawsARing() throws {
        let button = QuietButton("Theme ▾")
        let window = window(with: button)
        QuietFocus.fullKeyboardAccess = { true }
        window.key = true
        let plain = try XCTUnwrap(ChannelImages.png(of: button))

        window.makeFirstResponder(button)
        XCTAssertNotEqual(ChannelImages.png(of: button), plain)

        window.key = false
        XCTAssertEqual(ChannelImages.png(of: button), plain, "no ring once the window gives up the keyboard")
    }

    func testPressingAPlainButtonShowsMoreThanHoveringOverIt() throws {
        let button = QuietButton("Theme ▾", style: .plain)
        button.mouseEntered(with: mouseEntered)
        let hovering = try XCTUnwrap(ChannelImages.png(of: button))
        button.mouseDown(with: mouseDown)
        XCTAssertNotEqual(ChannelImages.png(of: button), hovering)
    }

    func testCopyPressedTwiceQuicklyStillGoesBackToCopy() throws {
        let copy = QuietButton("Copy", style: .text)
        let untouched = try XCTUnwrap(ChannelImages.png(of: QuietButton("Copy", style: .text)))

        copy.flash("Copied")
        copy.flash("Copied")
        XCTAssertNotEqual(ChannelImages.png(of: copy), untouched)
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        XCTAssertEqual(ChannelImages.png(of: copy), untouched)
    }

    func testEachAttachmentsRemoveButtonSaysWhichFileItTakesOff() {
        let chip = AttachmentChip()
        chip.show(name: "notes.pdf", thumbnail: nil)
        let remove = chip.subviews.compactMap { $0 as? QuietButton }.first
        XCTAssertEqual(remove?.accessibilityLabel(), "Remove notes.pdf")
    }
}
