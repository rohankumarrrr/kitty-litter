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
    private func book(waiting: Waiting = Waiting()) -> ChannelBook {
        ChannelBook.build(
            kittens: [steve, pepper],
            threads: [thread("s1", of: steve, title: "Resume"), thread("s2", of: steve, title: "Cover letter"), thread("s3", of: steve, title: "Interview prep"), thread("p1", of: pepper, title: "Budget")],
            transcripts: ["s1": said("e1", "Tidy my resume", at: 0), "s2": said("e2", "Write a cover letter", at: 10), "s3": said("e3", "Prep me for the interview", at: 20), "p1": said("e4", "Check my budget", at: 5)],
            isReading: false, unreadable: 0, cantReachT3: false,
            waiting: waiting,
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
        XCTAssertEqual(key(3, "f", .command), .search)
        XCTAssertEqual(key(53, "\u{1b}", []), .escape)
        XCTAssertEqual(key(17, "T", [.command, .shift]), .threads)
        XCTAssertEqual(key(46, "M", [.command, .shift]), .activity)
        XCTAssertEqual(key(45, "n", .command), .compose)
        XCTAssertEqual(key(11, "b", .command), .toggleSidebar)
        XCTAssertEqual(key(13, "w", .command), .close)
        XCTAssertEqual(key(44, "/", .command), .cheatsheet)
        XCTAssertEqual(key(43, ",", .command), .settings)
        XCTAssertNil(key(8, "c", .command), "⌘C is for copying")
        XCTAssertNil(key(126, "", []), "the arrows alone move through what's in front of you")
        XCTAssertNil(key(40, "k", [.command, .control]))
        XCTAssertNil(key(11, "b", [.control, .command]), "⌃⌘B, which opens and closes Messages, is left alone")
        XCTAssertTrue(MessagesShortcut.previousPlace.movesInText, "a box with words keeps ⌥ and the arrows")
        XCTAssertFalse(MessagesShortcut.nextThread.movesInText, "a thread key still works with words in the box, which stay in their own thread's")
        XCTAssertFalse(MessagesShortcut.toggleSidebar.movesInText, "⌘B hides the sidebar from a box with words in it too, which never makes anything bold")
    }

    func testNoShortcutDoesAnythingWhileMessagesDoesntHaveTheKeyboard() {
        let window = ChannelsWindow()
        window.update(book())
        window.view.select(.channel(.of(steve)))
        XCTAssertFalse(window.panel.isKeyWindow)
        let all: [MessagesShortcut] = [.previousThread, .nextThread, .previousPlace, .nextPlace, .previousUnread, .nextUnread, .back, .forward, .place(1), .jump, .search, .escape, .threads, .activity, .compose, .toggleSidebar, .close, .cheatsheet]
        var closed = false
        window.view.onCloseWindow = { closed = true }
        for shortcut in all {
            XCTAssertFalse(window.panel.handle(shortcut), "\(shortcut)")
        }
        XCTAssertEqual(window.view.selection, .channel(.of(steve)), "nothing moved")
        XCTAssertTrue(window.view.jumpBox.isHidden)
        XCTAssertTrue(window.view.cheatsheet.isHidden)
        XCTAssertFalse(window.view.isSidebarHidden)
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
        XCTAssertEqual(view.selection, .channel(.shades), "the cat, first of the kittens")
        view.perform(.previousPlace)
        XCTAssertEqual(view.selection, .threads)
        view.select(.channel(.of(pepper)))
        view.perform(.nextPlace)
        XCTAssertEqual(view.selection, .channel(.of(pepper)), "it stops at the bottom")
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
        view.select(.channel(.shades))
        view.perform(.forward)
        XCTAssertEqual(view.selection, .channel(.shades), "going somewhere new drops what was ahead")
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
        XCTAssertEqual(titles("pep"), ["Pepper", "Budget"], "a place by its name first, then what's in it")
        XCTAssertEqual(titles("cover"), ["Cover letter"], "a thread by its title")
        XCTAssertEqual(titles("steve"), ["Steve", "Interview prep", "Cover letter", "Resume"], "the place first, then its threads, newest first")
        XCTAssertEqual(titles("letter cover"), ["Cover letter"], "every word, in any order")
        XCTAssertEqual(titles("zebra"), [])
        XCTAssertEqual(Array(titles("").prefix(5)), ["Activity", "Threads", "Shades", "Steve", "Pepper"], "with nothing typed, every place, as the sidebar names it")
        XCTAssertTrue(titles("general").isEmpty, "and there's no #general to jump to")
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

    func testCommandFAndCommandKTurnTheBoxIntoEachOtherWithWhatsTyped() {
        let view = view()
        view.perform(.jump)
        view.jumpBox.query = "resume"
        XCTAssertEqual(view.jumpBox.items.map(\.title), ["Resume"])
        view.perform(.search)
        XCTAssertFalse(view.jumpBox.isHidden)
        XCTAssertEqual(view.jumpBox.mode, .search)
        XCTAssertEqual(view.jumpBox.query, "resume")
        XCTAssertEqual(view.jumpBox.items.map(\.found?.message.id), ["e1:ask"], "now it's what messages say")
        XCTAssertEqual(view.jumpBox.items.first?.title, CatWords.you)
        view.perform(.search)
        XCTAssertTrue(view.jumpBox.isHidden, "and the same key closes it")
    }

    func testSearchAsksT3OnlyOnceTypingPauses() {
        let view = view()
        var asked: [String] = []
        view.onAction = { if case .find(let words) = $0 { asked.append(words) } }
        view.perform(.search)
        view.jumpBox.query = "co"
        view.jumpBox.query = "coupon"
        let paused = expectation(description: "typing paused")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { paused.fulfill() }
        wait(for: [paused], timeout: 3)
        XCTAssertEqual(asked, ["coupon"], "not every letter")
    }

    func testSearchOpensAMessagesThreadAndScrollsToItHoweverFarBack() throws {
        let exchanges = (0..<80).map { index in
            Exchange(id: "x\(index)", asker: .you, askedAt: at.addingTimeInterval(TimeInterval(index * 60)), ask: index == 3 ? "Where did the coupon box go?" : "Ask \(index)", reply: "Done \(index).", repliedAt: at.addingTimeInterval(TimeInterval(index * 60 + 1)))
        }
        let book = ChannelBook.build(kittens: [steve, pepper], threads: [thread("long", of: steve, title: "Checkout")], transcripts: ["long": exchanges], isReading: false, unreadable: 0, cantReachT3: false)
        let view = ChannelsView(frame: NSRect(origin: .zero, size: ChannelsWindow.size))
        view.show(book)
        view.perform(.search)
        view.jumpBox.query = "coupon box"
        XCTAssertEqual(view.jumpBox.items.map(\.found?.message.id), ["x3:ask"])
        view.jumpBox.open()
        XCTAssertTrue(view.jumpBox.isHidden)
        XCTAssertEqual(view.selection, .thread("long", in: .channel(.of(steve))))
        let row = try XCTUnwrap(view.threadPane.shownMessageRows.first { $0.isFound }, "laid out, though a thread's pane opens on its newest")
        XCTAssertEqual(row.message.id, "x3:ask")
        XCTAssertGreaterThanOrEqual(row.frame.minY, view.threadPane.scrollOffset, "and on the screen")
        XCTAssertLessThanOrEqual(row.frame.maxY, view.threadPane.scrollOffset + view.threadPane.visibleHeight)
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
        for keys in ["⌘⇧[", "⌥↑", "⌥⇧↑", "⌘[", "⌘1", "⌘K", "Esc", "⌘⇧T", "⌘⇧M", "⌘B", "⌘N", "⌘W", "⌘/"] {
            XCTAssertTrue(listed.contains(keys), keys)
        }
        view.perform(.cheatsheet)
        XCTAssertTrue(view.cheatsheet.isHidden, "⌘/ again closes it")
    }

    func testEveryShortcutInTheListShowsAtEverySizeTheWindowCanBe() {
        for size in [ChannelsWindow.minimumSize, NSSize(width: 908, height: 560), ChannelsWindow.size] {
            let view = ChannelsView(frame: NSRect(origin: .zero, size: size))
            view.show(book())
            view.perform(.cheatsheet)
            view.layoutSubtreeIfNeeded()
            XCTAssertTrue(view.cheatsheet.bounds.contains(view.cheatsheet.card), "every row inside a window \(size)")
        }
        let roomy = ChannelsView(frame: NSRect(origin: .zero, size: ChannelsWindow.size))
        roomy.layoutSubtreeIfNeeded()
        XCTAssertLessThan(roomy.cheatsheet.card.width, ChannelsWindow.size.width / 2, "one column where it fits, as Slack's list is")
    }

    func testClickingIntoMessagesGivesItTheKeyboardWithoutActivatingShades() {
        let panel = ChannelsPanel()
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel), "so the app you were in stays active")
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
    }
}

// MARK: - Drafts

/// Words typed in a box stay with the place or thread they were typed in, as Slack keeps a draft in each, so no
/// shortcut, click or question arriving can send them anywhere else.
extension MessagesShortcutsTests {
    private func question(_ id: String, in thread: String, _ text: String) -> AgentQuestion {
        AgentQuestion(id: id, threadID: thread, threadTitle: "Cover letter", text: text, form: AnswerForm(parts: [AnswerForm.Part(key: "k", text: text, options: [], values: [], takesOwnWords: true)]))
    }

    func testAQuestionThatArrivesNeverTakesWordsTypedBeforeIt() {
        let ways: [(String, (ChannelsView) -> Void)] = [
            ("⌘⇧] then ⌘⇧[", { $0.perform(.nextThread); $0.perform(.previousThread) }),
            ("⌘[ then ⌘]", { $0.perform(.back); $0.perform(.forward) }),
            ("Esc, then opening it again", { $0.perform(.escape); $0.open(thread: "s2") }),
        ]
        let asked = question("q", in: "s2", "Delete the old version?")
        for (way, roundTrip) in ways {
            let view = view()
            var sent: [MessagesAction] = []
            view.onAction = { sent.append($0) }
            view.select(.channel(.of(steve)))
            view.open(thread: "s2")
            let composer = view.threadPane.composer
            composer.textView.string = "Make it shorter"
            view.show(book(waiting: Waiting(questions: [asked], owners: ["q": steve.id])))
            XCTAssertEqual(composer.target, .thread(id: "s2", title: "Cover letter"), way)

            roundTrip(view)
            XCTAssertEqual(view.selection.thread, "s2", way)
            XCTAssertEqual(composer.textView.string, "Make it shorter", way)
            XCTAssertEqual(composer.target, .thread(id: "s2", title: "Cover letter"), "\(way) still replies in the thread")
            composer.send(composer.textView.string)
            XCTAssertEqual(sent, [.send("Make it shorter", to: .thread(id: "s2", title: "Cover letter"), shownIn: .of(steve))], way)
        }
    }

    func testAThreadKeyLeavesADraftInItsThread() {
        let view = view()
        var sent: [MessagesAction] = []
        view.onAction = { sent.append($0) }
        view.select(.channel(.of(steve)))
        view.perform(.nextThread)
        let composer = view.threadPane.composer
        composer.textView.string = "Yes, delete every old draft"
        view.perform(.previousThread)
        XCTAssertEqual(view.selection.thread, "s2")
        XCTAssertEqual(composer.textView.string, "", "the thread above has a box of its own")
        composer.send(composer.textView.string)
        XCTAssertEqual(sent, [])

        view.perform(.nextThread)
        XCTAssertEqual(composer.textView.string, "Yes, delete every old draft", "and it's waiting back where it was typed")
        composer.send(composer.textView.string)
        XCTAssertEqual(sent, [.send("Yes, delete every old draft", to: .thread(id: "s3", title: "Interview prep"), shownIn: .of(steve))])
    }

    func testAThreadKeyInThreadsLeavesADraftWithItsKitten() {
        let view = view()
        var sent: [MessagesAction] = []
        view.onAction = { sent.append($0) }
        view.select(.threads)
        view.perform(.nextThread)
        XCTAssertEqual(view.selection.thread, "p1")
        let composer = view.threadPane.composer
        composer.textView.string = "Cancel the card"
        view.perform(.nextThread)
        XCTAssertEqual(view.selection.thread, "s3", "Steve's")
        XCTAssertEqual(composer.textView.string, "")
        composer.send(composer.textView.string)
        XCTAssertEqual(sent, [], "Pepper's words never reach Steve")

        view.perform(.previousThread)
        composer.send(composer.textView.string)
        XCTAssertEqual(sent, [.send("Cancel the card", to: .thread(id: "p1", title: "Budget"), shownIn: .of(pepper))])
    }

    func testAPlaceKeyLeavesADraftInItsPlace() {
        let view = view()
        var sent: [MessagesAction] = []
        view.onAction = { sent.append($0) }
        view.select(.channel(.shades))
        let composer = view.pane.composer
        composer.textView.string = "What's on my calendar?"
        view.perform(.place(4))
        XCTAssertEqual(view.selection, .channel(.of(steve)))
        XCTAssertEqual(composer.textView.string, "")
        XCTAssertEqual(composer.target, .newThread(steve))
        composer.send(composer.textView.string)
        XCTAssertEqual(sent, [], "what was for the router never starts work in Steve's folder")

        view.perform(.place(3))
        XCTAssertEqual(composer.textView.string, "What's on my calendar?")
        composer.send(composer.textView.string)
        XCTAssertEqual(sent, [.send("What's on my calendar?", to: .router, shownIn: .shades)])
    }

    func testAReplyLeftInAClosedThreadStaysThere() {
        let view = view()
        var sent: [MessagesAction] = []
        view.onAction = { sent.append($0) }
        view.open(thread: "s3", from: .channel(.of(steve)), typing: true)
        let composer = view.threadPane.composer
        composer.textView.string = "Yes, delete every old draft"
        view.perform(.escape)
        XCTAssertNil(view.selection.thread)

        view.open(thread: "p1", from: .channel(.of(pepper)), typing: true)
        XCTAssertEqual(composer.target, .thread(id: "p1", title: "Budget"))
        XCTAssertEqual(composer.textView.string, "", "Pepper's thread has a box of its own")
        composer.send(composer.textView.string)
        XCTAssertEqual(sent, [])

        view.open(thread: "s3", from: .channel(.of(steve)), typing: true)
        composer.send(composer.textView.string)
        XCTAssertEqual(sent, [.send("Yes, delete every old draft", to: .thread(id: "s3", title: "Interview prep"), shownIn: .of(steve))])
    }

    func testAlsoSendIsOnlyForTheThreadItWasTickedIn() {
        let view = view()
        var sent: [MessagesAction] = []
        view.onAction = { sent.append($0) }
        view.select(.thread("s3", in: .channel(.of(steve))))
        let composer = view.threadPane.composer
        composer.alsoSend.toggle()
        XCTAssertTrue(composer.alsoSends)
        view.perform(.previousThread)
        XCTAssertFalse(composer.alsoSends, "the thread above is another thread")

        view.perform(.nextThread)
        composer.alsoSend.toggle()
        view.perform(.place(5))
        view.perform(.nextThread)
        XCTAssertEqual(view.selection, .thread("p1", in: .channel(.of(pepper))))
        XCTAssertFalse(composer.alsoSends, "and so is one in another channel")
        composer.send("Pay the rent")
        XCTAssertEqual(sent, [.send("Pay the rent", to: .thread(id: "p1", title: "Budget"), shownIn: .of(pepper), alsoSent: false)])
    }

    func testWordsForAQuestionAnsweredWhileYouWereAwayWaitAndSendNowhereElse() {
        let first = question("q1", in: "s2", "Which font?")
        let next = question("q2", in: "s2", "Delete the old version?")
        let view = view()
        var sent: [MessagesAction] = []
        view.onAction = { sent.append($0) }
        view.show(book(waiting: Waiting(questions: [first], owners: ["q1": steve.id])))
        view.select(.thread("s2", in: .channel(.of(steve))))
        let composer = view.threadPane.composer
        XCTAssertEqual(composer.target, .question(first))
        composer.textView.string = "Yes"
        view.perform(.nextThread)

        // Meanwhile the font question is answered in T3, and another arrives.
        view.show(book(waiting: Waiting(questions: [next], owners: ["q2": steve.id])))
        view.perform(.previousThread)
        XCTAssertEqual(composer.textView.string, "Yes", "your words are still there")
        XCTAssertNotEqual(composer.target, .question(next))
        composer.send(composer.textView.string)
        XCTAssertEqual(sent, [], "but they don't answer the new question, or go to the thread instead")
        view.show(book(waiting: Waiting(questions: [next], owners: ["q2": steve.id])))
        composer.send(composer.textView.string)
        XCTAssertEqual(sent, [], "even after a refresh")

        composer.textView.string = ""
        composer.textDidChange(Notification(name: NSText.didChangeNotification))
        XCTAssertEqual(composer.target, .question(next), "cleared, the box points where it would now")
    }

    func testWhatYouSayForAThreadYouMovedAwayFromWaitsThere() {
        let view = view()
        var sent: [MessagesAction] = []
        view.onAction = { sent.append($0) }
        view.select(.thread("s3", in: .channel(.of(steve))))
        let composer = view.threadPane.composer
        composer.textView.string = "Keep it"
        view.threadPane.startSpeaking()
        view.perform(.previousThread)
        view.threadPane.spoke("to one page")
        XCTAssertEqual(sent, [])
        XCTAssertEqual(composer.textView.string, "", "nothing said for that thread lands in this one")

        view.perform(.nextThread)
        XCTAssertEqual(composer.textView.string, "Keep it to one page")
        XCTAssertEqual(composer.target, .thread(id: "s3", title: "Interview prep"))
    }
}

// MARK: - Activity

extension MessagesShortcutsTests {
    func testActivitysThreadKeysOnlyGoWhereAClickThereOpensABox() {
        // Another project of yours that Messages hasn't read, with an approval and a question with only choices.
        var other = AgentThread(id: "other", title: "Deploy billing", projectTitle: "billing", status: .running, model: "m", updatedAt: at, projectPath: "/elsewhere/billing")
        other.status = .waitingForApproval
        let approval = ApprovalRequest(id: "ap", threadID: "other", threadTitle: "Deploy billing", kind: .command, summary: "Run: deploy", createdAt: at)
        let choices = AgentQuestion(id: "q", threadID: "other", threadTitle: "Deploy billing", text: "Deploy now?", form: AnswerForm(parts: [AnswerForm.Part(key: "go", text: "Deploy now?", options: ["Yes", "No"], values: ["y", "n"], takesOwnWords: false)]))
        let book = ChannelBook.build(
            kittens: [steve, pepper], threads: [thread("s1", of: steve, title: "Resume"), other],
            transcripts: ["s1": said("e1", "Tidy my resume", at: 0)],
            isReading: false, unreadable: 0, cantReachT3: false,
            waiting: Waiting(approvals: [approval], questions: [choices])
        )
        let view = ChannelsView(frame: NSRect(origin: .zero, size: ChannelsWindow.size))
        view.show(book)
        XCTAssertEqual(view.threadOrder(in: book), [], "an approval and a question with only choices open in T3")
        XCTAssertFalse(view.perform(.nextThread))
        XCTAssertNil(view.selection.thread)
        XCTAssertTrue(view.threadPane.isHidden)
    }

    func testActivitysThreadKeysFollowTypeAnAnswerReplyAndWhatsInProgress() {
        var going = thread("s2", of: steve, title: "Cover letter")
        going.status = .running
        var unread = thread("s9", of: steve, title: "Not read yet")
        unread.status = .running
        let words = AgentQuestion(id: "q", threadID: "p1", threadTitle: "Budget", text: "Which account?", form: AnswerForm(parts: [AnswerForm.Part(key: "k", text: "Which account?", options: [], values: [], takesOwnWords: true)]))
        let report = InboxEntry(id: "r", kind: .decision, text: "Ship it?", threadID: "s1", threadTitle: "Resume", at: at)
        let book = ChannelBook.build(
            kittens: [steve, pepper],
            threads: [thread("s1", of: steve, title: "Resume"), going, unread, thread("p1", of: pepper, title: "Budget")],
            transcripts: ["s1": said("e1", "Tidy my resume", at: 0), "s2": said("e2", "Write a cover letter", at: 10), "p1": said("e4", "Check my budget", at: 5)],
            isReading: false, unreadable: 0, cantReachT3: false,
            waiting: Waiting(questions: [words], owners: ["q": pepper.id], reports: [report])
        )
        let view = ChannelsView(frame: NSRect(origin: .zero, size: ChannelsWindow.size))
        view.show(book)
        XCTAssertEqual(view.threadOrder(in: book), ["p1", "s1", "s2"], "Type an answer, Reply, then what's in progress that's been read")
        view.perform(.nextThread)
        XCTAssertEqual(view.threadPane.composer.target, .question(words))
    }
}
