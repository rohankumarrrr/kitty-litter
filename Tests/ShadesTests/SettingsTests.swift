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
    }

    func testAnOlderSettingsFileOpensInMessagesAtTheUsualSize() throws {
        let old = try JSONDecoder().decode(Settings.self, from: Data(#"{"phone": true}"#.utf8))
        XCTAssertEqual(old.textSize, .standard)
        XCTAssertTrue(old.openInMessages)

        var changed = Settings()
        changed.textSize = .larger
        changed.openInMessages = false
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
        XCTAssertNil(shown?.form.theme, "Shades' own colours")
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
        let form = SettingsForm(settings: settings, theme: nil, channels: [.init(id: .general, title: "#general"), .init(id: .of(steve), title: "#steve-pawsniak")])
        panel.show(form, near: NSPoint(x: 900, y: 800))
        addTeardownBlock { panel.hide() }
        return (panel, { changes })
    }

    private func controls(in panel: SettingsPanel) -> [NSView] {
        func all(_ view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(all) }
        return panel.panel.contentView.map(all) ?? []
    }

    private func control<T: NSView>(_ name: String, in panel: SettingsPanel) -> T? {
        controls(in: panel).first { $0.accessibilityIdentifier() == name || ($0 as? NSButton)?.title == name } as? T
    }

    func testPickingATextSizeTakesAtOnce() throws {
        let (panel, changes) = panel()
        panel.select(.messages)
        let size: NSPopUpButton = try XCTUnwrap(control("Text size", in: panel))
        size.selectItem(withTitle: "Larger")
        size.sendAction(size.action, to: size.target)
        XCTAssertEqual(changes().map(\.textSize), [.larger])
        XCTAssertTrue(panel.isVisible, "with nothing to save")
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
        let labels = controls(in: panel).compactMap { ($0 as? QuietButton)?.accessibilityLabel() }
        XCTAssertTrue(labels.contains("#steve-pawsniak: Muted"), "\(labels)")
        XCTAssertTrue(labels.contains("#general: Mac: Everything · Phone: Nothing"), "\(labels)")
        XCTAssertEqual(SettingsPanel.summary(ChannelNotifications(mac: .everything, phone: .nothing), phone: false), "Everything", "no phone, no phone in it")
    }

    func testDoNotDisturbIsTheOneSwitch() throws {
        let (panel, changes) = panel()
        var pressed = 0
        panel.onDoNotDisturb = { pressed += 1 }
        panel.select(.notifications)
        let quiet: NSButton = try XCTUnwrap(control(CatWords.doNotDisturb, in: panel))
        quiet.state = .on
        quiet.sendAction(quiet.action, to: quiet.target)
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
}
