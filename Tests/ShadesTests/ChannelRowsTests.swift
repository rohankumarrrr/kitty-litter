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

    private func dm(_ kitten: Kitten, in book: ChannelBook) -> [ChannelRow] {
        ChannelRows.rows(.channel(.direct(kitten)), in: book)
    }

    private func subjects(_ rows: [ChannelRow]) -> [String] {
        rows.compactMap {
            if case .subject(let title, _, _) = $0 { return title }
            return nil
        }
    }

    private func notes(_ rows: [ChannelRow]) -> [String] {
        rows.compactMap {
            if case .note(let text) = $0 { return text }
            return nil
        }
    }

    func testTheSubjectAppearsOnlyWhenTheThreadChanges() {
        let built = book(threads: [thread("a", title: "First"), thread("b", title: "Second")], transcripts: [
            "a": [exchange("a1", asked: 0), exchange("a2", asked: 10), exchange("a3", asked: 40)],
            "b": [exchange("b1", asked: 20)],
        ])
        XCTAssertEqual(subjects(dm(steve, in: built)), ["First", "Second", "First"])
        XCTAssertTrue(dm(steve, in: built).contains(.subject("Second", project: "Steve Pawsniak", threadID: "b")), "and it says which project, and knows what to open")
    }

    func testADayDividerComesBeforeEachNewDay() {
        let day = 86_400.0
        let built = book(threads: [thread("a")], transcripts: ["a": [
            exchange("yesterday", asked: -day),
            exchange("today1", asked: 0),
            exchange("today2", asked: 60),
        ]])
        let rows = dm(steve, in: built)
        let start = Calendar.current.startOfDay(for: noon)
        let days = rows.filter {
            if case .day = $0 { return true }
            return false
        }
        XCTAssertEqual(days, [.day(Calendar.current.date(byAdding: .day, value: -1, to: start)!), .day(start)])
        XCTAssertEqual(rows.first, days.first)
    }

    func testAnOldAskThatFinishedLaterDoesntBringADayBack() {
        let day = 86_400.0
        var slow = exchange("slow", asked: -day)
        slow.repliedAt = noon.addingTimeInterval(100)
        let built = book(threads: [thread("a")], transcripts: ["a": [exchange("quick", asked: -30), slow]])
        let days = dm(steve, in: built).filter {
            if case .day = $0 { return true }
            return false
        }
        XCTAssertEqual(days.count, 1)
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

    func testAnEmptyDMSaysSo() {
        XCTAssertEqual(notes(dm(steve, in: book())), ["You and Steve Pawsniak haven't talked yet."])
        XCTAssertEqual(notes(dm(cali, in: book())), ["Cali isn't set up yet."])
    }

    func testAnEmptyChannelWhileReadingSaysSo() {
        XCTAssertEqual(notes(dm(steve, in: book(isReading: true))), ["Reading their messages..."])
        XCTAssertEqual(notes(dm(cali, in: book(isReading: true))), ["Cali isn't set up yet."])
    }

    func testAnEmptyChannelWhenT3IsAwaySaysSo() {
        XCTAssertEqual(notes(dm(steve, in: book(isReading: true, cantReachT3: true))), ["I can't reach T3 Code. Open it and I'll catch up."])
    }

    func testAnEmptyChannelWithAFailedReadSaysThatInstead() {
        XCTAssertEqual(notes(dm(steve, in: book(unreadable: 2))), ["Couldn't read 2 threads. I'll try again."])
        XCTAssertEqual(notes(dm(steve, in: book(unreadable: 1))), ["Couldn't read 1 thread. I'll try again."])
    }

    func testTroubleDoesntTakeAwayWhatsAlreadyThere() {
        let rows = dm(steve, in: book(threads: [thread("a")], transcripts: ["a": [exchange("e")]], unreadable: 2, cantReachT3: true))
        XCTAssertEqual(rows.suffix(2), [.note("I can't reach T3 Code. Open it and I'll catch up."), .note("Couldn't read 2 threads. I'll try again.")])
        XCTAssertTrue(rows.contains {
            if case .message = $0 { return true }
            return false
        })
    }

    func testAChannelThatsGoneReadsAsEmpty() throws {
        let pair = try XCTUnwrap(ChannelID(.kitten(steve.id), .kitten(pepper.id)))
        XCTAssertEqual(notes(ChannelRows.rows(.channel(pair), in: book())), ["Steve Pawsniak and Pepper haven't talked yet."])
        XCTAssertEqual(notes(ChannelRows.rows(.channel(pair), in: book(isReading: true))), ["Reading their messages..."])
    }

    func testTheOlderMessagesNoteOpensACutChannel() {
        let many = (0..<201).map { exchange("e\($0)", asked: TimeInterval($0)) }
        let rows = dm(steve, in: book(threads: [thread("a")], transcripts: ["a": many]))
        XCTAssertEqual(rows.first, .note("Older messages are in T3."))
    }

    func testWhatEachKittenIsOnSitsUnderWhatNeedsYou() {
        let built = book(threads: [thread("a", status: .running), thread("b", status: .failed)])
        let rows = ChannelRows.rows(.needsYou, in: built)
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

    func testNeedsYouWhileReadingWithNothingYetSaysReading() {
        XCTAssertEqual(ChannelRows.rows(.needsYou, in: book(isReading: true)).last, .note("Reading their messages..."))
        let known = ChannelRows.rows(.needsYou, in: book(threads: [thread("a", status: .running)], isReading: true))
        XCTAssertFalse(known.contains(.note("Reading their messages...")), "threads are known before any words are")
    }

    func testNeedsYouWithNothingKnownAndNoT3SaysSoOnce() {
        let rows = ChannelRows.rows(.needsYou, in: book(isReading: true, cantReachT3: true))
        XCTAssertEqual(rows.first, .note("I can't reach T3 Code. Open it and I'll catch up."))
        XCTAssertEqual(rows.filter { $0 == .note("I can't reach T3 Code. Open it and I'll catch up.") }.count, 1)
    }

    func testNeedsYouLeadsWithAnyTrouble() {
        XCTAssertEqual(ChannelRows.rows(.needsYou, in: book(threads: [thread("a")], cantReachT3: true)).first, .note("I can't reach T3 Code. Open it and I'll catch up."))
    }

    private func issueIDs(_ rows: [ChannelRow]) -> [String] {
        rows.compactMap {
            if case .issue(let thread) = $0 { return thread.id }
            return nil
        }
    }

    func testAFinishedThreadLeavesNeedsYouForDone() {
        let built = book(threads: [thread("working", status: .running), thread("finished")])
        XCTAssertEqual(issueIDs(ChannelRows.rows(.needsYou, in: built)), ["working"])
        let done = ChannelRows.rows(.done, in: built)
        XCTAssertEqual(issueIDs(done), ["finished"])
        guard case .heading(let status) = done.first else { return XCTFail("\(done)") }
        XCTAssertEqual(status.kitten, steve)
        XCTAssertEqual(done.count, 2, "a kitten with nothing finished isn't listed")
    }

    func testDoneWithNothingInItSaysWhy() {
        XCTAssertEqual(ChannelRows.rows(.done, in: book(threads: [thread("a", status: .running)])), [.note("Nothing's finished yet.")])
        XCTAssertEqual(ChannelRows.rows(.done, in: book(isReading: true)), [.note("Reading their messages...")])
        XCTAssertEqual(ChannelRows.rows(.done, in: book(threads: [thread("a")], cantReachT3: true)).first, .note("I can't reach T3 Code. Open it and I'll catch up."))
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

    func testEveryoneGoesThroughTheRouterAndOnlyReadingPlacesHaveNoBox() {
        let built = book(threads: [thread("a")], transcripts: ["a": [exchange("e")]])
        XCTAssertEqual(MessageTarget.standard(for: .channel(.everyone), in: built), .router)
        XCTAssertNil(MessageTarget.standard(for: .needsYou, in: built))
        XCTAssertNil(MessageTarget.standard(for: .done, in: built))
        XCTAssertNil(MessageTarget.standard(for: .channel(.direct(cali)), in: built), "a kitten that isn't set up takes nothing")
        XCTAssertNil(MessageTarget.standard(for: .channel(ChannelID(.kitten(steve.id), .kitten(pepper.id))!), in: built), "what kittens say to each other is only read")
    }

    func testADMsOwnBoxStartsSomethingNewAndAThreadsCarriesOnInIt() {
        let built = book(threads: [thread("a", title: "Old"), thread("b", title: "Newer")], transcripts: ["a": [exchange("e1")], "b": [exchange("e2", asked: 10)]])
        XCTAssertEqual(MessageTarget.standard(for: .channel(.direct(steve)), in: built), .newThread(steve), "never a guess at which thread")
        XCTAssertEqual(MessageTarget.standard(for: .thread("a", in: .direct(steve)), in: built), .thread(id: "a", title: "Old"))
        XCTAssertEqual(MessageTarget.standard(for: .thread("b", in: .everyone), in: built), .thread(id: "b", title: "Newer"), "a thread opened from Everyone goes straight to it")
        XCTAssertEqual(MessageTarget.standard(for: .channel(.direct(pepper)), in: built), .newThread(pepper))
        XCTAssertNil(MessageTarget.standard(for: .thread("nowhere", in: .direct(steve)), in: built), "a thread nothing is known of has nowhere to send")
        XCTAssertNil(MessageTarget.standard(for: .thread("a", in: ChannelID(.kitten(steve.id), .kitten(pepper.id))!), in: built), "a thread between kittens is only read")
    }

    func testAQuestionThatTakesYourWordsIsWhatItsThreadAnswers() {
        let open = waitingBook(Waiting(questions: [question()], owners: ["q": steve.id]), transcripts: ["a": [exchange("e")]])
        XCTAssertEqual(MessageTarget.standard(for: .thread("a", in: .direct(steve)), in: open), .question(question()))
        XCTAssertEqual(MessageTarget.standard(for: .channel(.direct(steve)), in: open), .newThread(steve), "the box under everything never answers")
        let choicesOnly = waitingBook(Waiting(questions: [question(ownWords: false)], owners: ["q": steve.id]), transcripts: ["a": [exchange("e")]])
        XCTAssertEqual(MessageTarget.standard(for: .thread("a", in: .direct(steve)), in: choicesOnly), .thread(id: "a", title: "Work"))
    }

    func testYourWordsAnswerWhicheverPartOfAQuestionIsNext() {
        let parts = AnswerForm(parts: [
            AnswerForm.Part(key: "m", text: "Which month?", options: ["Dec", "Jan"], values: ["dec", "jan"], takesOwnWords: false),
            AnswerForm.Part(key: "c", text: "Which currency?", options: [], values: [], takesOwnWords: true),
        ])
        let asked = AgentQuestion(id: "q", threadID: "a", threadTitle: "Work", text: "Which month?", form: parts)
        let built = waitingBook(Waiting(questions: [asked], owners: ["q": steve.id]), transcripts: ["a": [exchange("e")]])
        XCTAssertEqual(MessageTarget.standard(for: .thread("a", in: .direct(steve)), in: built), .thread(id: "a", title: "Work"), "the month is picked, not typed")
        XCTAssertEqual(MessageTarget.standard(for: .thread("a", in: .direct(steve)), in: built, answered: ["q": 1]), .question(asked))
    }

    func testASubagentsQuestionIsAnsweredInTheThreadItHoldsUp() {
        var asked = question()
        asked.threadID = "subagent"
        let built = waitingBook(Waiting(questions: [asked], owners: ["q": steve.id], listed: ["q": "a"]), transcripts: ["a": [exchange("e")]])
        XCTAssertEqual(MessageTarget.standard(for: .thread("a", in: .direct(steve)), in: built), .question(asked))
        XCTAssertEqual(ChannelRows.rows(.thread("a", in: .direct(steve)), in: built).last, .question(asked))
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
        let rows = ChannelRows.rows(.thread("b", in: .direct(steve)), in: built)
        XCTAssertEqual(subjects(rows), [], "the header says which thread it is")
        let threads = rows.compactMap { row -> String? in
            if case .message(let message) = row { return message.threadID }
            return nil
        }
        XCTAssertEqual(threads, ["b", "b"])
        XCTAssertEqual(rows.last, .approval(approval))
        XCTAssertEqual(ChannelRows.rows(.thread("c", in: .direct(steve)), in: built), [.note("Its messages are in T3.")])
    }

    func testADMEndsWithWhatThatKittenIsWaitingOnYouFor() {
        let approval = ApprovalRequest(id: "ap", threadID: "a", threadTitle: "Work", kind: .command, summary: "Run: ls", createdAt: noon)
        let built = waitingBook(Waiting(approvals: [approval], questions: [question()], owners: ["ap": steve.id, "q": steve.id]), transcripts: ["a": [exchange("e")]])
        XCTAssertEqual(Array(dm(steve, in: built).suffix(2)), [.approval(approval), .question(question())])
        XCTAssertFalse(dm(pepper, in: built).contains(.approval(approval)))
        XCTAssertFalse(ChannelRows.rows(.channel(.everyone), in: built).contains(.approval(approval)), "Everyone is only what's been said")
    }

    func testNeedsYouPutsWhatsWaitingFirstThenReportsThenWhatsInProgress() {
        let approval = ApprovalRequest(id: "ap", threadID: "a", threadTitle: "Work", kind: .command, summary: "Run: ls", createdAt: noon)
        let decision = InboxEntry(id: "d", kind: .decision, text: "Merged. Say ship it.", threadID: "a", threadTitle: "Work", at: noon)
        let shipped = InboxEntry(id: "s", kind: .shipped, text: "Shipped.", threadID: "a", threadTitle: "Work", at: noon)
        let note = InboxEntry(id: "n", kind: .note, text: "FYI.", threadID: "a", threadTitle: "Work", at: noon)
        let rows = ChannelRows.rows(.needsYou, in: waitingBook(Waiting(approvals: [approval], questions: [question()], reports: [note, shipped, decision])))
        XCTAssertEqual(Array(rows.prefix(10)), [
            .section("Needs you", clearing: nil), .approval(approval), .question(question()), .report(decision),
            .section("Shipped", clearing: .shipped), .report(shipped),
            .section("Also", clearing: .note), .report(note),
            .section("In progress", clearing: nil), .heading(KittenBoard.statuses(kittens: [steve], threads: [thread("a")])[0]),
        ])
    }

    func testEveryoneWithNothingSaidSaysWhereItGoes() {
        XCTAssertEqual(ChannelRows.rows(.channel(.everyone), in: book()), [.note("Say something and it goes to whoever it's for.")])
    }

    func testShadesOwnWorkComesFirstInProgress() {
        let own = AgentThread(id: "own", title: "Find a cheaper flight", projectTitle: nil, status: .running, model: "m", updatedAt: noon)
        let built = ChannelBook.build(kittens: [steve, pepper, cali], threads: [thread("a")], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false, waiting: Waiting(shadesWork: [own]))
        let rows = ChannelRows.rows(.needsYou, in: built)
        let progress = Array(rows.drop { $0 != .section("In progress", clearing: nil) }.dropFirst())
        guard case .heading(let shades) = progress.first else { return XCTFail("\(rows)") }
        XCTAssertEqual(shades.kitten, KittenBoard.shades)
        XCTAssertEqual(shades.state, .working(sessions: 1))
        XCTAssertEqual(progress[1], .issue(own))
    }
}

// MARK: - Talking to the cat

extension ChannelRowsTests {
    func testTheCatsConversationIsOnlyForReading() {
        let talk = AgentThread(id: "r", title: "Which plan?", projectTitle: "Shades router", status: .completed, model: "m", updatedAt: noon, projectPath: "/shades/router")
        let built = ChannelBook.build(kittens: [steve], threads: [talk], transcripts: ["r": [exchange("1")]], isReading: false, unreadable: 0, cantReachT3: false, withShades: ["r"])
        XCTAssertNil(MessageTarget.standard(for: .channel(.shades), in: built), "the router answers in lines the app acts on, so nothing goes straight to it")
        XCTAssertNil(MessageTarget.standard(for: .thread("r", in: .shades), in: built))
        XCTAssertTrue(ChannelRows.rows(.channel(.shades), in: built).contains(.subject("Which plan?", project: nil, threadID: "r")), "the router's folder isn't a project you'd know")
        let empty = ChannelBook.build(kittens: [steve], threads: [], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false)
        XCTAssertEqual(ChannelRows.rows(.channel(.shades), in: empty), [.note(CatWords.shadesEmpty)])
    }
}
