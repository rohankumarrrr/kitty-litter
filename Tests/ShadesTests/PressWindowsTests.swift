import AppKit
@testable import Shades
import ShadesContext
import ShadesCore
import XCTest

/// The cat's bubble, the Ask box, the kittens view, pairing, Settings and the menu bar, each control pressed the way a
/// mouse and keyboard press it, through `Press`, in panels that never reach the screen.
@MainActor
final class PressWindowsTests: XCTestCase {
    /// A panel that never reaches the screen. It says it's showing once it's asked to, and has the keyboard once a test
    /// says it does.
    private final class HiddenPanel: QuietPanel {
        var key = false
        private var shown = false
        override var isVisible: Bool { shown }
        override var isKeyWindow: Bool { key }
        override func orderFrontRegardless() { shown = true }
        override func orderFront(_ sender: Any?) { shown = true }
        override func makeKeyAndOrderFront(_ sender: Any?) { shown = true }
        override func makeKey() {}
        override func orderOut(_ sender: Any?) { shown = false }
    }

    private let steve = Kitten(name: "Steve Pawsniak", role: "Professional", covers: "jobs", folder: "/k/steve")
    private let pepper = Kitten(name: "Pepper", role: "Money", covers: "money", folder: "/k/pepper", planned: true)
    private let at = Date(timeIntervalSince1970: 100_000)
    private let screen = NSRect(x: 0, y: 0, width: 1200, height: 800)
    private let motion = Motion.forced

    private var stage: FakeStage!
    private var backend: FakeBackend!
    private var voice: FakeVoice!
    private var kittens: [Kitten] = []
    private var controller: AppController!

    override func setUp() async throws {
        Motion.forced = true
        QuietFocus.fullKeyboardAccess = { false }
        let log = Log()
        stage = FakeStage(log: log)
        backend = FakeBackend()
        voice = FakeVoice()
        controller = AppController(
            dependencies: AppDependencies(
                backend: backend,
                context: FakeContext(log: log),
                voice: voice,
                inserter: FakeInserter(),
                keys: FakeKeys(),
                settings: Settings(),
                saveSettings: { _ in },
                kittens: { [unowned self] in self.kittens },
                routerFolder: { "/shades/router" }
            ),
            stage: stage,
            now: { [unowned self] in self.at }
        )
        controller.threadListWait = 0
    }

    override func tearDown() async throws {
        Motion.forced = motion
        QuietFocus.fullKeyboardAccess = { NSApplication.shared.isFullKeyboardAccessEnabled }
        MessagesInk.textSize = .standard
        MessagesInk.fontFamily = nil
    }

    private func settle() async {
        await controller.flow?.value
        await controller.replyTask?.value
        await controller.voiceTask?.value
        for _ in 0..<20 { await Task.yield() }
    }

    private func eventually(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { await Task.yield() }
    }

    private func subviews(of view: NSView?) -> [NSView] {
        guard let view else { return [] }
        return view.subviews + view.subviews.flatMap(subviews)
    }

    private func button(_ title: String, in view: NSView?, file: StaticString = #filePath, line: UInt = #line) throws -> QuietButton {
        try XCTUnwrap(subviews(of: view).compactMap { $0 as? QuietButton }.first { $0.accessibilityLabel() == title }, "no button [\(title)]", file: file, line: line)
    }

    /// Clicks it where it is, after checking that a click at its centre lands on it and not on something over it.
    private func click(_ control: NSView, _ name: String, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertTrue(try Press.hit(control, file: file, line: line) === control, "a click lands on \(name)", file: file, line: line)
        try Press.click(control, file: file, line: line)
    }

    // MARK: - The bubble

    /// The bubble as the app wires it to the controller, in a panel that never reaches the screen.
    private func bubble() -> (BubbleController, HiddenPanel) {
        let panel = HiddenPanel(allowsKey: true)
        let bubble = BubbleController(panel: panel)
        bubble.anchor = { [screen] in (NSRect(x: 500, y: 100, width: 64, height: 64), screen) }
        bubble.view.onAction = { [unowned controller] in controller!.bubbleAction($0) }
        bubble.view.opensInMessages = { [unowned controller] in controller!.opensInMessages($0) }
        addTeardownBlock { bubble.hide() }
        return (bubble, panel)
    }

    /// Long enough for buttons that start, allow or change things to take clicks.
    private func waitForArming() {
        RunLoop.main.run(until: Date().addingTimeInterval(BubbleController.armDelay + 0.1))
    }

    func testOpenInT3InTheBubbleOpensTheThreadInT3() async throws {
        let (bubble, _) = bubble()
        bubble.show(.reply(text: "The answer.", done: true, threadID: "mcp:launch:8f2c", note: nil))
        try click(try button(CatWords.openInT3, in: bubble.view), CatWords.openInT3)
        await eventually { !backend.opened.isEmpty }
        XCTAssertEqual(backend.opened, ["mcp:launch:8f2c"])
    }

    func testOpenInTheBubbleShowsAKittensThreadBesideItsChannel() throws {
        kittens = [steve]
        controller.threadsChanged([AgentThread(id: "s", title: "Tidy the site", projectTitle: "Steve", status: .completed, model: "m", updatedAt: at, projectPath: steve.folder)])
        controller.post(caption: "Steve finished", text: "The site's tidy.", threadID: "s")
        let (bubble, _) = bubble()
        bubble.show(stage.bubble)
        try click(try button("Open", in: bubble.view), "Open")
        XCTAssertEqual(stage.selections.last, .thread("s", in: .channel(.of(steve))))
        XCTAssertTrue(backend.opened.isEmpty, "not T3")
    }

    func testCopyInTheBubbleCopiesTheAnswer() throws {
        let (bubble, _) = bubble()
        bubble.show(.reply(text: "The answer.", done: true, threadID: nil, note: nil))
        try click(try button("Copy", in: bubble.view), "Copy")
        XCTAssertEqual(stage.copied, "The answer.")
    }

    func testReplaceInTheBubbleTakesClicksOnceItsArmed() throws {
        let (bubble, _) = bubble()
        var actions: [BubbleAction] = []
        bubble.view.onAction = { actions.append($0) }
        bubble.show(.reply(text: "Shorter.", done: true, threadID: nil, note: nil, canReplace: true))
        let replace = try button("Replace", in: bubble.view)
        try click(replace, "Replace")
        XCTAssertEqual(actions, [], "not while a click meant for something else could still land on it")
        waitForArming()
        try click(replace, "Replace")
        XCTAssertEqual(actions, [.replace("Shorter.")])
    }

    func testEachOfAnApprovalsChoicesAnswersIt() async throws {
        for (index, (title, decision)) in [("Allow", ApprovalDecision.accept), ("Deny", .decline), ("Allow for this session", .acceptForSession)].enumerated() {
            let request = ApprovalRequest(id: "r\(index)", threadID: "steve-1", threadTitle: "Tidy up", kind: .command, summary: "npm test", createdAt: at)
            controller.addApproval(request)
            let (bubble, _) = bubble()
            bubble.show(stage.bubble)
            waitForArming()
            try click(try button(title, in: bubble.view), title)
            await eventually { backend.responses.count > index }
            XCTAssertEqual(backend.responses.last?.0, request.id, title)
            XCTAssertEqual(backend.responses.last?.1, decision, title)
            bubble.hide()
        }
    }

    func testOpenSystemSettingsInTheBubbleOpensThePageItNames() throws {
        let (bubble, _) = bubble()
        bubble.show(.line(CatWords.needsMicrophone, threadID: nil))
        try click(try button(CatWords.openSystemSettings, in: bubble.view), CatWords.openSystemSettings)
        XCTAssertEqual(stage.openedSettings, [.microphone])
    }

    func testOpenOnWhatCameInOpensActivity() throws {
        let (bubble, _) = bubble()
        bubble.show(.inbox("Steve finished something."))
        try click(try button("Open", in: bubble.view), "Open")
        XCTAssertEqual(stage.selections.last, .activity)
    }

    /// What has the keyboard after each Tab from the bubble's words, once a click into them has given it the keyboard.
    private func tabs(through bubble: BubbleController, _ panel: HiddenPanel) throws -> [String] {
        panel.key = true
        XCTAssertTrue(panel.makeFirstResponder(bubble.view.textView), "a click into its words")
        var reached: [String] = []
        for _ in 0..<5 {
            guard let from = panel.firstResponder as? NSView else { break }
            try Press.key("\t", keyCode: 48, on: from)
            if panel.firstResponder === bubble.view.textView { break }
            reached.append((panel.firstResponder as? QuietButton)?.accessibilityLabel() ?? panel.firstResponder.map { "\(type(of: $0))" } ?? "nothing")
        }
        return reached
    }

    /// Clicking into its words gives the bubble the keyboard, and from there Tab goes round its buttons and Space presses one.
    func testTabFromTheBubblesWordsReachesItsButtonsAndSpacePressesOne() async throws {
        QuietFocus.fullKeyboardAccess = { true }
        let (bubble, panel) = bubble()
        bubble.show(.reply(text: "The answer.", done: true, threadID: "t", note: nil))
        let reached = try tabs(through: bubble, panel)
        XCTAssertEqual(Array(reached.prefix(2)), ["Copy", CatWords.openInT3], "Tab went to \(reached)")
        for _ in 0..<2 { try Press.key("\t", keyCode: 48, on: try XCTUnwrap(panel.firstResponder as? NSView)) }
        let open = try XCTUnwrap(panel.firstResponder as? QuietButton)
        try Press.key(" ", keyCode: 49, on: open)
        await eventually { !backend.opened.isEmpty }
        XCTAssertEqual(backend.opened, ["t"])
    }

    func testTabReachesEveryButtonInABubbleWhoseWordsCanBeClickedInto() async throws {
        QuietFocus.fullKeyboardAccess = { true }
        let request = ApprovalRequest(id: "r", threadID: "steve-1", threadTitle: "Tidy up", kind: .command, summary: "npm test", createdAt: at)
        let shows: [(BubbleContent, [String])] = [
            (.reply(text: "Shorter.", done: true, threadID: nil, note: nil, canReplace: true), ["Copy", "Replace"]),
            (.approval(request, position: 1, total: 1), ["Allow for this session", "Deny", "Allow"]),
            (.line(CatWords.needsMicrophone, threadID: nil), [CatWords.openSystemSettings]),
            (.notice(caption: "Steve finished", text: "The site's tidy.", threadID: "t"), [CatWords.openInT3]),
        ]
        for (content, buttons) in shows {
            let (bubble, panel) = bubble()
            bubble.show(content)
            XCTAssertEqual(try tabs(through: bubble, panel), buttons, "\(buttons)")
            bubble.hide()
        }

        controller.addApproval(request)
        let (bubble, panel) = bubble()
        bubble.show(stage.bubble)
        waitForArming()
        panel.key = true
        panel.makeFirstResponder(bubble.view.textView)
        for _ in 0..<3 { try Press.key("\t", keyCode: 48, on: try XCTUnwrap(panel.firstResponder as? NSView)) }
        let allow = try XCTUnwrap(panel.firstResponder as? QuietButton)
        XCTAssertEqual(allow.accessibilityLabel(), "Allow")
        try Press.key(" ", keyCode: 49, on: allow)
        await eventually { !backend.responses.isEmpty }
        XCTAssertEqual(backend.responses.map(\.1), [.accept], "Space on Allow allows")
    }

    /// Words that can't be selected, such as what came in while you were away, never give the bubble the keyboard.
    func testABubbleWithNothingToSelectNeverTakesTheKeyboard() throws {
        let (bubble, _) = bubble()
        bubble.show(.inbox("Steve finished something."))
        XCTAssertFalse(bubble.view.textView.needsPanelToBecomeKey)
    }

    // MARK: - The Ask box

    /// The Ask box as the app wires it, in a panel that never reaches the screen, showing what the controller asked it to.
    private func askBox() async throws -> (InputPanel, HiddenPanel) {
        let panel = HiddenPanel(allowsKey: true)
        let input = InputPanel(panel: panel)
        input.anchor = { [screen] in (NSRect(x: 500, y: 100, width: 64, height: 64), screen) }
        input.onMic = { [unowned controller] in controller!.micPressed(in: .ask) }
        panel.key = true
        input.show(try XCTUnwrap(stage.input, "the controller asked for the box"))
        return (input, panel)
    }

    private func field(_ panel: HiddenPanel) throws -> PlaceholderTextView {
        try XCTUnwrap(subviews(of: panel.contentView).compactMap { $0 as? PlaceholderTextView }.first)
    }

    private func typeKeys(_ text: String, into view: NSView) throws {
        for character in text { try Press.key(String(character), on: view) }
    }

    func testTypingInTheAskBoxAndPressingReturnAsksIt() async throws {
        controller.askPressed()
        await controller.flow?.value
        let (input, panel) = try await askBox()
        let field = try field(panel)
        XCTAssertTrue(try Press.hit(field) === field, "a click lands in the box")
        XCTAssertTrue(panel.firstResponder === field, "it has the keyboard as it opens")
        try typeKeys("What is this?", into: field)
        XCTAssertEqual(input.typedText, "What is this?")
        try Press.key("\r", keyCode: 36, on: field)
        XCTAssertFalse(input.isVisible)
        await settle()
        XCTAssertTrue(backend.sent.first?.prompt.text.contains("What is this?") == true, "what you typed is asked: \(backend.sent.map(\.prompt.text))")
    }

    func testEscInTheAskBoxPutsItAway() async throws {
        controller.askPressed()
        await controller.flow?.value
        var cancelled = 0
        let cancel = stage.input?.onCancel
        stage.input?.onCancel = { cancelled += 1; cancel?() }
        let (input, panel) = try await askBox()
        try typeKeys("Never mind", into: try field(panel))
        try Press.key("\u{1b}", keyCode: 53, on: try field(panel))
        XCTAssertFalse(input.isVisible)
        XCTAssertEqual(cancelled, 1)
        XCTAssertTrue(backend.sent.isEmpty, "nothing's asked")
    }

    func testTheAskBoxsMicListensForWhatYouSay() async throws {
        controller.askPressed()
        await controller.flow?.value
        let (input, _) = try await askBox()
        try click(input.mic, "the mic")
        XCTAssertEqual(voice.began, 1)
        XCTAssertEqual(stage.listeningIn, .ask)
    }

    /// Ctrl-Tab leaves the box for its mic, as it leaves a box anywhere on the Mac, and Space presses it.
    func testCtrlTabFromTheAskBoxReachesItsMicAndSpacePressesIt() async throws {
        QuietFocus.fullKeyboardAccess = { true }
        controller.askPressed()
        await controller.flow?.value
        let (input, panel) = try await askBox()
        // AppKit works out Tab's way round a window as it first shows, which this one never does.
        panel.recalculateKeyViewLoop()
        try Press.key("\t", keyCode: 48, modifiers: .control, on: try field(panel))
        XCTAssertTrue(panel.firstResponder === input.mic, "Ctrl-Tab went to \(panel.firstResponder.map { "\(type(of: $0))" } ?? "nothing")")
        try Press.key(" ", keyCode: 49, on: input.mic)
        XCTAssertEqual(voice.began, 1)
    }

    /// A file dropped on the cat shows by its name in the box, and Return with nothing typed asks for a summary of it.
    func testADroppedFileShowsInTheAskBoxAndReturnAsksAboutIt() async throws {
        controller.dropped(ScreenSnapshot(pageText: "Week 1: cats.", droppedNames: ["syllabus.pdf"]))
        await controller.flow?.value
        let (_, panel) = try await askBox()
        let chip = try XCTUnwrap(subviews(of: panel.contentView).first { $0.accessibilityLabel() == "syllabus.pdf" }, "its name shows")
        XCTAssertFalse(chip.isHidden)
        XCTAssertFalse(chip.frame.intersects(try field(panel).enclosingScrollView?.frame ?? .zero), "over what you type, not on it")
        try Press.key("\r", keyCode: 36, on: try field(panel))
        await settle()
        XCTAssertTrue(backend.sent.first?.prompt.text.contains("Week 1: cats.") == true, "it goes with the question: \(backend.sent.map(\.prompt.text))")
    }

    // MARK: - The kittens

    func testEachKittensTileOpensWhereItsWorkIs() throws {
        kittens = [steve, pepper]
        controller.threadsChanged([AgentThread(id: "s", title: "Tidy the site", projectTitle: "Steve", status: .completed, model: "m", updatedAt: at, projectPath: steve.folder)])
        let statuses = controller.kittenStatuses
        XCTAssertEqual(statuses.map(\.kitten.name), ["Steve Pawsniak", "Pepper"])
        for status in statuses {
            let panel = HiddenPanel()
            let view = KittenPanel(panel: panel)
            view.anchor = { [screen] in (NSRect(x: 500, y: 100, width: 64, height: 64), screen) }
            view.onOpen = { [unowned controller] in controller!.kittenPressed($0) }
            view.show(statuses)
            let tile = try XCTUnwrap(subviews(of: panel.contentView).compactMap { $0 as? KittenRow }.first { $0.status.id == status.id })
            try click(tile, status.kitten.name)
            let opened = status.threadID.map { ChannelSelection.thread($0, in: .channel(.of(status.kitten))) } ?? .channel(.of(status.kitten))
            XCTAssertEqual(stage.selections.last, opened, status.kitten.name)
            XCTAssertFalse(view.isVisible, "and the view goes")
        }
    }

    /// The kittens view never takes the keyboard, so the app you're in keeps it. VoiceOver presses a tile the same way.
    func testVoiceOverPressesAKittensTileAndTabNeverReachesOne() throws {
        kittens = [steve]
        QuietFocus.fullKeyboardAccess = { true }
        let panel = HiddenPanel()
        let view = KittenPanel(panel: panel)
        view.onOpen = { [unowned controller] in controller!.kittenPressed($0) }
        view.show(controller.kittenStatuses)
        XCTAssertFalse(panel.canBecomeKey)
        let tile = try XCTUnwrap(subviews(of: panel.contentView).compactMap { $0 as? KittenRow }.first)
        XCTAssertFalse(tile.acceptsFirstResponder)
        XCTAssertTrue(tile.accessibilityPerformPress())
        XCTAssertEqual(stage.selections.last, .channel(.of(steve)))
    }

    // MARK: - Pairing

    /// A controller with the phone page on, serving on a loopback port, as `PhoneServerTests` runs it.
    private func phoneController() async throws -> (AppController, FakeStage, UInt16) {
        let stage = FakeStage(log: Log())
        var settings = Settings()
        settings.phone = true
        let controller = AppController(
            dependencies: AppDependencies(
                backend: backend,
                context: FakeContext(log: Log()),
                voice: FakeVoice(),
                inserter: FakeInserter(),
                keys: FakeKeys(),
                settings: settings,
                saveSettings: { _ in },
                routerFolder: { "/shades/router" },
                servePhone: { _ in "https://mac.example.ts.net:4797" }
            ),
            stage: stage
        )
        controller.startPhone()
        addTeardownBlock { controller.stopPhone() }
        await controller.phoneTask?.value
        await until { stage.pairings.last??.code != nil }
        return (controller, stage, try XCTUnwrap(controller.phoneListening))
    }

    private func until(_ condition: () -> Bool) async {
        for _ in 0..<2000 where !condition() { try? await Task.sleep(nanoseconds: 2_000_000) }
    }

    /// What the phone page gets for typing this code, as it sends it.
    private func pairs(_ code: String, port: UInt16) async throws -> Int {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/pair")!)
        request.httpMethod = "POST"
        request.httpBody = Data(#"{"code":"\#(code)"}"#.utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "X-Shades")
        let (_, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }

    /// The pairing code shows, its picture scans to the page with the same code, and Cancel stops the code working.
    func testThePairingCodeShowsAndScansAndCancelStopsIt() async throws {
        let (controller, stage, port) = try await phoneController()
        let card = try XCTUnwrap(stage.pairings.last ?? nil)
        let panel = HiddenPanel(allowsKey: false)
        let pairing = PairingPanel(panel: panel)
        pairing.onClose = { controller.pairingClosed() }
        pairing.show(card, centeredIn: screen)

        let labels = subviews(of: panel.contentView).compactMap { $0 as? NSTextField }
        let code = try XCTUnwrap(labels.first { $0.stringValue == card.code }, "the code shows")
        XCTAssertTrue(try Press.hit(code) === code, "nothing covers it")
        let picture = try XCTUnwrap(subviews(of: panel.contentView).compactMap { $0 as? NSImageView }.first?.image)
        let scanned = try XCTUnwrap(picture.cgImage(forProposedRect: nil, context: nil, hints: nil).flatMap { image in
            CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: nil)?.features(in: CIImage(cgImage: image)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }.first
        })
        XCTAssertEqual(scanned, card.link)
        XCTAssertEqual(card.link, "https://mac.example.ts.net:4797/#pair=\(card.code)")

        try click(try button(CatWords.pairCancel, in: panel.contentView), CatWords.pairCancel)
        XCTAssertFalse(pairing.isVisible)
        let status = try await pairs(card.code, port: port)
        XCTAssertNotEqual(status, 200, "the code stops working once it's gone")
    }

    // MARK: - Settings

    private func settingsPanel(on page: SettingsPanel.Page = .agents) -> (SettingsPanel, HiddenPanel) {
        let panel = HiddenPanel(allowsKey: true)
        let settings = SettingsPanel(panel: panel)
        settings.onChange = { [unowned controller] in controller!.settingsEdited($0) }
        settings.onDoNotDisturb = { [unowned controller] in controller!.doNotDisturbPressed() }
        settings.onNotifications = { [unowned controller] channel, picked in controller!.setNotifications(picked, for: channel) }
        settings.onPairPhone = { [unowned controller] in controller!.pairPhone() }
        settings.openFolder = { _ in XCTFail("nothing opens Finder in a test") }
        controller.settingsPressed()
        panel.key = true
        settings.show(stage.settingsShown.last!.form, near: NSPoint(x: 1000, y: 700))
        if page != .agents { settings.select(page) }
        addTeardownBlock { settings.hide() }
        return (settings, panel)
    }

    private func control(_ id: String, in settings: SettingsPanel, file: StaticString = #filePath, line: UInt = #line) throws -> NSView {
        try XCTUnwrap(subviews(of: settings.panel.contentView).first { $0.accessibilityIdentifier() == id || $0.accessibilityLabel() == id }, "no control [\(id)]", file: file, line: line)
    }

    /// What a control is called, as the demo and VoiceOver find it, or a box's for its field editor.
    private func name(_ responder: NSResponder?) -> String {
        let view = (responder as? NSTextView).flatMap { $0.isFieldEditor ? $0.delegate as? NSView : nil } ?? responder as? NSView
        guard let view else { return "nothing" }
        if !view.accessibilityIdentifier().isEmpty { return view.accessibilityIdentifier() }
        return view.accessibilityLabel() ?? "\(Swift.type(of: view))"
    }

    /// Every control Tab reaches on the page, from where the keyboard is now, once round.
    private func tabRound(_ panel: HiddenPanel) throws -> [String] {
        var reached: [String] = []
        for _ in 0..<40 {
            try Press.key("\t", keyCode: 48, on: try XCTUnwrap(panel.firstResponder as? NSView, "something has the keyboard"))
            let now = name(panel.firstResponder)
            if reached.first == now { break }
            reached.append(now)
        }
        return reached
    }

    /// Tab until this control has the keyboard.
    private func tab(to id: String, in panel: HiddenPanel, file: StaticString = #filePath, line: UInt = #line) throws {
        for _ in 0..<40 where name(panel.firstResponder) != id {
            try Press.key("\t", keyCode: 48, on: try XCTUnwrap(panel.firstResponder as? NSView, file: file, line: line))
        }
        XCTAssertEqual(name(panel.firstResponder), id, "Tab reaches it", file: file, line: line)
    }

    func testEachTabInSettingsOpensItsPage() throws {
        let (settings, _) = settingsPanel()
        for page in SettingsPanel.Page.allCases.reversed() {
            try click(try control("tab \(page.title)", in: settings), page.title)
            XCTAssertEqual(settings.page, page)
        }
    }

    func testTabGoesRoundEveryControlOnEachPageOfSettings() throws {
        QuietFocus.fullKeyboardAccess = { true }
        kittens = [steve]
        var phone = controller.settings
        phone.phone = true
        controller.apply(phone)
        addTeardownBlock { [controller] in controller!.stopPhone() }
        let (settings, panel) = settingsPanel()
        for page in SettingsPanel.Page.allCases {
            settings.select(page)
            let controls = subviews(of: panel.contentView).filter { $0 is QuietButton || $0 is SettingsControl || $0 is OpalField }.map(name)
            XCTAssertEqual(Set(try tabRound(panel)), Set(controls), page.title)
        }
    }

    func testSpaceOnEachTabInSettingsOpensItsPageAndKeepsTheKeyboardThere() throws {
        QuietFocus.fullKeyboardAccess = { true }
        let (settings, panel) = settingsPanel()
        for page in SettingsPanel.Page.allCases.reversed() {
            try tab(to: "tab \(page.title)", in: panel)
            try Press.key(" ", keyCode: 49, on: try XCTUnwrap(panel.firstResponder as? NSView))
            XCTAssertEqual(settings.page, page)
            XCTAssertEqual(name(panel.firstResponder), "tab \(page.title)")
        }
    }

    /// A menu waits in its own loop for a pick, so each is checked to take the click, then picked from straight.
    func testEveryMenuInSettingsSetsWhatYouPick() throws {
        let menus: [(SettingsPanel.Page, String, [String], (Settings) -> String)] = [
            (.agents, "Front door mode", RuntimeMode.allCases.map { "\($0)" }, { "\($0.quickMode)" }),
            (.agents, "Frontier mode", RuntimeMode.allCases.map { "\($0)" }, { "\($0.frontierMode)" }),
            (.voice, "Hold to talk", HoldKey.allCases.map { "\($0)" }, { "\($0.talkKey)" }),
            (.voice, "Hold to dictate", HoldKey.allCases.map { "\($0)" }, { "\($0.dictateKey)" }),
        ]
        let (settings, _) = settingsPanel()
        for (page, id, values, read) in menus {
            settings.select(page)
            let button = try XCTUnwrap(try control(id, in: settings) as? QuietButton, id)
            XCTAssertTrue(try Press.hit(button) === button, "a click lands on \(id)")
            let menu = try XCTUnwrap(button.menu, id)
            XCTAssertEqual(menu.items.count, values.count, id)
            let index = try XCTUnwrap(menu.items.firstIndex { $0.state == .off }, id)
            menu.performActionForItem(at: index)
            XCTAssertEqual(read(controller.settings), values[index], id)
            XCTAssertEqual(try control(id, in: settings).accessibilityValue() as? String, menu.items[index].title, "\(id) says what's picked")
        }
    }

    /// Clicking into a box would hold the test in the box's own loop while it selects, so the box is given the keyboard
    /// the way that click gives it, after checking the click would land there.
    func testEveryBoxInSettingsTakesWhatsTypedWhenReturnIsPressed() throws {
        let boxes: [(SettingsPanel.Page, String, String, (Settings) -> String)] = [
            (.agents, "Front door model", "claudeAgent / claude-sonnet-5-5 / low", { "\($0.quickModel.provider) / \($0.quickModel.model) / \($0.quickModel.effort)" }),
            (.agents, "Frontier model", "claudeAgent / claude-opus-5-5 / max", { "\($0.frontierModel.provider) / \($0.frontierModel.model) / \($0.frontierModel.effort)" }),
            (.agents, "Summary model", "claudeAgent / claude-haiku-5-5 / low", { "\($0.summaryModel.provider) / \($0.summaryModel.model) / \($0.summaryModel.effort)" }),
            (.voice, "Extra words", "Pawsniak, Clawde", { $0.vocabulary.joined(separator: ", ") }),
            (.privacy, "Private apps", "com.example.notes, com.example.mail", { $0.privateApps.joined(separator: ", ") }),
        ]
        let (settings, panel) = settingsPanel()
        for (page, id, typed, read) in boxes {
            settings.select(page)
            let box = try XCTUnwrap(try control(id, in: settings) as? NSTextField, id)
            XCTAssertTrue(try Press.hit(box) === box, "a click lands in \(id)")
            XCTAssertTrue(panel.makeFirstResponder(box), id)
            let editor = try XCTUnwrap(box.currentEditor() as? NSTextView, id)
            editor.selectAll(nil)
            try typeKeys(typed, into: editor)
            try Press.key("\r", keyCode: 36, on: editor)
            XCTAssertEqual(read(controller.settings), typed, id)
        }
    }

    func testEverySwitchInSettingsTurnsItsSettingOnAndOff() throws {
        addTeardownBlock { [controller] in controller!.stopPhone() }
        let switches: [(SettingsPanel.Page, String, (Settings) -> Bool)] = [
            (.notifications, CatWords.doNotDisturb, \.doNotDisturb),
            (.notifications, "When a session finishes", \.notifyFinished),
            (.messages, "Phone", \.phone),
        ]
        let (settings, _) = settingsPanel()
        for (page, id, read) in switches {
            settings.select(page)
            let was = read(controller.settings)
            try click(try control(id, in: settings), id)
            XCTAssertEqual(read(controller.settings), !was, id)
            settings.update(stage.settingsForms.last!)
            XCTAssertEqual((try control(id, in: settings) as? QuietSwitch)?.isOn, !was, "\(id) shows it")
        }
    }

    func testSpaceOnEachSwitchInSettingsTurnsItsSettingOn() throws {
        QuietFocus.fullKeyboardAccess = { true }
        let (settings, panel) = settingsPanel()
        settings.select(.notifications)
        for (id, read) in [(CatWords.doNotDisturb, \Settings.doNotDisturb), ("When a session finishes", \Settings.notifyFinished)] {
            try tab(to: id, in: panel)
            try Press.key(" ", keyCode: 49, on: try XCTUnwrap(panel.firstResponder as? NSView))
            XCTAssertTrue(controller.settings[keyPath: read], id)
        }
    }

    /// Each choice side by side is picked where it's clicked, and with the arrow keys once Tab has reached it.
    func testEachSegmentInSettingsPicksItsChoiceByClickAndByArrow() throws {
        QuietFocus.fullKeyboardAccess = { true }
        let (settings, panel) = settingsPanel(on: .messages)
        func segments(_ id: String) throws -> QuietSegments { try XCTUnwrap(try control(id, in: settings) as? QuietSegments, id) }
        func point(_ index: Int, of segments: QuietSegments) -> NSPoint {
            let width = (segments.bounds.width - 4) / CGFloat(segments.titles.count)
            return NSPoint(x: 2 + width * (CGFloat(index) + 0.5), y: segments.bounds.midY)
        }
        for (index, size) in [TextSize.small, .standard, .large, .larger].enumerated().reversed() {
            let picker = try segments("Text size")
            XCTAssertTrue(try Press.hit(picker, at: point(index, of: picker)) === picker)
            try Press.click(picker, at: point(index, of: picker))
            XCTAssertEqual(controller.settings.textSize, size)
        }
        let opens = try segments("Open threads in")
        try Press.click(opens, at: point(1, of: opens))
        XCTAssertFalse(controller.settings.openInMessages, "T3")

        try tab(to: "Open threads in", in: panel)
        try Press.key(String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)), keyCode: 123, on: try XCTUnwrap(panel.firstResponder as? NSView))
        XCTAssertTrue(controller.settings.openInMessages, "back to The Kitty Litter")
        try tab(to: "Text size", in: panel)
        try Press.key(String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)), keyCode: 124, on: try XCTUnwrap(panel.firstResponder as? NSView))
        XCTAssertEqual(controller.settings.textSize, .standard, "one along from Small")
    }

    func testPairInSettingsShowsANewCode() async throws {
        let (controller, stage, _) = try await phoneController()
        let shown = stage.pairings.count
        let panel = HiddenPanel(allowsKey: true)
        let settings = SettingsPanel(panel: panel)
        settings.onPairPhone = { controller.pairPhone() }
        controller.settingsPressed()
        settings.show(stage.settingsShown.last!.form, near: NSPoint(x: 1000, y: 700))
        defer { settings.hide() }
        settings.select(.messages)
        try click(try button("Pair a phone", in: panel.contentView), "Pair…")
        await until { stage.pairings.count > shown }
        XCTAssertNotNil(stage.pairings.last ?? nil, "a code to scan")
    }

    func testDoneAndOpenSettingsFolderInSettings() throws {
        let (settings, _) = settingsPanel()
        var opened: [URL] = []
        settings.openFolder = { opened.append($0) }
        try click(try button("Open settings folder", in: settings.panel.contentView), "Open settings folder")
        XCTAssertEqual(opened, [Settings.directory])
        try click(try button("Done", in: settings.panel.contentView), "Done")
        XCTAssertFalse(settings.isVisible)
    }

    func testSpaceOnDoneClosesSettings() throws {
        QuietFocus.fullKeyboardAccess = { true }
        let (settings, panel) = settingsPanel()
        try tab(to: "Done", in: panel)
        try Press.key(" ", keyCode: 49, on: try XCTUnwrap(panel.firstResponder as? NSView))
        XCTAssertFalse(settings.isVisible)
    }

    func testEscClosesSettingsWhetherOrNotABoxIsTyping() throws {
        let (settings, panel) = settingsPanel()
        try Press.key("\u{1b}", keyCode: 53, on: try XCTUnwrap(panel.firstResponder as? NSView))
        XCTAssertFalse(settings.isVisible, "with no box typing")

        let (typing, typingPanel) = settingsPanel()
        let box = try XCTUnwrap(try control("Front door model", in: typing) as? NSTextField)
        typingPanel.makeFirstResponder(box)
        try Press.key("\u{1b}", keyCode: 53, on: try XCTUnwrap(box.currentEditor() as? NSTextView))
        XCTAssertFalse(typing.isVisible, "while a box has the keyboard")
    }

    func testCommandWClosesSettingsWhetherOrNotABoxIsTyping() throws {
        for typing in [false, true] {
            let (settings, panel) = settingsPanel()
            if typing { panel.makeFirstResponder(try control("Front door model", in: settings)) }
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0, context: nil, characters: "w", charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13))
            XCTAssertTrue(panel.performKeyEquivalent(with: event))
            XCTAssertFalse(settings.isVisible, typing ? "while a box has the keyboard" : "with no box typing")
        }
    }

    /// Font and each channel's notifications make their menu as it opens, so there's no menu to pick from without
    /// opening it, which a test can't do. This checks a click lands on each.
    func testAClickLandsOnFontAndEachChannelsNotifications() throws {
        kittens = [steve]
        let (settings, _) = settingsPanel(on: .notifications)
        for id in [CatWords.shades, "Steve Pawsniak"] {
            let button = try control(id, in: settings)
            XCTAssertTrue(try Press.hit(button) === button, id)
        }
        settings.select(.messages)
        let font = try control("Font", in: settings)
        XCTAssertTrue(try Press.hit(font) === font)
    }

    // MARK: - The menu bar

    /// The menu bar's items, wired to the controller as the app wires them.
    private func menuBar() -> MenuBar {
        let bar = MenuBar()
        bar.onAsk = { [unowned controller] in controller!.askPressed() }
        bar.onFix = { [unowned controller] in controller!.fixPressed() }
        bar.onKittens = { [unowned controller] in controller!.kittensPressed() }
        bar.onMessages = { [unowned controller] in controller!.channelsPressed() }
        bar.onSettings = { [unowned controller] in controller!.settingsPressed() }
        bar.isDoNotDisturb = { [unowned controller] in controller!.settings.doNotDisturb }
        bar.onDoNotDisturb = { [unowned controller] in controller!.doNotDisturbPressed() }
        bar.held = [.ask, .fix, .messages]
        return bar
    }

    /// An item runs once the menu has closed, so it's waited for.
    private func choose(_ title: String, in bar: MenuBar) async throws {
        let item = try XCTUnwrap(bar.shownItems.first { $0.title == title }, "no item [\(title)]")
        XCTAssertTrue(item.isEnabled, title)
        let menu = try XCTUnwrap(item.menu)
        menu.performActionForItem(at: menu.index(of: item))
        await drain()
    }

    private func drain() async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in DispatchQueue.main.async { done.resume() } }
        await settle()
    }

    func testEachMenuBarItemDoesWhatItSays() async throws {
        kittens = [steve]
        let bar = menuBar()
        try await choose(CatWords.appName, in: bar)
        XCTAssertEqual(stage.channelsShown.count, 1, "The Kitty Litter opens")
        try await choose("Ask…", in: bar)
        XCTAssertNotNil(stage.input, "the Ask box opens")
        stage.hideInput()
        try await choose("Fix What I'm Looking At", in: bar)
        XCTAssertTrue(stage.log.all.contains("pickRegion"), "Fix asks where to look")
        try await choose(CatWords.kittensTitle, in: bar)
        XCTAssertEqual(stage.kittens?.map(\.kitten.name), ["Steve Pawsniak"], "the kittens view opens")
        try await choose(CatWords.doNotDisturb, in: bar)
        XCTAssertTrue(controller.settings.doNotDisturb)
        XCTAssertEqual(bar.shownItems.first { $0.title == CatWords.doNotDisturb }?.state, .on, "ticked while it's on")
        try await choose("Settings…", in: bar)
        XCTAssertEqual(stage.settingsShown.count, 1, "Settings opens")
        var ran = 0
        bar.extras = [MenuBar.Extra(title: "Set Up Permissions…") { ran += 1 }]
        try await choose("Set Up Permissions…", in: bar)
        XCTAssertEqual(ran, 1)
    }

    func testPairPhoneInTheMenuShowsANewCode() async throws {
        let (controller, stage, _) = try await phoneController()
        let shown = stage.pairings.count
        let bar = MenuBar()
        bar.canPairPhone = { controller.phone != nil }
        bar.onPairPhone = { controller.pairPhone() }
        try await choose(CatWords.pairItem, in: bar)
        await until { stage.pairings.count > shown }
        XCTAssertNotNil(stage.pairings.last ?? nil)
    }

    /// While the menu is open, each shortcut it shows chooses its item.
    func testEachShortcutTheMenuShowsChoosesItsItem() async throws {
        let bar = menuBar()
        for (title, shortcut) in [(CatWords.appName, Shortcut.messages), ("Ask…", .ask), ("Fix What I'm Looking At", .fix)] {
            let item = try XCTUnwrap(bar.shownItems.first { $0.title == title })
            XCTAssertEqual(item.keyEquivalent, shortcut.key, title)
            XCTAssertEqual(item.keyEquivalentModifierMask, shortcut.keyModifiers, title)
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: shortcut.keyModifiers, timestamp: 0, windowNumber: 0, context: nil, characters: shortcut.key, charactersIgnoringModifiers: shortcut.key, isARepeat: false, keyCode: UInt16(shortcut.keyCode)))
            XCTAssertTrue(try XCTUnwrap(item.menu).performKeyEquivalent(with: event), title)
            await drain()
        }
        XCTAssertEqual(stage.channelsShown.count, 1, "⌃⌘B opens The Kitty Litter")
        XCTAssertTrue(stage.log.all.contains("showInput"), "⌥Space opens the Ask box")
        XCTAssertTrue(stage.log.all.contains("pickRegion"), "⌃⌥F asks where to look")
    }
}
