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

    // MARK: - The thread pane's edge

    func testDraggingTheThreadPanesEdgeChangesItsWidthWithinItsLimits() throws {
        let (panel, view, _) = messages(book())
        view.select(.thread("s1", in: .channel(.of(steve))))
        view.layoutSubtreeIfNeeded()
        XCTAssertTrue(try Press.hit(view.threadEdge) === view.threadEdge, "a press on the line between the panes lands on its edge")

        func drag(by dx: CGFloat, grabbing grab: CGFloat? = nil) throws {
            let edge = view.threadEdge
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
            view.layoutSubtreeIfNeeded()
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
