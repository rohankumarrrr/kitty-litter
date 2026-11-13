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
    private var kittens: [Kitten] = []
    private var controller: AppController!

    override func setUp() async throws {
        Motion.forced = true
        QuietFocus.fullKeyboardAccess = { false }
        stage = FakeStage(log: Log())
        backend = FakeBackend()
        controller = AppController(
            dependencies: AppDependencies(
                backend: backend,
                context: FakeContext(log: Log()),
                voice: FakeVoice(),
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
    }

    override func tearDown() async throws {
        Motion.forced = motion
        QuietFocus.fullKeyboardAccess = { NSApplication.shared.isFullKeyboardAccessEnabled }
        MessagesInk.textSize = .standard
        MessagesInk.fontFamily = nil
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
}
