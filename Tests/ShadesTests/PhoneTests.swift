@testable import Shades
import ShadesCore
import XCTest

/// What a phone can ask for, and what it's shown. A phone only names places and IDs, so every test here is about what
/// the book allows, never what the phone says.
@MainActor
final class PhoneTests: XCTestCase {
    private let steve = Kitten(name: "Steve Pawsniak", role: "Professional", covers: "", folder: "/k/steve")
    private let pepper = Kitten(name: "Pepper", role: "Finance", covers: "", folder: "/k/pep+per@home")
    private let noon = Date(timeIntervalSince1970: 1_000_000)

    private func thread(_ id: String, of kitten: Kitten) -> AgentThread {
        AgentThread(id: id, title: "Work", projectTitle: kitten.name, status: .completed, model: "m", updatedAt: noon, projectPath: kitten.folder)
    }

    private func book(waiting: Waiting = Waiting(), sentBetween: Bool = false, also: [AgentThread] = []) -> ChannelBook {
        var transcripts = ["a": [Exchange(id: "e1", asker: .you, askedAt: noon, ask: "How's it going?", reply: "Fine.", repliedAt: noon)]]
        // A thread of Pepper's that only Steve has talked in, which isn't yours to carry on.
        if sentBetween { transcripts["p"] = [Exchange(id: "e2", asker: .agent(threadID: "a"), askedAt: noon, ask: "Numbers?", reply: "Here.", repliedAt: noon)] }
        return ChannelBook.build(
            kittens: [steve, pepper],
            threads: [thread("a", of: steve), thread("p", of: pepper)] + also,
            transcripts: transcripts,
            isReading: false,
            unreadable: 0,
            cantReachT3: false,
            waiting: waiting
        )
    }

    private func ask(_ act: String, key: String? = nil, text: String? = nil, id: String? = nil, value: String? = nil, answers: [String]? = nil, kind: String? = nil) -> PhoneAsk {
        PhoneAsk(act: act, key: key, text: text, id: id, value: value, answers: answers, kind: kind)
    }

    // MARK: - Places

    func testEveryPlaceComesBackFromItsKey() {
        let book = book(sentBetween: true, also: [thread("a/b@c", of: pepper)])
        let places: [ChannelSelection] = [
            .needsYou, .done, .channel(.everyone), .channel(.direct(pepper)),
            .channel(ChannelID(.kitten(steve.id), .kitten(pepper.id))!),
            .channel(ChannelID(.kitten(pepper.id), .someoneElse)!),
            .thread("a/b@c", in: .direct(pepper)),
            .thread("a", in: .everyone),
        ]
        for selection in places {
            let key = PhonePlace.key(selection)
            XCTAssertEqual(PhonePlace(key, in: book).selection, selection, key)
        }
        XCTAssertNil(PhonePlace("home", in: book).selection)
        XCTAssertNil(PhonePlace("c:k.nobody", in: book).selection, "an unknown key is the list of places")
        XCTAssertNil(PhonePlace("t:@everyone", in: book).selection)
        XCTAssertEqual(PhonePlace(PhonePlace.key(.thread("made-up", in: .everyone)), in: book).selection, .channel(.everyone), "a thread nothing leads to is its channel")
    }

    func testANewTopicCarriesOnInItsThreadOnceItHasOne() {
        var book = book()
        book.started["sent-1"] = "a"
        let place = PhonePlace(PhonePlace.key(.thread("sent-1", in: .direct(steve))), in: book)
        XCTAssertEqual(place.selection, .thread("a", in: .direct(steve)))
        XCTAssertEqual(place.key, PhonePlace.key(.thread("a", in: .direct(steve))), "so the phone moves along too")
    }

    // MARK: - Sending

    func testWordsGoWhereTheWindowWouldSendThem() throws {
        let book = book()
        let everyone = try XCTUnwrap(ask("send", key: "everyone", text: " What's up? ").action(in: book) { "topic" })
        XCTAssertEqual(everyone.action, .send("What's up?", to: .router, shownIn: .everyone))

        let dm = try XCTUnwrap(ask("send", key: PhonePlace.key(.channel(.direct(steve))), text: "New idea").action(in: book) { "sent-9" })
        XCTAssertEqual(dm.action, .startTopic("New idea", with: steve, id: "sent-9"), "a DM's box starts a new topic")
        XCTAssertEqual(dm.opens, PhonePlace.key(.thread("sent-9", in: .direct(steve))), "which the phone opens")

        let thread = try XCTUnwrap(ask("send", key: PhonePlace.key(.thread("a", in: .direct(steve))), text: "And then?").action(in: book) { "x" })
        XCTAssertEqual(thread.action, .send("And then?", to: .thread(id: "a", title: "Work"), shownIn: .direct(steve)))
    }

    func testAPhoneCantSendAnywhereTheWindowCouldnt() {
        let book = book(sentBetween: true)
        let refused = [
            ask("send", key: PhonePlace.key(.thread("made-up", in: .direct(steve))), text: "Hi"),
            ask("send", key: PhonePlace.key(.thread("p", in: .direct(pepper))), text: "Hi"),
            ask("send", key: PhonePlace.key(.channel(ChannelID(.kitten(steve.id), .kitten(pepper.id))!)), text: "Hi"),
            ask("send", key: "needs", text: "Hi"),
            ask("send", key: "home", text: "Hi"),
            ask("send", key: "everyone", text: "   "),
            ask("send", key: "everyone"),
            ask("send", text: "Hi"),
            ask("speak", key: "everyone", text: "Hi"),
        ]
        for ask in refused {
            XCTAssertNil(ask.action(in: book) { "x" }, "\(ask.act) \(ask.key ?? "nil") \(ask.text ?? "nil")")
        }
    }

    func testAPhoneCantOpenAThreadNothingInTheWindowLeadsTo() {
        // Some other project of yours: no kitten's, not Shades' work, and never in Everyone. T3 lists it all the same.
        let other = AgentThread(id: "other", title: "Deploy billing", projectTitle: "billing", status: .completed, model: "m", updatedAt: noon, projectPath: "/elsewhere/billing")
        let book = ChannelBook.build(
            kittens: [steve, pepper],
            threads: [thread("a", of: steve), thread("p", of: pepper), other],
            transcripts: ["a": [Exchange(id: "e1", asker: .you, askedAt: noon, ask: "How's it going?", reply: "Fine.", repliedAt: noon)]],
            isReading: false,
            unreadable: 0,
            cantReachT3: false
        )
        for selection in [ChannelSelection.thread("other", in: .everyone), .thread("p", in: .direct(steve))] {
            let key = PhonePlace.key(selection)
            XCTAssertNil(ask("send", key: key, text: "ship it").action(in: book) { "x" }, key)
            XCTAssertNotEqual(PhonePlace(key, in: book).selection, selection, "and it isn't shown there either")
        }
        XCTAssertNotNil(ask("send", key: PhonePlace.key(.thread("a", in: .everyone)), text: "And?").action(in: book) { "x" }, "a thread Everyone shows is still yours to carry on")
        XCTAssertNotNil(ask("send", key: PhonePlace.key(.thread("p", in: .direct(pepper))), text: "And?").action(in: book) { "x" }, "and so is one on a kitten's list of what it's on")
    }

    func testAReplyToAReportGoesUnderItEvenFromElsewhere() throws {
        let report = InboxEntry(id: "r1", kind: .decision, text: "Ship it?", threadID: "p", threadTitle: "Pepper: Work", at: noon)
        let book = book(waiting: Waiting(reports: [report]), sentBetween: true)
        let reply = try XCTUnwrap(ask("send", key: PhonePlace.reply(to: report), text: "Yes").action(in: book) { "x" })
        XCTAssertEqual(reply.action, .send("Yes", to: .thread(id: "p", title: "Work", report: "r1"), shownIn: .direct(pepper)))
        XCTAssertNil(ask("send", key: "r:gone", text: "Yes").action(in: book) { "x" }, "a report that's gone is Needs you, which has no box")
    }

    // MARK: - Approvals, questions and the inbox

    func testOnlyAnApprovalThatsWaitingCanBeAnswered() throws {
        let command = ApprovalRequest(id: "ap", threadID: "a", threadTitle: "Work", kind: .command, summary: "Run: ls", createdAt: noon)
        let permission = ApprovalRequest(id: "perm", threadID: "a", threadTitle: "Work", kind: .permission, summary: "Full access", createdAt: noon)
        let book = book(waiting: Waiting(approvals: [command, permission]))
        XCTAssertEqual(ask("approval", id: "ap", value: "accept").action(in: book) { "x" }?.action, .approval(command, .accept))
        XCTAssertEqual(ask("approval", id: "ap", value: "acceptForSession").action(in: book) { "x" }?.action, .approval(command, .acceptForSession))
        XCTAssertEqual(ask("approval", id: "perm", value: "decline").action(in: book) { "x" }?.action, .approval(permission, .decline))
        XCTAssertNil(ask("approval", id: "perm", value: "acceptForSession").action(in: book) { "x" }, "the window doesn't offer it for this kind")
        XCTAssertNil(ask("approval", id: "made-up", value: "accept").action(in: book) { "x" })
        XCTAssertNil(ask("approval", id: "ap", value: "always").action(in: book) { "x" })
        XCTAssertNil(ask("approval", id: "ap").action(in: book) { "x" })
    }

    func testAnAnswerHasToFitEveryPartOfTheQuestion() throws {
        let form = AnswerForm(parts: [
            AnswerForm.Part(key: "month", text: "Which month?", options: ["June", "July"], values: ["6", "7"], takesOwnWords: false),
            AnswerForm.Part(key: "why", text: "Why?", options: [], values: [], takesOwnWords: true),
        ])
        let question = AgentQuestion(id: "q", threadID: "a", threadTitle: "Work", text: "Which month?", form: form)
        let unreadable = AgentQuestion(id: "u", threadID: "a", threadTitle: "Work", text: "Hmm?", form: nil)
        let book = book(waiting: Waiting(questions: [question, unreadable]))
        XCTAssertEqual(ask("answer", id: "q", answers: ["7", "It's warmer"]).action(in: book) { "x" }?.action, .answer(question, ["7", "It's warmer"]))
        XCTAssertNil(ask("answer", id: "q", answers: ["August", "It's warmer"]).action(in: book) { "x" }, "only its own choices where it doesn't take words")
        XCTAssertNil(ask("answer", id: "q", answers: ["7", " "]).action(in: book) { "x" })
        XCTAssertNil(ask("answer", id: "q", answers: ["7"]).action(in: book) { "x" }, "T3 takes every part at once")
        XCTAssertNil(ask("answer", id: "u", answers: ["Yes"]).action(in: book) { "x" }, "one Shades can't read is answered in T3")
        XCTAssertNil(ask("answer", id: "gone", answers: ["7", "x"]).action(in: book) { "x" })
    }

    func testTheInboxOnlyTakesWhatItsButtonsDo() {
        let decision = InboxEntry(id: "d", kind: .decision, text: "Ship it?", threadID: "a", threadTitle: "Work", at: noon)
        let shipped = InboxEntry(id: "s", kind: .shipped, text: "Live.", threadID: "a", threadTitle: "Work", at: noon)
        let book = book(waiting: Waiting(reports: [decision, shipped]))
        XCTAssertEqual(ask("done", id: "d").action(in: book) { "x" }?.action, .inbox(.done(id: "d")))
        XCTAssertNil(ask("done", id: "s").action(in: book) { "x" }, "only a decision has Done")
        XCTAssertEqual(ask("clear", kind: "shipped").action(in: book) { "x" }?.action, .inbox(.clear(.shipped)))
        XCTAssertNil(ask("clear", kind: "decision").action(in: book) { "x" }, "decisions aren't cleared in bulk")
        XCTAssertEqual(ask("seen", key: PhonePlace.key(.channel(.direct(steve)))).action(in: book) { "x" }?.action, .seen(.channel(.direct(steve))))
        XCTAssertNil(ask("seen", key: "home").action(in: book) { "x" })
    }

    // MARK: - The door

    func testOnlyTheCodeShowingPairsAndOnlyOnce() throws {
        let keys = MemoryPhoneKeys()
        let door = PhoneDoor(keys: keys)
        XCTAssertNil(door.pair("ABCDEFGH", now: noon), "nothing pairs until you ask for a code")
        let pairing = door.openPairing(now: noon)
        XCTAssertEqual(pairing.code.count, 8)
        let token = try XCTUnwrap(door.pair(pairing.shown.lowercased(), now: noon.addingTimeInterval(30)), "typed as shown, in any case")
        XCTAssertNil(door.pair(pairing.code, now: noon), "it works once")
        XCTAssertTrue(door.admits(request(key: "Bearer \(token)")))
        XCTAssertFalse(door.admits(request(key: "Bearer \(token)x")))
        XCTAssertFalse(door.admits(request(key: token)))
        XCTAssertEqual(keys.hashes.count, 1)
        XCTAssertFalse(keys.hashes[0].contains(token), "only a hash of it is kept")
        XCTAssertTrue(PhoneDoor(keys: keys).admits(request(key: "Bearer \(token)")), "and it still works after a restart")
        door.forgetPhones()
        XCTAssertFalse(door.admits(request(key: "Bearer \(token)")))
        XCTAssertEqual(keys.hashes, [])
    }

    func testGuessingUsesTheCodeUpAndItRunsOut() {
        let door = PhoneDoor(keys: MemoryPhoneKeys())
        var pairing = door.openPairing(now: noon)
        for _ in 0..<5 { XCTAssertNil(door.pair("WRONGONE", now: noon)) }
        XCTAssertNil(door.pair(pairing.code, now: noon), "five wrong tries and the code is gone")
        pairing = door.openPairing(now: noon)
        XCTAssertNil(door.pair(pairing.code, now: noon.addingTimeInterval(601)), "and ten minutes on it's gone too")
    }

    private func request(key: String) -> PhoneServer.Request {
        PhoneServer.Request(method: "GET", path: "/events", query: [:], headers: ["authorization": key], body: Data())
    }

    // MARK: - What it shows

    func testThePhoneSeesWhatTheWindowShows() throws {
        let command = ApprovalRequest(id: "ap", threadID: "a", threadTitle: "Steve Pawsniak: Work", kind: .command, summary: "Run: ls", createdAt: noon)
        var waiting = Waiting(approvals: [command])
        waiting.owners["ap"] = steve.id
        let book = book(waiting: waiting)

        let home = PhoneView(PhonePlace("home", in: book), in: book, now: noon)
        XCTAssertEqual(home.places.map(\.title), ["Needs you", "Everyone", "Done", "Steve Pawsniak", "Pepper"])
        XCTAssertEqual(home.places[0].count, 1)
        XCTAssertNil(home.box)
        XCTAssertEqual(home.rows, [])

        let dm = PhoneView(PhonePlace(PhonePlace.key(.channel(.direct(steve))), in: book), in: book, now: noon)
        XCTAssertEqual(dm.rows.map(\.kind), ChannelRows.rows(.channel(.direct(steve)), in: book).map(Self.kind), "row for row")
        XCTAssertEqual(dm.rows.compactMap(\.text).filter { $0 == "Fine." || $0 == "How's it going?" }, ["How's it going?", "Fine."])
        XCTAssertEqual(dm.box, PhoneView.Box(label: "New topic with Steve Pawsniak", placeholder: "Start a new topic"))
        XCTAssertEqual(dm.rows.last?.choices?.map(\.value), ["decline", "accept", "acceptForSession"], "Deny first, as in the window")
        XCTAssertEqual(dm.rows.first { $0.kind == "subject" }?.open, PhonePlace.key(.thread("a", in: .direct(steve))))
        XCTAssertEqual(dm.back, "home")
    }

    func testAQuestionIsAnsweredFromItsCardNotTheBox() {
        let form = AnswerForm(parts: [AnswerForm.Part(key: "why", text: "Why?", options: [], values: [], takesOwnWords: true)])
        let question = AgentQuestion(id: "q", threadID: "a", threadTitle: "Work", text: "Why?", form: form)
        var waiting = Waiting(questions: [question])
        waiting.owners["q"] = steve.id
        let book = book(waiting: waiting)
        let place = PhonePlace(PhonePlace.key(.thread("a", in: .direct(steve))), in: book)
        XCTAssertNil(place.target, "so every part goes at once")
        XCTAssertEqual(PhoneView(place, in: book, now: noon).rows.last?.parts, [PhoneView.Part(text: "Why?", choices: [], words: true)])
    }

    private static func kind(_ row: ChannelRow) -> String {
        switch row {
        case .day: return "day"
        case .subject: return "subject"
        case .message: return "message"
        case .section: return "section"
        case .heading: return "heading"
        case .issue: return "issue"
        case .approval: return "approval"
        case .question: return "question"
        case .report: return "report"
        case .note: return "note"
        }
    }
}
