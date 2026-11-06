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

    private func subviews(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(subviews)
    }

    func testThePanelTakesTheKeyboardOnlyWhenNeededAndNeverFloatsOverYourWork() {
        let panel = ChannelsPanel()
        XCTAssertTrue(panel.canBecomeKey, "for the box at the bottom")
        XCTAssertTrue(panel.becomesKeyOnlyIfNeeded, "a click anywhere else leaves the keyboard where it was")
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

    func testEveryViewTakesClicksAndRefusesTheKeyboard() {
        let view = view()
        view.show(book())
        view.select(.channel(.direct(steve)))
        let rows = subviews(of: view).filter { $0 is QuietView || $0 is QuietButton || $0 is QuietScrollView }
        XCTAssertGreaterThan(rows.count, 10)
        for row in rows {
            XCTAssertTrue(row.acceptsFirstMouse(for: nil), "\(row)")
            XCTAssertFalse(row.acceptsFirstResponder, "\(row)")
            XCTAssertFalse(row.needsPanelToBecomeKey, "\(row)")
        }
        let box = Set(subviews(of: view.pane.composer).map(ObjectIdentifier.init))
        let typing = subviews(of: view).filter { !box.contains(ObjectIdentifier($0)) && ($0.acceptsFirstResponder || $0.needsPanelToBecomeKey) }
        XCTAssertTrue(typing.isEmpty, "only the box takes the keyboard, not \(typing.map { type(of: $0) })")
        XCTAssertTrue(view.pane.composer.textView.acceptsFirstResponder)
        XCTAssertTrue(view.pane.composer.textView.needsPanelToBecomeKey)
    }

    func testItStartsOnNeedsYou() {
        let view = view()
        view.show(book())
        XCTAssertEqual(view.selection, .needsYou)
        XCTAssertEqual(view.sidebar.row(for: .needsYou)?.isSelected, true)
    }

    func testPressingARowSelectsItsChannelAndShowsIt() throws {
        let view = view()
        let book = book()
        view.show(book)
        let row = try XCTUnwrap(view.sidebar.row(for: .channel(.direct(steve))))
        row.press()
        XCTAssertEqual(view.selection, .channel(.direct(steve)))
        XCTAssertTrue(row.isSelected)
        XCTAssertEqual(view.sidebar.row(for: .needsYou)?.isSelected, false)
        XCTAssertEqual(view.pane.shown, ChannelRows.rows(.channel(.direct(steve)), in: book))
        XCTAssertTrue(row.accessibilityPerformPress())
    }

    func testAnEmptyBetweenSectionIsntDrawnAndAPairGetsARowOnceTheyTalk() throws {
        XCTAssertFalse(ChannelSidebarItem.groups(in: book()).contains { $0.heading == CatWords.betweenKittens })

        let pepperThread = AgentThread(id: "p", title: "Work", projectTitle: "Pepper", status: .completed, model: "m", updatedAt: at, projectPath: "/k/pepper")
        let steveThread = AgentThread(id: "s", title: "Work", projectTitle: "Steve", status: .completed, model: "m", updatedAt: at, projectPath: "/k/steve")
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

    func testSelectingAChannelGoesToTheBottomAndNeedsYouToTheTop() {
        let view = view()
        view.show(book(exchanges: 40))
        view.select(.channel(.direct(steve)))
        XCTAssertGreaterThan(view.pane.scrollOffset, 0)
        XCTAssertEqual(view.pane.distanceFromBottom, 0, accuracy: 1)

        view.select(.needsYou)
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

    // MARK: - The box

    func testTheBoxSendsYourWordsWhereItSays() {
        let view = view()
        var sent: [MessagesAction] = []
        view.pane.onAction = { sent.append($0) }
        view.show(book())
        view.select(.channel(.direct(steve)))
        XCTAssertEqual(view.pane.composer.target, .thread(id: "t", title: "Work"))

        view.pane.composer.send("  Make it shorter  ")
        XCTAssertEqual(sent, [.send("Make it shorter", to: .thread(id: "t", title: "Work"), shownIn: .direct(steve))])
        XCTAssertEqual(view.pane.composer.textView.string, "")

        view.pane.composer.send("   ")
        XCTAssertEqual(sent.count, 1, "nothing to send")
    }

    func testANewTopicLastsUntilItsSentOrYouLookElsewhere() throws {
        let view = view()
        var sent: [MessagesAction] = []
        view.pane.onAction = { sent.append($0) }
        view.show(book())
        view.select(.channel(.direct(steve)))
        view.pane.pick(.newThread(steve))
        view.pane.composer.send("Something else")
        XCTAssertEqual(sent.last, .send("Something else", to: .newThread(steve), shownIn: .direct(steve)))
        XCTAssertEqual(view.pane.composer.target, .thread(id: "t", title: "Work"), "back to carrying on")

        view.pane.pick(.newThread(steve))
        view.select(.channel(.direct(pepper)))
        view.select(.channel(.direct(steve)))
        XCTAssertEqual(view.pane.composer.target, .thread(id: "t", title: "Work"))
    }

    func testNeedsYouHasNoBoxUntilYouReplyToSomething() throws {
        let report = InboxEntry(id: "r", kind: .decision, text: "Merged. Say ship it.", threadID: "t", threadTitle: "Work", at: at)
        let thread = AgentThread(id: "t", title: "Work", projectTitle: "Steve", status: .completed, model: "m", updatedAt: at, projectPath: "/k/steve")
        let built = ChannelBook.build(kittens: [steve, pepper], threads: [thread], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false, waiting: Waiting(reports: [report]))
        let view = view()
        view.show(built)
        XCTAssertTrue(view.pane.composer.isHidden)
        XCTAssertNil(view.pane.composer.target)

        let card = try XCTUnwrap(subviews(of: view).compactMap { $0 as? CardRowView }.first)
        XCTAssertTrue(try XCTUnwrap(card.buttons.first).accessibilityPerformPress())
        XCTAssertEqual(view.pane.composer.target, .thread(id: "t", title: "Work"))
        XCTAssertFalse(view.pane.composer.isHidden)
    }

    func testLookingAtAConversationCountsAsSeeingIt() {
        let view = view()
        var seen: [ChannelSelection] = []
        view.onSeen = { seen.append($0) }
        view.show(book())
        view.select(.channel(.direct(steve)))
        XCTAssertEqual(seen, [.needsYou, .channel(.direct(steve))])
    }

    private func work(_ id: String, title: String, updated: TimeInterval = 0) -> AgentThread {
        AgentThread(id: id, title: title, projectTitle: "Steve", status: .completed, model: "m", updatedAt: at.addingTimeInterval(updated), projectPath: "/k/steve")
    }

    private func said(_ id: String, ask: String, reply: String, at offset: TimeInterval) -> Exchange {
        Exchange(id: id, asker: .you, askedAt: at.addingTimeInterval(offset), ask: ask, reply: reply, repliedAt: at.addingTimeInterval(offset + 1))
    }

    func testTheBoxDoesntMoveToAnotherThreadWhileYoureTyping() {
        var threads = [work("t", title: "Resume", updated: 61), work("c", title: "Cover letter", updated: 1)]
        var transcripts = ["t": [said("e1", ask: "Tidy my resume", reply: "Done.", at: 60)], "c": [said("e2", ask: "Draft a cover letter", reply: "On it.", at: 0)]]
        let view = view()
        var sent: [MessagesAction] = []
        view.pane.onAction = { sent.append($0) }
        view.show(ChannelBook.build(kittens: [steve, pepper], threads: threads, transcripts: transcripts, isReading: false, unreadable: 0, cantReachT3: false))
        view.select(.channel(.direct(steve)))
        XCTAssertEqual(view.pane.composer.target, .thread(id: "t", title: "Resume"))
        view.pane.composer.textView.string = "Make the summary shorter"

        threads[1] = work("c", title: "Cover letter", updated: 121)
        transcripts["c"] = [said("e2", ask: "Draft a cover letter", reply: "Here's the draft.", at: 120)]
        let question = AgentQuestion(id: "q", threadID: "c", threadTitle: "Cover letter", text: "Which company?", form: AnswerForm(parts: [AnswerForm.Part(key: "k", text: "Which company?", options: [], values: [], takesOwnWords: true)]))
        view.show(ChannelBook.build(kittens: [steve, pepper], threads: threads, transcripts: transcripts, isReading: false, unreadable: 0, cantReachT3: false, waiting: Waiting(questions: [question], owners: ["q": steve.id])))
        view.pane.composer.send(view.pane.composer.textView.string)
        XCTAssertEqual(sent, [.send("Make the summary shorter", to: .thread(id: "t", title: "Resume"), shownIn: .direct(steve))])
        XCTAssertEqual(view.pane.composer.target, .question(question), "with nothing typed, it goes back to what needs answering")
    }

    func testANewTopicHoldsTheBoxUntilItsThreadExistsAndThenCarriesOnThere() {
        let threads = [work("t", title: "Resume")]
        let transcripts = ["t": [said("e", ask: "Tidy my resume", reply: "Done.", at: 0)]]
        let view = view()
        var sent: [MessagesAction] = []
        view.pane.onAction = { sent.append($0) }
        view.show(ChannelBook.build(kittens: [steve, pepper], threads: threads, transcripts: transcripts, isReading: false, unreadable: 0, cantReachT3: false))
        view.select(.channel(.direct(steve)))

        var echo = ChannelMessage(exchangeID: "sent-1", kind: .ask, speaker: .you, text: "Write a cover letter", at: at.addingTimeInterval(60), threadID: "", threadTitle: "")
        view.show(ChannelBook.build(kittens: [steve, pepper], threads: threads, transcripts: transcripts, isReading: false, unreadable: 0, cantReachT3: false, sent: [SentMessage(channel: .direct(steve), message: echo)]))
        XCTAssertEqual(view.pane.composer.target, .starting(steve))
        view.pane.composer.send("Keep it to one page")
        XCTAssertEqual(sent, [], "nothing goes to the old thread while the new one starts")

        echo.threadID = "n"
        echo.threadTitle = "Write a cover letter"
        view.show(ChannelBook.build(kittens: [steve, pepper], threads: threads, transcripts: transcripts, isReading: false, unreadable: 0, cantReachT3: false, sent: [SentMessage(channel: .direct(steve), message: echo)]))
        view.pane.composer.send("Keep it to one page")
        XCTAssertEqual(sent, [.send("Keep it to one page", to: .thread(id: "n", title: "Write a cover letter"), shownIn: .direct(steve))])
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
        view.pane.onAction = { sent.append($0) }
        view.show(ChannelBook.build(kittens: [steve, pepper], threads: [], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false, waiting: Waiting(questions: [question], owners: ["q": steve.id])))
        try press("January", in: view)
        XCTAssertEqual(sent, [], "nothing goes until every part has an answer")
        XCTAssertNil(try card(in: view).buttons.first { $0.accessibilityLabel() == "January" })

        try press(CatWords.answerInWords, in: view)
        XCTAssertEqual(view.pane.composer.target, .question(question))
        view.pane.composer.send("Pounds, please")
        XCTAssertEqual(sent, [.answer(question, ["jan", "Pounds, please"])])
    }

    func testADMCarriesOnInANewerThreadEvenBeforeItsWordsAreRead() {
        let older = AgentThread(id: "old", title: "Old budget", projectTitle: "Steve", status: .completed, model: "m", updatedAt: at, projectPath: "/k/steve")
        let newer = AgentThread(id: "new", title: "New budget", projectTitle: "Steve", status: .running, model: "m", updatedAt: at.addingTimeInterval(60), projectPath: "/k/steve")
        let built = ChannelBook.build(kittens: [steve, pepper], threads: [older, newer], transcripts: ["old": [said("e", ask: "Old question", reply: "Old answer", at: 0)], "new": []], isReading: false, unreadable: 0, cantReachT3: false)
        XCTAssertEqual(MessageTarget.standard(for: .channel(.direct(steve)), in: built), .thread(id: "new", title: "New budget"))

        let between = AgentThread(id: "asked", title: "From Pepper", projectTitle: "Steve", status: .completed, model: "m", updatedAt: at.addingTimeInterval(120), projectPath: "/k/steve")
        let pepperThread = AgentThread(id: "p", title: "Plans", projectTitle: "Pepper", status: .completed, model: "m", updatedAt: at, projectPath: "/k/pepper")
        let asked = Exchange(id: "x", asker: .agent(threadID: "p"), askedAt: at.addingTimeInterval(100), ask: "Which font?", reply: "Silkscreen.", repliedAt: at.addingTimeInterval(101))
        let withBetween = ChannelBook.build(kittens: [steve, pepper], threads: [older, between, pepperThread], transcripts: ["old": [said("e", ask: "Old question", reply: "Old answer", at: 0)], "asked": [asked], "p": []], isReading: false, unreadable: 0, cantReachT3: false)
        XCTAssertEqual(MessageTarget.standard(for: .channel(.direct(steve)), in: withBetween), .thread(id: "old", title: "Old budget"), "a thread only another kitten talks in isn't yours to carry on")
    }
}


// MARK: - Messages, review round 2

extension ChannelsWindowTests {
    func testADraftNeverStaysOnAThreadOnlyAnotherKittenTalksIn() {
        let older = AgentThread(id: "old", title: "Old budget", projectTitle: "Steve", status: .completed, model: "m", updatedAt: at, projectPath: "/k/steve")
        let between = AgentThread(id: "asked", title: "From Pepper", projectTitle: "Steve", status: .completed, model: "m", updatedAt: at.addingTimeInterval(120), projectPath: "/k/steve")
        let pepperThread = AgentThread(id: "p", title: "Plans", projectTitle: "Pepper", status: .completed, model: "m", updatedAt: at, projectPath: "/k/pepper")
        let threads = [older, between, pepperThread]
        let view = view()
        var sent: [MessagesAction] = []
        view.pane.onAction = { sent.append($0) }
        view.show(ChannelBook.build(kittens: [steve, pepper], threads: threads, transcripts: [:], isReading: true, unreadable: 0, cantReachT3: false))
        view.select(.channel(.direct(steve)))
        view.pane.composer.textView.string = "Make the summary shorter"

        let asked = Exchange(id: "x", asker: .agent(threadID: "p"), askedAt: at.addingTimeInterval(100), ask: "Which font?", reply: "Silkscreen.", repliedAt: at.addingTimeInterval(101))
        let mine = Exchange(id: "e", asker: .you, askedAt: at, ask: "Old question", reply: "Old answer", repliedAt: at.addingTimeInterval(1))
        let read = ChannelBook.build(kittens: [steve, pepper], threads: threads, transcripts: ["old": [mine], "asked": [asked], "p": []], isReading: false, unreadable: 0, cantReachT3: false)
        view.show(read)
        view.pane.composer.send(view.pane.composer.textView.string)
        XCTAssertEqual(sent, [.send("Make the summary shorter", to: .thread(id: "old", title: "Old budget"), shownIn: .direct(steve))], "your DM went into the thread where Pepper was asking Steve")
    }

    func testANewTopicHoldsTheBoxEvenIfAnotherThreadAnswersFirst() {
        var threads = [AgentThread(id: "t", title: "Resume", projectTitle: "Steve", status: .running, model: "m", updatedAt: at, projectPath: "/k/steve")]
        var transcripts = ["t": [Exchange(id: "e", asker: .you, askedAt: at, ask: "Tidy my resume", reply: nil, repliedAt: nil)]]
        let view = view()
        var sent: [MessagesAction] = []
        view.pane.onAction = { sent.append($0) }
        view.show(ChannelBook.build(kittens: [steve, pepper], threads: threads, transcripts: transcripts, isReading: false, unreadable: 0, cantReachT3: false))
        view.select(.channel(.direct(steve)))

        // New topic sent at +60, and T3 hasn't said what its thread is yet.
        let echo = ChannelMessage(exchangeID: "sent-1", kind: .ask, speaker: .you, text: "Write a cover letter", at: at.addingTimeInterval(60), threadID: "", threadTitle: "")
        let pending = [SentMessage(channel: .direct(steve), message: echo)]
        view.show(ChannelBook.build(kittens: [steve, pepper], threads: threads, transcripts: transcripts, isReading: false, unreadable: 0, cantReachT3: false, sent: pending))
        XCTAssertEqual(view.pane.composer.target, .starting(steve))

        // Meanwhile the resume thread finishes.
        threads[0].status = .completed
        threads[0].updatedAt = at.addingTimeInterval(61)
        transcripts["t"] = [Exchange(id: "e", asker: .you, askedAt: at, ask: "Tidy my resume", reply: "Done.", repliedAt: at.addingTimeInterval(61))]
        view.show(ChannelBook.build(kittens: [steve, pepper], threads: threads, transcripts: transcripts, isReading: false, unreadable: 0, cantReachT3: false, sent: pending))
        view.pane.composer.send("Keep it to one page")
        XCTAssertEqual(sent, [], "the follow-up to the new topic went to the old thread")
    }
}

extension ChannelsWindowTests {
    func testANewTopicKeepsTheBoxWhenAnOldThreadAnswersLate() {
        let view = ChannelsView(frame: NSRect(x: 0, y: 0, width: 820, height: 560))
        var sent: [MessagesAction] = []
        view.pane.onAction = { sent.append($0) }
        let echo = SentMessage(channel: .direct(steve), message: ChannelMessage(exchangeID: "new-topic", kind: .ask, speaker: .you, text: "Write a new cover letter", at: at.addingTimeInterval(60), threadID: "", threadTitle: ""))
        let old = AgentThread(id: "old-resume", title: "Old resume", projectTitle: "Steve", status: .running, model: "m", updatedAt: at, projectPath: "/k/steve")
        let initial = Exchange(id: "resume", asker: .you, askedAt: at, ask: "Tidy my old resume")
        view.show(ChannelBook.build(kittens: [steve], threads: [old], transcripts: [old.id: [initial]], isReading: false, unreadable: 0, cantReachT3: false, sent: [echo]))
        view.select(.channel(.direct(steve)))
        XCTAssertEqual(view.pane.composer.target, .starting(steve))
        view.pane.composer.textView.string = "Keep the new letter to one page"

        var finished = old
        finished.status = .completed
        finished.updatedAt = at.addingTimeInterval(90)
        let lateReply = Exchange(id: "resume", asker: .you, askedAt: at, ask: "Tidy my old resume", reply: "The old resume is ready.", repliedAt: at.addingTimeInterval(90))
        view.show(ChannelBook.build(kittens: [steve], threads: [finished], transcripts: [old.id: [lateReply]], isReading: false, unreadable: 0, cantReachT3: false, sent: [echo]))
        XCTAssertEqual(view.pane.composer.target, .starting(steve), "The pending new topic must hold its target even when the old thread answers later")
        view.pane.composer.send(view.pane.composer.textView.string)
        XCTAssertEqual(sent, [], "A follow-up for the new topic must not go to the old resume thread")
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
        view.select(.channel(.direct(red)))
        let rows = bubbles(in: view)
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
