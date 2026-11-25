import AppKit
@testable import Shades
import ShadesCore
import XCTest

@MainActor
final class PressMarkReadTests: XCTestCase {
    private let steve = Kitten(name: "Steve Pawsniak", role: "Professional", covers: "", folder: "/k/steve")
    private let pepper = Kitten(name: "Pepper", role: "Finance", covers: "", folder: "/k/pepper")
    private let at = Date(timeIntervalSince1970: 1_000_000)

    private final class KeyPanel: ChannelsPanel {
        override var isKeyWindow: Bool { true }
    }

    override func setUp() async throws {
        QuietFocus.fullKeyboardAccess = { false }
    }

    override func tearDown() async throws {
        QuietFocus.fullKeyboardAccess = { NSApplication.shared.isFullKeyboardAccessEnabled }
    }

    private func book(unread: Set<String>) -> ChannelBook {
        let threads = [("a", steve, "Resume"), ("b", steve, "Cover letter"), ("p", pepper, "Budget")].map { id, kitten, title in
            AgentThread(id: id, title: title, projectTitle: kitten.name, status: .completed, model: "m", updatedAt: at, projectPath: kitten.folder)
        }
        let said = Dictionary(uniqueKeysWithValues: threads.enumerated().map { index, thread in
            let asked = at.addingTimeInterval(TimeInterval(index * 10))
            return (thread.id, [
                Exchange(id: "\(thread.id)1", asker: .you, askedAt: asked, ask: "Look at \(thread.title)", reply: "Looked.", repliedAt: asked.addingTimeInterval(1)),
                Exchange(id: "\(thread.id)2", asker: .you, askedAt: asked.addingTimeInterval(2), ask: "And again", reply: "Again.", repliedAt: asked.addingTimeInterval(3)),
            ])
        })
        return ChannelBook.build(kittens: [steve, pepper], threads: threads, transcripts: said, isReading: false, unreadable: 0, cantReachT3: false, isUnread: { unread.contains($0.id) })
    }

    private func messages(_ book: ChannelBook, at selection: ChannelSelection) -> (panel: KeyPanel, view: ChannelsView, sent: () -> [MessagesAction]) {
        let panel = KeyPanel()
        let view = ChannelsView(frame: NSRect(origin: .zero, size: ChannelsWindow.size))
        panel.contentView = view
        panel.setContentSize(ChannelsWindow.size)
        var sent: [MessagesAction] = []
        view.onAction = { sent.append($0) }
        view.show(book)
        view.select(selection)
        view.layoutSubtreeIfNeeded()
        return (panel, view, { sent })
    }

    private func rightClick(_ control: NSView, file: StaticString = #filePath, line: UInt = #line) throws -> NSMenu {
        let window = try XCTUnwrap(control.window, file: file, line: line)
        let centre = control.convert(NSPoint(x: control.bounds.midX, y: control.bounds.midY), to: nil)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: centre, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1), file: file, line: line)
        var view: NSView? = try Press.hit(control, file: file, line: line)
        XCTAssertTrue(view?.isDescendant(of: control) == true, "a right-click on it lands on it", file: file, line: line)
        while let current = view {
            if let menu = current.menu(for: event) { return menu }
            view = current.superview
        }
        return try XCTUnwrap(nil as NSMenu?, "a right-click on it opens a menu", file: file, line: line)
    }

    private func subviews(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(subviews)
    }

    private func choose(_ title: String, in menu: NSMenu, file: StaticString = #filePath, line: UInt = #line) {
        let index = menu.indexOfItem(withTitle: title)
        XCTAssertGreaterThanOrEqual(index, 0, "\(title) is in \(menu.items.map(\.title))", file: file, line: line)
        if index >= 0 { menu.performActionForItem(at: index) }
    }

    private func voiceOver(_ name: String, on view: NSView, file: StaticString = #filePath, line: UInt = #line) {
        let action = view.accessibilityCustomActions()?.first { $0.name == name }
        XCTAssertNotNil(action, "VoiceOver offers \(name)", file: file, line: line)
        _ = action?.handler?()
    }

    func testRightClickingAChannelInTheSidebarMarksItOrEverythingRead() throws {
        let (_, view, sent) = messages(book(unread: ["a", "b", "p"]), at: .channel(.of(pepper)))
        let row = try XCTUnwrap(view.sidebar.row(for: .channel(.of(steve))))
        XCTAssertEqual(row.item.unread, 2)
        XCTAssertTrue(row.accessibilityLabel()?.contains("2 unread") == true, "it says how much is new without opening it")

        let menu = try rightClick(row)
        XCTAssertEqual(menu.items.map(\.title), [CatWords.markRead, CatWords.markAllRead])
        choose(CatWords.markRead, in: menu)
        XCTAssertEqual(sent(), [.markRead(["a", "b"])])
        choose(CatWords.markAllRead, in: menu)
        XCTAssertEqual(sent().last, .markRead(["a", "b", "p"]))

        voiceOver(CatWords.markRead, on: row)
        XCTAssertEqual(sent().last, .markRead(["a", "b"]), "the same from the keyboard, with VoiceOver")
    }

    func testAChannelWithNothingNewOffersOnlyMarkAllAsRead() throws {
        let (_, view, sent) = messages(book(unread: ["a"]), at: .channel(.of(steve)))
        let pepperRow = try XCTUnwrap(view.sidebar.row(for: .channel(.of(pepper))))
        XCTAssertEqual(pepperRow.item.unread, 0)
        XCTAssertEqual(try rightClick(pepperRow).items.map(\.title), [CatWords.markAllRead])
        voiceOver(CatWords.markAllRead, on: pepperRow)
        XCTAssertEqual(sent(), [.markRead(["a"])])

        let (_, readView, _) = messages(book(unread: []), at: .channel(.of(steve)))
        let quiet = try XCTUnwrap(readView.sidebar.row(for: .channel(.of(steve))))
        XCTAssertNil(quiet.menu(for: try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))), "nothing to mark, so no menu")
    }

    func testShiftEscapeMarksEverythingRead() throws {
        XCTAssertEqual(MessagesShortcut(keyCode: 53, characters: "\u{1b}", modifiers: .shift), .markAllRead, "Slack's own")
        let (panel, _, sent) = messages(book(unread: ["b", "p"]), at: .channel(.of(steve)))
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: .shift, timestamp: 0, windowNumber: panel.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
            if type == .keyUp || !panel.performKeyEquivalent(with: event) { panel.sendEvent(event) }
        }
        XCTAssertEqual(sent(), [.markRead(["b", "p"])])
    }

    func testRightClickingAThreadInThreadsMarksItReadOrUnread() throws {
        let (_, view, sent) = messages(book(unread: ["a"]), at: .threads)
        let digests = subviews(of: view.pane).compactMap { $0 as? ThreadDigestRowView }
        XCTAssertEqual(digests.count, 3)
        let unread = try XCTUnwrap(digests.first { $0.accessibilityLabel()?.contains("unread") == true })
        let menu = try rightClick(unread)
        XCTAssertEqual(menu.items.map(\.title), [CatWords.threadTitle, CatWords.markRead])
        choose(CatWords.markRead, in: menu)
        XCTAssertEqual(sent(), [.markRead(["a"])])

        let read = try XCTUnwrap(digests.first { $0.accessibilityLabel()?.contains("Budget") == true || $0.accessibilityLabel()?.contains("Pepper") == true })
        let readMenu = try rightClick(read)
        XCTAssertEqual(readMenu.items.map(\.title), [CatWords.threadTitle, CatWords.markUnread])
        choose(CatWords.markUnread, in: readMenu)
        XCTAssertEqual(sent().last, .markUnread("p", from: "p2:reply"), "from its latest reply, as Mail marks a message")

        voiceOver(CatWords.markRead, on: unread)
        XCTAssertEqual(sent().last, .markRead(["a"]))
        choose(CatWords.threadTitle, in: menu)
        XCTAssertEqual(view.selection, .thread("a", in: .threads))
    }

    func testAThreadWithNewRepliesSaysSoUnderItsParentAndMarksReadFromThere() throws {
        let (_, view, sent) = messages(book(unread: ["b"]), at: .channel(.of(steve)))
        let parents = view.pane.shownMessageRows.filter { $0.replyBar != nil }
        let b = try XCTUnwrap(parents.first { $0.message.threadID == "b" })
        let a = try XCTUnwrap(parents.first { $0.message.threadID == "a" })
        XCTAssertEqual(b.replyBar?.isUnread, true)
        XCTAssertTrue(b.replyBar?.accessibilityWords(now: at).contains(CatWords.unreadLabel) == true)
        XCTAssertEqual(a.replyBar?.isUnread, false)

        let menu = try rightClick(b)
        XCTAssertTrue(menu.items.map(\.title).contains(CatWords.markRead))
        choose(CatWords.markRead, in: menu)
        XCTAssertEqual(sent(), [.markRead(["b"])])
        XCTAssertFalse(try rightClick(a).items.map(\.title).contains(CatWords.markRead), "one you've read has nothing to mark")
    }
}
