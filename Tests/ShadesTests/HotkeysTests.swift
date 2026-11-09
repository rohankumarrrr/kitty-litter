import Carbon.HIToolbox
@testable import Shades
import XCTest

@MainActor
final class HotkeysTests: XCTestCase {
    func testShortcutsAreClaimedSoATakenOneIsNoticed() {
        XCTAssertEqual(Hotkeys.options, OptionBits(kEventHotKeyExclusive), "a shared claim on another app's shortcut succeeds, and the cat would never say it's taken")
    }

    func testADemoLeavesItsShortcutsToTheInstalledApp() {
        // A key nobody has, so claiming it for a moment can't get in anyone's way.
        let key = (keyCode: kVK_F19, modifiers: controlKey | optionKey | cmdKey | shiftKey)
        let demo = Hotkeys()
        demo.claimsKeys = false
        XCTAssertNotNil(demo.register(keyCode: key.keyCode, modifiers: key.modifiers) {}, "the demo carries on as if it had it, so it never says it's taken")
        let installed = Hotkeys()
        let id = installed.register(keyCode: key.keyCode, modifiers: key.modifiers) {}
        XCTAssertNotNil(id, "the installed app starting while a demo runs still gets it")
        id.map(installed.unregister)
    }

    func testMessagesLeavesTheShortcutsPeopleOftenGiveOtherAppsAlone() {
        XCTAssertEqual(Shortcut.messages.modifiers, controlKey | cmdKey)
        XCTAssertNotEqual(Shortcut.messages.keyCode, kVK_ANSI_M, "often Messages")
        XCTAssertNotEqual(Shortcut.messages.keyCode, kVK_ANSI_Q, "Lock Screen in macOS")
        XCTAssertEqual(Shortcut.messagesLabel, "⌃⌘B")
    }
}
