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
            if case .subject(let title, _) = $0 { return title }
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
        XCTAssertTrue(dm(steve, in: built).contains(.subject("Second", threadID: "b")), "and it knows what to open")
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

    func testIssuesAreGroupedByKitten() {
        let built = book(threads: [thread("a", status: .running), thread("b")])
        let rows = ChannelRows.rows(.issues, in: built)
        XCTAssertEqual(rows.count, 5)
        guard case .heading(let first) = rows[0], case .heading(let second) = rows[3] else { return XCTFail("\(rows)") }
        XCTAssertEqual(first.kitten, steve)
        XCTAssertEqual(second.kitten, pepper)
        XCTAssertEqual(rows[1], .issue(built.issues[0].threads[0]))
        XCTAssertEqual(rows[2], .issue(built.issues[0].threads[1]))
        XCTAssertEqual(rows[4], .note("Nothing open."))
    }

    func testIssuesWhileReadingWithNothingYetSayReading() {
        XCTAssertEqual(ChannelRows.rows(.issues, in: book(isReading: true)), [.note("Reading their messages...")])
        let known = ChannelRows.rows(.issues, in: book(threads: [thread("a")], isReading: true))
        XCTAssertFalse(known.contains(.note("Reading their messages...")), "threads are known before any words are")
    }

    func testIssuesWithNothingKnownAndNoT3SayOnlyThat() {
        XCTAssertEqual(ChannelRows.rows(.issues, in: book(isReading: true, cantReachT3: true)), [.note("I can't reach T3 Code. Open it and I'll catch up.")])
    }

    func testIssuesLeadWithAnyTrouble() {
        XCTAssertEqual(ChannelRows.rows(.issues, in: book(threads: [thread("a")], cantReachT3: true)).first, .note("I can't reach T3 Code. Open it and I'll catch up."))
    }
}
