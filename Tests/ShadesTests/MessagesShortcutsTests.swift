import AppKit
@testable import Shades
import ShadesCore
import XCTest

/// Messages' keyboard shortcuts. Each test calls what the key calls, never a made-up key press, since those would land
/// on whatever's really on the desktop.
@MainActor
final class MessagesShortcutsTests: XCTestCase {
    private let steve = Kitten(name: "Steve", role: "Professional", covers: "", folder: "/k/steve")
    private let pepper = Kitten(name: "Pepper", role: "Finance", covers: "", folder: "/k/pepper")
    private let at = Date(timeIntervalSince1970: 1_000_000)

    private func thread(_ id: String, of kitten: Kitten, title: String) -> AgentThread {
        AgentThread(id: id, title: title, projectTitle: kitten.name, status: .completed, model: "m", updatedAt: at, projectPath: kitten.folder)
    }

    private func said(_ id: String, _ ask: String, at offset: TimeInterval) -> [Exchange] {
        [Exchange(id: id, asker: .you, askedAt: at.addingTimeInterval(offset), ask: ask, reply: "Done.", repliedAt: at.addingTimeInterval(offset + 1))]
    }

    /// Steve has three threads, oldest first, and Pepper one you haven't seen.
    private func book() -> ChannelBook {
        ChannelBook.build(
            kittens: [steve, pepper],
            threads: [thread("s1", of: steve, title: "Resume"), thread("s2", of: steve, title: "Cover letter"), thread("s3", of: steve, title: "Interview prep"), thread("p1", of: pepper, title: "Budget")],
            transcripts: ["s1": said("e1", "Tidy my resume", at: 0), "s2": said("e2", "Write a cover letter", at: 10), "s3": said("e3", "Prep me for the interview", at: 20), "p1": said("e4", "Check my budget", at: 5)],
            isReading: false, unreadable: 0, cantReachT3: false,
            isUnread: { $0.id == "p1" }
        )
    }

    private func view() -> ChannelsView {
        let view = ChannelsView(frame: NSRect(origin: .zero, size: ChannelsWindow.size))
        view.show(book())
        return view
    }

    func testTheKeysAreTheOnesT3CodeTheClaudeAppAndSlackUse() {
        func key(_ code: UInt16, _ characters: String, _ modifiers: NSEvent.ModifierFlags) -> MessagesShortcut? {
            MessagesShortcut(keyCode: code, characters: characters, modifiers: modifiers)
        }
        XCTAssertEqual(key(33, "{", [.command, .shift]), .previousThread)
        XCTAssertEqual(key(30, "}", [.command, .shift]), .nextThread)
        XCTAssertEqual(key(33, "[", .command), .back)
        XCTAssertEqual(key(30, "]", .command), .forward)
        XCTAssertEqual(key(126, "", [.option, .numericPad, .function]), .previousPlace, "the arrows carry flags of their own")
        XCTAssertEqual(key(125, "", .option), .nextPlace)
        XCTAssertEqual(key(126, "", [.option, .shift]), .previousUnread)
        XCTAssertEqual(key(125, "", [.option, .shift]), .nextUnread)
        XCTAssertEqual(key(18, "1", .command), .place(1))
        XCTAssertEqual(key(25, "9", .command), .place(9))
        XCTAssertEqual(key(40, "k", .command), .jump)
        XCTAssertEqual(key(53, "\u{1b}", []), .escape)
        XCTAssertEqual(key(17, "T", [.command, .shift]), .threads)
        XCTAssertEqual(key(46, "M", [.command, .shift]), .activity)
        XCTAssertEqual(key(45, "n", .command), .compose)
        XCTAssertEqual(key(13, "w", .command), .close)
        XCTAssertEqual(key(44, "/", .command), .cheatsheet)
        XCTAssertNil(key(8, "c", .command), "⌘C is for copying")
        XCTAssertNil(key(126, "", []), "the arrows alone move through what's in front of you")
        XCTAssertNil(key(40, "k", [.command, .control]))
        XCTAssertNil(key(11, "b", [.control, .command]), "⌃⌘B, which opens and closes Messages, is left alone")
        XCTAssertTrue(MessagesShortcut.previousPlace.movesInText, "a box with words keeps ⌥ and the arrows")
        XCTAssertFalse(MessagesShortcut.nextThread.movesInText)
    }

    func testNoShortcutDoesAnythingWhileMessagesDoesntHaveTheKeyboard() {
        let window = ChannelsWindow()
        window.update(book())
        window.view.select(.channel(.of(steve)))
        XCTAssertFalse(window.panel.isKeyWindow)
        let all: [MessagesShortcut] = [.previousThread, .nextThread, .previousPlace, .nextPlace, .previousUnread, .nextUnread, .back, .forward, .place(1), .jump, .escape, .threads, .activity, .compose, .close, .cheatsheet]
        var closed = false
        window.view.onCloseWindow = { closed = true }
        for shortcut in all {
            XCTAssertFalse(window.panel.handle(shortcut), "\(shortcut)")
        }
        XCTAssertEqual(window.view.selection, .channel(.of(steve)), "nothing moved")
        XCTAssertTrue(window.view.jumpBox.isHidden)
        XCTAssertTrue(window.view.cheatsheet.isHidden)
        XCTAssertFalse(closed)
    }

    func testThreadKeysStepThroughAChannelsThreadsFromTheNewest() {
        let view = view()
        view.select(.channel(.of(steve)))
        XCTAssertTrue(view.perform(.nextThread))
        XCTAssertEqual(view.selection, .thread("s3", in: .channel(.of(steve))), "with none open, the newest, at the bottom")
        view.perform(.previousThread)
        XCTAssertEqual(view.selection.thread, "s2", "then the one above")
        view.perform(.previousThread)
        XCTAssertEqual(view.selection.thread, "s1")
        view.perform(.previousThread)
        XCTAssertEqual(view.selection.thread, "s1", "and it stops at the top")
        view.perform(.nextThread)
        XCTAssertEqual(view.selection.thread, "s2")
        XCTAssertFalse(view.threadPane.isHidden)
        XCTAssertEqual(view.selection.place, .channel(.of(steve)), "beside the same channel")
    }

    func testThreadKeysInThreadsFollowThatList() {
        let view = view()
        view.select(.threads)
        let order = book().yours.map(\.id)
        XCTAssertEqual(order.first, "p1", "unread first")
        view.perform(.nextThread)
        XCTAssertEqual(view.selection, .thread(order[0], in: .threads), "with none open, the newest, at the top")
        view.perform(.nextThread)
        XCTAssertEqual(view.selection.thread, order[1])
    }

    func testPlaceKeysMoveThroughTheSidebar() {
        let view = view()
        XCTAssertEqual(view.selection, .activity)
        view.perform(.nextPlace)
        XCTAssertEqual(view.selection, .threads)
        view.perform(.nextPlace)
        XCTAssertEqual(view.selection, .channel(.general))
        view.perform(.previousPlace)
        XCTAssertEqual(view.selection, .threads)
        view.select(.channel(.shades))
        view.perform(.nextPlace)
        XCTAssertEqual(view.selection, .channel(.shades), "it stops at the bottom")
        view.open(thread: "s1", from: .channel(.of(steve)))
        view.perform(.nextPlace)
        XCTAssertEqual(view.selection, .channel(.of(pepper)), "and moving closes the thread")
    }

    func testUnreadKeysGoRoundToTheNextBoldChannel() {
        let view = view()
        view.perform(.nextUnread)
        XCTAssertEqual(view.selection, .channel(.of(pepper)))
        view.perform(.nextUnread)
        XCTAssertEqual(view.selection, .channel(.of(pepper)), "it's the only one, so it stays")
        view.select(.channel(.shades))
        view.perform(.previousUnread)
        XCTAssertEqual(view.selection, .channel(.of(pepper)))
    }

    func testBackAndForwardRetraceWhereYouveBeen() {
        let view = view()
        view.select(.channel(.of(steve)))
        view.open(thread: "s2")
        view.select(.threads)
        view.perform(.back)
        XCTAssertEqual(view.selection, .thread("s2", in: .channel(.of(steve))))
        view.perform(.back)
        XCTAssertEqual(view.selection, .channel(.of(steve)))
        view.perform(.back)
        XCTAssertEqual(view.selection, .activity)
        view.perform(.back)
        XCTAssertEqual(view.selection, .activity, "and no further")
        view.perform(.forward)
        view.perform(.forward)
        XCTAssertEqual(view.selection, .thread("s2", in: .channel(.of(steve))))
        view.select(.channel(.general))
        view.perform(.forward)
        XCTAssertEqual(view.selection, .channel(.general), "going somewhere new drops what was ahead")
        view.perform(.back)
        XCTAssertEqual(view.selection, .thread("s2", in: .channel(.of(steve))))
    }

    func testBackFollowsANewThreadToItsOwnID() {
        let view = view()
        view.select(.channel(.of(steve)))
        view.open(thread: "sent-1")
        view.select(.activity)
        var started = book()
        started.started["sent-1"] = "s3"
        view.show(started)
        view.perform(.back)
        XCTAssertEqual(view.selection, .thread("s3", in: .channel(.of(steve))))
    }

    func testANumberGoesToThatRowOfTheSidebarAndLettersToThreadsAndActivity() {
        let view = view()
        view.perform(.place(4))
        XCTAssertEqual(view.selection, .channel(.of(steve)))
        XCTAssertFalse(view.perform(.place(9)), "there's no ninth row")
        view.perform(.threads)
        XCTAssertEqual(view.selection, .threads)
        view.perform(.activity)
        XCTAssertEqual(view.selection, .activity)
    }

    func testEscClosesTheJumpBoxThenTheShortcutsThenTheThread() {
        let view = view()
        view.select(.channel(.of(steve)))
        view.open(thread: "s1")
        view.perform(.cheatsheet)
        view.perform(.jump)
        XCTAssertFalse(view.jumpBox.isHidden)
        XCTAssertTrue(view.cheatsheet.isHidden, "one over the window at a time")
        view.perform(.escape)
        XCTAssertTrue(view.jumpBox.isHidden)
        view.perform(.cheatsheet)
        view.perform(.escape)
        XCTAssertTrue(view.cheatsheet.isHidden)
        XCTAssertNotNil(view.selection.thread)
        view.perform(.escape)
        XCTAssertNil(view.selection.thread)
        XCTAssertFalse(view.perform(.escape), "with nothing to close, Esc goes on")
    }

    func testEscInAThreadsBoxClosesItToo() {
        let view = view()
        view.open(thread: "s1", from: .channel(.of(steve)))
        let composer = view.threadPane.composer
        XCTAssertTrue(composer.textView(composer.textView, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        XCTAssertNil(view.selection.thread)
    }

    func testTheJumpBoxFiltersPlacesAndThreadsByName() {
        let book = book()
        let titles = { (query: String) in JumpItem.matching(query, in: book).map(\.title) }
        XCTAssertEqual(titles("pep"), ["#pepper", "Budget"], "a place by its name first, then what's in it")
        XCTAssertEqual(titles("cover"), ["Cover letter"], "a thread by its title")
        XCTAssertEqual(titles("steve"), ["#steve", "Interview prep", "Cover letter", "Resume"], "the place first, then its threads, newest first")
        XCTAssertEqual(titles("letter cover"), ["Cover letter"], "every word, in any order")
        XCTAssertEqual(titles("zebra"), [])
        XCTAssertEqual(Array(titles("").prefix(6)), ["Activity", "Threads", "#general", "#steve", "#pepper", "Shades"], "with nothing typed, every place")
        XCTAssertEqual(JumpItem.matching("cover", in: book).first?.selection, .thread("s2", in: .channel(.of(steve))))
    }

    func testTheJumpBoxOpensWhatsHighlighted() {
        let view = view()
        view.perform(.jump)
        view.jumpBox.query = "steve"
        view.jumpBox.move(by: 1)
        XCTAssertEqual(view.jumpBox.highlighted, 1)
        view.jumpBox.open()
        XCTAssertTrue(view.jumpBox.isHidden)
        XCTAssertEqual(view.selection, .thread("s3", in: .channel(.of(steve))))
        view.perform(.jump)
        view.jumpBox.query = "pepper"
        view.jumpBox.open()
        XCTAssertEqual(view.selection, .channel(.of(pepper)))
    }

    func testNewPutsTheKeyboardInThePlacesBox() {
        let window = ChannelsWindow()
        window.update(book())
        let view = window.view
        view.select(.channel(.of(steve)))
        XCTAssertTrue(view.perform(.compose))
        XCTAssertTrue(window.panel.firstResponder === view.pane.composer.textView)
        view.select(.thread("s1", in: .threads))
        XCTAssertTrue(view.perform(.compose))
        XCTAssertTrue(window.panel.firstResponder === view.threadPane.composer.textView, "Threads has no box, so the thread's")
        view.select(.activity)
        XCTAssertFalse(view.perform(.compose), "and Activity has neither")
    }

    func testCloseClosesMessagesAndTheLinkOpensEveryShortcut() throws {
        let view = view()
        var closed = 0
        view.onCloseWindow = { closed += 1 }
        view.perform(.close)
        XCTAssertEqual(closed, 1)

        XCTAssertTrue(view.cheatsheet.isHidden)
        XCTAssertTrue(view.sidebar.shortcutsButton.accessibilityPerformPress())
        XCTAssertFalse(view.cheatsheet.isHidden)
        let listed = view.cheatsheet.accessibilityLabel() ?? ""
        for keys in ["⌘⇧[", "⌥↑", "⌥⇧↑", "⌘[", "⌘1", "⌘K", "Esc", "⌘⇧T", "⌘⇧M", "⌘N", "⌘W", "⌘/"] {
            XCTAssertTrue(listed.contains(keys), keys)
        }
        view.perform(.cheatsheet)
        XCTAssertTrue(view.cheatsheet.isHidden, "⌘/ again closes it")
    }

    func testClickingIntoMessagesGivesItTheKeyboardWithoutActivatingShades() {
        let panel = ChannelsPanel()
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel), "so the app you were in stays active")
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
    }
}
