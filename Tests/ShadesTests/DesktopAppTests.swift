import AppKit
@testable import Shades
@testable import ShadesContext
import ShadesCore
import XCTest

@MainActor
final class DesktopAppTests: XCTestCase {
    private let steve = Kitten(name: "Steve Pawsniak", role: "Professional", covers: "", folder: "/k/steve")
    private let at = Date(timeIntervalSince1970: 1_000_000)
    private var stage: FakeStage!
    private var inserter: FakeInserter!
    private var controller: AppController!

    override func setUp() async throws {
        stage = FakeStage(log: Log())
        inserter = FakeInserter()
        controller = makeController()
    }

    private func makeController(inbox: Inbox = Inbox(since: .distantPast)) -> AppController {
        AppController(
            dependencies: AppDependencies(
                backend: FakeBackend(),
                context: FakeContext(log: stage.log),
                voice: FakeVoice(),
                inserter: inserter,
                keys: FakeKeys(),
                settings: Settings(),
                saveSettings: { _ in },
                kittens: { [steve] in [steve] },
                inbox: inbox
            ),
            stage: stage,
            now: { [at] in at }
        )
    }

    private func menuBar() -> MenuBar {
        let bar = MenuBar()
        bar.onAsk = { [unowned controller] in controller!.askPressed() }
        bar.onFix = { [unowned controller] in controller!.fixPressed() }
        bar.onKittens = { [unowned controller] in controller!.kittensPressed() }
        bar.onMessages = { [unowned controller] in controller!.channelsPressed() }
        bar.messagesSummary = { [unowned controller] in controller!.messagesMenuLine }
        bar.onSettings = { [unowned controller] in controller!.settingsPressed() }
        bar.isDoNotDisturb = { [unowned controller] in controller!.settings.doNotDisturb }
        bar.onDoNotDisturb = { [unowned controller] in controller!.doNotDisturbPressed() }
        bar.canPairPhone = { false }
        bar.lockdownKittens = { [unowned controller] in controller!.loadKittens() }
        bar.lockedDownKitten = { [unowned controller] in controller!.settings.lockdown?.kitten }
        bar.onLockdown = { [unowned controller] in controller!.lockdownPicked($0) }
        bar.held = [.ask, .fix, .messages]
        return bar
    }

    private func settle() async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in DispatchQueue.main.async { done.resume() } }
        await controller.flow?.value
        await controller.voiceTask?.value
    }

    private func item(_ path: String..., in menu: NSMenu) throws -> NSMenuItem {
        var menu = menu
        var found: NSMenuItem?
        for title in path {
            let row = try XCTUnwrap(menu.items.first { $0.title == title }, "no item [\(title)]")
            found = row
            if let submenu = row.submenu {
                menu.delegate?.menuWillOpen?(menu)
                submenu.delegate?.menuWillOpen?(submenu)
                menu = submenu
            }
        }
        return try XCTUnwrap(found)
    }

    private func choose(_ path: String..., in main: NSMenu) async throws {
        var menu = main
        menu.delegate?.menuWillOpen?(menu)
        for title in path.dropLast() {
            menu = try XCTUnwrap(menu.items.first { $0.title.hasPrefix(title) }?.submenu, "no menu [\(title)]")
            menu.delegate?.menuWillOpen?(menu)
        }
        let row = try XCTUnwrap(menu.items.first { $0.title == path.last }, "no item [\(path.last ?? "")]")
        XCTAssertFalse(row.isHidden, row.title)
        menu.update()
        XCTAssertTrue(row.isEnabled, row.title)
        menu.performActionForItem(at: menu.index(of: row))
        await settle()
    }

    private func everyItem(in menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { [$0] + ($0.submenu.map(everyItem) ?? []) }
    }

    private func press(_ key: String, _ modifiers: NSEvent.ModifierFlags, in main: NSMenu) async throws {
        let matching = everyItem(in: main).filter { $0.keyEquivalent == key && $0.keyEquivalentModifierMask == modifiers }
        XCTAssertEqual(matching.count, 1, "one item answers \(modifiers) \(key)")
        let row = try XCTUnwrap(matching.first)
        let menu = try XCTUnwrap(row.menu)
        menu.update()
        XCTAssertTrue(row.isEnabled)
        menu.performActionForItem(at: menu.index(of: row))
        await settle()
    }

    func testTheKittyLitterIsAMainWindowLikeAnyMacApps() {
        let window = ChannelsMainWindow()
        XCTAssertTrue(ChannelsMainWindow.superclass() == NSWindow.self, "a window and not a panel, so a click into it brings the app forward")
        XCTAssertTrue(window.canBecomeKey)
        XCTAssertTrue(window.styleMask.isSuperset(of: [.titled, .closable, .miniaturizable, .resizable]), "minimizes to the Dock")
        XCTAssertTrue(window.collectionBehavior.contains(.primary), "a stage of its own in Stage Manager")
        XCTAssertTrue(window.collectionBehavior.contains(.managed), "in Mission Control")
        XCTAssertTrue(window.collectionBehavior.contains(.participatesInCycle), "in ⌘`")
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenPrimary), "goes full screen")
        XCTAssertFalse(window.collectionBehavior.contains(.moveToActiveSpace), "stays on its Space, as windows do")
        XCTAssertFalse(window.isExcludedFromWindowsMenu, "in the Window menu")
        XCTAssertTrue(window.canHide, "⌘H hides it")
        XCTAssertFalse(window.hidesOnDeactivate)
        XCTAssertFalse(window.isReleasedWhenClosed, "closing it keeps it, as Slack's does")
        XCTAssertEqual(window.level, .normal)
        XCTAssertEqual(window.title, CatWords.appName, "what the Window menu and Mission Control call it")
    }

    func testTheDemosWindowNeverActivatesSoItNeverTakesYourDesktop() {
        let panel = ChannelsPanel()
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.becomesKeyOnlyIfNeeded)
        XCTAssertTrue(panel.collectionBehavior.contains(.ignoresCycle))
    }

    func testOnlyARegularAppGetsTheMainWindowAndComesForward() {
        XCTAssertNotEqual(NSApplication.shared.activationPolicy(), .regular, "tests never bring themselves forward")
        XCTAssertNotEqual(NSApplication.shared.activationPolicy(), .accessory)
        XCTAssertTrue(ChannelsWindow().window is ChannelsMainWindow, "what the installed app opens")
    }

    func testWhatFloatsWithTheCatStaysOnEveryStageAndNeverHidesOrActivates() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let floating: [NSPanel] = [QuietPanel(), QuietPanel(allowsKey: true), QuietPanel(shadow: false), RegionPanel(screen: screen)]
        for panel in floating {
            let name = "\(type(of: panel))"
            XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel), name)
            XCTAssertFalse(panel.canBecomeMain, name)
            XCTAssertFalse(panel.canHide, "\(name): ⌘H on the app, and Hide Others from another, leave it")
            XCTAssertFalse(panel.hidesOnDeactivate, name)
            XCTAssertEqual(panel.collectionBehavior, .floatsOverEverything, name)
        }
        let floats = NSWindow.CollectionBehavior.floatsOverEverything
        XCTAssertTrue(floats.contains(.canJoinAllApplications), "on whichever stage is in front")
        XCTAssertTrue(floats.contains(.canJoinAllSpaces))
        XCTAssertTrue(floats.contains(.stationary), "out of Mission Control")
        XCTAssertTrue(floats.contains(.ignoresCycle), "out of ⌘`")
        XCTAssertFalse(floats.contains(.primary))
    }

    func testWithTheKittyLitterInFrontTheCatLooksAtTheAppBehindIt() {
        let me: pid_t = 10, editor: pid_t = 20, browser: pid_t = 30
        func window(_ owner: pid_t, layer: Int = 0) -> [String: Any] {
            [kCGWindowOwnerPID as String: owner, kCGWindowLayer as String: layer]
        }
        let stack = [window(me, layer: 25), window(me), window(1, layer: 24), window(editor), window(browser)]
        XCTAssertEqual(FrontApp.pid(frontmost: me, me: me, windows: stack), editor, "its own windows, the cat's included, are passed over")
        XCTAssertEqual(FrontApp.pid(frontmost: browser, me: me, windows: stack), browser, "with another app active, that's the one")
        XCTAssertNil(FrontApp.pid(frontmost: me, me: me, windows: [window(me)]), "nothing of anyone else's to look at")
    }

    func testDictatingWhileTheKittyLitterIsInFrontTypesIntoItsBoxAndNeverPastes() async {
        stage.isFrontmost = true
        stage.ownBoxTakesTyping = true
        controller.dictateDown()
        await controller.dictateUp()
        XCTAssertEqual(stage.typedInOwnBox, ["What is this?"])
        XCTAssertTrue(inserter.inserted.isEmpty, "nothing goes through the clipboard or Accessibility into its own window")
    }

    func testDictatingWhileTheKittyLitterIsInFrontWithNoBoxTypesNowhere() async {
        stage.isFrontmost = true
        controller.dictateDown()
        await controller.dictateUp()
        XCTAssertTrue(stage.typedInOwnBox.isEmpty)
        XCTAssertTrue(inserter.inserted.isEmpty)
        XCTAssertEqual(stage.bubble, .line(CatWords.noBoxToTypeIn, threadID: nil))
    }

    func testDictatingInAnotherAppTypesThere() async {
        controller.dictateDown()
        await controller.dictateUp()
        XCTAssertEqual(inserter.inserted, ["What is this?"])
        XCTAssertTrue(stage.typedInOwnBox.isEmpty)
    }

    func testTheDockBadgeIsTheMenusCountOfWhatNeedsYou() {
        var inbox = Inbox(since: .distantPast)
        for (id, decision) in [("d1", "Ship it?"), ("d2", "Merge it?")] {
            let thread = AgentThread(id: "t-\(id)", title: "Work", projectTitle: steve.name, status: .completed, model: "m", updatedAt: at, projectPath: steve.folder)
            inbox.flag(decision, from: thread, at: at, id: id)
        }
        controller = makeController(inbox: inbox)
        controller.startInbox()
        XCTAssertEqual(stage.needsYouBadge, 2)
        XCTAssertEqual(controller.messagesMenuLine, "2 need you", "the same count the menu shows")

        controller.inboxAction(.done(id: "d1"))
        XCTAssertEqual(stage.needsYouBadge, 1)
        controller.inboxAction(.done(id: "d2"))
        XCTAssertEqual(stage.needsYouBadge, 0, "no badge once nothing needs you")
    }

    func testClickingTheDockIconOpensTheKittyLitter() {
        let delegate = AppDelegate(controller: controller, menuBar: menuBar())
        XCTAssertFalse(delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: true), "the cat is always showing, so that's never the question")
        XCTAssertEqual(stage.channelsShown.count, 1)
        stage.isChannelsCovered = true
        _ = delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: true)
        XCTAssertEqual(stage.channelsShown.count, 2, "open behind your work, it comes to the front")
    }

    func testSwitchingToTheAppOpensItsWindowUnlessItStartedAtLogin() throws {
        let delegate = AppDelegate(controller: controller, menuBar: menuBar())
        delegate.applicationDidBecomeActive(Notification(name: NSApplication.didBecomeActiveNotification))
        XCTAssertEqual(stage.channelsShown.count, 1, "⌘Tab, or opening it from the Dock or Finder, shows its window")
        delegate.applicationDidBecomeActive(Notification(name: NSApplication.didBecomeActiveNotification))
        XCTAssertEqual(stage.channelsShown.count, 1, "already open, so nothing more happens")

        stage.hideChannels()
        let atLogin = AppDelegate(controller: controller, menuBar: menuBar())
        atLogin.launched(by: try loginEvent())
        atLogin.applicationDidBecomeActive(Notification(name: NSApplication.didBecomeActiveNotification))
        XCTAssertEqual(stage.channelsShown.count, 1, "starting at login brings up the cat and no window")
        _ = atLogin.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: true)
        XCTAssertEqual(stage.channelsShown.count, 2, "the Dock icon still opens it")
    }

    private func loginEvent(_ data: AEKeyword = keyAELaunchedAsLogInItem) throws -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenApplication), targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(enumCode: data), forKeyword: AEKeyword(keyAEPropData))
        return event
    }

    func testOnlyALoginItemsLaunchCountsAsALoginLaunch() throws {
        XCTAssertTrue(AppDelegate.isLoginLaunch(try loginEvent()))
        XCTAssertFalse(AppDelegate.isLoginLaunch(try loginEvent(keyAELaunchedAsServiceItem)))
        XCTAssertFalse(AppDelegate.isLoginLaunch(NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenApplication), targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))), "a plain open from the Dock or Finder")
        XCTAssertFalse(AppDelegate.isLoginLaunch(nil), "started from a terminal")
    }

    func testTheDockMenuOffersAskFixAndDoNotDisturb() async throws {
        let bar = menuBar()
        let delegate = AppDelegate(controller: controller, menuBar: bar)
        let dock = try XCTUnwrap(delegate.applicationDockMenu(NSApplication.shared))
        XCTAssertEqual(dock.items.map(\.title), ["Ask…", "Fix What I'm Looking At", "", CatWords.doNotDisturb])
        try await choose("Ask…", in: dock)
        XCTAssertNotNil(stage.input, "the Ask box opens")
        stage.hideInput()
        try await choose("Fix What I'm Looking At", in: dock)
        XCTAssertTrue(stage.log.all.contains("pickRegion"))
        try await choose(CatWords.doNotDisturb, in: dock)
        XCTAssertTrue(controller.settings.doNotDisturb)
        XCTAssertEqual(try XCTUnwrap(delegate.applicationDockMenu(NSApplication.shared)).items.last?.state, .on, "ticked while it's on")
    }

    func testTheSelfCheckSaysWhenTheDockCallsItSomethingElse() throws {
        XCTAssertEqual(HealthCheck.findings(from: HealthFacts(shownName: CatWords.appName)).first { $0.check == "name" }?.ok, true)
        let wrong = try XCTUnwrap(HealthCheck.findings(from: HealthFacts(shownName: "Shades")).first { $0.check == "name" })
        XCTAssertFalse(wrong.ok)
        XCTAssertEqual(wrong.problem, "The Dock and ⌘Tab call me Shades, not The Kitty Litter.")
        XCTAssertEqual(HealthCheck.findings(from: HealthFacts(isBundled: false, shownName: "shades")).first { $0.check == "name" }?.ok, true, "a build from source has no bundle to name it")
    }

    func testARestartComesBackWithoutTakingYouOutOfYourApp() {
        XCTAssertFalse(Setup.relaunch.activates)
        XCTAssertTrue(Setup.relaunch.createsNewApplicationInstance)
    }

    func testTheMainMenuIsAMacAppsWithTheStatusMenusActionsWhereTheyFit() {
        let main = menuBar().mainMenu()
        XCTAssertEqual(main.items.map(\.title), [CatWords.appName, "File", "Edit", "View", "Window", "Help"])
        XCTAssertEqual(main.items.first?.submenu?.items.map(\.title), [
            "About \(CatWords.appName)", "", "Settings…", CatWords.pairItem, "", CatWords.doNotDisturb, CatWords.lockdown, "",
            "Services", "", "Hide \(CatWords.appName)", "Hide Others", "Show All", "", "Quit \(CatWords.appName)",
        ])
        XCTAssertEqual(main.item(withTitle: "File")?.submenu?.items.map(\.title), ["Ask…", "Fix What I'm Looking At", "", "Close Window"])
        XCTAssertEqual(main.item(withTitle: "View")?.submenu?.items.map(\.title), [CatWords.kittensTitle, "", "Enter Full Screen"])
        XCTAssertEqual(main.item(withTitle: "Window")?.submenu?.items.map(\.title), ["Minimize", "Zoom", "", CatWords.appName, "", "Bring All to Front"])
    }

    func testTheAppMenusSystemItemsDoWhatEveryMacAppsDo() throws {
        let main = menuBar().mainMenu()
        let expected: [(String, Selector, String, NSEvent.ModifierFlags)] = [
            ("About \(CatWords.appName)", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), "", .command),
            ("Hide \(CatWords.appName)", #selector(NSApplication.hide(_:)), "h", .command),
            ("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            ("Show All", #selector(NSApplication.unhideAllApplications(_:)), "", .command),
            ("Quit \(CatWords.appName)", #selector(NSApplication.terminate(_:)), "q", .command),
        ]
        for (title, action, key, modifiers) in expected {
            let row = try item(CatWords.appName, title, in: main)
            XCTAssertEqual(row.action, action, title)
            XCTAssertTrue(row.target === NSApplication.shared, title)
            XCTAssertEqual(row.keyEquivalent, key, title)
            XCTAssertEqual(row.keyEquivalentModifierMask, modifiers, title)
        }
        let window: [(String, Selector, String)] = [
            ("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            ("Zoom", #selector(NSWindow.performZoom(_:)), ""),
            ("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)), ""),
        ]
        for (title, action, key) in window {
            let row = try item("Window", title, in: main)
            XCTAssertEqual(row.action, action, title)
            XCTAssertEqual(row.keyEquivalent, key, title)
        }
        let fullScreen = try item("View", "Enter Full Screen", in: main)
        XCTAssertEqual(fullScreen.action, #selector(NSWindow.toggleFullScreen(_:)))
        XCTAssertEqual(fullScreen.keyEquivalentModifierMask, [.command, .control])
        XCTAssertEqual(try item("File", "Close Window", in: main).action, #selector(NSWindow.performClose(_:)))
        let edits = try XCTUnwrap(main.item(withTitle: "Edit")?.submenu).items.filter { !$0.isSeparatorItem }
        XCTAssertEqual(edits.map(\.title), ["Undo", "Redo", "Cut", "Copy", "Paste", "Select All"])
        XCTAssertEqual(edits.map(\.keyEquivalent), ["z", "z", "x", "c", "v", "a"])
        XCTAssertEqual(edits.map(\.action), [Selector(("undo:")), Selector(("redo:")), #selector(NSText.cut(_:)), #selector(NSText.copy(_:)), #selector(NSText.paste(_:)), #selector(NSText.selectAll(_:))])
        XCTAssertTrue(edits.allSatisfy { $0.target == nil }, "they go to whatever has the keyboard")
    }

    func testEachMainMenuActionDoesWhatItSays() async throws {
        let bar = menuBar()
        var checked = 0
        bar.extras = [MenuBar.Extra(title: "Check Myself") { checked += 1 }]
        let main = bar.mainMenu()
        try await choose(CatWords.appName, "Settings…", in: main)
        XCTAssertEqual(stage.settingsShown.count, 1, "Settings opens")
        try await choose("File", "Ask…", in: main)
        XCTAssertNotNil(stage.input, "the Ask box opens")
        stage.hideInput()
        try await choose("File", "Fix What I'm Looking At", in: main)
        XCTAssertTrue(stage.log.all.contains("pickRegion"), "Fix asks where to look")
        try await choose("View", CatWords.kittensTitle, in: main)
        XCTAssertEqual(stage.kittens?.map(\.kitten.name), ["Steve Pawsniak"], "the kittens view opens")
        try await choose("Window", CatWords.appName, in: main)
        XCTAssertEqual(stage.channelsShown.count, 1, "The Kitty Litter opens")
        try await choose(CatWords.appName, CatWords.doNotDisturb, in: main)
        XCTAssertTrue(controller.settings.doNotDisturb)
        XCTAssertEqual(try item(CatWords.appName, CatWords.doNotDisturb, in: main).state, .on, "ticked while it's on")
        try await choose(CatWords.appName, CatWords.lockdown, "Steve Pawsniak", in: main)
        XCTAssertEqual(controller.settings.lockdown, Lockdown(kitten: steve.id))
        XCTAssertEqual(try item(CatWords.appName, CatWords.lockdownOn("Steve Pawsniak"), in: main).state, .on, "its name shows in the menu")
        try await choose("Help", "Check Myself", in: main)
        XCTAssertEqual(checked, 1)
    }

    func testTheMainMenusShortcutsWorkFromTheKeyboardAndNoTwoShareAKey() async throws {
        let bar = menuBar()
        let main = bar.mainMenu()
        try await press(",", .command, in: main)
        XCTAssertEqual(stage.settingsShown.count, 1, "⌘, opens Settings")
        try await press("b", [.control, .command], in: main)
        XCTAssertEqual(stage.channelsShown.count, 1, "⌃⌘B opens The Kitty Litter")
        try await press(" ", .option, in: main)
        XCTAssertNotNil(stage.input, "⌥Space opens the Ask box")
        let keys = everyItem(in: main).filter { !$0.keyEquivalent.isEmpty }.map { "\($0.keyEquivalentModifierMask.rawValue) \($0.keyEquivalent)" }
        XCTAssertEqual(keys.count, Set(keys).count, "each shortcut does one thing: \(keys.sorted())")
        withExtendedLifetime(bar) {}
    }

    func testThePairItemOnlyShowsWithAPhoneToPairAndTheWindowItemCarriesTheCount() throws {
        let bar = menuBar()
        var phone = false
        bar.canPairPhone = { phone }
        bar.messagesSummary = { "1 needs you" }
        let main = bar.mainMenu()
        XCTAssertTrue(try item(CatWords.appName, CatWords.pairItem, in: main).isHidden)
        phone = true
        XCTAssertFalse(try item(CatWords.appName, CatWords.pairItem, in: main).isHidden)
        XCTAssertEqual(try item("Window", CatWords.appName, in: main).badge?.stringValue, "1 needs you")
        XCTAssertEqual(try item("Window", CatWords.appName, in: main).keyEquivalent, "b", "the shortcut the app holds")
    }
}
