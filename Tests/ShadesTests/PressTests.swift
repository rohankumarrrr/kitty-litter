import AppKit
@testable import Shades
import ShadesCore
import ShadesT3
import XCTest

/// Controls pressed the way a mouse and keyboard press them, through `Press`, in a window that's never shown.
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

    private func eventually(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { await Task.yield() }
    }

    func testOpenInT3OnAKittensMessageHandsT3ItsThreadsLink() async throws {
        for (threadID, link) in [("mcp:launch:8f2c", "t3code://threads/env-1/mcp%3Alaunch%3A8f2c"), ("t", "t3code://threads/env-1/t")] {
            for width: CGFloat in [1100, 820] {
                for inThread in [false, true] {
                    let name = "\(threadID), \(Int(width)) wide, \(inThread ? "in its thread" : "in the channel")"
                    let opened = Opened()
                    let (_, view) = try messages(width: width, opened: opened)
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
                        XCTAssertTrue(try Press.hit(toolbar.more) === toolbar.more, "\(name): a click lands on More")
                        let menu = try XCTUnwrap(row.menu(for: NSEvent()), name)
                        menu.performActionForItem(at: menu.indexOfItem(withTitle: CatWords.openInT3))
                    } else {
                        XCTAssertTrue(try Press.click(open) === open, "\(name): the click lands on Open in T3")
                    }
                    await eventually { !opened.links.isEmpty }
                    XCTAssertEqual(opened.links, [link], name)
                }
            }
        }
    }

    func testSpaceOnOpenInT3HandsT3TheSameLink() async throws {
        QuietFocus.fullKeyboardAccess = { true }
        let opened = Opened()
        let (_, view) = try messages(width: 1100, opened: opened)
        view.show(book(threadID: "mcp:launch:8f2c"))
        view.select(.channel(.of(steve)))
        let row = try XCTUnwrap(view.pane.shownMessageRows.last)
        row.isCurrent = true
        let open = try XCTUnwrap(row.toolbar?.button(CatWords.openInT3))
        try Press.key(" ", keyCode: 49, on: open)
        await eventually { !opened.links.isEmpty }
        XCTAssertEqual(opened.links, ["t3code://threads/env-1/mcp%3Alaunch%3A8f2c"], "Tab reaches it once the arrow keys are on its message, and Space presses it")
    }
}
