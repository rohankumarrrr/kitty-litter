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
        let thread = AgentThread(id: "t", title: "Work", projectTitle: "Steve", status: .completed, model: "m", updatedAt: at)
        let said = (0..<exchanges).map { index in
            Exchange(id: "e\(index)", asker: .you, askedAt: at.addingTimeInterval(TimeInterval(index)), ask: "Ask", reply: text, repliedAt: at.addingTimeInterval(TimeInterval(index)))
        }
        return ChannelBook.build(kittens: [steve, pepper], threads: [thread], transcripts: ["t": said], isReading: false, unreadable: 0, cantReachT3: false)
    }

    private func subviews(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(subviews)
    }

    func testThePanelCanNeverTakeTheKeyboardOrFloatOverYourWork() {
        let panel = ChannelsPanel()
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertEqual(panel.level, .normal)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertFalse(panel.isReleasedWhenClosed)
        XCTAssertTrue(panel.collectionBehavior.contains(.ignoresCycle))
    }

    func testEveryViewTakesClicksAndRefusesTheKeyboard() {
        let view = view()
        view.show(book())
        view.select(.channel(.direct(steve)))
        let rows = subviews(of: view).filter { $0 is QuietView || $0 is QuietButton || $0 is QuietScrollView }
        XCTAssertGreaterThan(rows.count, 10)
        for row in rows {
            XCTAssertTrue(row.acceptsFirstMouse(for: nil), "\(row)")
            XCTAssertFalse(row.acceptsFirstResponder, "\(row)")
        }
    }

    func testItStartsOnIssues() {
        let view = view()
        view.show(book())
        XCTAssertEqual(view.selection, .issues)
        XCTAssertEqual(view.sidebar.row(for: .issues)?.isSelected, true)
    }

    func testPressingARowSelectsItsChannelAndShowsIt() throws {
        let view = view()
        let book = book()
        view.show(book)
        let row = try XCTUnwrap(view.sidebar.row(for: .channel(.direct(steve))))
        row.press()
        XCTAssertEqual(view.selection, .channel(.direct(steve)))
        XCTAssertTrue(row.isSelected)
        XCTAssertEqual(view.sidebar.row(for: .issues)?.isSelected, false)
        XCTAssertEqual(view.pane.shown, ChannelRows.rows(.channel(.direct(steve)), in: book))
        XCTAssertTrue(row.accessibilityPerformPress())
    }

    func testAnEmptyBetweenSectionIsntDrawnAndAPairGetsARowOnceTheyTalk() throws {
        XCTAssertFalse(ChannelSidebarItem.groups(in: book()).contains { $0.heading == CatWords.betweenKittens })

        let pepperThread = AgentThread(id: "p", title: "Work", projectTitle: "Pepper", status: .completed, model: "m", updatedAt: at)
        let steveThread = AgentThread(id: "s", title: "Work", projectTitle: "Steve", status: .completed, model: "m", updatedAt: at)
        let talked = ChannelBook.build(
            kittens: [steve, pepper],
            threads: [pepperThread, steveThread],
            transcripts: ["s": [Exchange(id: "e", asker: .agent(threadID: pepperThread.id), askedAt: at, ask: "Ask")]],
            isReading: false,
            unreadable: 0,
            cantReachT3: false
        )
        let view = view()
        view.show(talked)
        XCTAssertEqual(ChannelSidebarItem.groups(in: talked).last?.heading, CatWords.betweenKittens)
        let pair = try XCTUnwrap(ChannelID(.kitten(steve.id), .kitten(pepper.id)))
        XCTAssertNotNil(view.sidebar.row(for: .channel(pair)))
    }

    func testOnlyAKittenThatsWorkingOrNeedsYouMoves() {
        func moves(_ state: KittenStatus.State) -> Bool {
            let status = KittenStatus(kitten: steve, state: state)
            return ChannelSidebarRow(item: ChannelSidebarItem(selection: .channel(.direct(steve)), title: "Steve", cats: [.kitten(status)])).isLive
        }
        XCTAssertTrue(moves(.working(sessions: 1)))
        XCTAssertTrue(moves(.needsYou))
        XCTAssertFalse(moves(.idle))
        XCTAssertFalse(moves(.notSetUp))
    }

    func testALongMessageIsCutAndShowMoreSurvivesARefresh() throws {
        let view = view()
        view.show(book(text: long))
        view.select(.channel(.direct(steve)))
        let row = try XCTUnwrap(view.pane.longMessageRow)
        let cutHeight = row.frame.height

        row.pressShowMore()
        XCTAssertFalse(row.isCut)
        XCTAssertGreaterThan(row.frame.height, cutHeight)

        view.show(book(exchanges: 2, text: long))
        let first = view.pane.shownMessageRows.first { $0.isExpanded }
        XCTAssertNotNil(first, "still open after new messages came in")
        XCTAssertEqual(view.pane.shownMessageRows.filter(\.isCut).count, 1, "and the new one starts cut")
    }

    func testAShortMessageIsntCut() {
        let view = view()
        view.show(book())
        view.select(.channel(.direct(steve)))
        XCTAssertNil(view.pane.longMessageRow)
    }

    func testSelectingAChannelGoesToTheBottomAndIssuesToTheTop() {
        let view = view()
        view.show(book(exchanges: 40))
        view.select(.channel(.direct(steve)))
        XCTAssertGreaterThan(view.pane.scrollOffset, 0)
        XCTAssertEqual(view.pane.distanceFromBottom, 0, accuracy: 1)

        view.select(.issues)
        XCTAssertEqual(view.pane.scrollOffset, 0)
    }

    func testARefreshKeepsYouAtTheBottomOrLeavesYouAlone() {
        let view = view()
        view.show(book(exchanges: 40))
        view.select(.channel(.direct(steve)))

        view.show(book(exchanges: 41))
        XCTAssertEqual(view.pane.distanceFromBottom, 0, accuracy: 1, "at the bottom, you follow along")

        view.pane.scrollOffset -= 30
        view.show(book(exchanges: 42))
        XCTAssertEqual(view.pane.distanceFromBottom, 0, accuracy: 1, "close enough counts")

        view.pane.scrollOffset = 100
        view.show(book(exchanges: 43))
        XCTAssertEqual(view.pane.scrollOffset, 100, "reading further up, you're left alone")
    }

    func testRowsThatHaventChangedArentRebuilt() {
        let view = view()
        view.show(book(exchanges: 2))
        view.select(.channel(.direct(steve)))
        let first = view.pane.shownMessageRows.first

        view.show(book(exchanges: 2))
        XCTAssertTrue(view.pane.shownMessageRows.first === first)
        view.show(book(exchanges: 3))
        XCTAssertTrue(view.pane.shownMessageRows.first === first, "new rows don't disturb the ones above")
    }

    func testClosingForgetsEveryWordButKeepsTheSelection() {
        let window = ChannelsWindow()
        var closed = 0
        window.onClose = { closed += 1 }
        window.update(book())
        window.view.select(.channel(.direct(steve)))
        XCTAssertFalse(window.view.pane.shownMessageRows.isEmpty)

        window.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        XCTAssertEqual(closed, 1)
        XCTAssertTrue(window.view.pane.shownMessageRows.isEmpty)
        XCTAssertEqual(window.view.pane.shown, [])
        XCTAssertEqual(window.view.selection, .channel(.direct(steve)))
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
        for expected in ["threads read: 7", "unreadable: 1", "DMs with messages: 1", "between channels: 1", "messages: 4", "asked by you: 1", "asked by a kitten: 0", "asked by someone else: 1", "replies with no ask: 0", "issues: 1", "milliseconds: 9"] {
            XCTAssertTrue(line.contains(expected), expected)
        }
    }
}
