import AppKit
@testable import Shades
import ShadesContext
import ShadesCore
import XCTest

/// Messages' chrome, boxes and shortcuts, pressed the way a person presses them: by mouse through the window's own
/// hit-testing, and by keyboard with Tab, Space and the real keys, routed through Messages' own panel. The panel is
/// never shown, and nothing is posted to the system.
@MainActor
final class PressChromeTests: XCTestCase {
    private let steve = Kitten(name: "Steve Pawsniak", role: "Professional", covers: "", folder: "/k/steve")
    private let pepper = Kitten(name: "Pepper", role: "Finance", covers: "", folder: "/k/pepper")
    private let at = Date(timeIntervalSince1970: 1_000_000)

    /// Messages' own panel, title bar and all, saying it has the keyboard, since a test can't make a real one key.
    private final class KeyPanel: ChannelsPanel {
        override var isKeyWindow: Bool { true }
    }

    /// Everything Messages hands to the rest of the app.
    private final class Calls {
        var actions: [MessagesAction] = []
        var openedInT3: [String] = []
        var phone: [String] = []
        var attach = 0
        var mic = 0
        var settings = 0
        var closedWindow = 0
    }

    override func setUp() async throws {
        QuietFocus.fullKeyboardAccess = { false }
    }

    override func tearDown() async throws {
        QuietFocus.fullKeyboardAccess = { NSApplication.shared.isFullKeyboardAccessEnabled }
    }

    // MARK: - Data

    private func thread(_ id: String, of kitten: Kitten, title: String, status: AgentStatus = .completed) -> AgentThread {
        AgentThread(id: id, title: title, projectTitle: kitten.name, status: status, model: "m", updatedAt: at, projectPath: kitten.folder)
    }

    private func said(_ id: String, _ ask: String, at offset: TimeInterval, count: Int = 1) -> [Exchange] {
        (0..<count).map { index in
            let when = at.addingTimeInterval(offset + TimeInterval(index * 2))
            return Exchange(id: "\(id)-\(index)", asker: .you, askedAt: when, ask: "\(ask) \(index)", reply: "Done \(index).", repliedAt: when.addingTimeInterval(1))
        }
    }

    /// Steve has a finished thread and one in progress, Pepper one, and the cat a piece of its own work.
    private func book(waiting: Waiting = Waiting(), exchanges: Int = 1, hasPhone: Bool = false, olderPages: [ChannelID: Int] = [:]) -> ChannelBook {
        let fix = AgentThread(id: "fix", title: "Fix: the dock", projectTitle: nil, status: .completed, model: "m", updatedAt: at)
        return ChannelBook.build(
            kittens: [steve, pepper],
            threads: [thread("s1", of: steve, title: "Resume"), thread("s2", of: steve, title: "Cover letter", status: .running), thread("p1", of: pepper, title: "Budget"), fix],
            transcripts: ["s1": said("s1", "Tidy my resume", at: 0, count: exchanges), "s2": said("s2", "Write a cover letter", at: 1000), "p1": said("p1", "Check my budget", at: 500), "fix": said("fix", "Fix it", at: 200)],
            isReading: false, unreadable: 0, cantReachT3: false,
            waiting: waiting,
            catsWork: ["fix"],
            hasPhone: hasPhone,
            olderPages: olderPages
        )
    }

    /// Messages in its own panel, at its usual size, recording what it hands on.
    private func messages(_ book: ChannelBook) -> (KeyPanel, ChannelsView, Calls) {
        let panel = KeyPanel()
        let view = ChannelsView(frame: NSRect(origin: .zero, size: ChannelsWindow.size))
        panel.contentView = view
        panel.setContentSize(ChannelsWindow.size)
        let calls = Calls()
        view.onAction = { calls.actions.append($0) }
        view.onOpenThread = { calls.openedInT3.append($0) }
        view.onShowOnPhone = { calls.phone.append($0) }
        view.onAttach = { _, _ in calls.attach += 1 }
        view.onMic = { calls.mic += 1 }
        view.onSettings = { calls.settings += 1 }
        view.sidebar.onSettings = { calls.settings += 1 }
        view.onCloseWindow = { calls.closedWindow += 1 }
        view.show(book)
        view.layoutSubtreeIfNeeded()
        return (panel, view, calls)
    }

    private func subviews(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(subviews)
    }

    private func button(_ title: String, in view: NSView, file: StaticString = #filePath, line: UInt = #line) throws -> QuietButton {
        view.window?.contentView?.layoutSubtreeIfNeeded()
        let buttons = subviews(of: view).compactMap { $0 as? QuietButton }.filter { !$0.isHiddenOrHasHiddenAncestor }
        return try XCTUnwrap(buttons.first { $0.accessibilityLabel() == title }, "no \(title) in \(buttons.compactMap { $0.accessibilityLabel() })", file: file, line: line)
    }

    // MARK: - Pressing

    /// A click that lands on `control` itself, not on something over it, pressed down and let go there.
    private func click(_ control: NSView, _ name: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let hit = try Press.hit(control, file: file, line: line)
        XCTAssertTrue(hit === control, "a click on \(name) lands on it, not on \(type(of: hit))", file: file, line: line)
        try Press.click(control, file: file, line: line)
    }

    /// A click at `point` in `view`, for what's drawn rather than made of views, such as the jump box's rows.
    @discardableResult
    private func click(at point: NSPoint, in view: NSView, file: StaticString = #filePath, line: UInt = #line) throws -> NSView {
        let window = try XCTUnwrap(view.window, file: file, line: line)
        window.contentView?.layoutSubtreeIfNeeded()
        let root = try XCTUnwrap(window.contentView?.superview, file: file, line: line)
        let location = view.convert(point, to: nil)
        let target = try XCTUnwrap(root.hitTest(root.convert(location, from: nil)), file: file, line: line)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1), file: file, line: line)
            type == .leftMouseDown ? target.mouseDown(with: event) : target.mouseUp(with: event)
        }
        return target
    }

    /// A key pressed and let go in the panel, handed on the way the app hands it on: as a key equivalent first, and then
    /// to whatever has the keyboard.
    private func key(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = [], in panel: NSWindow, file: StaticString = #filePath, line: UInt = #line) throws {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: panel.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode), file: file, line: line)
            if type == .keyUp || !panel.performKeyEquivalent(with: event) { panel.sendEvent(event) }
        }
    }

    private func space(in panel: NSWindow) throws { try key(" ", keyCode: 49, in: panel) }
    private func escape(in panel: NSWindow) throws { try key("\u{1b}", keyCode: 53, in: panel) }
    private func returnKey(in panel: NSWindow) throws { try key("\r", keyCode: 36, in: panel) }
    private func arrow(_ up: Bool, modifiers: NSEvent.ModifierFlags = [], in panel: NSWindow) throws {
        let characters = String(Character(UnicodeScalar(up ? NSUpArrowFunctionKey : NSDownArrowFunctionKey)!))
        try key(characters, keyCode: up ? 126 : 125, modifiers: modifiers.union([.numericPad, .function]), in: panel)
    }

    /// Tabs round the panel from its first stop until the keyboard is on `control`, as Tab does with Full Keyboard
    /// Access on.
    private func tab(to control: NSView, in panel: NSWindow, file: StaticString = #filePath, line: UInt = #line) {
        panel.recalculateKeyViewLoop()
        panel.makeFirstResponder(panel.contentView?.nextValidKeyView)
        var stops: [String] = []
        for _ in 0..<80 {
            if panel.firstResponder === control { return }
            stops.append((panel.firstResponder as? NSView)?.accessibilityLabel() ?? "\(type(of: panel.firstResponder!))")
            panel.selectNextKeyView(nil)
        }
        XCTFail("Tab never reaches \(control.accessibilityLabel() ?? "\(type(of: control))"), only \(stops)", file: file, line: line)
    }

    /// Tab reaches it, and Space presses it.
    private func tabAndSpace(_ control: NSView, in panel: NSWindow, file: StaticString = #filePath, line: UInt = #line) throws {
        tab(to: control, in: panel, file: file, line: line)
        try space(in: panel)
    }

    // MARK: - The header

    func testAThreadsHeaderShowsOnPhoneOpensInT3AndClosesByMouse() throws {
        let (_, view, calls) = messages(book(hasPhone: true))
        view.select(.thread("fix", in: .channel(.shades)))
        try click(try button(CatWords.showOnPhone, in: view.threadPane), "Show on phone")
        XCTAssertEqual(calls.phone, ["fix"])
        try click(try button(CatWords.openInT3, in: view.threadPane), "Open in T3")
        XCTAssertEqual(calls.openedInT3, ["fix"])
        try click(try button(CatWords.closeThread, in: view.threadPane), "✕")
        XCTAssertEqual(view.selection, .channel(.shades))
        XCTAssertTrue(view.threadPane.isHidden)
    }

    func testAThreadsHeaderShowsOnPhoneOpensInT3AndClosesByKeyboard() throws {
        QuietFocus.fullKeyboardAccess = { true }
        let (panel, view, calls) = messages(book(hasPhone: true))
        view.select(.thread("fix", in: .channel(.shades)))
        try tabAndSpace(try button(CatWords.showOnPhone, in: view.threadPane), in: panel)
        XCTAssertEqual(calls.phone, ["fix"])
        try tabAndSpace(try button(CatWords.openInT3, in: view.threadPane), in: panel)
        XCTAssertEqual(calls.openedInT3, ["fix"])
        try tabAndSpace(try button(CatWords.closeThread, in: view.threadPane), in: panel)
        XCTAssertEqual(view.selection, .channel(.shades))
    }

    func testAChannelsInProgressGoesToActivityByMouseAndKeyboard() throws {
        let (panel, view, _) = messages(book())
        view.select(.channel(.of(steve)))
        try click(try button(CatWords.issues(1), in: view.pane), "1 in progress")
        XCTAssertEqual(view.selection, .activity)

        QuietFocus.fullKeyboardAccess = { true }
        view.select(.channel(.of(steve)))
        try tabAndSpace(try button(CatWords.issues(1), in: view.pane), in: panel)
        XCTAssertEqual(view.selection, .activity)
    }

    // MARK: - The sidebar

    func testEverySidebarRowShowsItsPlaceWhenClicked() throws {
        let (_, view, _) = messages(book())
        let places: [ChannelPlace] = [.threads, .channel(.general), .channel(.of(steve)), .channel(.of(pepper)), .channel(.shades), .activity]
        XCTAssertEqual(Set(places.map { "\($0)" }), Set(ChannelSidebarItem.places(in: book()).map { "\($0)" }), "every row")
        for place in places {
            let row = try XCTUnwrap(view.sidebar.row(for: place))
            try click(row, row.item.title)
            XCTAssertEqual(view.selection, ChannelSelection(place), row.item.title)
            XCTAssertTrue(row.isSelected)
        }
    }

    func testTheSidebarsPlacesAreReachedByTheirKeys() throws {
        let (panel, view, _) = messages(book())
        let places = ChannelSidebarItem.places(in: book())
        for (index, place) in places.enumerated() {
            let digit = ["1", "2", "3", "4", "5", "6"][index]
            let code: UInt16 = [18, 19, 20, 21, 23, 22][index]
            try key(digit, keyCode: code, modifiers: .command, in: panel)
            XCTAssertEqual(view.selection, ChannelSelection(place), "⌘\(digit)")
        }
        try key("1", keyCode: 18, modifiers: .command, in: panel)
        try arrow(false, modifiers: .option, in: panel)
        XCTAssertEqual(view.selection, ChannelSelection(places[1]), "⌥↓")
        try arrow(true, modifiers: .option, in: panel)
        XCTAssertEqual(view.selection, ChannelSelection(places[0]), "⌥↑")
    }

    func testDoNotDisturbShortcutsAndSettingsWorkByMouse() throws {
        let (_, view, calls) = messages(book())
        try click(view.sidebar.quietButton, "Do Not Disturb")
        XCTAssertEqual(calls.actions, [.doNotDisturb])
        var quiet = book()
        quiet.waiting.doNotDisturb = true
        view.show(quiet)
        try click(view.sidebar.quietOnButton, "Do Not Disturb, on")
        XCTAssertEqual(calls.actions, [.doNotDisturb, .doNotDisturb], "and again to turn it off")

        try click(view.sidebar.shortcutsButton, "⌘/ Shortcuts")
        XCTAssertFalse(view.cheatsheet.isHidden)
        view.cheatsheet.isHidden = true
        try click(view.sidebar.settingsButton, "Settings")
        XCTAssertEqual(calls.settings, 1)
    }

    func testDoNotDisturbShortcutsAndSettingsWorkByKeyboard() throws {
        QuietFocus.fullKeyboardAccess = { true }
        let (panel, view, calls) = messages(book())
        try tabAndSpace(view.sidebar.quietButton, in: panel)
        XCTAssertEqual(calls.actions, [.doNotDisturb])
        try tabAndSpace(view.sidebar.shortcutsButton, in: panel)
        XCTAssertFalse(view.cheatsheet.isHidden)
        view.cheatsheet.isHidden = true
        try tabAndSpace(view.sidebar.settingsButton, in: panel)
        XCTAssertEqual(calls.settings, 1)
        try key(",", keyCode: 43, modifiers: .command, in: panel)
        XCTAssertEqual(calls.settings, 2, "⌘,")
    }

    // MARK: - The thread pane's edge

    /// Takes hold of `edge` `grab` into it, or at its middle, drags it `dx` across in two steps, and lets go.
    private func drag(_ edge: NSView, by dx: CGFloat, grabbing grab: CGFloat? = nil, in panel: NSWindow) throws {
        let start = edge.convert(NSPoint(x: grab ?? edge.bounds.midX, y: edge.bounds.midY), to: nil)
        let target = try Press.hit(edge)
        for (type, x) in [(NSEvent.EventType.leftMouseDown, start.x), (.leftMouseDragged, start.x + dx / 2), (.leftMouseDragged, start.x + dx), (.leftMouseUp, start.x + dx)] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: start.y), modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            switch type {
            case .leftMouseDown: target.mouseDown(with: event)
            case .leftMouseDragged: target.mouseDragged(with: event)
            default: target.mouseUp(with: event)
            }
        }
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    func testDraggingTheSidebarsEdgeChangesItsWidthHidesItAndCommandBBringsItBack() throws {
        let (panel, view, _) = messages(book())
        view.select(.channel(.of(steve)))
        view.layoutSubtreeIfNeeded()
        let edge = view.sidebarEdge
        XCTAssertTrue(try Press.hit(edge) === edge, "a press on the line beside the sidebar lands on its edge")
        let before = view.sidebar.frame.width
        for grab in [0.5, edge.bounds.midX, edge.bounds.maxX - 0.5] {
            try drag(edge, by: 0, grabbing: grab, in: panel)
            XCTAssertEqual(view.sidebar.frame.width, before, accuracy: 0.01, "taking hold of the line \(grab) into its edge doesn't move it")
        }
        try drag(edge, by: 40, grabbing: 0.5, in: panel)
        XCTAssertEqual(view.sidebar.frame.width, before + 40, accuracy: 0.01, "dragged right, the sidebar widens as far as the pointer went")
        XCTAssertEqual(view.pane.frame.minX, view.sidebar.frame.maxX)
        try drag(edge, by: -2000, in: panel)
        XCTAssertTrue(view.sidebar.isHidden, "dragged most of the way shut, it hides")

        try key("b", keyCode: 11, modifiers: .command, in: panel)
        view.layoutSubtreeIfNeeded()
        XCTAssertFalse(view.sidebar.isHidden, "⌘B brings it back")
        try key("b", keyCode: 11, modifiers: .command, in: panel)
        view.layoutSubtreeIfNeeded()
        XCTAssertTrue(view.sidebar.isHidden, "and hides it again")
    }

    func testDraggingTheThreadPanesEdgeChangesItsWidthWithinItsLimits() throws {
        let (panel, view, _) = messages(book())
        view.select(.thread("s1", in: .channel(.of(steve))))
        view.layoutSubtreeIfNeeded()
        XCTAssertTrue(try Press.hit(view.threadEdge) === view.threadEdge, "a press on the line between the panes lands on its edge")

        func drag(by dx: CGFloat, grabbing grab: CGFloat? = nil) throws {
            try self.drag(view.threadEdge, by: dx, grabbing: grab, in: panel)
        }

        let before = view.threadPane.frame.width
        for grab in [0.5, view.threadEdge.bounds.midX, view.threadEdge.bounds.maxX - 0.5] {
            try drag(by: 0, grabbing: grab)
            XCTAssertEqual(view.threadPane.frame.width, before, accuracy: 0.01, "taking hold of the line \(grab) into its edge doesn't move it")
        }
        try drag(by: -60, grabbing: view.threadEdge.bounds.maxX - 0.5)
        XCTAssertEqual(view.threadPane.frame.width, before + 60, accuracy: 0.01, "dragged left, the thread's pane widens as far as the pointer went")
        XCTAssertEqual(view.pane.frame.maxX, view.threadPane.frame.minX)
        try drag(by: 30)
        XCTAssertEqual(view.threadPane.frame.width, before + 30, accuracy: 0.01, "and right, it narrows")
        try drag(by: -2000)
        XCTAssertEqual(view.pane.frame.width, ChannelsView.narrowestPlace, "the place beside it still reads")
        try drag(by: 2000)
        XCTAssertEqual(view.threadPane.frame.width, ChannelsView.threadWidths.lowerBound, "and so does the thread")
    }
}

// MARK: - Threads and Activity

extension PressChromeTests {
    private var approval: ApprovalRequest {
        ApprovalRequest(id: "ap", threadID: "s1", threadTitle: "Resume", kind: .command, summary: "Run: ls", createdAt: at)
    }

    private var question: AgentQuestion {
        AgentQuestion(id: "q", threadID: "s1", threadTitle: "Resume", text: "Which font?", form: AnswerForm(parts: [AnswerForm.Part(key: "f", text: "Which font?", options: ["Serif", "Sans"], values: ["serif", "sans"], takesOwnWords: false)]))
    }

    private var months: AgentQuestion {
        AgentQuestion(id: "q2", threadID: "p1", threadTitle: "Budget", text: "Which months?", form: AnswerForm(parts: [AnswerForm.Part(key: "m", text: "Which months?", options: ["Dec", "Jan"], values: ["dec", "jan"], takesOwnWords: false, picksSeveral: true)]))
    }

    private var decision: InboxEntry {
        InboxEntry(id: "d", kind: .decision, text: "Merged. Say ship it.", threadID: "s1", threadTitle: "Resume", at: at)
    }

    /// Shipped work in a thread Messages hasn't read, so it opens in T3.
    private var shipped: InboxEntry {
        InboxEntry(id: "sh", kind: .shipped, text: "Shipped the old work.", threadID: "gone", threadTitle: "Old work", at: at)
    }

    /// An approval, a question with one answer, one you pick several for, a decision and something shipped.
    private func activityBook() -> ChannelBook {
        book(waiting: Waiting(approvals: [approval], questions: [question, months], owners: ["ap": steve.id, "q": steve.id, "q2": pepper.id], reports: [decision, shipped]))
    }

    private func rows(in pane: ChannelPane) -> [ChannelRowView] {
        subviews(of: pane.list).compactMap { $0 as? ChannelRowView }
    }

    /// The card that says `text`, scrolled to where you can see it.
    private func card(_ text: String, in view: ChannelsView, file: StaticString = #filePath, line: UInt = #line) throws -> CardRowView {
        let card = try XCTUnwrap(rows(in: view.pane).compactMap { $0 as? CardRowView }.first { $0.accessibilityLabel()?.contains(text) == true }, "a card saying \(text)", file: file, line: line)
        card.scrollToVisible(card.bounds)
        return card
    }

    private func cardButton(_ title: String, on text: String, in view: ChannelsView, file: StaticString = #filePath, line: UInt = #line) throws -> QuietButton {
        let card = try card(text, in: view, file: file, line: line)
        return try XCTUnwrap(card.buttons.first { $0.accessibilityLabel() == title }, "\(title) on \(text)", file: file, line: line)
    }

    /// Tab to the pane's messages, then the arrow keys down to `row`, the way a person gets to a row and its buttons.
    private func arrow(to row: () throws -> ChannelRowView, in pane: ChannelPane, panel: NSWindow, file: StaticString = #filePath, line: UInt = #line) throws {
        tab(to: pane.list, in: panel, file: file, line: line)
        let target = try row()
        for _ in 0..<40 where pane.currentRow !== target { try arrow(false, in: panel) }
        XCTAssertTrue(pane.currentRow === target, "the arrow keys reach it", file: file, line: line)
    }

    /// Each button on Activity's cards, pressed by mouse and then by keyboard in a fresh window, and what it did.
    private func pressEveryWay(_ title: String, on text: String, file: StaticString = #filePath, line: UInt = #line, check: (ChannelsView, Calls, String) throws -> Void) throws {
        for byKeyboard in [false, true] {
            QuietFocus.fullKeyboardAccess = { byKeyboard }
            let (panel, view, calls) = messages(activityBook())
            if byKeyboard {
                try arrow(to: { try card(text, in: view) }, in: view.pane, panel: panel, file: file, line: line)
                try tabAndSpace(try cardButton(title, on: text, in: view, file: file, line: line), in: panel, file: file, line: line)
            } else {
                try click(try cardButton(title, on: text, in: view, file: file, line: line), title, file: file, line: line)
            }
            try check(view, calls, "\(title) on \(text) \(byKeyboard ? "by keyboard" : "by mouse")")
        }
    }

    func testAnApprovalsButtonsAnswerItOrOpenItsThread() throws {
        for (title, decision) in [("Deny", ApprovalDecision.decline), ("Allow", .accept), ("Allow for this session", .acceptForSession)] {
            try pressEveryWay(title, on: "Run: ls") { _, calls, name in
                XCTAssertEqual(calls.actions, [.approval(approval, decision)], name)
            }
        }
        try pressEveryWay(CatWords.viewThread, on: "Run: ls") { view, calls, name in
            XCTAssertEqual(view.selection, .thread("s1", in: .channel(.of(steve))), name)
            XCTAssertEqual(calls.actions, [], name)
        }
    }

    func testAQuestionsOptionsAnswerIt() throws {
        for (option, value) in [("Serif", "serif"), ("Sans", "sans")] {
            try pressEveryWay(option, on: "Which font?") { _, calls, name in
                XCTAssertEqual(calls.actions, [.answer(question, [[value]])], name)
            }
        }
        try pressEveryWay(CatWords.viewThread, on: "Which font?") { view, _, name in
            XCTAssertEqual(view.selection, .thread("s1", in: .channel(.of(steve))), name)
        }
    }

    func testPickingSeveralOptionsSendsThemOnlyOnceSubmitIsPressed() throws {
        for byKeyboard in [false, true] {
            QuietFocus.fullKeyboardAccess = { byKeyboard }
            let (panel, view, calls) = messages(activityBook())
            func press(_ title: String) throws {
                let button = try cardButton(title, on: "Which months?", in: view)
                if byKeyboard {
                    try arrow(to: { try card("Which months?", in: view) }, in: view.pane, panel: panel)
                    try tabAndSpace(button, in: panel)
                } else {
                    try click(button, title)
                }
            }
            let name = byKeyboard ? "by keyboard" : "by mouse"
            try press(CatWords.sendPicked)
            XCTAssertEqual(calls.actions, [], "\(name): nothing's picked, so Send does nothing")
            try press("Dec")
            XCTAssertEqual(try cardButton("Dec", on: "Which months?", in: view).accessibilityValue() as? Int, 1, "\(name): picked")
            XCTAssertEqual(calls.actions, [], "\(name): picking only marks it")
            try press("Jan")
            try press("Jan")
            try press(CatWords.sendPicked)
            XCTAssertEqual(calls.actions, [.answer(months, [["dec"]])], name)
        }
    }

    func testAReportsReplyDoneAndWayToItsThreadWork() throws {
        try pressEveryWay("Reply", on: "Merged. Say ship it.") { view, _, name in
            XCTAssertEqual(view.selection, .thread("s1", in: .channel(.of(steve))), name)
            XCTAssertTrue(view.window?.firstResponder === view.threadPane.composer.textView, "\(name): ready to type")
        }
        try pressEveryWay("Done", on: "Merged. Say ship it.") { _, calls, name in
            XCTAssertEqual(calls.actions, [.inbox(.done(id: "d"))], name)
        }
        try pressEveryWay(CatWords.viewThread, on: "Merged. Say ship it.") { view, _, name in
            XCTAssertEqual(view.selection, .thread("s1", in: .channel(.of(steve))), name)
        }
        try pressEveryWay("Ask", on: "Shipped the old work.") { view, _, name in
            XCTAssertEqual(view.selection.thread, "gone", name)
            XCTAssertTrue(view.window?.firstResponder === view.threadPane.composer.textView, "\(name): ready to type")
        }
        try pressEveryWay(CatWords.openInT3, on: "Shipped the old work.") { _, calls, name in
            XCTAssertEqual(calls.openedInT3, ["gone"], name)
        }
    }

    func testClearingASectionOfActivityByMouseAndKeyboard() throws {
        for byKeyboard in [false, true] {
            QuietFocus.fullKeyboardAccess = { byKeyboard }
            let (panel, view, calls) = messages(activityBook())
            func section() throws -> SectionRowView {
                let row = try XCTUnwrap(rows(in: view.pane).compactMap { $0 as? SectionRowView }.first { $0.clear != nil })
                row.scrollToVisible(row.bounds)
                return row
            }
            let clear = try XCTUnwrap(try section().clear)
            if byKeyboard {
                try arrow(to: section, in: view.pane, panel: panel)
                try tabAndSpace(clear, in: panel)
            } else {
                try click(clear, "Clear")
            }
            XCTAssertEqual(calls.actions, [.inbox(.clear(.shipped))], byKeyboard ? "by keyboard" : "by mouse")
        }
    }

    func testWhatsInProgressInActivityOpensBesideItsChannel() throws {
        for byKeyboard in [false, true] {
            QuietFocus.fullKeyboardAccess = { byKeyboard }
            let (panel, view, _) = messages(book())
            func issue() throws -> IssueRowView {
                let row = try XCTUnwrap(rows(in: view.pane).compactMap { $0 as? IssueRowView }.first)
                row.scrollToVisible(row.bounds)
                return row
            }
            if byKeyboard {
                try arrow(to: issue, in: view.pane, panel: panel)
                try space(in: panel)
            } else {
                try click(try issue(), "Cover letter, in progress")
            }
            XCTAssertEqual(view.selection, .thread("s2", in: .channel(.of(steve))), byKeyboard ? "by keyboard" : "by mouse")
        }
    }

    func testThreadsRowsOpenEachThreadBesideTheList() throws {
        for byKeyboard in [false, true] {
            QuietFocus.fullKeyboardAccess = { byKeyboard }
            let (panel, view, _) = messages(book())
            view.select(.threads)
            let ids = book().yours.map(\.id)
            XCTAssertGreaterThan(ids.count, 1)
            for (index, id) in ids.enumerated() {
                view.select(.threads)
                func row() throws -> ThreadDigestRowView {
                    let rows = rows(in: view.pane).compactMap { $0 as? ThreadDigestRowView }
                    XCTAssertEqual(rows.count, ids.count)
                    let row = rows[index]
                    row.scrollToVisible(row.bounds)
                    return row
                }
                if byKeyboard {
                    try arrow(to: row, in: view.pane, panel: panel)
                    try space(in: panel)
                } else {
                    try click(try row(), "a thread in Threads")
                }
                XCTAssertEqual(view.selection, .thread(id, in: .threads), "\(id) \(byKeyboard ? "by keyboard" : "by mouse")")
            }
        }
    }
}

// MARK: - The box

extension PressChromeTests {
    private func threadBox() -> (KeyPanel, ChannelsView, Calls, ChannelComposer) {
        let (panel, view, calls) = messages(book())
        view.select(.thread("s1", in: .channel(.of(steve))))
        view.layoutSubtreeIfNeeded()
        return (panel, view, calls, view.threadPane.composer)
    }

    func testAttachAndTheMicWorkByMouseAndKeyboard() throws {
        for byKeyboard in [false, true] {
            QuietFocus.fullKeyboardAccess = { byKeyboard }
            let (panel, _, calls, composer) = threadBox()
            let name = byKeyboard ? "by keyboard" : "by mouse"
            let attach = try button(CatWords.attachRecent, in: composer)
            byKeyboard ? try tabAndSpace(attach, in: panel) : try click(attach, "Attach")
            XCTAssertEqual(calls.attach, 1, name)
            byKeyboard ? try tabAndSpace(composer.mic, in: panel) : try click(composer.mic, "the mic")
            XCTAssertEqual(calls.mic, 1, name)
            XCTAssertTrue(panel.firstResponder === composer.textView, "\(name): what you say goes in this box")
        }
    }

    func testAnAttachmentsCrossTakesItOff() throws {
        for byKeyboard in [false, true] {
            QuietFocus.fullKeyboardAccess = { byKeyboard }
            let (panel, view, _, composer) = threadBox()
            XCTAssertTrue(composer.attach([.bytes(Data("notes".utf8), name: "notes.txt"), .bytes(Data("plan".utf8), name: "plan.txt")]))
            view.threadPane.arrange(force: true)
            view.layoutSubtreeIfNeeded()
            let cross = try button(CatWords.remove("notes.txt"), in: composer)
            byKeyboard ? try tabAndSpace(cross, in: panel) : try click(cross, "✕ on notes.txt")
            XCTAssertEqual(composer.attachments.map(\.name), ["plan.txt"], byKeyboard ? "by keyboard" : "by mouse")
        }
    }

    func testAlsoSendTicksByMouseAndKeyboardAndReturnSendsWithIt() throws {
        for byKeyboard in [false, true] {
            QuietFocus.fullKeyboardAccess = { byKeyboard }
            let (panel, _, calls, composer) = threadBox()
            let name = byKeyboard ? "by keyboard" : "by mouse"
            XCTAssertFalse(composer.alsoSend.isHidden, "\(name): Steve's thread offers his channel")
            if byKeyboard {
                tab(to: composer.alsoSend, in: panel)
                try space(in: panel)
            } else {
                try click(composer.alsoSend, "Also send")
            }
            XCTAssertTrue(composer.alsoSends, name)

            XCTAssertTrue(try Press.hit(composer.textView) === composer.textView, "\(name): a click in the box lands on its words")
            panel.makeFirstResponder(composer.textView)
            composer.textView.insertText("Looks good", replacementRange: composer.textView.selectedRange())
            try returnKey(in: panel)
            guard case .send(let words, let target, let shownIn, let alsoSent, _)? = calls.actions.last else { return XCTFail("\(name): Return sent nothing, \(calls.actions)") }
            XCTAssertEqual(words, "Looks good", name)
            XCTAssertEqual(target, .thread(id: "s1", title: "Resume"), name)
            XCTAssertEqual(shownIn, .of(steve), name)
            XCTAssertTrue(alsoSent, name)
            XCTAssertEqual(composer.textView.string, "", "\(name): and the box is empty again")
            XCTAssertFalse(composer.alsoSends, "\(name): and unticks")
        }
    }
}

// MARK: - Shortcuts

extension PressChromeTests {
    private func jumpRow(_ index: Int, in box: JumpBoxView) -> NSPoint {
        let rowHeight = MessagesInk.title + 26
        return NSPoint(x: box.bounds.midX, y: 70 + MessagesInk.title + 32 + (CGFloat(index) + 0.5) * rowHeight)
    }

    func testCommandKOpensTheJumpBoxWhoseRowsArrowsAndReturnWork() throws {
        let (panel, view, _) = messages(book())
        try key("k", keyCode: 40, modifiers: .command, in: panel)
        XCTAssertFalse(view.jumpBox.isHidden, "⌘K")
        let field = try XCTUnwrap(panel.firstResponder as? NSTextView, "typing goes in its box")
        XCTAssertTrue(field.delegate === view.jumpBox.field)

        field.insertText("budget", replacementRange: field.selectedRange())
        XCTAssertEqual(view.jumpBox.items.map(\.title), ["Budget"])
        try returnKey(in: panel)
        XCTAssertTrue(view.jumpBox.isHidden)
        XCTAssertEqual(view.selection, .thread("p1", in: .channel(.of(pepper))), "Return opens it")

        try key("k", keyCode: 40, modifiers: .command, in: panel)
        XCTAssertEqual(view.jumpBox.highlighted, 0)
        try arrow(false, in: panel)
        try arrow(false, in: panel)
        try arrow(true, in: panel)
        XCTAssertEqual(view.jumpBox.highlighted, 1, "↓↓↑")
        try returnKey(in: panel)
        XCTAssertEqual(view.selection, .threads, "the second row")

        try key("k", keyCode: 40, modifiers: .command, in: panel)
        let titles = view.jumpBox.items.map(\.title)
        let row = try XCTUnwrap(titles.firstIndex(of: "#pepper"))
        XCTAssertTrue(try click(at: jumpRow(row, in: view.jumpBox), in: view.jumpBox) === view.jumpBox, "a click on a row lands on the box")
        XCTAssertTrue(view.jumpBox.isHidden)
        XCTAssertEqual(view.selection, .channel(.of(pepper)), "clicking a row opens it")

        try key("k", keyCode: 40, modifiers: .command, in: panel)
        try click(at: NSPoint(x: 300, y: view.bounds.height - 10), in: view.jumpBox)
        XCTAssertTrue(view.jumpBox.isHidden, "a click outside it closes it")
        try key("k", keyCode: 40, modifiers: .command, in: panel)
        try key("k", keyCode: 40, modifiers: .command, in: panel)
        XCTAssertTrue(view.jumpBox.isHidden, "and ⌘K again")
        try key("k", keyCode: 40, modifiers: .command, in: panel)
        try escape(in: panel)
        XCTAssertTrue(view.jumpBox.isHidden, "and Esc")
        XCTAssertFalse(panel.firstResponder is NSTextView, "taking the keyboard out of it")
    }

    func testCommandFFindsAMessageAndReturnOpensIt() throws {
        let (panel, view, _) = messages(book())
        try key("f", keyCode: 3, modifiers: .command, in: panel)
        XCTAssertFalse(view.jumpBox.isHidden, "⌘F")
        XCTAssertEqual(view.jumpBox.mode, .search)
        let field = try XCTUnwrap(panel.firstResponder as? NSTextView)
        field.insertText("cover letter", replacementRange: field.selectedRange())
        XCTAssertEqual(view.jumpBox.items.map(\.found?.message.id), ["s2-0:ask"])
        try returnKey(in: panel)
        XCTAssertEqual(view.selection, .thread("s2", in: .channel(.of(steve))))
        XCTAssertTrue(view.threadPane.shownMessageRows.contains { $0.isFound }, "with the message marked")

        try key("f", keyCode: 3, modifiers: .command, in: panel)
        try key("k", keyCode: 40, modifiers: .command, in: panel)
        XCTAssertEqual(view.jumpBox.mode, .jump, "⌘K turns it into the jump box")
        try key("f", keyCode: 3, modifiers: .command, in: panel)
        try key("f", keyCode: 3, modifiers: .command, in: panel)
        XCTAssertTrue(view.jumpBox.isHidden, "⌘F again closes it")
    }

    func testCommandSlashShowsTheShortcutsWhichCloseEveryWay() throws {
        let (panel, view, _) = messages(book())
        try key("/", keyCode: 44, modifiers: .command, in: panel)
        XCTAssertFalse(view.cheatsheet.isHidden, "⌘/")
        try click(try button(CatWords.closeThread, in: view.cheatsheet), "the shortcuts' ✕")
        XCTAssertTrue(view.cheatsheet.isHidden)

        try key("/", keyCode: 44, modifiers: .command, in: panel)
        try click(at: NSPoint(x: 300, y: view.bounds.height - 4), in: view.cheatsheet)
        XCTAssertTrue(view.cheatsheet.isHidden, "a click outside it")

        try key("/", keyCode: 44, modifiers: .command, in: panel)
        try key("/", keyCode: 44, modifiers: .command, in: panel)
        XCTAssertTrue(view.cheatsheet.isHidden, "⌘/ again")

        try key("/", keyCode: 44, modifiers: .command, in: panel)
        try escape(in: panel)
        XCTAssertTrue(view.cheatsheet.isHidden, "Esc")

        QuietFocus.fullKeyboardAccess = { true }
        try key("/", keyCode: 44, modifiers: .command, in: panel)
        try tabAndSpace(try button(CatWords.closeThread, in: view.cheatsheet), in: panel)
        XCTAssertTrue(view.cheatsheet.isHidden, "Tab to its ✕ and Space")
    }

    func testEscClosesTheJumpBoxThenTheShortcutsThenTheThread() throws {
        let (panel, view, _) = messages(book())
        view.select(.thread("s1", in: .channel(.of(steve))))
        try key("k", keyCode: 40, modifiers: .command, in: panel)
        try escape(in: panel)
        XCTAssertTrue(view.jumpBox.isHidden)
        XCTAssertNotNil(view.selection.thread)
        try key("/", keyCode: 44, modifiers: .command, in: panel)
        try escape(in: panel)
        XCTAssertTrue(view.cheatsheet.isHidden)
        XCTAssertNotNil(view.selection.thread)
        try escape(in: panel)
        XCTAssertEqual(view.selection, .channel(.of(steve)))

        view.select(.thread("s1", in: .channel(.of(steve))))
        view.threadPane.focusComposer()
        try escape(in: panel)
        XCTAssertEqual(view.selection, .channel(.of(steve)), "and from its box")
    }
}

// MARK: - New messages and older ones

extension PressChromeTests {
    func testNewMessagesTakesYouUpToTheNewLine() throws {
        for byKeyboard in [false, true] {
            QuietFocus.fullKeyboardAccess = { byKeyboard }
            var unread = book(exchanges: 30)
            unread.newFrom = ["s1": "s1-2:reply"]
            let (panel, view, _) = messages(unread)
            view.select(.thread("s1", in: .channel(.of(steve))))
            view.layoutSubtreeIfNeeded()
            let title = try XCTUnwrap(view.threadPane.jumpTitle, "the New line is above what you can see")
            let jump = try button(title, in: view.threadPane)
            byKeyboard ? try tabAndSpace(jump, in: panel) : try click(jump, title)
            XCTAssertNil(view.threadPane.jumpTitle, "\(byKeyboard ? "by keyboard" : "by mouse"): the line's in view")
        }
    }

    func testLoadOlderMessagesLoadsThemByMouseAndKeyboard() throws {
        let threads = (0..<40).map { thread("o\($0)", of: steve, title: "Work \($0)") }
        let said = Dictionary(uniqueKeysWithValues: (1..<40).map { ("o\($0)", self.said("o\($0)", "Ask", at: TimeInterval($0 * 10))) })
        let cut = ChannelBook.build(kittens: [steve, pepper], threads: threads, transcripts: said, isReading: false, unreadable: 0, cantReachT3: false)
        for byKeyboard in [false, true] {
            QuietFocus.fullKeyboardAccess = { byKeyboard }
            let (panel, view, calls) = messages(cut)
            view.select(.channel(.of(steve)))
            view.layoutSubtreeIfNeeded()
            XCTAssertEqual(view.pane.shown.first, .older(isLoading: false))
            func older() throws -> OlderRowView {
                for _ in 0..<5 { view.pane.scrollOffset = 0 }
                return try XCTUnwrap(rows(in: view.pane).first as? OlderRowView)
            }
            let row = try older()
            if byKeyboard {
                tab(to: view.pane.list, in: panel)
                for _ in 0..<120 where view.pane.currentRow !== row { try arrow(true, in: panel) }
                XCTAssertTrue(view.pane.currentRow === row, "↑ reaches it")
            }
            // Scrolling back to it asks for older ones by itself, which the feed answers once, so this counts the press.
            calls.actions = []
            if byKeyboard {
                try space(in: panel)
            } else {
                try click(try XCTUnwrap(subviews(of: row).first as? QuietButton), CatWords.loadOlder)
            }
            XCTAssertEqual(calls.actions, [.older(.of(steve))], byKeyboard ? "by keyboard" : "by mouse")
        }
    }
}

// MARK: - The bell

extension PressChromeTests {
    func testAChannelsBellOpensItsNotificationsWhoseItemsSetThem() throws {
        var opened: [(menu: NSMenu, anchor: NSView)] = []
        let popUp = NotificationsMenu.popUp
        NotificationsMenu.popUp = { opened.append(($0, $1)) }
        defer { NotificationsMenu.popUp = popUp }
        for byKeyboard in [false, true] {
            QuietFocus.fullKeyboardAccess = { byKeyboard }
            opened = []
            var quietPhone = book()
            quietPhone.waiting.phone = true
            let (panel, view, calls) = messages(quietPhone)
            view.select(.channel(.of(steve)))
            let name = byKeyboard ? "by keyboard" : "by mouse"
            let bell = try button(CatWords.notifications, in: view.pane)
            byKeyboard ? try tabAndSpace(bell, in: panel) : try click(bell, "the bell")
            let shown = try XCTUnwrap(opened.first, "\(name): the bell opens its menu")
            XCTAssertEqual(opened.count, 1, name)
            XCTAssertTrue(shown.anchor === bell, "\(name): under the bell")

            let menu = shown.menu
            let picks = menu.items.filter { $0.action != nil }
            XCTAssertEqual(picks.first?.title, CatWords.mute, name)
            XCTAssertGreaterThan(picks.count, NotifyLevel.allCases.count, "\(name): the Mac's levels and the phone's")
            for item in picks {
                menu.performActionForItem(at: menu.index(of: item))
                XCTAssertEqual(calls.actions.last, .notifications(.of(steve), try XCTUnwrap(item.representedObject as? ChannelNotifications)), "\(name): \(item.title)")
            }
            XCTAssertEqual(calls.actions.count, picks.count, name)
            XCTAssertEqual(calls.actions.first, .notifications(.of(steve), ChannelNotifications(muted: true)), "\(name): Mute mutes it")
        }
    }
}

