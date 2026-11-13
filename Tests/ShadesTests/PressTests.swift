import AppKit
@testable import Shades
import ShadesCore
import ShadesT3
import XCTest

/// Controls pressed the way a mouse presses them: the window works out which view is under the pointer, and that view
/// gets the press and the release. The events are made here and handed straight to the view, never posted, so nothing
/// reaches the desktop, and the window is never shown.
@MainActor
final class PressTests: XCTestCase {
    private let steve = Kitten(name: "Steve Pawsniak", role: "Professional", covers: "", folder: "/k/steve")
    private let at = Date(timeIntervalSince1970: 1_000_000)

    private final class Opened: @unchecked Sendable {
        private let lock = NSLock()
        private var _links: [String] = []
        var links: [String] { lock.withLock { _links } }
        func add(_ link: URL) { lock.withLock { _links.append(link.absoluteString) } }
    }

    override func setUp() async throws {
        QuietFocus.fullKeyboardAccess = { false }
    }

    override func tearDown() async throws {
        QuietFocus.fullKeyboardAccess = { NSApplication.shared.isFullKeyboardAccessEnabled }
    }

    private func book(threadID: String) -> ChannelBook {
        let thread = AgentThread(id: threadID, title: "Work", projectTitle: "Steve", status: .completed, model: "m", updatedAt: at, projectPath: steve.folder)
        let said = (0..<3).map { index in
            Exchange(id: "e\(index)", asker: .you, askedAt: at.addingTimeInterval(TimeInterval(index)), ask: "Ask \(index)", reply: "Reply \(index)", repliedAt: at.addingTimeInterval(TimeInterval(index)))
        }
        return ChannelBook.build(kittens: [steve], threads: [thread], transcripts: [threadID: said], isReading: false, unreadable: 0, cantReachT3: false)
    }

    /// Messages in a window that's never shown, opening threads through T3's client, which hands its links to `opened`.
    private func messages(width: CGFloat, opened: Opened) throws -> (NSWindow, ChannelsView) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 560), styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let view = ChannelsView(frame: NSRect(x: 0, y: 0, width: width, height: 560))
        window.contentView = view
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("press-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("userdata"), withIntermediateDirectories: true)
        try "env-1\n".write(to: home.appendingPathComponent("userdata/environment-id"), atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: home) }
        let backend = T3Backend(home: home, credentials: MemoryCredentialStore(), openLink: { opened.add($0) })
        view.onOpenThread = { id in Task { try await backend.open(threadID: id) } }
        return (window, view)
    }

    /// The view a click at `control`'s centre lands on, as the window's own hit-testing finds it.
    private func hit(_ control: NSView, in window: NSWindow) throws -> NSView {
        window.contentView?.layoutSubtreeIfNeeded()
        let centre = control.convert(NSPoint(x: control.bounds.midX, y: control.bounds.midY), to: nil)
        return try XCTUnwrap(window.contentView?.hitTest(centre), "something is under the pointer")
    }

    /// Presses whatever is at `control`'s centre, down and then up, and says what that was.
    @discardableResult
    private func click(_ control: NSView, in window: NSWindow) throws -> NSView {
        let target = try hit(control, in: window)
        let centre = control.convert(NSPoint(x: control.bounds.midX, y: control.bounds.midY), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: centre, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            type == .leftMouseDown ? target.mouseDown(with: event) : target.mouseUp(with: event)
        }
        return target
    }

    private func eventually(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { await Task.yield() }
    }

    func testOpenInT3OnAKittensMessageHandsT3ItsThreadsLink() async throws {
        for (threadID, link) in [("mcp:launch:8f2c", "t3code://threads/env-1/mcp%3Alaunch%3A8f2c"), ("t", "t3code://threads/env-1/t")] {
            for width: CGFloat in [1100, 820] {
                for inThread in [false, true] {
                    let name = "\(threadID), \(Int(width)) wide, \(inThread ? "in its thread" : "in the channel")"
                    let opened = Opened()
                    let (window, view) = try messages(width: width, opened: opened)
                    view.show(book(threadID: threadID))
                    view.select(inThread ? .thread(threadID, in: .channel(.of(steve))) : .channel(.of(steve)))
                    let pane = inThread ? view.threadPane : view.pane
                    let row = try XCTUnwrap(pane.shownMessageRows.last { inThread ? !$0.isYours : true }, name)
                    row.hovering = true
                    let toolbar = try XCTUnwrap(row.toolbar, name)
                    let open = try XCTUnwrap(toolbar.button(CatWords.openInT3), name)
                    if open.isHidden {
                        // Folded under More, whose menu is the one a right-click opens. Pressing More would hold the
                        // test in the menu's own loop, so its items are chosen straight from that menu.
                        XCTAssertTrue(try hit(toolbar.more, in: window) === toolbar.more, "\(name): a click lands on More")
                        let menu = try XCTUnwrap(row.menu(for: NSEvent()), name)
                        menu.performActionForItem(at: menu.indexOfItem(withTitle: CatWords.openInT3))
                    } else {
                        XCTAssertTrue(try click(open, in: window) === open, "\(name): the click lands on Open in T3")
                    }
                    await eventually { !opened.links.isEmpty }
                    XCTAssertEqual(opened.links, [link], name)
                }
            }
        }
    }
}
