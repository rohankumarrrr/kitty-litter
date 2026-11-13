@testable import Shades
import ShadesCore
import XCTest

final class ChannelRowsTests: XCTestCase {
    private let steve = Kitten(name: "Steve Pawsniak", role: "Professional", covers: "", folder: "/k/steve")
    private let pepper = Kitten(name: "Pepper", role: "Finance", covers: "", folder: "/k/pepper")
    private let cali = Kitten(name: "Cali", role: "Scheduling", covers: "", folder: "/k/cali", planned: true)
    private let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_000_000))!

    private func thread(_ id: String, title: String = "Work", status: AgentStatus = .completed) -> AgentThread {
        AgentThread(id: id, title: title, projectTitle: "Steve Pawsniak", status: status, model: "m", updatedAt: noon, projectPath: "/k/steve")
    }

    private func pepperThread(_ id: String) -> AgentThread {
        AgentThread(id: id, title: "Plans", projectTitle: "Pepper", status: .completed, model: "m", updatedAt: noon, projectPath: "/k/pepper")
    }

    private func exchange(_ id: String, asked: TimeInterval = 0, reply: String? = "Reply") -> Exchange {
        Exchange(id: id, asker: .you, askedAt: noon.addingTimeInterval(asked), ask: "Ask", reply: reply, repliedAt: reply == nil ? nil : noon.addingTimeInterval(asked + 1))
    }

    private func book(
        threads: [AgentThread] = [],
        transcripts: [String: [Exchange]] = [:],
        isReading: Bool = false,
        unreadable: Int = 0,
        cantReachT3: Bool = false
    ) -> ChannelBook {
        ChannelBook.build(kittens: [steve, pepper, cali], threads: threads, transcripts: transcripts, isReading: isReading, unreadable: unreadable, cantReachT3: cantReachT3)
    }

    private func channel(_ kitten: Kitten, in book: ChannelBook) -> [ChannelRow] {
        ChannelRows.rows(.channel(.of(kitten)), in: book)
    }

    private func parents(_ rows: [ChannelRow]) -> [ThreadPost] {
        rows.compactMap {
            if case .parent(let post) = $0 { return post }
            return nil
        }
    }

    private func notes(_ rows: [ChannelRow]) -> [String] {
        rows.compactMap {
            if case .note(let text) = $0 { return text }
            return nil
        }
    }

    func testAChannelShowsEachThreadsParentWithItsReplyBar() throws {
        let built = book(threads: [thread("a", title: "First"), thread("b", title: "Second")], transcripts: [
            "a": [exchange("a1", asked: 0), exchange("a2", asked: 10), exchange("a3", asked: 40)],
            "b": [exchange("b1", asked: 20)],
        ])
        let posts = parents(channel(steve, in: built))
        XCTAssertEqual(posts.map(\.threadID), ["a", "b"])
        XCTAssertFalse(channel(steve, in: built).contains { if case .message = $0 { true } else { false } }, "replies stay in their thread")
        let first = try XCTUnwrap(posts.first)
        XCTAssertEqual(first.parent.id, "a1:ask")
        XCTAssertEqual(first.replies, 5)
        XCTAssertEqual(first.repliers, [.kitten(steve.id), .you])
        XCTAssertEqual(first.lastReply, noon.addingTimeInterval(41))
        XCTAssertFalse(first.isGoing)
    }

    @MainActor
    func testTheReplyBarCountsSaysWhosRepliedAndWhenTheLastWas() throws {
        let built = book(
            threads: [thread("a", status: .running), pepperThread("p")],
            transcripts: ["a": [
                exchange("a1", asked: 0),
                Exchange(id: "a2", asker: .agent(threadID: "p"), askedAt: noon.addingTimeInterval(10), ask: "From Pepper", reply: "Sure.", repliedAt: noon.addingTimeInterval(12)),
                exchange("a3", asked: 30, reply: nil),
            ], "p": []]
        )
        let post = try XCTUnwrap(parents(channel(steve, in: built)).first)
        XCTAssertEqual(post.replies, 4, "Steve, Pepper, Steve, you, and not the reply still coming")
        XCTAssertEqual(post.repliers, [.kitten(steve.id), .kitten(pepper.id), .you])
        XCTAssertEqual(post.lastReply, noon.addingTimeInterval(30), "the last that's said anything")
        XCTAssertTrue(post.isGoing)
        let bar = ReplyBar(post, in: built)
        XCTAssertEqual(bar.accessibilityWords(now: noon.addingTimeInterval(60)), "4 replies, Last reply \(noon.addingTimeInterval(30).formatted(date: .omitted, time: .shortened))  ·  Working on it")
        XCTAssertEqual(CatWords.replies(1), "1 reply")
        XCTAssertEqual(CatWords.replies(12), "12 replies")
    }

    func testAThreadsReplyBarSaysWhenItNeedsYou() throws {
        let approval = ApprovalRequest(id: "ap", threadID: "a", threadTitle: "Work", kind: .command, summary: "Run: ls", createdAt: noon)
        let built = waitingBook(Waiting(approvals: [approval], owners: ["ap": steve.id]), transcripts: ["a": [exchange("e")]])
        XCTAssertEqual(try XCTUnwrap(parents(channel(steve, in: built)).first).needsYou, true)
        XCTAssertFalse(channel(steve, in: built).contains(.approval(approval)), "it's answered in the thread and Activity")
    }

    func testADayDividerComesBeforeEachNewDay() {
        let day = 86_400.0
        let built = book(threads: [thread("y"), thread("a"), thread("b")], transcripts: [
            "y": [exchange("yesterday", asked: -day)],
            "a": [exchange("today1", asked: 0)],
            "b": [exchange("today2", asked: 60)],
        ])
        let rows = channel(steve, in: built)
        let start = Calendar.current.startOfDay(for: noon)
        let days = rows.filter {
            if case .day = $0 { return true }
            return false
        }
        XCTAssertEqual(days, [.day(Calendar.current.date(byAdding: .day, value: -1, to: start)!), .day(start)])
        XCTAssertEqual(rows.first, days.first)
    }

    func testAThreadPaneShowsItsParentHowManyRepliesThenEachReply() {
        let day = 86_400.0
        var late = exchange("late", asked: day)
        late.repliedAt = noon.addingTimeInterval(day + 5)
        let built = book(threads: [thread("a")], transcripts: ["a": [exchange("first", asked: 0), late]])
        let rows = ChannelRows.thread("a", in: built)
        guard case .message(let parent) = rows.first else { return XCTFail("\(rows)") }
        XCTAssertEqual(parent.id, "first:ask")
        XCTAssertEqual(rows[1], .replies(3))
        XCTAssertEqual(rows.filter { if case .day = $0 { true } else { false } }.count, 1, "a day divider once the replies reach a new day")
    }

    // MARK: - What's new

    private func lines(_ rows: [ChannelRow]) -> [ChannelRow] {
        rows.filter { if case .new = $0 { true } else { false } }
    }

    func testAThreadsNewLineGoesOverItsFirstNewMessageAndCountsWhatsUnderIt() throws {
        let built = book(threads: [thread("a")], transcripts: ["a": [exchange("a1", asked: 0), exchange("a2", asked: 10)]])
        let rows = ChannelRows.thread("a", in: built, newFrom: ["a": "a2:ask"])
        XCTAssertEqual(lines(rows), [.new(2)])
        let line = try XCTUnwrap(rows.firstIndex(of: .new(2)))
        XCTAssertEqual(rows[line + 1], .message(try XCTUnwrap(built.threads["a"]?.replies[1])))
        XCTAssertEqual(ChannelRows.thread("a", in: built, newFrom: ["a": "a1:ask"]).first, .new(4), "all of it, over its parent")
        XCTAssertEqual(lines(ChannelRows.thread("a", in: built)), [], "nothing new, no line")
    }

    func testAChannelsNewLineGoesOverTheFirstThreadThatsAllNew() throws {
        let built = book(threads: [thread("a"), thread("b"), thread("c")], transcripts: [
            "a": [exchange("a1", asked: 0), exchange("a2", asked: 50)],
            "b": [exchange("b1", asked: 20)],
            "c": [exchange("c1", asked: 30)],
        ])
        let rows = ChannelRows.rows(.channel(.of(steve)), in: built, newFrom: ["a": "a2:ask", "b": "b1:ask", "c": "c1:ask"])
        XCTAssertEqual(lines(rows), [.new(2)], "a has only new replies, which are new in its pane, as in Slack")
        let line = try XCTUnwrap(rows.firstIndex(of: .new(2)))
        guard case .parent(let post) = rows[line + 1] else { return XCTFail("\(rows)") }
        XCTAssertEqual(post.threadID, "b")
    }

    func testTheBookKnowsWhereEachUnreadThreadsNewMessagesStart() {
        let built = ChannelBook.build(
            kittens: [steve], threads: [thread("a"), thread("b")], transcripts: ["a": [exchange("a1")], "b": [exchange("b1")]],
            isReading: false, unreadable: 0, cantReachT3: false,
            isUnread: { $0.id == "a" },
            firstNew: { thread, messages in "\(thread.id) \(messages.map(\.id).joined(separator: " "))" }
        )
        XCTAssertEqual(built.newFrom, ["a": "a a1:ask a1:reply"], "only unread threads, given their messages oldest first")
    }

    func testDaysReadTodayYesterdayOrTheDate() {
        let calendar = Calendar.current
        XCTAssertEqual(CatWords.day(noon, now: noon.addingTimeInterval(60)), "Today")
        XCTAssertEqual(CatWords.day(calendar.date(byAdding: .day, value: -1, to: noon)!, now: noon), "Yesterday")
        let older = CatWords.day(calendar.date(byAdding: .day, value: -3, to: noon)!, now: noon)
        XCTAssertFalse(["Today", "Yesterday"].contains(older))
        XCTAssertFalse(older.isEmpty)
    }

    func testAgesAreShort() {
        XCTAssertEqual(CatWords.age(of: noon, now: noon.addingTimeInterval(10)), "just now")
        XCTAssertEqual(CatWords.age(of: noon, now: noon.addingTimeInterval(300)), "5m ago")
        XCTAssertEqual(CatWords.age(of: noon, now: noon.addingTimeInterval(7_200)), "2h ago")
        XCTAssertEqual(CatWords.age(of: noon, now: noon.addingTimeInterval(90_000)), "1d ago")
    }

    @MainActor
    func testWhoSaidItWhenAndWhatsOverItGrowWithTheTextSize() throws {
        defer { MessagesInk.textSize = .standard }
        let built = book(threads: [thread("a", title: "Rewrite the pricing copy")], transcripts: ["a": [exchange("a1"), exchange("a2", asked: 30)]])
        let post = try XCTUnwrap(parents(channel(steve, in: built)).first)
        let search = JumpBoxView(frame: NSRect(x: 0, y: 0, width: 900, height: 560))
        func measured(_ size: TextSize) -> [String: CGFloat] {
            MessagesInk.textSize = size
            search.show(built, mode: .search)
            search.layout()
            return [
                "reply bar": ReplyBar(post, in: built).width(now: noon.addingTimeInterval(60)),
                "kitten's name and state": HeadingRowView(status: KittenStatus(kitten: steve, state: .idle)).fit(width: 600),
                "thread in Activity": IssueRowView(thread: thread("a"), now: { self.noon }).fit(width: 600),
                "search box": search.field.frame.height,
            ]
        }
        let sizes = TextSize.allCases.map { ($0, measured($0)) }
        for ((smaller, before), (bigger, after)) in zip(sizes, sizes.dropFirst()) {
            for (what, height) in before {
                XCTAssertGreaterThan(try XCTUnwrap(after[what]), height, "\(what) from \(smaller) to \(bigger)")
            }
        }
    }

    func testNumbersThatChangeHoldStillInEveryFace() {
        for family in [nil] + MessagesInk.systemFaces.map(\.name) {
            let font = MessagesInk.font(ofSize: MessagesInk.meta, tabular: true, family: family)
            let widths = Set((0...9).map { NSAttributedString(string: "\($0)", attributes: [.font: font]).size().width })
            XCTAssertEqual(widths.count, 1, "every digit one width in \(family ?? "the system's")")
        }
    }

    func testAnEmptyChannelSaysSo() {
        XCTAssertEqual(notes(channel(steve, in: book())), ["You and Steve Pawsniak haven't started a thread yet."])
        XCTAssertEqual(notes(channel(cali, in: book())), ["Cali isn't set up yet. Once it's ready for work, take planned: true out of its kitten.json."])
    }

    func testAnEmptyChannelWhileReadingSaysSo() {
        XCTAssertEqual(notes(channel(steve, in: book(isReading: true))), ["Reading their messages…"])
        XCTAssertEqual(notes(channel(cali, in: book(isReading: true))), ["Cali isn't set up yet. Once it's ready for work, take planned: true out of its kitten.json."])
    }

    func testAnEmptyChannelWhenT3IsAwaySaysSo() {
        XCTAssertEqual(notes(channel(steve, in: book(isReading: true, cantReachT3: true))), ["I can't reach T3 Code. Open it and try again."])
    }

    func testAnEmptyChannelWithAFailedReadSaysThatInstead() {
        XCTAssertEqual(notes(channel(steve, in: book(unreadable: 2))), ["Couldn't read 2 threads. I'll try again."])
        XCTAssertEqual(notes(channel(steve, in: book(unreadable: 1))), ["Couldn't read 1 thread. I'll try again."])
    }

    func testTroubleDoesntTakeAwayWhatsAlreadyThere() {
        let rows = channel(steve, in: book(threads: [thread("a")], transcripts: ["a": [exchange("e")]], unreadable: 2, cantReachT3: true))
        XCTAssertEqual(rows.suffix(2), [.note("I can't reach T3 Code. Open it and try again."), .note("Couldn't read 2 threads. I'll try again.")])
        XCTAssertEqual(parents(rows).count, 1)
    }

    func testLoadOlderOpensACutChannel() {
        let threads = (0..<201).map { thread("t\($0)") }
        let rows = channel(steve, in: book(threads: threads, transcripts: Dictionary(uniqueKeysWithValues: threads.enumerated().map { ($1.id, [exchange("e\($0)", asked: TimeInterval($0))]) })))
        XCTAssertEqual(rows.first, .older(isLoading: false))
    }

    func testWhatEachKittenIsOnSitsUnderWhatsWaitingInActivity() {
        let built = book(threads: [thread("a", status: .running), thread("b", status: .failed)])
        let rows = ChannelRows.rows(.activity, in: built)
        XCTAssertEqual(Array(rows.prefix(2)), [.note("Nothing needs you."), .section("In progress", clearing: nil)])
        let progress = Array(rows.dropFirst(2))
        XCTAssertEqual(progress.count, 5)
        guard case .heading(let first) = progress[0], case .heading(let second) = progress[3] else { return XCTFail("\(rows)") }
        XCTAssertEqual(first.kitten, steve)
        XCTAssertEqual(second.kitten, pepper)
        XCTAssertEqual(progress[1], .issue(built.issues[0].threads[0]))
        XCTAssertEqual(progress[2], .issue(built.issues[0].threads[1]))
        XCTAssertEqual(progress[4], .note("Nothing open."))
    }

    func testActivityWhileReadingWithNothingYetSaysReading() {
        XCTAssertEqual(ChannelRows.rows(.activity, in: book(isReading: true)).last, .note("Reading their messages…"))
        let known = ChannelRows.rows(.activity, in: book(threads: [thread("a", status: .running)], isReading: true))
        XCTAssertFalse(known.contains(.note("Reading their messages…")), "threads are known before any words are")
    }

    func testActivityWithNothingKnownAndNoT3SaysSoOnce() {
        let rows = ChannelRows.rows(.activity, in: book(isReading: true, cantReachT3: true))
        XCTAssertEqual(rows.first, .note("I can't reach T3 Code. Open it and try again."))
        XCTAssertEqual(rows.filter { $0 == .note("I can't reach T3 Code. Open it and try again.") }.count, 1)
    }

    func testActivityLeadsWithAnyTrouble() {
        XCTAssertEqual(ChannelRows.rows(.activity, in: book(threads: [thread("a")], cantReachT3: true)).first, .note("I can't reach T3 Code. Open it and try again."))
    }

    private func issueIDs(_ rows: [ChannelRow]) -> [String] {
        rows.compactMap {
            if case .issue(let thread) = $0 { return thread.id }
            return nil
        }
    }

    func testAFinishedThreadLeavesActivityForItsChannel() {
        let built = book(threads: [thread("working", status: .running), thread("finished")], transcripts: ["finished": [exchange("e")]])
        XCTAssertEqual(issueIDs(ChannelRows.rows(.activity, in: built)), ["working"])
        XCTAssertEqual(parents(channel(steve, in: built)).map(\.threadID), ["finished"])
    }

    func testThreadsListsEachThreadYouWroteInWithItsLatestReply() throws {
        let built = book(threads: [thread("a"), thread("b")], transcripts: [
            "a": [exchange("a1", asked: 0), exchange("a2", asked: 10)],
            "b": [Exchange(id: "b1", asker: .agent(threadID: nil), askedAt: noon, ask: "Someone's", reply: "Not yours", repliedAt: noon)],
        ])
        let rows = ChannelRows.rows(.threads, in: built)
        XCTAssertEqual(rows.count, 1, "only threads you've written in")
        guard case .digest(let digest) = rows.first else { return XCTFail("\(rows)") }
        XCTAssertEqual(digest.threadID, "a")
        XCTAssertEqual(digest.channel, .of(steve))
        XCTAssertEqual(digest.parent.id, "a1:ask")
        XCTAssertEqual(digest.latest?.id, "a2:reply")
        XCTAssertEqual(digest.more, 2)
        XCTAssertEqual(CatWords.moreReplies(2), "2 more replies")
        XCTAssertEqual(ChannelRows.rows(.threads, in: book()), [.note(CatWords.threadsEmpty)])
        XCTAssertEqual(ChannelRows.rows(.threads, in: book(isReading: true)), [.note("Reading their messages…")])
    }

    func testAReplyAlsoSentToAChannelSaysWhichThreadItsIn() throws {
        let reply = ChannelMessage(exchangeID: "sent-1", kind: .ask, speaker: .you, text: "Keep the FAQ", at: noon.addingTimeInterval(30), threadID: "a", threadTitle: "")
        let built = ChannelBook.build(
            kittens: [steve], threads: [thread("a")], transcripts: ["a": [Exchange(id: "e", asker: .you, askedAt: noon, ask: "Rewrite the pricing copy so it sounds like a person wrote it, please", reply: "Done.", repliedAt: noon)]],
            isReading: false, unreadable: 0, cantReachT3: false, sent: [SentMessage(channel: .of(steve), message: reply, alsoSent: true)]
        )
        var shown = reply
        shown.threadTitle = "Work"
        XCTAssertEqual(channel(steve, in: built).last, .alsoSent(shown, threadID: "a", parent: "Rewrite the pricing copy so it sounds like a person wrote i…"))
        XCTAssertEqual(CatWords.repliedToThread("Tidy it"), "replied to a thread: Tidy it")
    }

    // MARK: - Messages

    private func question(_ id: String = "q", ownWords: Bool = true, form: Bool = true) -> AgentQuestion {
        AgentQuestion(
            id: id, threadID: "a", threadTitle: "Work", text: "Which?", options: ["A", "B"],
            form: form ? AnswerForm(parts: [AnswerForm.Part(key: "k", text: "Which?", options: ["A", "B"], values: ["A", "B"], takesOwnWords: ownWords)]) : nil
        )
    }

    private func waitingBook(_ waiting: Waiting, transcripts: [String: [Exchange]] = [:]) -> ChannelBook {
        ChannelBook.build(kittens: [steve, pepper, cali], threads: [thread("a")], transcripts: transcripts, isReading: false, unreadable: 0, cantReachT3: false, waiting: waiting)
    }

    /// An @ names a kitten by its name written as one word, the first one that's set up, as a word of its own.
    func testAnAtNamesTheFirstKittenThatsSetUpByItsNameAsOneWord() {
        let named = Kitten(name: "Steve Pawsniak", role: "", covers: "", folder: "/k/sp")
        let built = ChannelBook.build(kittens: [named, pepper, cali], threads: [], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false)
        XCTAssertEqual(MessageTarget.mentioned(in: "Ask @Steve-Pawsniak: and @pepper", among: built.mentionable), named)
        XCTAssertNil(MessageTarget.mentioned(in: "me@pepper.com @cali", among: built.mentionable), "an email, and a kitten that's only planned")
    }

    func testTheCatGoesThroughTheRouterAndOnlyReadingPlacesHaveNoBox() {
        let built = book(threads: [thread("a")], transcripts: ["a": [exchange("e")]])
        XCTAssertEqual(MessageTarget.standard(for: .channel(.shades), in: built), .router)
        XCTAssertNil(MessageTarget.standard(for: .activity, in: built))
        XCTAssertNil(MessageTarget.standard(for: .threads, in: built))
        XCTAssertNil(MessageTarget.standard(for: .channel(.of(cali)), in: built), "a kitten that isn't set up takes nothing")
    }

    func testAChannelsOwnBoxStartsSomethingNewAndAThreadsCarriesOnInIt() {
        let built = book(threads: [thread("a", title: "Old"), thread("b", title: "Newer")], transcripts: ["a": [exchange("e1")], "b": [exchange("e2", asked: 10)]])
        XCTAssertEqual(MessageTarget.standard(for: .channel(.of(steve)), in: built), .newThread(steve), "never a guess at which thread")
        XCTAssertEqual(MessageTarget.reply(in: "a", of: built), .thread(id: "a", title: "Old"))
        XCTAssertEqual(MessageTarget.standard(for: .channel(.of(pepper)), in: built), .newThread(pepper))
        XCTAssertNil(MessageTarget.reply(in: "nowhere", of: built), "a thread nothing is known of has nowhere to send")
    }

    func testAThreadAnotherKittenStartedTakesYourReplyAsInSlack() {
        let built = book(threads: [thread("a"), pepperThread("p")], transcripts: ["a": [Exchange(id: "e", asker: .agent(threadID: "p"), askedAt: noon, ask: "From Pepper", reply: "Sure.", repliedAt: noon)], "p": []])
        XCTAssertEqual(MessageTarget.reply(in: "a", of: built), .thread(id: "a", title: "Work"))
    }

    func testAQuestionThatTakesYourWordsIsWhatItsThreadAnswers() {
        let open = waitingBook(Waiting(questions: [question()], owners: ["q": steve.id]), transcripts: ["a": [exchange("e")]])
        XCTAssertEqual(MessageTarget.reply(in: "a", of: open), .question(question()))
        XCTAssertEqual(MessageTarget.standard(for: .channel(.of(steve)), in: open), .newThread(steve), "the box under the channel never answers")
        let choicesOnly = waitingBook(Waiting(questions: [question(ownWords: false)], owners: ["q": steve.id]), transcripts: ["a": [exchange("e")]])
        XCTAssertEqual(MessageTarget.reply(in: "a", of: choicesOnly), .thread(id: "a", title: "Work"))
    }

    func testYourWordsAnswerWhicheverPartOfAQuestionIsNext() {
        let parts = AnswerForm(parts: [
            AnswerForm.Part(key: "m", text: "Which month?", options: ["Dec", "Jan"], values: ["dec", "jan"], takesOwnWords: false),
            AnswerForm.Part(key: "c", text: "Which currency?", options: [], values: [], takesOwnWords: true),
        ])
        let asked = AgentQuestion(id: "q", threadID: "a", threadTitle: "Work", text: "Which month?", form: parts)
        let built = waitingBook(Waiting(questions: [asked], owners: ["q": steve.id]), transcripts: ["a": [exchange("e")]])
        XCTAssertEqual(MessageTarget.reply(in: "a", of: built), .thread(id: "a", title: "Work"), "the month is picked, not typed")
        XCTAssertEqual(MessageTarget.reply(in: "a", of: built, answered: ["q": 1]), .question(asked))
    }

    func testASubagentsQuestionIsAnsweredInTheThreadItHoldsUp() {
        var asked = question()
        asked.threadID = "subagent"
        let built = waitingBook(Waiting(questions: [asked], owners: ["q": steve.id], listed: ["q": "a"]), transcripts: ["a": [exchange("e")]])
        XCTAssertEqual(MessageTarget.reply(in: "a", of: built), .question(asked))
        XCTAssertEqual(ChannelRows.thread("a", in: built).last, .question(asked))
    }

    func testAThreadOnItsOwnShowsOnlyItsWordsAndWhatItsWaitingOn() {
        let approval = ApprovalRequest(id: "ap", threadID: "b", threadTitle: "Second", kind: .command, summary: "Run: ls", createdAt: noon)
        let built = ChannelBook.build(
            kittens: [steve, pepper, cali],
            threads: [thread("a", title: "First"), thread("b", title: "Second")],
            transcripts: ["a": [exchange("a1", asked: 0)], "b": [exchange("b1", asked: 20)]],
            isReading: false, unreadable: 0, cantReachT3: false,
            waiting: Waiting(approvals: [approval], owners: ["ap": steve.id])
        )
        let rows = ChannelRows.thread("b", in: built)
        let threads = rows.compactMap { row -> String? in
            if case .message(let message) = row { return message.threadID }
            return nil
        }
        XCTAssertEqual(threads, ["b", "b"])
        XCTAssertEqual(rows.last, .approval(approval))
        XCTAssertEqual(ChannelRows.thread("c", in: built), [.note("It's archived or deleted in T3, so I can't read it here.")])
    }

    func testAScheduledRunIsItsKittensOwnWork() throws {
        let run = Exchange(id: "run", asker: .schedule, askedAt: noon, ask: "Check the packages, as you do every morning.", reply: "Two have updates. Merge them?", repliedAt: noon.addingTimeInterval(60))
        let built = book(threads: [thread("s", title: "Morning check")], transcripts: ["s": [run]])
        let said = ChannelRows.thread("s", in: built).compactMap { row -> ChannelMessage? in
            if case .message(let message) = row { return message }
            return nil
        }
        XCTAssertEqual(said.map(\.text), ["Two have updates. Merge them?"], "its report, without the schedule's prompt")
        XCTAssertEqual(said.map(\.speaker), [.kitten(steve.id)])
        XCTAssertEqual(parents(channel(steve, in: built)).map(\.threadID), ["s"], "in its kitten's own channel")
        XCTAssertEqual(MessageTarget.reply(in: "s", of: built), .thread(id: "s", title: "Morning check"), "and it takes your answer")
        let posted = try XCTUnwrap(built.threads["s"])
        XCTAssertEqual(posted.home, .of(steve))
        XCTAssertFalse(posted.messages.contains { $0.speaker == .someoneElse }, "nobody else was in it")
        XCTAssertEqual(ChannelRows.rows(.channel(.shades), in: built), [.note(CatWords.shadesEmpty)])
    }

    func testAnEmptyThreadSaysWhy() {
        let listed = book(threads: [thread("a")])
        XCTAssertEqual(ChannelRows.thread("a", in: listed), [.note("Its messages are in T3.")])
        XCTAssertEqual(ChannelRows.thread("gone", in: listed), [.note("It's archived or deleted in T3, so I can't read it here.")])
        let unread = book(threads: [thread("a")], unreadable: 1)
        XCTAssertEqual(ChannelRows.thread("a", in: unread), [.note("Couldn't read 1 thread. I'll try again.")])
    }

    func testActivityPutsWhatsWaitingFirstThenReportsThenWhatsInProgress() {
        let approval = ApprovalRequest(id: "ap", threadID: "a", threadTitle: "Work", kind: .command, summary: "Run: ls", createdAt: noon)
        let decision = InboxEntry(id: "d", kind: .decision, text: "Merged. Say ship it.", threadID: "a", threadTitle: "Work", at: noon)
        let shipped = InboxEntry(id: "s", kind: .shipped, text: "Shipped.", threadID: "a", threadTitle: "Work", at: noon)
        let note = InboxEntry(id: "n", kind: .note, text: "FYI.", threadID: "a", threadTitle: "Work", at: noon)
        let rows = ChannelRows.rows(.activity, in: waitingBook(Waiting(approvals: [approval], questions: [question()], reports: [note, shipped, decision])))
        XCTAssertEqual(Array(rows.prefix(10)), [
            .section("Waiting on you", clearing: nil), .approval(approval), .question(question()), .report(decision),
            .section("Shipped", clearing: .shipped), .report(shipped),
            .section("Also", clearing: .note), .report(note),
            .section("In progress", clearing: nil), .heading(KittenBoard.statuses(kittens: [steve], threads: [thread("a")])[0]),
        ])
    }

    func testShadesOwnWorkComesFirstInProgress() {
        let own = AgentThread(id: "own", title: "Find a cheaper flight", projectTitle: nil, status: .running, model: "m", updatedAt: noon)
        let built = ChannelBook.build(kittens: [steve, pepper, cali], threads: [thread("a")], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false, waiting: Waiting(shadesWork: [own]))
        let rows = ChannelRows.rows(.activity, in: built)
        let progress = Array(rows.drop { $0 != .section("In progress", clearing: nil) }.dropFirst())
        guard case .heading(let shades) = progress.first else { return XCTFail("\(rows)") }
        XCTAssertEqual(shades.kitten, KittenBoard.shades)
        XCTAssertEqual(shades.state, .working(sessions: 1))
        XCTAssertEqual(progress[1], .issue(own))
    }
}

// MARK: - Talking to the cat

extension ChannelRowsTests {
    func testTheCatsBoxGoesThroughTheRouterAndItsThreadsTakeNothingStraightIn() {
        let talk = AgentThread(id: "r", title: "Which plan?", projectTitle: "Shades router", status: .completed, model: "m", updatedAt: noon, projectPath: "/shades/router")
        let built = ChannelBook.build(kittens: [steve], threads: [talk], transcripts: ["r": [exchange("1")]], isReading: false, unreadable: 0, cantReachT3: false, withShades: ["r"])
        XCTAssertEqual(MessageTarget.standard(for: .channel(.shades), in: built), .router, "so the app acts on what the router says")
        XCTAssertNil(MessageTarget.reply(in: "r", of: built), "the router answers in lines the app acts on, so nothing goes straight into one of its threads")
        XCTAssertEqual(CatWords.target(.router), "To me, without looking at your screen")
        XCTAssertEqual(CatWords.placeholder(.router), "Message Shades")
        XCTAssertEqual(CatWords.placeholder(.newThread(steve)), "Message \(steve.name)", "a kitten's box names it the way the sidebar does, with no #")
        XCTAssertEqual(parents(ChannelRows.rows(.channel(.shades), in: built)).map(\.threadID), ["r"])
        XCTAssertNil(ChannelHeader.words(forThread: "r", in: built).subtitle?.range(of: "Shades router"), "the router's folder isn't a project you'd know")
        let empty = ChannelBook.build(kittens: [steve], threads: [], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false)
        XCTAssertEqual(ChannelRows.rows(.channel(.shades), in: empty), [.note(CatWords.shadesEmpty)])
    }
}
