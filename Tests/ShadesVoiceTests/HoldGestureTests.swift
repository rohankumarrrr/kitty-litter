import CoreGraphics
import ShadesCore
@testable import ShadesVoice
import XCTest

final class HoldGestureTests: XCTestCase {
    private var gesture = HoldGesture()

    override func setUp() {
        gesture = HoldGesture()
    }

    func testAHoldPressesAtOnceAndReleasesOnLettingGo() {
        XCTAssertEqual(gesture.keyChanged(.rightOption, isDown: true, otherModifiers: false, at: 10), .press(.rightOption))
        XCTAssertEqual(gesture.keyChanged(.rightOption, isDown: false, otherModifiers: false, at: 12), .release(.rightOption))
    }

    func testATapIsCalledOff() {
        XCTAssertEqual(gesture.keyChanged(.fn, isDown: true, otherModifiers: false, at: 10), .press(.fn))
        XCTAssertEqual(gesture.keyChanged(.fn, isDown: false, otherModifiers: false, at: 10.1), .cancel(.fn))
    }

    func testJustOverTheTapThresholdCounts() {
        _ = gesture.keyChanged(.fn, isDown: true, otherModifiers: false, at: 10)
        XCTAssertEqual(gesture.keyChanged(.fn, isDown: false, otherModifiers: false, at: 10.2), .release(.fn))
    }

    func testAKeySoonAfterPressingIsAShortcut() {
        _ = gesture.keyChanged(.rightOption, isDown: true, otherModifiers: false, at: 10)
        XCTAssertEqual(gesture.otherKeyPressed(at: 10.2), .cancel(.rightOption))
        // Letting go afterwards doesn't fire anything else.
        XCTAssertNil(gesture.keyChanged(.rightOption, isDown: false, otherModifiers: false, at: 10.4))
        XCTAssertNil(gesture.activeKey)
    }

    func testAKeyLongAfterPressingDoesNotLoseWhatYouSaid() {
        _ = gesture.keyChanged(.fn, isDown: true, otherModifiers: false, at: 10)
        XCTAssertNil(gesture.otherKeyPressed(at: 13))
        XCTAssertEqual(gesture.keyChanged(.fn, isDown: false, otherModifiers: false, at: 15), .release(.fn))
    }

    func testEscapeCancelsAtAnyTime() {
        _ = gesture.keyChanged(.fn, isDown: true, otherModifiers: false, at: 10)
        XCTAssertEqual(gesture.escapePressed(), .cancel(.fn))
        XCTAssertNil(gesture.escapePressed())
        XCTAssertNil(gesture.keyChanged(.fn, isDown: false, otherModifiers: false, at: 20))
    }

    func testPressingWhileHoldingAnotherModifierIsIgnored() {
        XCTAssertNil(gesture.keyChanged(.rightOption, isDown: true, otherModifiers: true, at: 10))
        XCTAssertNil(gesture.activeKey)
        XCTAssertNil(gesture.keyChanged(.rightOption, isDown: false, otherModifiers: false, at: 12))
    }

    func testASecondHoldKeyIsAChord() {
        _ = gesture.keyChanged(.fn, isDown: true, otherModifiers: false, at: 10)
        XCTAssertEqual(gesture.keyChanged(.rightOption, isDown: true, otherModifiers: false, at: 10.3), .cancel(.fn))
        XCTAssertNil(gesture.keyChanged(.rightOption, isDown: false, otherModifiers: false, at: 10.5))
        XCTAssertNil(gesture.keyChanged(.fn, isDown: false, otherModifiers: false, at: 11))
    }

    func testASecondHoldKeyLaterKeepsTheFirstGoing() {
        _ = gesture.keyChanged(.fn, isDown: true, otherModifiers: false, at: 10)
        XCTAssertNil(gesture.keyChanged(.rightOption, isDown: true, otherModifiers: false, at: 13))
        XCTAssertNil(gesture.keyChanged(.rightOption, isDown: false, otherModifiers: false, at: 13.5))
        XCTAssertEqual(gesture.keyChanged(.fn, isDown: false, otherModifiers: false, at: 15), .release(.fn))
    }

    func testAMissedReleaseEndsTheTakeNormally() {
        _ = gesture.keyChanged(.fn, isDown: true, otherModifiers: false, at: 10)
        XCTAssertEqual(gesture.releaseWasMissed(), .release(.fn))
        XCTAssertNil(gesture.activeKey)
        XCTAssertNil(gesture.releaseWasMissed())
    }

    func testAMissedReleaseAfterCancelDoesNothing() {
        _ = gesture.keyChanged(.fn, isDown: true, otherModifiers: false, at: 10)
        _ = gesture.otherKeyPressed(at: 10.1)
        XCTAssertNil(gesture.releaseWasMissed())
    }

    func testARepeatedDownEventDoesNotStickTheKey() {
        _ = gesture.keyChanged(.fn, isDown: true, otherModifiers: false, at: 10)
        XCTAssertNil(gesture.keyChanged(.fn, isDown: true, otherModifiers: false, at: 10.5))
        XCTAssertEqual(gesture.keyChanged(.fn, isDown: false, otherModifiers: false, at: 11), .release(.fn))
        XCTAssertNil(gesture.activeKey)
    }

    func testIdleKeysDoNothing() {
        XCTAssertNil(gesture.otherKeyPressed(at: 1))
        XCTAssertNil(gesture.escapePressed())
        XCTAssertNil(gesture.keyChanged(.fn, isDown: false, otherModifiers: false, at: 1))
    }

    func testPressingAgainAfterAChordWorks() {
        _ = gesture.keyChanged(.rightOption, isDown: true, otherModifiers: false, at: 10)
        _ = gesture.otherKeyPressed(at: 10.1)
        _ = gesture.keyChanged(.rightOption, isDown: false, otherModifiers: false, at: 10.2)
        XCTAssertEqual(gesture.keyChanged(.rightOption, isDown: true, otherModifiers: false, at: 20), .press(.rightOption))
    }
}

final class KeyCodesTests: XCTestCase {
    private func flags(_ raw: UInt64) -> CGEventFlags { CGEventFlags(rawValue: raw) }

    func testLeftAndRightAreDifferentKeys() {
        XCTAssertEqual(KeyCodes.key(for: 61), .rightOption)
        XCTAssertNil(KeyCodes.key(for: 58))
        XCTAssertEqual(KeyCodes.key(for: 54), .rightCommand)
        XCTAssertNil(KeyCodes.key(for: 55))
        XCTAssertEqual(KeyCodes.key(for: 62), .rightControl)
        XCTAssertNil(KeyCodes.key(for: 59))
        XCTAssertEqual(KeyCodes.key(for: 63), .fn)
    }

    func testRightOptionUsesItsDeviceBit() {
        // Left Option held and right Option up: the shared flag is set, but the right one isn't down.
        let leftOnly = flags(CGEventFlags.maskAlternate.rawValue | 0x20)
        XCTAssertFalse(KeyCodes.isDown(.rightOption, flags: leftOnly))
        let right = flags(CGEventFlags.maskAlternate.rawValue | 0x40)
        XCTAssertTrue(KeyCodes.isDown(.rightOption, flags: right))
    }

    func testRightCommandAndControlUseTheirDeviceBits() {
        XCTAssertTrue(KeyCodes.isDown(.rightCommand, flags: flags(CGEventFlags.maskCommand.rawValue | 0x10)))
        XCTAssertFalse(KeyCodes.isDown(.rightCommand, flags: flags(CGEventFlags.maskCommand.rawValue | 0x08)))
        XCTAssertTrue(KeyCodes.isDown(.rightControl, flags: flags(CGEventFlags.maskControl.rawValue | 0x2000)))
        XCTAssertFalse(KeyCodes.isDown(.rightControl, flags: flags(CGEventFlags.maskControl.rawValue | 0x01)))
    }

    func testFnUsesItsFlag() {
        XCTAssertTrue(KeyCodes.isDown(.fn, flags: .maskSecondaryFn))
        XCTAssertFalse(KeyCodes.isDown(.fn, flags: []))
    }

    func testOtherModifiers() {
        XCTAssertFalse(KeyCodes.otherModifiersDown(besides: .rightOption, flags: flags(0x40)))
        XCTAssertTrue(KeyCodes.otherModifiersDown(besides: .rightOption, flags: flags(0x40 | 0x08)))
        XCTAssertTrue(KeyCodes.otherModifiersDown(besides: .fn, flags: flags(0x02)))
        XCTAssertFalse(KeyCodes.otherModifiersDown(besides: .fn, flags: .maskSecondaryFn))
        XCTAssertTrue(KeyCodes.otherModifiersDown(besides: .rightCommand, flags: .maskSecondaryFn))
    }

    func testOffHasNoKey() {
        XCTAssertNil(KeyCodes.code(for: .off))
        XCTAssertFalse(KeyCodes.isDown(.off, flags: flags(0xFFFF)))
    }
}

/// Runs real CGEvents through the monitor's handler, without a tap or any permission.
final class KeyHoldMonitorEventTests: XCTestCase {
    private func flagsEvent(code: CGKeyCode, flags: UInt64) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!
        event.type = .flagsChanged
        event.flags = CGEventFlags(rawValue: flags)
        return event
    }

    func testDistinguishesLeftAndRightOption() throws {
        let monitor = KeyHoldMonitor()
        var pressed: [HoldKey] = []
        var released: [HoldKey] = []
        monitor.onPress = { pressed.append($0) }
        monitor.onRelease = { released.append($0) }
        monitor.setKeysForTesting([.rightOption])

        // Left Option does nothing.
        monitor.handle(type: .flagsChanged, event: flagsEvent(code: 58, flags: CGEventFlags.maskAlternate.rawValue | 0x20))
        monitor.handle(type: .flagsChanged, event: flagsEvent(code: 58, flags: 0))
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertTrue(pressed.isEmpty)

        // Right Option presses.
        monitor.handle(type: .flagsChanged, event: flagsEvent(code: 61, flags: CGEventFlags.maskAlternate.rawValue | 0x40))
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(pressed, [.rightOption])
        monitor.stop()
        XCTAssertTrue(released.isEmpty)
    }

    func testChordCancels() throws {
        let monitor = KeyHoldMonitor()
        var cancelled: [HoldKey] = []
        var released: [HoldKey] = []
        monitor.onCancel = { cancelled.append($0) }
        monitor.onRelease = { released.append($0) }
        monitor.setKeysForTesting([.rightOption])

        let down = flagsEvent(code: 61, flags: CGEventFlags.maskAlternate.rawValue | 0x40)
        monitor.handle(type: .flagsChanged, event: down)
        let letter = CGEvent(keyboardEventSource: nil, virtualKey: 14, keyDown: true)!
        letter.timestamp = down.timestamp
        monitor.handle(type: .keyDown, event: letter)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(cancelled, [.rightOption])
        XCTAssertTrue(released.isEmpty)
        monitor.stop()
    }
}
