import AppKit
@testable import Shades
import TestSupport
import XCTest

@MainActor
final class OffstageTests: XCTestCase {
    private final class KeyWindow: NSWindow {
        override var canBecomeKey: Bool { true }
    }

    private final class Opens: NSObject, NSMenuDelegate {
        var count = 0
        func menuWillOpen(_ menu: NSMenu) { count += 1 }
    }

    private let away = NSRect(x: -20_000, y: -20_000, width: 300, height: 200)
    private let motion = Motion.forced
    private let fix = "Set Offstage.isOn before the run makes its first window, as main.swift does for every run DevFlags.staysOffstage names, and show windows only through NSWindow's own methods."

    override func setUp() {
        super.setUp()
        Motion.forced = true
    }

    override func tearDown() {
        Offstage.isOn = false
        Motion.forced = motion
        super.tearDown()
    }

    private func whatAppKitDid<T>(_ read: () -> T) -> T {
        Offstage.isOn = false
        defer { Offstage.isOn = true }
        return read()
    }

    func testTheDemoAndEveryFlowStayOffstageUnlessYouAskToSeeThem() {
        XCTAssertTrue(DevFlags.staysOffstage(["shades", "--demo", "--no-script", "--commands", "steps.txt"]))
        XCTAssertTrue(DevFlags.staysOffstage(["shades", "--demo"]), "a worker can't forget a flag to keep it out of sight")
        XCTAssertTrue(DevFlags.staysOffstage(["Shades", "--ask", "What is this?", "--image", "made-up.png"]))
        XCTAssertTrue(DevFlags.staysOffstage(["Shades", "--hand-off", "Tidy up"]))
        XCTAssertTrue(DevFlags.staysOffstage(["Shades", "--fix", "The button"]))
        XCTAssertFalse(DevFlags.staysOffstage(["shades", "--demo", "--show"]), "a person asked to see it")
        XCTAssertFalse(DevFlags.staysOffstage(["/Applications/Shades.app/Contents/MacOS/Shades"]), "the installed app")
    }

    func testNothingARunTryingTheAppOutShowsCanBeSeenClickedOrTypedInto() {
        Offstage.isOn = true
        let quiet = QuietPanel(allowsKey: true)
        let window = KeyWindow(contentRect: away, styleMask: [.borderless], backing: .buffered, defer: true)
        let panel = NSPanel(contentRect: away, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        let cover = NSWindow(contentRect: away, styleMask: [.borderless], backing: .buffered, defer: false)
        let shows: [(String, NSWindow, () -> Void)] = [
            ("the Ask box fading in and taking the keyboard", quiet, { quiet.fadeIn(); quiet.makeKey() }),
            ("a window made key and ordered front", window, { window.makeKeyAndOrderFront(nil) }),
            ("a panel ordered front, as the phone's is", panel, { panel.orderFront(nil) }),
            ("a window ordered in above another", cover, { cover.order(.above, relativeTo: 0) }),
        ]
        for (name, shown, show) in shows {
            shown.setFrame(away, display: false)
            shown.alphaValue = 1
            shown.ignoresMouseEvents = false
            show()
            defer { shown.orderOut(nil) }
            XCTAssertTrue(shown.isVisible, "\(name) is showing as far as the run can tell")
            XCTAssertEqual(Offstage.alpha(of: shown), 1, "\(name) says how it would look on the screen")
            XCTAssertTrue(Offstage.takesClicks(shown), "\(name) says it would take clicks on the screen")
            XCTAssertFalse(Offstage.isSeen(shown), "\(name) shows on the screen. \(fix)")
            XCTAssertTrue(shown.ignoresMouseEvents, "\(name) takes a click. \(fix)")
            XCTAssertFalse(whatAppKitDid { shown.isKeyWindow }, "\(name) takes the keyboard. \(fix)")
        }
        XCTAssertFalse(NSApp.isActive, "nothing took the keyboard. \(fix)")
        XCTAssertNil(whatAppKitDid { NSApp.keyWindow }, "nothing took the keyboard. \(fix)")
    }

    func testAFadeThatAnimatesStaysClearAllTheWay() {
        Offstage.isOn = true
        Motion.forced = false
        let bubble = QuietPanel(allowsKey: true)
        bubble.setFrame(away, display: false)
        defer { bubble.orderOut(nil) }
        bubble.fadeIn()
        XCTAssertFalse(Offstage.isSeen(bubble), "the bubble shows on the screen as it starts to fade in. \(fix)")
        runMainLoop(until: { Offstage.alpha(of: bubble) == 1 })
        XCTAssertEqual(Offstage.alpha(of: bubble), 1, "the fade still runs")
        XCTAssertFalse(Offstage.isSeen(bubble), "the bubble shows on the screen once it's faded in. \(fix)")
        bubble.fadeOut()
        runMainLoop(until: { !bubble.isVisible })
        bubble.fadeIn()
        runMainLoop(until: { Offstage.alpha(of: bubble) == 1 })
        XCTAssertFalse(Offstage.isSeen(bubble), "the bubble shows on the screen coming back. \(fix)")
    }

    func testTheRunStillKnowsWhichWindowHasTheKeyboard() {
        Offstage.isOn = true
        let ask = QuietPanel(allowsKey: true)
        let bubble = QuietPanel(allowsKey: true)
        let cat = QuietPanel()
        for panel in [ask, bubble, cat] {
            panel.setFrame(away, display: false)
            panel.orderFrontRegardless()
        }
        defer { [ask, bubble, cat].forEach { $0.orderOut(nil) } }
        var resigned = 0
        let watch = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: ask, queue: nil) { _ in resigned += 1 }
        defer { NotificationCenter.default.removeObserver(watch) }

        ask.makeKey()
        XCTAssertTrue(ask.isKeyWindow)
        XCTAssertTrue(NSApp.keyWindow === ask, "so Tab and Copy go where they would")
        cat.makeKey()
        XCTAssertTrue(ask.isKeyWindow, "the cat never takes the keyboard")
        bubble.makeKey()
        XCTAssertFalse(ask.isKeyWindow)
        XCTAssertTrue(bubble.isKeyWindow)
        XCTAssertEqual(resigned, 1, "what watches for losing the keyboard hears it")
        bubble.orderOut(nil)
        XCTAssertFalse(bubble.isKeyWindow, "hiding a window takes the keyboard with it")
        XCTAssertNil(NSApp.keyWindow)
        bubble.orderFrontRegardless()
        XCTAssertFalse(bubble.isKeyWindow, "showing it again doesn't give it back")
        ask.makeKey()
        ask.close()
        ask.orderFrontRegardless()
        XCTAssertFalse(ask.isKeyWindow, "nor does closing it and showing it again, as The Kitty Litter's window closes")
    }

    func testAMenuNeverOpensOverYourScreen() {
        Offstage.isOn = true
        let window = NSWindow(contentRect: away, styleMask: [.borderless], backing: .buffered, defer: true)
        let menu = NSMenu()
        let opens = Opens()
        menu.delegate = opens
        menu.addItem(withTitle: "Settings…", action: nil, keyEquivalent: "")
        RunLoop.main.perform(inModes: [.eventTracking]) { menu.cancelTracking() }
        XCTAssertFalse(menu.popUp(positioning: nil, at: .zero, in: window.contentView))
        XCTAssertEqual(opens.count, 0, "a menu opened over the screen. \(fix)")
    }

    func testTheMenuBarItemStaysOutOfYourMenuBar() {
        Offstage.isOn = true
        XCTAssertNil(MenuBar().item, "the menu bar shows this run's cat. \(fix)")
    }

    func testALaunchedDemoNeverTakesTheActiveAppFromWhoeverIsTyping() throws {
        let journey = FileManager.default.temporaryDirectory.appendingPathComponent("front-\(UUID().uuidString).txt")
        try "front\nwait 3\nfront\nwindows\n".write(to: journey, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: journey) }
        let demo = Process()
        demo.executableURL = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("shades")
        demo.arguments = ["--demo", "--no-script", "--commands", journey.path]
        let printed = Pipe()
        demo.standardOutput = printed
        try demo.run()
        let lines = String(decoding: printed.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n")
        demo.waitUntilExit()
        let fronts = lines.filter { $0.hasPrefix("front ") }
        XCTAssertEqual(fronts.count, 2, "\(lines)")
        XCTAssertFalse(fronts.contains("front \(CatWords.appName)"), "as it launched and 3 seconds later: \(fronts)")
        XCTAssertTrue(lines.contains { $0.hasPrefix("state ") && $0.contains("active=false madeActive=0 ") }, "macOS never made it the active app, even for a moment: \(lines.filter { $0.hasPrefix("state ") })")
    }
}
