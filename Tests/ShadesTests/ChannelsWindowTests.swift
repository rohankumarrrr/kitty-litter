import AppKit
@testable import Shades
import ShadesCore
import XCTest

@MainActor
final class ChannelsWindowTests: XCTestCase {
    private let steve = Kitten(name: "Steve", role: "Professional", covers: "", folder: "/k/steve")
    private let pepper = Kitten(name: "Pepper", role: "Finance", covers: "", folder: "/k/pepper")
    private let at = Date(timeIntervalSince1970: 1_000_000)
    private let long = (1...40).map { "Line \($0) of something long." }.joined(separator: "\n")

    private func view(height: CGFloat = 560) -> ChannelsView {
        ChannelsView(frame: NSRect(x: 0, y: 0, width: 820, height: height))
    }

    private func book(exchanges: Int = 1, text: String = "Reply") -> ChannelBook {
        let thread = AgentThread(id: "t", title: "Work", projectTitle: "Steve", status: .completed, model: "m", updatedAt: at, projectPath: "/k/steve")
        let said = (0..<exchanges).map { index in
            Exchange(id: "e\(index)", asker: .you, askedAt: at.addingTimeInterval(TimeInterval(index)), ask: "Ask", reply: text, repliedAt: at.addingTimeInterval(TimeInterval(index)))
        }
        return ChannelBook.build(kittens: [steve, pepper], threads: [thread], transcripts: ["t": said], isReading: false, unreadable: 0, cantReachT3: false)
    }

    /// A channel with `count` threads of Steve's, each one exchange, for scrolling a channel.
    private func book(threads count: Int) -> ChannelBook {
        let threads = (0..<count).map { AgentThread(id: "t\($0)", title: "Work \($0)", projectTitle: "Steve", status: .completed, model: "m", updatedAt: at, projectPath: "/k/steve") }
        let said = Dictionary(uniqueKeysWithValues: (0..<count).map { ("t\($0)", [Exchange(id: "e\($0)", asker: .you, askedAt: at.addingTimeInterval(TimeInterval($0)), ask: "Ask \($0)", reply: "Reply", repliedAt: at.addingTimeInterval(TimeInterval($0)))]) })
        return ChannelBook.build(kittens: [steve, pepper], threads: threads, transcripts: said, isReading: false, unreadable: 0, cantReachT3: false)
    }

    private let inThread = ChannelSelection.thread("t", in: .channel(.kitten("/k/steve")))

    private func subviews(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(subviews)
    }

    func testThePanelTakesTheKeyboardOnlyWhenNeededAndNeverFloatsOverYourWork() {
        let panel = ChannelsPanel()
        XCTAssertTrue(panel.canBecomeKey, "for the box at the bottom")
        XCTAssertTrue(panel.becomesKeyOnlyIfNeeded, "opening it leaves the keyboard where it was, and only a click into it, which makes it key without activating Shades, takes it")
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertEqual(panel.level, .normal)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertFalse(panel.isReleasedWhenClosed)
        XCTAssertTrue(panel.collectionBehavior.contains(.ignoresCycle))
    }

    func testNoScreenCaptureCanSeeIt() {
        XCTAssertEqual(ChannelsPanel().sharingType, .none, "so a kitten's own screen tools can't be shown another kitten's messages")
    }

    func testEveryViewTakesClicksAndOnlyTheBoxesAndWordsYouPressInTakeTheKeyboard() throws {
        let view = view()
        view.show(book())
        view.select(inThread)
        let rows = subviews(of: view).filter { $0 is QuietView || $0 is QuietButton || $0 is QuietScrollView || $0 is QuietCheckbox }
        XCTAssertGreaterThan(rows.count, 10)
        XCTAssertTrue(rows.contains { $0 is QuietCheckbox }, "the thread's Also send box is there")
        for row in rows {
            XCTAssertTrue(row.acceptsFirstMouse(for: nil), "\(row)")
            XCTAssertFalse(row.acceptsFirstResponder, "\(row)")
            XCTAssertFalse(row.needsPanelToBecomeKey, "\(row)")
        }
        // The jump box is a box too, only there once ⌘K opens it.
        let boxes = Set(([view.jumpBox.field] + subviews(of: view.pane.composer) + subviews(of: view.threadPane.composer) + subviews(of: view.jumpBox)).map(ObjectIdentifier.init))
        let taking = subviews(of: view).filter { !boxes.contains(ObjectIdentifier($0)) && ($0.acceptsFirstResponder || $0.needsPanelToBecomeKey) }
        XCTAssertFalse(taking.isEmpty, "the words can be selected")
        for taker in taking {
            // Only so you can select and copy them, the way the bubble's reply does, and never to type into.
            let words = try XCTUnwrap(taker as? ChannelTextView, "only the boxes and words take the keyboard, not \(type(of: taker))")
            XCTAssertFalse(words.isEditable)
            XCTAssertTrue(words.isSelectable)
            XCTAssertTrue(words.acceptsFirstMouse(for: nil), "the first press starts selecting")
        }
        for composer in [view.pane.composer, view.threadPane.composer] {
            XCTAssertTrue(composer.textView.acceptsFirstResponder)
            XCTAssertTrue(composer.textView.needsPanelToBecomeKey)
        }
    }

    func testPartOfAMessageCanBeSelectedAndCopiesAsPlainWords() throws {
        let view = view()
        view.show(book())
        view.select(inThread)
        let row = try XCTUnwrap(view.threadPane.shownMessageRows.first { !$0.isYours })
        let words = try XCTUnwrap(subviews(of: row).compactMap { $0 as? ChannelTextView }.first)
        XCTAssertTrue(row.bubble.contains(words.frame), "the words sit in their bubble, so pressing beside it selects nothing")
        XCTAssertFalse(words.string.isEmpty)

        // Command-C copies the selection. The pasteboard itself is out of reach of tests, so this checks what it'd get.
        words.setSelectedRange(NSRange(location: 0, length: 4))
        XCTAssertEqual((words.string as NSString).substring(with: words.selectedRange()), String(words.string.prefix(4)))
        XCTAssertEqual(words.writablePasteboardTypes.map(\.rawValue), ["NSStringPboardType"], "plain words, without the bubble's colours")
        XCTAssertTrue(words.resignFirstResponder())
        XCTAssertEqual(words.selectedRange().length, 0, "one selection at a time")
    }

    func testItStartsOnActivity() {
        let view = view()
        view.show(book())
        XCTAssertEqual(view.selection, .activity)
        XCTAssertEqual(view.sidebar.row(for: .activity)?.isSelected, true)
        XCTAssertTrue(view.threadPane.isHidden, "with no thread open")
    }

    func testPressingARowSelectsItsChannelAndShowsIt() throws {
        let view = view()
        let book = book()
        view.show(book)
        let row = try XCTUnwrap(view.sidebar.row(for: .channel(.of(steve))))
        row.press()
        XCTAssertEqual(view.selection, .channel(.of(steve)))
        XCTAssertTrue(row.isSelected)
        XCTAssertEqual(view.sidebar.row(for: .activity)?.isSelected, false)
        XCTAssertEqual(view.pane.shown, ChannelRows.rows(.channel(.of(steve)), in: book))
        XCTAssertTrue(row.accessibilityPerformPress())
    }

    func testAFinishedThreadIsInItsChannelAndOutOfActivity() throws {
        let view = view()
        view.show(book())
        let issues = { view.pane.shown.compactMap { row -> String? in if case .issue(let thread) = row { thread.id } else { nil } } }
        XCTAssertEqual(issues(), [])
        try XCTUnwrap(view.sidebar.row(for: .channel(.of(steve)))).press()
        XCTAssertEqual(view.pane.shown.compactMap { row -> String? in if case .parent(let post) = row { post.threadID } else { nil } }, ["t"])
    }

    func testTheSidebarHasActivityThreadsEachChannelAndTheDM() throws {
        let groups = ChannelSidebarItem.groups(in: book())
        XCTAssertEqual(groups.map(\.heading), [nil, CatWords.channelsHeading, CatWords.directMessages])
        XCTAssertEqual(groups.map { $0.items.map(\.title) }, [["Activity", "Threads"], ["general", "steve", "pepper"], ["Shades"]])
        XCTAssertEqual(ChannelSidebarItem.places(in: book()), [.activity, .threads, .channel(.general), .channel(.of(steve)), .channel(.of(pepper)), .channel(.shades)])
        XCTAssertFalse(groups.contains { $0.items.contains { ["Done", "Needs you", "Everyone"].contains($0.title) } })
    }

    func testOnlyAKittenThatsWorkingOrNeedsYouMoves() {
        func moves(_ state: KittenStatus.State) -> Bool {
            let status = KittenStatus(kitten: steve, state: state)
            return ChannelSidebarRow(item: ChannelSidebarItem(place: .channel(.of(steve)), title: "steve", icon: .kitten(status))).isLive
        }
        XCTAssertTrue(moves(.working(sessions: 1)))
        XCTAssertTrue(moves(.needsYou))
        XCTAssertFalse(moves(.idle))
        XCTAssertFalse(moves(.notSetUp))
    }

    func testALongMessageIsCutAndShowMoreSurvivesARefresh() throws {
        let view = view()
        view.show(book(text: long))
        view.select(inThread)
        let row = try XCTUnwrap(view.threadPane.longMessageRow)
        let cutHeight = row.frame.height

        row.pressShowMore()
        XCTAssertFalse(row.isCut)
        XCTAssertGreaterThan(row.frame.height, cutHeight)

        view.show(book(exchanges: 2, text: long))
        let first = view.threadPane.shownMessageRows.first { $0.isExpanded }
        XCTAssertNotNil(first, "still open after new messages came in")
        XCTAssertEqual(view.threadPane.shownMessageRows.filter(\.isCut).count, 1, "and the new one starts cut")
    }

    func testAShortMessageIsntCut() {
        let view = view()
        view.show(book())
        view.select(inThread)
        XCTAssertNil(view.threadPane.longMessageRow)
    }

    func testSelectingAChannelGoesToTheBottomAndActivityToTheTop() {
        let view = view()
        view.show(book(threads: 40))
        view.select(.channel(.of(steve)))
        XCTAssertGreaterThan(view.pane.scrollOffset, 0)
        XCTAssertEqual(view.pane.distanceFromBottom, 0, accuracy: 1)

        view.select(.activity)
        XCTAssertEqual(view.pane.scrollOffset, 0)
    }

    func testARefreshKeepsYouAtTheBottomOrLeavesYouAlone() {
        let view = view()
        view.show(book(exchanges: 40))
        view.select(inThread)
        let pane = view.threadPane

        view.show(book(exchanges: 41))
        XCTAssertEqual(pane.distanceFromBottom, 0, accuracy: 1, "at the bottom, you follow along")

        pane.scrollOffset -= 30
        view.show(book(exchanges: 42))
        XCTAssertEqual(pane.distanceFromBottom, 0, accuracy: 1, "close enough counts")

        // Near the top, older rows are laid out above what you're reading, so where you are is wherever that leaves you.
        pane.scrollOffset = 100
        let reading = pane.scrollOffset
        view.show(book(exchanges: 43))
        XCTAssertEqual(pane.scrollOffset, reading, "reading further up, you're left alone")
    }

    func testRowsThatHaventChangedArentRebuilt() {
        let view = view()
        view.show(book(exchanges: 2))
        view.select(inThread)
        let first = view.threadPane.shownMessageRows.first
        let parent = view.pane.shownMessageRows.first

        view.show(book(exchanges: 2))
        XCTAssertTrue(view.threadPane.shownMessageRows.first === first)
        view.show(book(exchanges: 3))
        XCTAssertTrue(view.threadPane.shownMessageRows.first === first, "new rows don't disturb the ones above")
        XCTAssertFalse(view.pane.shownMessageRows.first === parent, "the parent's reply bar says there's one more")
    }

    private func rowViews(in view: ChannelsView) -> [ChannelRowView] {
        subviews(of: view.threadPane).compactMap { $0 as? ChannelRowView }
    }

    func testALongThreadOnlyHasViewsNearWhatYouCanSee() {
        let view = view()
        view.show(book(exchanges: 300))
        view.select(inThread)
        let pane = view.threadPane
        XCTAssertGreaterThan(pane.shown.count, 400)
        XCTAssertLessThan(rowViews(in: view).count, 60, "only the rows near the bottom are in the window")
        XCTAssertLessThanOrEqual(pane.shownMessageRows.count, ChannelPane.page, "and only the newest page is laid out")
        XCTAssertEqual(pane.distanceFromBottom, 0, accuracy: 1)

        pane.scrollOffset -= 2_000
        XCTAssertLessThan(rowViews(in: view).count, 60, "scrolling swaps rows in and out rather than adding them all")
        XCTAssertTrue(rowViews(in: view).allSatisfy { $0.frame.intersects(NSRect(x: 0, y: pane.scrollOffset - 700, width: 820, height: 1_900)) })
    }

    func testScrollingUpLaysOutOlderRowsWithoutMovingWhatYoureReading() throws {
        let view = view()
        view.show(book(exchanges: 300))
        view.select(inThread)
        let pane = view.threadPane
        let laidOut = pane.shownMessageRows.count

        pane.scrollOffset = pane.visibleHeight + 50
        XCTAssertEqual(pane.shownMessageRows.count, laidOut, "a screen from the top, nothing more is laid out yet")
        let reading = try XCTUnwrap(pane.shownMessageRows.first { $0.superview != nil && $0.frame.maxY > pane.scrollOffset })
        let above = pane.scrollOffset - reading.frame.minY

        pane.scrollOffset -= 100
        XCTAssertGreaterThan(pane.shownMessageRows.count, laidOut, "the page before it is laid out")
        XCTAssertEqual(pane.scrollOffset - reading.frame.minY, above - 100, accuracy: 0.5, "and what you were reading moved only as far as you scrolled")

        for _ in 0..<20 { pane.scrollOffset = 0 }
        XCTAssertEqual(pane.shownMessageRows.count, 600, "every message is there once you've scrolled to the top")
        guard case .message(let parent) = pane.shown.first else { return XCTFail("\(pane.shown.prefix(3))") }
        XCTAssertEqual(parent.id, "e0:ask", "starting with its parent")
    }

    func testANewMessageInALongThreadOnlyMakesViewsForItself() {
        let view = view()
        view.show(book(exchanges: 200))
        view.select(inThread)
        let before = Set(view.threadPane.shownMessageRows.map(ObjectIdentifier.init))

        view.show(book(exchanges: 201))
        let made = view.threadPane.shownMessageRows.filter { !before.contains(ObjectIdentifier($0)) }
        XCTAssertEqual(made.count, 2, "only the new ask and reply are new views")
        XCTAssertEqual(view.threadPane.distanceFromBottom, 0, accuracy: 1)
    }

    func testClosingKeepsEverythingSoItOpensAgainAsYouLeftIt() {
        let window = ChannelsWindow()
        var closed = 0
        window.onClose = { closed += 1 }
        window.update(book())
        window.view.select(.channel(.of(steve)))
        window.view.pane.composer.textView.string = "Half a thought"
        let rows = window.view.pane.shownMessageRows.map(ObjectIdentifier.init)
        XCTAssertFalse(rows.isEmpty)

        window.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        XCTAssertEqual(closed, 1)
        window.update(book())
        XCTAssertEqual(window.view.pane.shownMessageRows.map(ObjectIdentifier.init), rows, "nothing is laid out again")
        XCTAssertEqual(window.view.selection, .channel(.of(steve)))
        XCTAssertEqual(window.view.pane.composer.textView.string, "Half a thought", "a draft waits, as it does in Slack")
    }

    func testTheFirstOpenIsCentredOnTheCatsScreen() {
        let screen = NSRect(x: 100, y: 50, width: 1440, height: 900)
        let frame = ChannelsWindow.centered(in: screen)
        XCTAssertEqual(frame.size, ChannelsWindow.size)
        XCTAssertEqual(frame.midX, screen.midX, accuracy: 1)
        XCTAssertEqual(frame.midY, screen.midY, accuracy: 1)
    }

    func testMarkdownIsInlineOnlyAndNothingCanAct() {
        let text = ChannelMarkdown.attributed("**Bold** and *soft* with `code` and [a link](https://example.com)\n# Not a heading")
        XCTAssertEqual(text.string, "Bold and soft with code and a link\n# Not a heading")
        var links = 0
        text.enumerateAttribute(.link, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if value != nil { links += 1 }
        }
        XCTAssertEqual(links, 0)
        let bold = text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertEqual(bold?.fontDescriptor.symbolicTraits.contains(.bold), true)
    }

    func testTextThatIsntMarkdownStillComesThrough() {
        XCTAssertEqual(ChannelMarkdown.attributed("plain words").string, "plain words")
        XCTAssertEqual(ChannelMarkdown.attributed("a * b ` c [d").string, "a * b ` c [d")
    }

    func testACutBlockNeverEndsOnABlankLine() {
        let block = ChannelTextBlock(ChannelMarkdown.attributed("one\n\nthree\nfour"))
        let full = block.fit(width: 400)
        XCTAssertFalse(block.isCut)
        let cut = block.fit(width: 400, maxLines: 2)
        XCTAssertTrue(block.isCut)
        XCTAssertLessThan(cut, full)
        XCTAssertEqual(block.fit(width: 400, maxLines: 1), cut, "stopping at the blank line leaves just the first")
    }

    func testTheCheckPrintsOnlyCounts() {
        let secret = "SENTINEL"
        let kitten = Kitten(name: secret, role: secret, covers: secret, folder: "/k/\(secret)")
        let thread = AgentThread(id: secret, title: "\(secret): \(secret)", projectTitle: secret, status: .running, model: secret, updatedAt: at)
        let built = ChannelBook.build(
            kittens: [kitten],
            threads: [thread],
            transcripts: [secret: [
                Exchange(id: secret, asker: .you, askedAt: at, ask: secret, reply: secret, repliedAt: at),
                Exchange(id: "2", asker: .agent(threadID: nil), askedAt: at, ask: secret),
            ]],
            isReading: false,
            unreadable: 1,
            cantReachT3: false
        )
        let line = DevFlags.checkLine(built, threadsRead: 7, milliseconds: 9)
        XCTAssertFalse(line.contains(secret))
        for expected in ["threads read: 7", "unreadable: 1", "channels with threads: 1", "threads: 1", "replies: 3", "messages: 4", "asked by you: 1", "asked by a kitten: 0", "asked by someone else: 1", "replies with no ask: 0", "issues: 1", "milliseconds: 9"] {
            XCTAssertTrue(line.contains(expected), expected)
        }
    }

    // MARK: - The box

    private func header(in view: NSView) -> String? {
        subviews(of: view).compactMap { $0 as? ChannelHeader }.first?.accessibilityLabel()
    }

    private func pressButton(_ title: String, in view: NSView) throws {
        let buttons = subviews(of: view).compactMap { $0 as? QuietButton }
        let button = try XCTUnwrap(buttons.first { $0.accessibilityLabel() == title }, "no \(title) in \(buttons.compactMap { $0.accessibilityLabel() })")
        XCTAssertTrue(button.accessibilityPerformPress())
    }

    func testAChannelsBoxStartsANewThreadAndOpensItInThePane() {
        let view = view()
        var sent: [MessagesAction] = []
        view.onAction = { sent.append($0) }
        view.show(book())
        view.select(.channel(.of(steve)))
        XCTAssertEqual(view.pane.composer.target, .newThread(steve), "the box under the channel never guesses a thread")

        view.pane.composer.send("  Write a cover letter  ")
        guard case .startTopic("Write a cover letter", steve, let topic)? = sent.last else { return XCTFail("\(sent)") }
        XCTAssertEqual(view.selection, .thread(topic, in: .channel(.of(steve))), "so what you add next goes into it")
        XCTAssertFalse(view.threadPane.isHidden)
        XCTAssertEqual(view.pane.composer.textView.string, "")

        view.pane.composer.send("   ")
        XCTAssertEqual(sent.count, 1, "nothing to send")
    }

    func testAThreadsBoxRepliesOnlyIntoItAndStaysThere() {
        let view = view()
        var sent: [MessagesAction] = []
        view.onAction = { sent.append($0) }
        view.show(book())
        view.select(inThread)
        XCTAssertEqual(view.threadPane.composer.target, .thread(id: "t", title: "Work"))

        view.threadPane.composer.send("Make it shorter")
        XCTAssertEqual(sent, [.send("Make it shorter", to: .thread(id: "t", title: "Work"), shownIn: .of(steve))])
        XCTAssertEqual(view.selection, inThread)
        XCTAssertEqual(view.threadPane.composer.target, .thread(id: "t", title: "Work"))
        XCTAssertEqual(view.pane.composer.target, .newThread(steve), "and the channel's own box still starts something new")
    }

    func testAlsoSendToTheChannelGoesWithTheReplyAndThenUnticks() {
        let view = view()
        var sent: [MessagesAction] = []
        view.onAction = { sent.append($0) }
        view.show(book())
        view.select(inThread)
        let also = view.threadPane.composer.alsoSend
        XCTAssertFalse(also.isHidden)
        XCTAssertEqual(also.title, "Also send to #steve", "the thread's home channel")
        XCTAssertFalse(also.isOn)

        also.toggle()
        view.threadPane.composer.send("Keep the FAQ")
        XCTAssertEqual(sent, [.send("Keep the FAQ", to: .thread(id: "t", title: "Work"), shownIn: .of(steve), alsoSent: true)])
        XCTAssertFalse(also.isOn, "as in Slack, it's for one reply")
        view.threadPane.composer.send("Only in the thread")
        XCTAssertEqual(sent.last, .send("Only in the thread", to: .thread(id: "t", title: "Work"), shownIn: .of(steve), alsoSent: false))
        XCTAssertTrue(view.pane.composer.alsoSend.isHidden, "a channel's own box has none")
    }

    func testAThreadFromGeneralOffersGeneral() {
        let thread = AgentThread(id: "t", title: "Work", projectTitle: "Steve", status: .completed, model: "m", updatedAt: at, projectPath: "/k/steve")
        let said = Exchange(id: "e", asker: .you, askedAt: at, ask: "Ask", reply: "Reply", repliedAt: at)
        let built = ChannelBook.build(kittens: [steve], threads: [thread], transcripts: ["t": [said]], isReading: false, unreadable: 0, cantReachT3: false, inGeneral: ["t": at])
        let view = view()
        view.show(built)
        view.select(.thread("t", in: .channel(.general)))
        XCTAssertEqual(view.threadPane.composer.alsoSend.title, "Also send to #general")
    }

    func testClickingAParentOpensItsThreadBesideTheChannel() throws {
        let view = view()
        var opened: [String] = []
        view.onOpenThread = { opened.append($0) }
        view.show(book())
        view.select(.channel(.of(steve)))
        let parent = try XCTUnwrap(view.pane.shownMessageRows.first { $0.replyBar != nil })
        XCTAssertEqual(parent.replyBar?.count, 1)
        XCTAssertTrue(parent.isPressable)

        parent.press()
        XCTAssertEqual(view.selection, inThread)
        XCTAssertFalse(view.threadPane.isHidden)
        XCTAssertEqual(header(in: view.threadPane), "Thread, #steve  ·  Work · Steve · Done")
        XCTAssertTrue(view.sidebar.row(for: .channel(.of(steve)))?.isSelected == true, "its channel stays selected")
        XCTAssertEqual(view.pane.shown, ChannelRows.rows(.channel(.of(steve)), in: book()), "and still showing beside it")
        guard case .message(let first) = view.threadPane.shown.first else { return XCTFail("\(view.threadPane.shown)") }
        XCTAssertEqual(first.id, "e0:ask")
        XCTAssertEqual(view.threadPane.shown[1], .replies(1))

        try pressButton(CatWords.openInT3, in: view.threadPane)
        XCTAssertEqual(opened, ["t"])
        try pressButton(CatWords.closeThread, in: view.threadPane)
        XCTAssertEqual(view.selection, .channel(.of(steve)))
        XCTAssertTrue(view.threadPane.isHidden)
    }

    func testEscInTheBoxClosesTheThreadPane() {
        let view = view()
        view.show(book())
        view.select(inThread)
        let composer = view.threadPane.composer
        XCTAssertTrue(composer.textView(composer.textView, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        XCTAssertEqual(view.selection, .channel(.of(steve)))
    }

    func testThePaneFitsBesideTheChannelEvenAtItsNarrowest() {
        let view = ChannelsView(frame: NSRect(origin: .zero, size: ChannelsWindow.minimumSize))
        view.show(book())
        view.select(inThread)
        view.layoutSubtreeIfNeeded()
        XCTAssertGreaterThanOrEqual(view.pane.frame.width, 300, "the channel still reads")
        XCTAssertGreaterThanOrEqual(view.threadPane.frame.width, ChannelsView.threadWidths.lowerBound)
        XCTAssertEqual(view.pane.frame.maxX, view.threadPane.frame.minX)
        XCTAssertEqual(view.threadPane.frame.maxX, ChannelsWindow.minimumSize.width)
    }

    func testThreadsOpensEachThreadBesideTheList() throws {
        let view = view()
        view.show(book(exchanges: 3))
        view.select(.threads)
        let digest = try XCTUnwrap(subviews(of: view.pane).compactMap { $0 as? ThreadDigestRowView }.first)
        digest.press()
        XCTAssertEqual(view.selection, .thread("t", in: .threads), "Threads stays beside it")
    }

    func testAReplyAlsoSentToTheChannelOpensItsThread() throws {
        let thread = AgentThread(id: "t", title: "Work", projectTitle: "Steve", status: .completed, model: "m", updatedAt: at, projectPath: "/k/steve")
        let reply = ChannelMessage(exchangeID: "sent", kind: .ask, speaker: .you, text: "Keep the FAQ", at: at.addingTimeInterval(5), threadID: "t", threadTitle: "")
        let built = ChannelBook.build(
            kittens: [steve], threads: [thread], transcripts: ["t": [Exchange(id: "e", asker: .you, askedAt: at, ask: "Rewrite it", reply: "Done.", repliedAt: at)]],
            isReading: false, unreadable: 0, cantReachT3: false, sent: [SentMessage(channel: .of(steve), message: reply, alsoSent: true)]
        )
        let view = view()
        view.show(built)
        view.select(.channel(.of(steve)))
        let row = try XCTUnwrap(view.pane.shownMessageRows.first { $0.context != nil })
        XCTAssertEqual(row.context, "replied to a thread: Rewrite it")
        row.press()
        XCTAssertEqual(view.selection, inThread)
    }

    func testActivityStaysAtTheTopWhenMoreComesIn() {
        let view = view(height: 300)
        let report = InboxEntry(id: "r", kind: .decision, text: "Ship it?", threadID: "t", threadTitle: "Work", at: at)
        view.show(ChannelBook.build(kittens: [steve, pepper], threads: [], transcripts: [:], isReading: true, unreadable: 0, cantReachT3: false, waiting: Waiting(reports: [report])))
        let busy = (0..<12).map { AgentThread(id: "w\($0)", title: "Work \($0)", projectTitle: "Steve", status: .running, model: "m", updatedAt: at, projectPath: "/k/steve") }
        view.show(ChannelBook.build(kittens: [steve, pepper], threads: busy, transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false, waiting: Waiting(reports: [report])))
        XCTAssertEqual(view.pane.scrollOffset, 0, "what's waiting is at the top, so In progress growing mustn't scroll it away")
    }

    func testAThreadOpensAtItsLatestLikeAConversation() {
        let view = view(height: 300)
        view.show(book(exchanges: 30))
        view.select(inThread)
        XCTAssertGreaterThan(view.threadPane.scrollOffset, 0)
        XCTAssertLessThanOrEqual(view.threadPane.distanceFromBottom, 1)
    }

    func testReplyOnAParentOpensItsThreadReadyToType() throws {
        let view = view()
        view.show(book())
        view.select(.channel(.of(steve)))
        let reply = try XCTUnwrap(view.pane.shownMessageRows.last?.onReply)
        reply()
        XCTAssertEqual(view.selection, inThread)
        XCTAssertEqual(view.threadPane.composer.target, .thread(id: "t", title: "Work"))
        XCTAssertNil(view.threadPane.shownMessageRows.last?.onReply, "in the thread, the box already replies")
    }

    func testReplyingToAReportOpensItsThreadBesideItsChannel() throws {
        let report = InboxEntry(id: "r", kind: .decision, text: "Merged. Say ship it.", threadID: "t", threadTitle: "Work", at: at)
        let thread = AgentThread(id: "t", title: "Work", projectTitle: "Steve", status: .completed, model: "m", updatedAt: at, projectPath: "/k/steve")
        let built = ChannelBook.build(kittens: [steve, pepper], threads: [thread], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false, waiting: Waiting(reports: [report]))
        let view = view()
        view.show(built)
        XCTAssertTrue(view.pane.composer.isHidden)
        XCTAssertNil(view.pane.composer.target)

        let card = try XCTUnwrap(subviews(of: view).compactMap { $0 as? CardRowView }.first)
        XCTAssertTrue(try XCTUnwrap(card.buttons.first).accessibilityPerformPress())
        XCTAssertEqual(view.selection, inThread, "in its home channel")
        XCTAssertEqual(view.threadPane.composer.target, .thread(id: "t", title: "Work", report: "r"), "and the answer goes under that report")
        XCTAssertFalse(view.threadPane.composer.isHidden)

        view.select(.channel(.of(steve)))
        view.select(inThread)
        XCTAssertEqual(view.threadPane.composer.target, .thread(id: "t", title: "Work"), "coming back some other way is just the thread")
    }

    func testLookingAtAConversationCountsAsSeeingIt() {
        let view = view()
        var seen: [ChannelSelection] = []
        view.onSeen = { seen.append($0) }
        view.show(book())
        view.select(.channel(.of(steve)))
        view.select(inThread)
        XCTAssertEqual(seen, [.activity, .channel(.of(steve)), inThread])
    }

    private func work(_ id: String, title: String, updated: TimeInterval = 0) -> AgentThread {
        AgentThread(id: id, title: title, projectTitle: "Steve", status: .completed, model: "m", updatedAt: at.addingTimeInterval(updated), projectPath: "/k/steve")
    }

    private func said(_ id: String, ask: String, reply: String, at offset: TimeInterval) -> Exchange {
        Exchange(id: id, asker: .you, askedAt: at.addingTimeInterval(offset), ask: ask, reply: reply, repliedAt: at.addingTimeInterval(offset + 1))
    }

    func testTheBoxDoesntChangeWhileYoureTyping() {
        let threads = [work("t", title: "Resume")]
        let transcripts = ["t": [said("e1", ask: "Tidy my resume", reply: "Done.", at: 0)]]
        let view = view()
        var sent: [MessagesAction] = []
        view.onAction = { sent.append($0) }
        view.show(ChannelBook.build(kittens: [steve, pepper], threads: threads, transcripts: transcripts, isReading: false, unreadable: 0, cantReachT3: false))
        view.select(inThread)
        view.threadPane.composer.textView.string = "Make the summary shorter"

        let question = AgentQuestion(id: "q", threadID: "t", threadTitle: "Resume", text: "Which font?", form: AnswerForm(parts: [AnswerForm.Part(key: "k", text: "Which font?", options: [], values: [], takesOwnWords: true)]))
        view.show(ChannelBook.build(kittens: [steve, pepper], threads: threads, transcripts: transcripts, isReading: false, unreadable: 0, cantReachT3: false, waiting: Waiting(questions: [question], owners: ["q": steve.id])))
        view.threadPane.composer.send(view.threadPane.composer.textView.string)
        XCTAssertEqual(sent, [.send("Make the summary shorter", to: .thread(id: "t", title: "Resume"), shownIn: .of(steve))])
        XCTAssertEqual(view.threadPane.composer.target, .question(question), "with nothing typed, it goes on to what needs answering")
    }

    func testANewTopicHoldsTheBoxUntilItsThreadExistsAndThenCarriesOnThere() {
        let threads = [work("t", title: "Resume")]
        let transcripts = ["t": [said("e", ask: "Tidy my resume", reply: "Done.", at: 0)]]
        let view = view()
        var sent: [MessagesAction] = []
        view.onAction = { sent.append($0) }
        view.show(ChannelBook.build(kittens: [steve, pepper], threads: threads, transcripts: transcripts, isReading: false, unreadable: 0, cantReachT3: false))
        view.select(.channel(.of(steve)))
        view.pane.composer.send("Write a cover letter")
        guard case .startTopic(_, _, let topic)? = sent.last else { return XCTFail("\(sent)") }

        var echo = ChannelMessage(exchangeID: topic, kind: .ask, speaker: .you, text: "Write a cover letter", at: at.addingTimeInterval(60), threadID: "", threadTitle: "")
        view.show(ChannelBook.build(kittens: [steve, pepper], threads: threads, transcripts: transcripts, isReading: false, unreadable: 0, cantReachT3: false, sent: [SentMessage(channel: .of(steve), message: echo, startsThread: true)]))
        XCTAssertEqual(view.threadPane.composer.target, .starting(steve))
        let said = view.threadPane.shown.compactMap { row -> String? in
            if case .message(let message) = row { return message.text }
            return nil
        }
        XCTAssertEqual(said, ["Write a cover letter"], "only the new topic, not the resume")
        view.threadPane.composer.send("Keep it to one page")
        XCTAssertEqual(sent.count, 1, "nothing goes anywhere while it starts")

        echo.threadID = "n"
        echo.threadTitle = "Write a cover letter"
        view.show(ChannelBook.build(kittens: [steve, pepper], threads: threads, transcripts: transcripts, isReading: false, unreadable: 0, cantReachT3: false, sent: [SentMessage(channel: .of(steve), message: echo, startsThread: true)]))
        XCTAssertEqual(view.selection, .thread("n", in: .channel(.of(steve))))
        view.threadPane.composer.send(view.threadPane.composer.textView.string)
        XCTAssertEqual(sent.last, .send("Keep it to one page", to: .thread(id: "n", title: "Write a cover letter"), shownIn: .of(steve)))
    }

    func testANewTopicHoldsTheBoxEvenIfAnotherThreadAnswersFirst() {
        var threads = [AgentThread(id: "t", title: "Resume", projectTitle: "Steve", status: .running, model: "m", updatedAt: at, projectPath: "/k/steve")]
        var transcripts = ["t": [Exchange(id: "e", asker: .you, askedAt: at, ask: "Tidy my resume", reply: nil, repliedAt: nil)]]
        let view = view()
        var sent: [MessagesAction] = []
        view.onAction = { sent.append($0) }
        let echo = ChannelMessage(exchangeID: "sent-1", kind: .ask, speaker: .you, text: "Write a cover letter", at: at.addingTimeInterval(60), threadID: "", threadTitle: "")
        let pending = [SentMessage(channel: .of(steve), message: echo, startsThread: true)]
        view.show(ChannelBook.build(kittens: [steve, pepper], threads: threads, transcripts: transcripts, isReading: false, unreadable: 0, cantReachT3: false, sent: pending))
        view.select(.thread("sent-1", in: .channel(.of(steve))))
        XCTAssertEqual(view.threadPane.composer.target, .starting(steve))
        view.threadPane.composer.textView.string = "Keep it to one page"

        // Meanwhile the resume thread finishes.
        threads[0].status = .completed
        threads[0].updatedAt = at.addingTimeInterval(61)
        transcripts["t"] = [Exchange(id: "e", asker: .you, askedAt: at, ask: "Tidy my resume", reply: "Done.", repliedAt: at.addingTimeInterval(61))]
        view.show(ChannelBook.build(kittens: [steve, pepper], threads: threads, transcripts: transcripts, isReading: false, unreadable: 0, cantReachT3: false, sent: pending))
        XCTAssertEqual(view.threadPane.composer.target, .starting(steve))
        view.threadPane.composer.send(view.threadPane.composer.textView.string)
        XCTAssertEqual(sent, [], "the follow-up to the new topic went to the old thread")
    }

    func testANewTopicThatDidntStartOffersToStartAgain() {
        var echo = ChannelMessage(exchangeID: "sent-1", kind: .ask, speaker: .you, text: "Write a cover letter", at: at, threadID: "", threadTitle: "")
        echo.failure = CatWords.didntStart
        let view = view()
        view.show(ChannelBook.build(kittens: [steve, pepper], threads: [], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false, sent: [SentMessage(channel: .of(steve), message: echo, startsThread: true)]))
        view.select(.thread("sent-1", in: .channel(.of(steve))))
        XCTAssertEqual(view.threadPane.composer.target, .newThread(steve))
    }

    func testClosingWhileANewTopicStartsKeepsItForNextTime() {
        let window = ChannelsWindow()
        let echo = ChannelMessage(exchangeID: "sent-1", kind: .ask, speaker: .you, text: "Write a cover letter", at: at, threadID: "", threadTitle: "")
        window.update(ChannelBook.build(kittens: [steve, pepper], threads: [], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false, sent: [SentMessage(channel: .of(steve), message: echo, startsThread: true)]))
        window.view.select(.thread("sent-1", in: .channel(.of(steve))))
        window.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        XCTAssertEqual(window.view.selection, .thread("sent-1", in: .channel(.of(steve))), "what you sent is still known, so it's still there")
    }

    private func twoPartQuestion() -> AgentQuestion {
        AgentQuestion(id: "q", threadID: "t", threadTitle: "Work", text: "Which month?", options: ["December", "January"], moreCount: 1, form: AnswerForm(parts: [
            AnswerForm.Part(key: "month", text: "Which month?", options: ["December", "January"], values: ["dec", "jan"], takesOwnWords: true),
            AnswerForm.Part(key: "currency", text: "Which currency?", options: ["USD", "EUR"], values: ["usd", "eur"], takesOwnWords: true),
        ]))
    }

    private func card(in view: NSView) throws -> CardRowView {
        try XCTUnwrap(subviews(of: view).compactMap { $0 as? CardRowView }.first)
    }

    private func press(_ title: String, in view: NSView) throws {
        let buttons = try card(in: view).buttons
        let button = try XCTUnwrap(buttons.first { $0.accessibilityLabel() == title }, "no \(title) in \(buttons.compactMap { $0.accessibilityLabel() })")
        XCTAssertTrue(button.accessibilityPerformPress())
    }

    func testAQuestionInSeveralPartsIsAnsweredOneAtATimeAndSentWhole() throws {
        let question = twoPartQuestion()
        let view = view()
        var sent: [MessagesAction] = []
        view.onAction = { sent.append($0) }
        view.show(ChannelBook.build(kittens: [steve, pepper], threads: [], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false, waiting: Waiting(questions: [question], owners: ["q": steve.id])))
        try press("January", in: view)
        XCTAssertEqual(sent, [], "nothing goes until every part has an answer")
        XCTAssertNil(try card(in: view).buttons.first { $0.accessibilityLabel() == "January" })

        try press(CatWords.answerInWords, in: view)
        XCTAssertEqual(view.selection, inThread, "answering in words opens the thread it's in")
        XCTAssertEqual(view.threadPane.composer.target, .question(question))
        view.threadPane.composer.send("Pounds, please")
        XCTAssertEqual(sent, [.answer(question, ["jan", "Pounds, please"])])
    }

    func testAThreadAnotherKittenStartedTakesYourReplyOnlyIntoIt() {
        let older = AgentThread(id: "old", title: "Old budget", projectTitle: "Steve", status: .completed, model: "m", updatedAt: at, projectPath: "/k/steve")
        let between = AgentThread(id: "asked", title: "From Pepper", projectTitle: "Steve", status: .completed, model: "m", updatedAt: at.addingTimeInterval(120), projectPath: "/k/steve")
        let pepperThread = AgentThread(id: "p", title: "Plans", projectTitle: "Pepper", status: .completed, model: "m", updatedAt: at, projectPath: "/k/pepper")
        let threads = [older, between, pepperThread]
        let view = view()
        var sent: [MessagesAction] = []
        view.onAction = { sent.append($0) }
        let asked = Exchange(id: "x", asker: .agent(threadID: "p"), askedAt: at.addingTimeInterval(100), ask: "Which font?", reply: "Silkscreen.", repliedAt: at.addingTimeInterval(101))
        let mine = Exchange(id: "e", asker: .you, askedAt: at, ask: "Old question", reply: "Old answer", repliedAt: at.addingTimeInterval(1))
        view.show(ChannelBook.build(kittens: [steve, pepper], threads: threads, transcripts: ["old": [mine], "asked": [asked], "p": []], isReading: false, unreadable: 0, cantReachT3: false))
        view.select(.thread("asked", in: .channel(.of(steve))))
        XCTAssertEqual(view.threadPane.composer.target, .thread(id: "asked", title: "From Pepper"))
        view.threadPane.composer.send("Make the summary shorter")
        XCTAssertEqual(sent, [.send("Make the summary shorter", to: .thread(id: "asked", title: "From Pepper"), shownIn: .of(steve))], "only your words, and only into that thread")
    }
}

// MARK: - Bubbles

extension ChannelsWindowTests {
    private func bubbles(in view: NSView) -> [MessageRowView] {
        subviews(of: view).compactMap { $0 as? MessageRowView }
    }

    func testYourBubblesAreOnTheRightInBlueAndAKittensOnTheLeftInItsColour() throws {
        let red = Kitten(name: "Ruby", role: "Finance", covers: "", folder: "/k/ruby", color: 0xb3261e)
        let thread = AgentThread(id: "t", title: "Work", projectTitle: "Ruby", status: .completed, model: "m", updatedAt: at, projectPath: "/k/ruby")
        let said = Exchange(id: "e", asker: .you, askedAt: at, ask: "Hi", reply: "Hello there, this is a longer answer.", repliedAt: at.addingTimeInterval(1))
        let view = view()
        view.show(ChannelBook.build(kittens: [red], threads: [thread], transcripts: ["t": [said]], isReading: false, unreadable: 0, cantReachT3: false))
        view.select(.thread("t", in: .channel(.of(red))))
        let rows = bubbles(in: view.threadPane)
        let yours = try XCTUnwrap(rows.first(where: \.isYours))
        let theirs = try XCTUnwrap(rows.first { !$0.isYours })

        XCTAssertEqual(yours.bubble.maxX, yours.bounds.width - ChannelRowView.margin, accuracy: 1)
        XCTAssertEqual(theirs.bubble.minX, ChannelRowView.textLeft, accuracy: 1)
        XCTAssertLessThan(yours.bubble.width, yours.bounds.width / 2, "a short message makes a short bubble")
        XCTAssertEqual(yours.fill, Ink.hex(ChannelSpeakerLook.yours))
        XCTAssertEqual(theirs.fill, Ink.hex(0xb3261e))
    }

    func testAKittenWithoutAColourStillGetsItsOwnEveryTimeAndTheTextReads() {
        let plain = Kitten(name: "Sam", role: "", covers: "", folder: "/k/sam")
        XCTAssertEqual(ChannelSpeakerLook.color(of: plain), ChannelSpeakerLook.color(of: plain))
        XCTAssertNotNil(ChannelSpeakerLook.color(of: plain))
        XCTAssertNotEqual(ChannelSpeakerLook.color(of: plain), ChannelSpeakerLook.yours, "blue is yours")
        XCTAssertNil(ChannelSpeakerLook.color(of: KittenBoard.shades), "the cat keeps its black jacket")

        let book = ChannelBook.build(kittens: [plain, Kitten(name: "Sunny", role: "", covers: "", folder: "/k/sunny", color: 0xffcc00)], threads: [], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false)
        XCTAssertEqual(ChannelSpeakerLook(.kitten("/k/sunny"), in: book).bubbleText, .black, "dark words on a light bubble")
        XCTAssertEqual(ChannelSpeakerLook(.you, in: book).bubbleText, .white)
    }
}

// MARK: - Messages, review round 1

extension ChannelsWindowTests {
    private static func luminance(_ color: NSColor) -> Double {
        let c = color.usingColorSpace(.sRGB)!
        let linear = { (value: CGFloat) -> Double in
            let value = Double(value)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(c.redComponent) + 0.7152 * linear(c.greenComponent) + 0.0722 * linear(c.blueComponent)
    }

    private static func contrast(_ a: NSColor, _ b: NSColor) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    private func resolved(_ color: NSColor, in name: NSAppearance.Name) -> NSColor {
        var solid = color
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance { solid = color.usingColorSpace(.sRGB)! }
        return solid
    }

    private func looks() -> [(String, ChannelSpeakerLook)] {
        let colours = ChannelSpeakerLook.palette + Demo.kittens.compactMap(ChannelSpeakerLook.color(of:))
        let kittens = colours.enumerated().map { Kitten(name: "K\($0.offset)", role: "", covers: "", folder: "/k/k\($0.offset)", color: $0.element) }
        let book = ChannelBook.build(kittens: kittens, threads: [], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false)
        return [("yours", ChannelSpeakerLook(.you, in: book))] + kittens.map { (String(format: "%06x", $0.color!), ChannelSpeakerLook(.kitten($0.id), in: book)) }
    }

    func testWordsOnEveryBubbleReadWell() {
        for (name, look) in looks() {
            let ratio = Self.contrast(look.bubbleText, look.bubbleFill)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(name) gives \(ratio)")
        }
    }

    func testWordsStillReadWhileAReplyIsStillComing() {
        for (name, look) in looks() {
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let ratio = Self.contrast(resolved(look.text(fadedTo: 0.55), in: appearance), resolved(look.fill(fadedTo: 0.55), in: appearance))
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(name) in \(appearance.rawValue) gives \(ratio)")
            }
        }
    }

    func testAStillComingBubbleIsDrawnInTheColourItsWordsWerePickedFor() throws {
        let kitten = Kitten(name: "K", role: "", covers: "", folder: "/k/k", color: 0x30b0c7)
        let thread = AgentThread(id: "t", title: "Work", projectTitle: "K", status: .running, model: "m", updatedAt: at, projectPath: kitten.folder)
        let book = ChannelBook.build(kittens: [kitten], threads: [thread], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false)
        let message = ChannelMessage(exchangeID: "e", kind: .reply, speaker: .kitten(kitten.id), text: "Moved the plans onto the new grid.", at: at, threadID: "t", threadTitle: "Work", isStillGoing: true)
        let look = ChannelSpeakerLook(message.speaker, in: book)
        let row = MessageRowView(message: message, look: look)
        let host = QuietView(frame: NSRect(x: 0, y: 0, width: 640, height: 200))
        host.appearance = NSAppearance(named: .aqua)
        host.addSubview(row)
        row.frame = NSRect(x: 0, y: 0, width: 640, height: row.fit(width: 640))
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / host.bounds.width
        let pixel = try XCTUnwrap(rep.colorAt(x: Int((row.bubble.minX + 5) * scale), y: Int(row.bubble.midY * scale))?.usingColorSpace(.sRGB))
        let ratio = Self.contrast(resolved(look.text(fadedTo: 0.55), in: .aqua), pixel)
        XCTAssertGreaterThanOrEqual(ratio, 4.5, "white words on a faded teal were \(ratio)")
    }
}

// MARK: - Messages, review round 2

extension ChannelsWindowTests {
    func testWordsYouStartedSayingStayWhereTheBoxPointedWhenAQuestionArrives() {
        let threads = [work("t", title: "Resume")]
        let transcripts = ["t": [said("e1", ask: "Tidy my resume", reply: "Done.", at: 0)]]
        let view = view()
        var sent: [MessagesAction] = []
        view.onAction = { sent.append($0) }
        view.show(ChannelBook.build(kittens: [steve, pepper], threads: threads, transcripts: transcripts, isReading: false, unreadable: 0, cantReachT3: false))
        view.select(inThread)
        view.threadPane.startSpeaking()

        let question = AgentQuestion(id: "q", threadID: "t", threadTitle: "Resume", text: "Which font?", form: AnswerForm(parts: [AnswerForm.Part(key: "k", text: "Which font?", options: [], values: [], takesOwnWords: true)]))
        view.show(ChannelBook.build(kittens: [steve, pepper], threads: threads, transcripts: transcripts, isReading: false, unreadable: 0, cantReachT3: false, waiting: Waiting(questions: [question], owners: ["q": steve.id])))
        XCTAssertEqual(view.threadPane.composer.target, .thread(id: "t", title: "Resume"), "the box doesn't move while you talk")
        view.threadPane.spoke("Make the summary shorter")
        XCTAssertEqual(sent, [.send("Make the summary shorter", to: .thread(id: "t", title: "Resume"), shownIn: .of(steve))])
        XCTAssertEqual(view.threadPane.composer.target, .question(question), "and once it's sent, it goes on to the question")
    }

    func testWhatYouSayGoesAfterWhatYouTyped() {
        let view = view()
        var sent: [MessagesAction] = []
        view.onAction = { sent.append($0) }
        view.show(book())
        view.select(inThread)
        view.threadPane.composer.textView.string = "Make the summary"
        view.threadPane.startSpeaking()
        view.threadPane.spoke("shorter, and keep it to one page")
        XCTAssertEqual(sent, [.send("Make the summary shorter, and keep it to one page", to: .thread(id: "t", title: "Work"), shownIn: .of(steve))])
        XCTAssertEqual(view.threadPane.composer.textView.string, "")
    }

    func testWordsForAQuestionAnsweredMeanwhileWaitInTheBox() {
        let question = AgentQuestion(id: "q", threadID: "t", threadTitle: "Work", text: "Which font?", form: AnswerForm(parts: [AnswerForm.Part(key: "k", text: "Which font?", options: [], values: [], takesOwnWords: true)]))
        let thread = AgentThread(id: "t", title: "Work", projectTitle: "Steve", status: .completed, model: "m", updatedAt: at, projectPath: "/k/steve")
        let view = view()
        var sent: [MessagesAction] = []
        view.onAction = { sent.append($0) }
        view.show(ChannelBook.build(kittens: [steve, pepper], threads: [thread], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false, waiting: Waiting(questions: [question], owners: ["q": steve.id])))
        view.select(inThread)
        XCTAssertEqual(view.threadPane.composer.target, .question(question))
        view.threadPane.startSpeaking()
        view.show(ChannelBook.build(kittens: [steve, pepper], threads: [thread], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false))
        view.threadPane.spoke("Silkscreen")
        XCTAssertEqual(sent, [], "it was answered in T3 meanwhile, so the words don't go to the thread instead")
        XCTAssertEqual(view.threadPane.composer.textView.string, "Silkscreen")
    }

    func testReplyingToAReportWhoseThreadT3NoLongerListsStillHasABox() throws {
        let report = InboxEntry(id: "r", kind: .decision, text: "Merged. Say ship it.", threadID: "gone", threadTitle: "Work", at: at)
        let built = ChannelBook.build(kittens: [steve, pepper], threads: [], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false, waiting: Waiting(reports: [report]))
        let view = view()
        view.show(built)
        let card = try XCTUnwrap(subviews(of: view).compactMap { $0 as? CardRowView }.first)
        XCTAssertTrue(try XCTUnwrap(card.buttons.first { $0.accessibilityLabel() == "Reply" }).accessibilityPerformPress())
        XCTAssertEqual(view.threadPane.composer.target, .thread(id: "gone", title: "Work", report: "r"), "an archived thread still takes a reply to its report")
        XCTAssertFalse(view.threadPane.composer.isHidden)
    }

    func testTypeAnAnswerWorksInAThreadAnotherKittenStarted() throws {
        let between = AgentThread(id: "asked", title: "From Pepper", projectTitle: "Steve", status: .completed, model: "m", updatedAt: at, projectPath: "/k/steve")
        let pepperThread = AgentThread(id: "p", title: "Plans", projectTitle: "Pepper", status: .completed, model: "m", updatedAt: at, projectPath: "/k/pepper")
        let asked = Exchange(id: "x", asker: .agent(threadID: "p"), askedAt: at, ask: "Can you draft the budget email?", reply: "Before I send it, which tone?", repliedAt: at.addingTimeInterval(1))
        let question = AgentQuestion(id: "q", threadID: "asked", threadTitle: "From Pepper", text: "Which tone?", options: ["Formal"], form: AnswerForm(parts: [
            AnswerForm.Part(key: "tone", text: "Which tone?", options: ["Formal"], values: ["formal"], takesOwnWords: true),
        ]))
        let view = view()
        var sent: [MessagesAction] = []
        view.onAction = { sent.append($0) }
        let built = ChannelBook.build(kittens: [steve, pepper], threads: [between, pepperThread], transcripts: ["asked": [asked], "p": []], isReading: false, unreadable: 0, cantReachT3: false, waiting: Waiting(questions: [question], owners: ["q": steve.id], listed: ["q": "asked"]))
        view.show(built)
        try press(CatWords.answerInWords, in: view)
        XCTAssertEqual(view.selection, .thread("asked", in: .channel(.of(steve))))
        XCTAssertEqual(view.threadPane.composer.target, .question(question))
        view.threadPane.composer.send("Warm but brief")
        XCTAssertEqual(sent, [.answer(question, ["Warm but brief"])])

        view.show(ChannelBook.build(kittens: [steve, pepper], threads: [between, pepperThread], transcripts: ["asked": [asked], "p": []], isReading: false, unreadable: 0, cantReachT3: false))
        XCTAssertEqual(view.threadPane.composer.target, .thread(id: "asked", title: "From Pepper"), "once it's answered, the box replies in that thread, as Slack's does")
    }
}

extension ChannelsWindowTests {
    func testAskingAboutAReportDoesntAnswerAQuestionWaitingInItsThread() throws {
        let report = InboxEntry(id: "shipped", kind: .shipped, text: "The staging backup is ready.", threadID: "t", threadTitle: "Work", at: at)
        let question = AgentQuestion(id: "q", threadID: "t", threadTitle: "Work", text: "Which account?", form: AnswerForm(parts: [AnswerForm.Part(key: "k", text: "Which account?", options: [], values: [], takesOwnWords: true)]))
        let thread = AgentThread(id: "t", title: "Work", projectTitle: "Steve", status: .waitingForAnswer, model: "m", updatedAt: at, projectPath: "/k/steve")
        let view = view()
        var sent: [MessagesAction] = []
        view.onAction = { sent.append($0) }
        view.show(ChannelBook.build(kittens: [steve, pepper], threads: [thread], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false, waiting: Waiting(questions: [question], owners: ["q": steve.id], reports: [report])))
        let card = try XCTUnwrap(subviews(of: view).compactMap { $0 as? CardRowView }.first { $0.accessibilityLabel()?.contains(report.text) == true })
        XCTAssertTrue(try XCTUnwrap(card.buttons.first { $0.accessibilityLabel() == "Ask" }).accessibilityPerformPress())
        view.threadPane.composer.send("Where is the staging backup stored?")
        XCTAssertEqual(sent, [.send("Where is the staging backup stored?", to: .thread(id: "t", title: "Work", report: "shipped"), shownIn: .of(steve))])

        try press(CatWords.answerInWords, in: view)
        XCTAssertEqual(view.threadPane.composer.target, .question(question), "Type an answer is how to answer it")
    }
}

// MARK: - Messages, review round 3

extension ChannelsWindowTests {
    /// Steve's thread that Pepper's thread started, with a report in Steve's inbox.
    private func reportInAThreadBetweenKittens() -> (ChannelBook, InboxEntry) {
        let asked = AgentThread(id: "asked", title: "From Pepper", projectTitle: "Steve", status: .completed, model: "m", updatedAt: at, projectPath: "/k/steve")
        let plans = AgentThread(id: "p", title: "Plans", projectTitle: "Pepper", status: .completed, model: "m", updatedAt: at, projectPath: "/k/pepper")
        let exchange = Exchange(id: "x", asker: .agent(threadID: "p"), askedAt: at, ask: "Can you draft the budget email?", reply: "Drafted. Ship it?", repliedAt: at.addingTimeInterval(1))
        let report = InboxEntry(id: "r", kind: .decision, text: "Drafted the budget email. Ship it?", threadID: "asked", threadTitle: "From Pepper", at: at)
        let book = ChannelBook.build(kittens: [steve, pepper], threads: [asked, plans], transcripts: ["asked": [exchange], "p": []], isReading: false, unreadable: 0, cantReachT3: false, waiting: Waiting(reports: [report]))
        return (book, report)
    }

    func testSayingAReplyToAReportGoesWhereTypingItWouldEvenInAThreadBetweenKittens() throws {
        let (book, report) = reportInAThreadBetweenKittens()
        let view = view()
        var sent: [MessagesAction] = []
        view.onAction = { sent.append($0) }
        view.show(book)
        let card = try XCTUnwrap(subviews(of: view).compactMap { $0 as? CardRowView }.first { $0.accessibilityLabel()?.contains(report.text) == true })
        XCTAssertTrue(try XCTUnwrap(card.buttons.first { $0.accessibilityLabel() == "Reply" }).accessibilityPerformPress())
        XCTAssertEqual(view.threadPane.composer.target, .thread(id: "asked", title: "From Pepper", report: "r"))
        view.threadPane.startSpeaking()
        view.threadPane.spoke("Ship it")
        XCTAssertEqual(sent, [.send("Ship it", to: .thread(id: "asked", title: "From Pepper", report: "r"), shownIn: .of(steve))], "saying it counts as pressing Return")
        XCTAssertEqual(view.threadPane.composer.textView.string, "")
    }
}

// MARK: - Themes

extension ChannelsWindowTests {
    private static let opal = ColorTheme(name: "Opal Horizon", isDark: true, paper: 0x0c0a10, text: 0xe7e4ec, soft: 0x837d90, accent: 0x7458e8, sidebar: 0x0a080d)
    private static let paper = ColorTheme(name: "Paper", isDark: false, paper: 0xffffff, text: 0x1d1d1f, accent: 0x0066cc)

    private func themed(_ theme: ColorTheme?, _ body: () throws -> Void) rethrows {
        MessagesInk.theme = theme
        defer { MessagesInk.theme = nil }
        try body()
    }

    func testAThemeTintsYourMessagesAndTheWindowAndLeavesEveryKittenItsOwnColour() throws {
        let colours = ChannelSpeakerLook.palette + Demo.kittens.compactMap(ChannelSpeakerLook.color(of:))
        let kittens = colours.enumerated().map { Kitten(name: "K\($0.offset)", role: "", covers: "", folder: "/k/k\($0.offset)", color: $0.element) }
        let book = ChannelBook.build(kittens: kittens, threads: [], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false)
        for theme in [Self.opal, Self.paper] {
            try themed(theme) {
                let yours = ChannelSpeakerLook(.you, in: book)
                XCTAssertEqual(yours.bubble, theme.yours)
                XCTAssertGreaterThanOrEqual(ColorTheme.contrast(try XCTUnwrap(yours.words), theme.yours), 4.5, theme.name)
                XCTAssertEqual(MessagesInk.paper, Ink.hex(theme.paper))
                XCTAssertEqual(ChannelSpeakerLook.grey, Ink.hex(theme.bubble), "the cat's own messages")
                for kitten in kittens {
                    let look = ChannelSpeakerLook(.kitten(kitten.id), in: book)
                    XCTAssertEqual(look.bubble, kitten.color, "\(kitten.name) keeps its colour in \(theme.name)")
                    // Yours is a quiet tint and every kitten's is a strong colour, so they never look alike.
                    XCTAssertGreaterThan(Self.distance(look.bubble!, theme.yours), 100, "\(kitten.name) against yours in \(theme.name)")
                }
            }
        }
    }

    func testTheWholeWindowTakesATheme() throws {
        let window = ChannelsWindow()
        window.update(book())
        window.view.select(.channel(.of(steve)))
        window.apply(Self.opal)
        defer { window.apply(nil) }
        XCTAssertEqual(window.panel.appearance?.name, .darkAqua, "its buttons, scrollers and cats go dark too")
        let row = try XCTUnwrap(window.view.pane.shownMessageRows.first { $0.isYours })
        XCTAssertEqual(row.fill, Ink.hex(Self.opal.yours), "rows are made again in the theme's colours")

        window.apply(nil)
        XCTAssertNil(window.panel.appearance, "and back to following the system")
        XCTAssertEqual(try XCTUnwrap(window.view.pane.shownMessageRows.first { $0.isYours }).fill, Ink.hex(ChannelSpeakerLook.yours))
    }

    func testTheThemeMenuOffersShadesAndEachAppsThemesAndSaysToDropTheRest() throws {
        let found = [
            ColorTheme.Found(theme: Self.paper, app: "T3 Code", file: URL(fileURLWithPath: "/t3/paper.json")),
            ColorTheme.Found(theme: Self.opal, app: "T3 Code", file: URL(fileURLWithPath: "/t3/opal.json")),
            ColorTheme.Found(theme: Self.opal, app: "iTerm2", file: URL(fileURLWithPath: "/iterm/opal.json")),
        ]
        let menu = ThemeMenu()
        let items = menu.items(found, current: Self.opal)
        let shown = items.map { item in
            item.isSeparatorItem ? "---" : "\(item.state == .on ? "* " : "")\(item.title)\(item.submenu == nil ? "" : " >")\(item.isEnabled ? "" : " (off)")"
        }
        XCTAssertEqual(shown, ["Shades", "---", "* T3 Code >", "* iTerm2 >", "---", CatWords.dropATheme + " (off)"])
        let t3 = try XCTUnwrap(items[2].submenu).items
        XCTAssertEqual(t3.map(\.title), ["Opal Horizon", "Paper"], "by name")
        XCTAssertEqual(t3.map(\.state), [.on, .off])
        XCTAssertEqual(t3.map { $0.representedObject as? URL }, [URL(fileURLWithPath: "/t3/opal.json"), URL(fileURLWithPath: "/t3/paper.json")])

        XCTAssertEqual(menu.items([], current: nil).compactMap { $0.isSeparatorItem ? nil : $0.title }, [CatWords.plainTheme, CatWords.noThemesFound, CatWords.dropATheme])
        XCTAssertEqual(menu.items([], current: nil)[0].state, .on)
        let dropped = ColorTheme(name: "Dropped", isDark: false, paper: 0xfafafa, text: 0x111111, accent: 0xcc0000)
        XCTAssertEqual(menu.items(found, current: dropped)[1].title, "Dropped", "a theme you dropped shows as the one in use")
    }

    private static func distance(_ a: UInt32, _ b: UInt32) -> Double {
        let channels = { (color: UInt32) in [16, 8, 0].map { Double((color >> UInt32($0)) & 0xff) } }
        return zip(channels(a), channels(b)).map { ($0 - $1) * ($0 - $1) }.reduce(0, +).squareRoot()
    }
}
