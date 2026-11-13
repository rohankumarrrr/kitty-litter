import AppKit
@testable import Shades
import ShadesCore
import XCTest

/// Every setting in one place: what it shows, what changing one does, and what it leaves to the switch and menus that
/// change the rest.
@MainActor
final class SettingsTests: XCTestCase {
    private var stage: FakeStage!
    private var backend: FakeBackend!
    private var clock = Date(timeIntervalSince1970: 100_000)
    private var kittens: [Kitten] = []
    private var savedSettings: Settings?
    private var controller: AppController!
    private let steve = Kitten(name: "Steve Pawsniak", role: "Careers", covers: "jobs", folder: "/k/steve")

    override func setUp() async throws {
        stage = FakeStage(log: Log())
        backend = FakeBackend()
        var settings = Settings()
        settings.quickMode = .approvalRequired
        controller = AppController(
            dependencies: AppDependencies(
                backend: backend,
                context: FakeContext(log: Log()),
                voice: FakeVoice(),
                inserter: FakeInserter(),
                keys: FakeKeys(),
                settings: settings,
                saveSettings: { [unowned self] in self.savedSettings = $0 },
                kittens: { [unowned self] in self.kittens },
                routerFolder: { "/shades/router" },
                inbox: Inbox(since: .distantPast),
                saveInbox: { _ in }
            ),
            stage: stage,
            now: { [unowned self] in self.clock }
        )
    }

    override func tearDown() async throws {
        MessagesInk.textSize = .standard
        MessagesInk.fontFamily = nil
    }

    func testAnOlderSettingsFileOpensInMessagesAtTheUsualSize() throws {
        let old = try JSONDecoder().decode(Settings.self, from: Data(#"{"phone": true}"#.utf8))
        XCTAssertEqual(old.textSize, .standard)
        XCTAssertTrue(old.openInMessages)
        XCTAssertNil(old.messagesFont, "the system's font")

        var changed = Settings()
        changed.textSize = .larger
        changed.openInMessages = false
        changed.messagesFont = "Georgia"
        let read = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(changed))
        XCTAssertEqual(read, changed)
    }

    func testItListsEveryChannelWithWhatEachTellsYou() {
        kittens = [steve]
        controller.settingsPressed(overMessages: true)
        let shown = stage.settingsShown.last
        XCTAssertEqual(shown?.overMessages, true)
        XCTAssertEqual(shown?.form.channels.map(\.title), ["#general", "#steve-pawsniak", "Shades"])
        XCTAssertEqual(shown?.form.channels.map(\.id), [.general, .of(steve), .shades])
    }

    func testAChangeMadeElsewhereShowsInSettingsAndItsOwnChangesCantUndoIt() {
        kittens = [steve]
        controller.settingsPressed()
        let opened = stage.settingsShown.last!.form.settings

        controller.messagesAction(.notifications(.of(steve), ChannelNotifications(muted: true)))
        controller.doNotDisturbPressed()
        XCTAssertEqual(stage.settingsForms.last?.settings.notifications(for: "kitten:/k/steve"), ChannelNotifications(muted: true))
        XCTAssertEqual(stage.settingsForms.last?.settings.doNotDisturb, true)

        var edited = opened
        edited.vocabulary = ["Pawsniak"]
        controller.settingsEdited(edited)
        XCTAssertEqual(controller.settings.vocabulary, ["Pawsniak"])
        XCTAssertEqual(controller.settings.notifications(for: "kitten:/k/steve"), ChannelNotifications(muted: true), "still muted")
        XCTAssertTrue(controller.settings.doNotDisturb)
        XCTAssertEqual(savedSettings?.vocabulary, ["Pawsniak"])
    }

    func testTextSizeGoesToMessages() {
        var larger = controller.settings
        larger.textSize = .larger
        controller.settingsEdited(larger)
        XCTAssertEqual(stage.textSizes, [.larger])
        controller.settingsEdited(larger)
        XCTAssertEqual(stage.textSizes, [.larger], "only when it changes")
    }

    func testWithOpenSetToT3OpenGoesThereEvenForAThreadMessagesShows() {
        kittens = [steve]
        let steves = AgentThread(id: "s", title: "Tidy the site", projectTitle: "Steve", status: .completed, model: "m", updatedAt: clock, projectPath: "/k/steve")
        controller.threadsChanged([steves])
        XCTAssertTrue(controller.opensInMessages("s"))

        var t3 = controller.settings
        t3.openInMessages = false
        controller.settingsEdited(t3)
        XCTAssertFalse(controller.opensInMessages("s"), "the bubble says Open in T3")
        controller.bubbleAction(.show(threadID: "s"))
        XCTAssertEqual(backend.opened, ["s"])
        XCTAssertTrue(stage.selections.isEmpty, "and Messages stays shut")
    }

    // MARK: - The panel

    private func panel(_ settings: Settings = Settings()) -> (SettingsPanel, () -> [Settings]) {
        let panel = SettingsPanel()
        var changes: [Settings] = []
        panel.onChange = { changes.append($0) }
        let form = SettingsForm(settings: settings, channels: [.init(id: .general, title: "#general"), .init(id: .of(steve), title: "#steve-pawsniak")])
        panel.show(form, near: NSPoint(x: 900, y: 800))
        addTeardownBlock { panel.hide() }
        return (panel, { changes })
    }

    private func controls(in panel: SettingsPanel) -> [NSView] {
        func all(_ view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(all) }
        return panel.panel.contentView.map(all) ?? []
    }

    private func control<T: NSView>(_ name: String, in panel: SettingsPanel) -> T? {
        controls(in: panel).first { $0.accessibilityIdentifier() == name || ($0 as? QuietCheckbox)?.title == name } as? T
    }

    /// The same as clicking that choice in the row's menu.
    private func pick(_ choice: String, in row: String, of panel: SettingsPanel) throws {
        let button: QuietButton = try XCTUnwrap(control(row, in: panel))
        let menu = try XCTUnwrap(button.menu)
        menu.performActionForItem(at: try XCTUnwrap(menu.items.firstIndex { $0.title == choice }))
    }

    func testPickingATextSizeTakesAtOnce() throws {
        let (panel, changes) = panel()
        panel.select(.messages)
        try pick("Larger", in: "Text size", of: panel)
        XCTAssertEqual(changes().map(\.textSize), [.larger])
        XCTAssertTrue(panel.isVisible, "with nothing to save")
        let size: QuietButton = try XCTUnwrap(control("Text size", in: panel))
        XCTAssertEqual(size.accessibilityValue() as? String, "Larger", "its button says what's picked")
        XCTAssertEqual(size.menu?.items.filter { $0.state == .on }.map(\.title), ["Larger"])
    }

    func testEveryChoiceFromAMenuIsTheSameQuietButton() {
        let (panel, _) = panel()
        var menus: [String] = []
        for page in SettingsPanel.Page.allCases {
            panel.select(page)
            XCTAssertFalse(controls(in: panel).contains { $0 is NSPopUpButton }, "no system pop-up on \(page.title)")
            menus += controls(in: panel).filter { $0.accessibilityRole() == .popUpButton }.map { view in
                XCTAssertTrue(view is QuietButton, "\(view.accessibilityIdentifier()) on \(page.title)")
                return "\(view.accessibilityLabel() ?? ""): \(view.accessibilityValue() as? String ?? "")"
            }
        }
        XCTAssertEqual(menus, [
            "Front door mode: Auto", "Frontier mode: Auto", "Hold to talk: Right Option", "Hold to dictate: fn",
            "#general: Everything", "#steve-pawsniak: Everything", "Font: SF Pro", "Text size: Default",
            "Open threads: In \(CatWords.appName) first",
        ])
    }

    func testSettingsIsOpalGlass() throws {
        let glass = Opal.raised
        let (panel, _) = panel()
        let root = try XCTUnwrap(panel.panel.contentView)
        let picture = try XCTUnwrap(ChannelImages.bitmap(of: root, scale: 1))
        let corner = try XCTUnwrap(picture.colorAt(x: 12, y: picture.pixelsHigh - 12)?.usingColorSpace(.sRGB))
        let drawn = [corner.redComponent, corner.greenComponent, corner.blueComponent].map { UInt32(($0 * 255).rounded()) }
        let want = [glass >> 16 & 0xff, glass >> 8 & 0xff, glass & 0xff]
        for (got, wanted) in zip(drawn, want) {
            XCTAssertLessThanOrEqual(abs(Int(got) - Int(wanted)), 3, "it floats, so it's Opal's glass: drew \(drawn), not \(want)")
        }
    }

    func testThePrivacyBoxShowsItsWholeList() throws {
        var settings = Settings()
        settings.privateApps += ["com.example.vault", "com.example.diary", "com.example.journal"]
        let (panel, _) = panel(settings)
        panel.select(.privacy)
        let apps: NSTextField = try XCTUnwrap(control("Private apps", in: panel))
        panel.panel.contentView?.layoutSubtreeIfNeeded()
        let inside = try XCTUnwrap(apps.cell?.drawingRect(forBounds: apps.bounds))
        // Laid out the way the box lays it out once you click into it, which wraps a little sooner than its drawing.
        let storage = NSTextStorage(attributedString: apps.attributedStringValue)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: inside.width, height: .greatestFiniteMagnitude))
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        XCTAssertGreaterThanOrEqual(inside.height, layout.usedRect(for: container).height, "no app hides past the box's edge")
    }

    func testTypingInABoxTakesWhenSettingsCloses() throws {
        let (panel, changes) = panel()
        panel.select(.voice)
        let words: NSTextField = try XCTUnwrap(control("Extra words", in: panel))
        panel.panel.makeFirstResponder(words)
        words.currentEditor()?.string = "Pawsniak, Clawde"
        panel.hide()
        XCTAssertEqual(changes().last?.vocabulary, ["Pawsniak", "Clawde"])
    }

    func testEachChannelSaysWhatItTellsYou() {
        var settings = Settings(phone: true)
        settings.setNotifications(ChannelNotifications(muted: true), for: "kitten:/k/steve")
        settings.setNotifications(ChannelNotifications(mac: .everything, phone: .nothing), for: "general")
        let (panel, _) = panel(settings)
        panel.select(.notifications)
        let labels = controls(in: panel).compactMap { $0 as? QuietButton }.map { "\($0.accessibilityLabel() ?? ""): \($0.accessibilityValue() as? String ?? "")" }
        XCTAssertTrue(labels.contains("#steve-pawsniak: Muted"), "\(labels)")
        XCTAssertTrue(labels.contains("#general: Mac: Everything · Phone: Nothing"), "\(labels)")
        XCTAssertEqual(SettingsPanel.summary(ChannelNotifications(mac: .everything, phone: .nothing), phone: false), "Everything", "no phone, no phone in it")
    }

    func testDoNotDisturbIsTheOneSwitch() throws {
        let (panel, changes) = panel()
        var pressed = 0
        panel.onDoNotDisturb = { pressed += 1 }
        panel.select(.notifications)
        let quiet: QuietCheckbox = try XCTUnwrap(control(CatWords.doNotDisturb, in: panel))
        quiet.toggle()
        XCTAssertEqual(pressed, 1)
        XCTAssertTrue(changes().isEmpty, "it doesn't set the switch itself")
    }

    // MARK: - Text size

    func testWordsInMessagesGrowWithTheTextSize() {
        let text = "The pricing page feels cramped on a laptop, so here's a long enough message to wrap a few times."
        let block = ChannelTextBlock(ChannelMarkdown.attributed(text))
        let usual = block.fit(width: 240)
        MessagesInk.textSize = .larger
        block.restyle(ChannelMarkdown.attributed(text))
        XCTAssertGreaterThan(block.fit(width: 240), usual)
    }

    // MARK: - Font

    func testAFontGoesToMessages() {
        var georgia = controller.settings
        georgia.messagesFont = "Georgia"
        controller.settingsEdited(georgia)
        XCTAssertEqual(stage.fonts, ["Georgia"])
        georgia.messagesFont = nil
        controller.settingsEdited(georgia)
        XCTAssertEqual(stage.fonts, ["Georgia", nil], "back to the system's")
    }

    func testMessagesDrawsInThePickedFontAndTheSystemsWhenItsNotHere() {
        let system = MessagesInk.font(ofSize: 13)
        MessagesInk.fontFamily = "Georgia"
        XCTAssertEqual(MessagesInk.font(ofSize: 13).familyName, "Georgia")
        XCTAssertEqual(MessagesInk.font(ofSize: 13, weight: .semibold).fontDescriptor.symbolicTraits.contains(.bold), true, "bold in Georgia too")
        let words = ChannelMarkdown.attributed("Plain words")
        XCTAssertEqual((words.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.familyName, "Georgia")

        MessagesInk.fontFamily = "New York"
        XCTAssertNotEqual(MessagesInk.font(ofSize: 13).fontName, system.fontName, "the system's serif")
        MessagesInk.fontFamily = "A Font Nobody Has"
        XCTAssertEqual(MessagesInk.font(ofSize: 13).fontName, system.fontName)
    }

    func testWordsAlreadyLaidOutFollowANewFont() throws {
        let book = ChannelBook.build(kittens: [], threads: [], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false)
        let look = ChannelSpeakerLook(.you, in: book)
        let message = ChannelMessage(exchangeID: "e", kind: .ask, speaker: .you, text: "Rewrite the pricing copy so it sounds like a person wrote it.", at: clock, threadID: "", threadTitle: "")
        let words = MessageWords(message, look: look)
        _ = words.words?.fit(width: 900)
        let system = try XCTUnwrap(words.words?.width)
        MessagesInk.fontFamily = "Courier"
        words.paint(for: look)
        _ = words.words?.fit(width: 900)
        XCTAssertGreaterThan(try XCTUnwrap(words.words?.width), system, "Courier's letters are wider")
    }

    func testTheFontMenuHasTheSystemsFacesThenEveryFamily() throws {
        let menu = FontMenu()
        let families = ["Georgia", ".Hidden", "Avenir Next"]
        let items = menu.items(current: nil, families: families)
        XCTAssertEqual(items.map(\.title), ["SF Pro", "New York", "SF Pro Rounded", "SF Mono", "", CatWords.allFonts])
        XCTAssertEqual(items.first?.state, .on)
        XCTAssertNil(items.first?.representedObject, "the system's is no font at all in the file")
        XCTAssertEqual(items[1].representedObject as? String, "New York")
        let all = try XCTUnwrap(items.last?.submenu)
        XCTAssertEqual(all.items.map(\.title), ["Avenir Next", "Georgia"], "sorted, without the ones macOS keeps for itself")

        let picked = menu.items(current: "Georgia", families: families)
        XCTAssertEqual(picked.first?.state, .off)
        XCTAssertEqual(picked.last?.state, .on)
        XCTAssertEqual(picked.last?.submenu?.items.first { $0.state == .on }?.title, "Georgia")

        let gone = menu.items(current: "A Font Nobody Has", families: families)
        XCTAssertEqual(gone[4].title, "A Font Nobody Has")
        XCTAssertFalse(gone[4].isEnabled, "written by hand, and not on this Mac")
    }

    func testFontIsFirstOnTheMessagesPage() {
        let (panel, _) = panel(Settings(messagesFont: "Georgia"))
        panel.select(.messages)
        let rows = controls(in: panel).map { $0.accessibilityIdentifier() }.filter { !$0.isEmpty }
        XCTAssertEqual(rows.first, "Font", "with no theme above it, since Opal is the only look")
        let font = controls(in: panel).first { $0.accessibilityIdentifier() == "Font" } as? QuietButton
        XCTAssertEqual(font?.accessibilityValue() as? String, "Georgia")
    }
}
