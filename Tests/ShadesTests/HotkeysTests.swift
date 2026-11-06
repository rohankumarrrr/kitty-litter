import Carbon.HIToolbox
@testable import Shades
import XCTest

@MainActor
final class HotkeysTests: XCTestCase {
    func testShortcutsAreClaimedSoATakenOneIsNoticed() {
        XCTAssertEqual(Hotkeys.options, OptionBits(kEventHotKeyExclusive), "a shared claim on another app's shortcut succeeds, and the cat would never say it's taken")
    }

    func testMessagesLeavesTheShortcutsPeopleOftenGiveOtherAppsAlone() {
        XCTAssertEqual(Shortcut.messages.modifiers, controlKey | cmdKey)
        XCTAssertNotEqual(Shortcut.messages.keyCode, kVK_ANSI_M, "often Messages")
        XCTAssertNotEqual(Shortcut.messages.keyCode, kVK_ANSI_K, "often Lock Screen")
        XCTAssertNotEqual(Shortcut.messages.keyCode, kVK_ANSI_Q, "Lock Screen in macOS")
        XCTAssertEqual(Shortcut.messagesLabel, "⌃⌘B")
    }
}
