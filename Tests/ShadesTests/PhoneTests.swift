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
        // A thread of Pepper's that Steve started, which is a thread in Pepper's channel with Steve's ask as its parent.
        if sentBetween { transcripts["p"] = [Exchange(id: "e2", asker: .agent(threadID: "a"), askedAt: noon, ask: "Numbers?", reply: "Here.", repliedAt: noon)] }
        for thread in also { transcripts[thread.id] = [Exchange(id: "e-\(thread.id)", asker: .you, askedAt: noon, ask: "Also", reply: "Yes.", repliedAt: noon)] }
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
            .activity, .threads, .channel(.general), .channel(.of(pepper)), .channel(.of(steve)),
            .thread("a/b@c", in: .channel(.of(pepper))),
            .thread("p", in: .channel(.of(pepper))),
            .thread("a", in: .channel(.of(steve))),
            .thread("a", in: .threads),
        ]
        for selection in places {
            let key = PhonePlace.key(selection)
            XCTAssertEqual(PhonePlace(key, in: book).selection, selection, key)
        }
        XCTAssertNil(PhonePlace("home", in: book).selection)
        XCTAssertNil(PhonePlace("c:nobody", in: book).selection, "an unknown key is the list of places")
        XCTAssertNil(PhonePlace("t:@general", in: book).selection)
        XCTAssertEqual(PhonePlace(PhonePlace.key(.thread("made-up", in: .channel(.general))), in: book).selection, .channel(.general), "a thread nothing leads to is its place")
        XCTAssertEqual(PhonePlace("needs", in: book).selection, .activity, "a page still open from before")
        XCTAssertEqual(PhonePlace("everyone", in: book).selection, .channel(.general))
    }

    func testANewTopicCarriesOnInItsThreadOnceItHasOne() {
        var book = book()
        book.started["sent-1"] = "a"
        let place = PhonePlace(PhonePlace.key(.thread("sent-1", in: .channel(.of(steve)))), in: book)
        XCTAssertEqual(place.selection, .thread("a", in: .channel(.of(steve))))
        XCTAssertEqual(place.key, PhonePlace.key(.thread("a", in: .channel(.of(steve)))), "so the phone moves along too")
    }

    // MARK: - Sending

    func testWordsGoWhereTheWindowWouldSendThem() throws {
        let book = book()
        let general = try XCTUnwrap(ask("send", key: "general", text: " What's up? ").action(in: book) { "topic" })
        XCTAssertEqual(general.action, .send("What's up?", to: .router, shownIn: .general))

        let channel = try XCTUnwrap(ask("send", key: PhonePlace.key(.channel(.of(steve))), text: "New idea").action(in: book) { "sent-9" })
        XCTAssertEqual(channel.action, .startTopic("New idea", with: steve, id: "sent-9"), "a kitten's channel starts a new thread")
        XCTAssertEqual(channel.opens, PhonePlace.key(.thread("sent-9", in: .channel(.of(steve)))), "which the phone opens")

        let thread = try XCTUnwrap(ask("send", key: PhonePlace.key(.thread("a", in: .channel(.of(steve)))), text: "And then?").action(in: book) { "x" })
        XCTAssertEqual(thread.action, .send("And then?", to: .thread(id: "a", title: "Work"), shownIn: .of(steve)))

        var alsoSent = ask("send", key: PhonePlace.key(.thread("a", in: .threads)), text: "Keep the FAQ")
        alsoSent.also = true
        XCTAssertEqual(alsoSent.action(in: book) { "x" }?.action, .send("Keep the FAQ", to: .thread(id: "a", title: "Work"), shownIn: .of(steve), alsoSent: true), "Also send to its channel, from Threads too")
        var general2 = ask("send", key: "general", text: "Hi")
        general2.also = true
        XCTAssertEqual(general2.action(in: book) { "x" }?.action, .send("Hi", to: .router, shownIn: .general), "only a thread's reply can be also sent")
    }

    func testAPhoneCantSendAnywhereTheWindowCouldnt() {
        let book = book(sentBetween: true)
        let refused = [
            ask("send", key: PhonePlace.key(.thread("made-up", in: .channel(.of(steve)))), text: "Hi"),
            ask("send", key: PhonePlace.key(.thread("p", in: .channel(.of(steve)))), text: "Hi"),
            ask("send", key: "activity", text: "Hi"),
            ask("send", key: "threads", text: "Hi"),
            ask("send", key: "shades", text: "Hi"),
            ask("send", key: "home", text: "Hi"),
            ask("send", key: "general", text: "   "),
            ask("send", key: "general"),
            ask("send", text: "Hi"),
            ask("speak", key: "general", text: "Hi"),
        ]
        for ask in refused {
            XCTAssertNil(ask.action(in: book) { "x" }, "\(ask.act) \(ask.key ?? "nil") \(ask.text ?? "nil")")
        }
    }

    func testAPhoneOnlyReachesAThreadTheWindowLeadsTo() {
        // Some other project of yours: no kitten's, not Shades' work, and never in #general. T3 lists it all the same.
        let other = AgentThread(id: "other", title: "Deploy billing", projectTitle: "billing", status: .completed, model: "m", updatedAt: noon, projectPath: "/elsewhere/billing")
        var working = thread("w", of: pepper)
        working.status = .running
        let book = ChannelBook.build(
            kittens: [steve, pepper],
            threads: [thread("a", of: steve), thread("p", of: pepper), other, working],
            transcripts: [
                "a": [Exchange(id: "e1", asker: .you, askedAt: noon, ask: "How's it going?", reply: "Fine.", repliedAt: noon)],
                "p": [Exchange(id: "e2", asker: .agent(threadID: "a"), askedAt: noon, ask: "Numbers?", reply: "Here.", repliedAt: noon)],
            ],
            isReading: false,
            unreadable: 0,
            cantReachT3: false
        )
        let nowhere: [ChannelSelection] = [
            .thread("other", in: .channel(.general)),
            .thread("other", in: .activity),
            .thread("p", in: .channel(.of(steve))),
            .thread("p", in: .threads),
            .thread("a", in: .channel(.of(pepper))),
            .thread("a", in: .activity),
        ]
        for selection in nowhere {
            let key = PhonePlace.key(selection)
            XCTAssertNil(ask("send", key: key, text: "ship it").action(in: book) { "x" }, key)
            XCTAssertEqual(PhonePlace(key, in: book).selection, selection.closed, "and it's only the place: \(key)")
        }
        let leads: [ChannelSelection] = [
            .thread("a", in: .channel(.of(steve))),
            .thread("a", in: .threads),
            .thread("p", in: .channel(.of(pepper))),
            .thread("w", in: .activity),
        ]
        for selection in leads {
            XCTAssertEqual(PhonePlace(PhonePlace.key(selection), in: book).selection, selection, PhonePlace.key(selection))
        }
        XCTAssertNotNil(ask("send", key: PhonePlace.key(.thread("p", in: .channel(.of(pepper)))), text: "And?").action(in: book) { "x" }, "a thread Pepper's channel shows is yours to reply in")
        XCTAssertTrue(PhonePlace.leadsTo("w", from: .activity, in: book), "what's in progress")

        let approval = ApprovalRequest(id: "ap", threadID: "a", threadTitle: "Work", kind: .command, summary: "Run: ls", createdAt: noon)
        let waiting = ChannelBook.build(kittens: [steve, pepper], threads: [thread("a", of: steve)], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false, waiting: Waiting(approvals: [approval]))
        XCTAssertTrue(PhonePlace.leadsTo("a", from: .activity, in: waiting), "and what's waiting on you")
    }

    func testAReplyToAReportGoesUnderItEvenFromElsewhere() throws {
        let report = InboxEntry(id: "r1", kind: .decision, text: "Ship it?", threadID: "p", threadTitle: "Pepper: Work", at: noon)
        let book = book(waiting: Waiting(reports: [report]), sentBetween: true)
        let reply = try XCTUnwrap(ask("send", key: PhonePlace.reply(to: report), text: "Yes").action(in: book) { "x" })
        XCTAssertEqual(reply.action, .send("Yes", to: .thread(id: "p", title: "Work", report: "r1"), shownIn: .of(pepper)))
        XCTAssertEqual(PhonePlace(PhonePlace.reply(to: report), in: book).selection, .thread("p", in: .activity))
        XCTAssertNil(ask("send", key: "r:gone", text: "Yes").action(in: book) { "x" }, "a report that's gone is Activity, which has no box")
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
        XCTAssertEqual(ask("seen", key: PhonePlace.key(.channel(.of(steve)))).action(in: book) { "x" }?.action, .seen(.channel(.of(steve))))
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
    }

    func testGuessingUsesTheCodeUpAndItRunsOut() {
        let door = PhoneDoor(keys: MemoryPhoneKeys())
        var pairing = door.openPairing(now: noon)
        for _ in 0..<5 { XCTAssertNil(door.pair("WRONGONE", now: noon)) }
        XCTAssertNil(door.pair(pairing.code, now: noon), "five wrong tries and the code is gone")
        pairing = door.openPairing(now: noon)
        XCTAssertNil(door.pair(pairing.code, now: noon.addingTimeInterval(601)), "and ten minutes on it's gone too")
    }

    func testThePageTakesMessagesThemeAsColoursAlone() {
        XCTAssertEqual(PhonePage.colors(nil), "")
        let theme = ColorTheme(name: "Opal; } body { display: none } :root {", isDark: true, paper: 0x0c0a10, text: 0xe7e4ec, accent: 0x7458e8)
        let css = PhonePage.colors(theme)
        for line in ["color-scheme: dark", "--paper: #0c0a10", "--text: #e7e4ec", "--you: #7458e8", "--grey: \(ColorTheme.hex(theme.bubble))", "--on-you: #"] {
            XCTAssertTrue(css.contains(line), line)
        }
        XCTAssertFalse(css.contains("display"), "only colours worked out on the Mac, never the theme's own words")
        XCTAssertTrue(PhonePage.style.contains("--on-you: #ffffff"), "and without one, the page's own")
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
        XCTAssertEqual(home.places.map(\.title), ["Activity", "Threads", "#general", "#steve-pawsniak", "#pepper"])
        XCTAssertEqual(home.places.map(\.group), [nil, nil, CatWords.channelsHeading, CatWords.channelsHeading, CatWords.channelsHeading])
        XCTAssertEqual(home.places[0].count, 1)
        XCTAssertEqual(home.places[3].count, 1, "Steve's channel has its badge")
        XCTAssertNil(home.box)
        XCTAssertEqual(home.rows, [])

        let channel = PhoneView(PhonePlace(PhonePlace.key(.channel(.of(steve))), in: book), in: book, now: noon)
        XCTAssertEqual(channel.rows.map(\.kind), ChannelRows.rows(.channel(.of(steve)), in: book).map(Self.kind), "row for row")
        let parent = try XCTUnwrap(channel.rows.first { $0.kind == "parent" })
        XCTAssertEqual(parent.text, "How's it going?")
        XCTAssertEqual(parent.replies, 1)
        XCTAssertEqual(parent.waiting, true, "it says it needs you")
        XCTAssertEqual(parent.open, PhonePlace.key(.thread("a", in: .channel(.of(steve)))))
        XCTAssertFalse(channel.rows.contains { $0.text == "Fine." }, "replies stay in their thread")
        XCTAssertEqual(channel.box, PhoneView.Box(label: "Starts a new thread with Steve Pawsniak", placeholder: "Message #steve-pawsniak"))
        XCTAssertEqual(channel.back, "home")

        let thread = PhoneView(PhonePlace(PhonePlace.key(.thread("a", in: .channel(.of(steve)))), in: book), in: book, now: noon)
        XCTAssertEqual(thread.rows.map(\.kind), ChannelRows.thread("a", in: book).map(Self.kind))
        XCTAssertEqual(thread.rows.compactMap(\.text).filter { $0 == "Fine." || $0 == "How's it going?" }, ["How's it going?", "Fine."])
        XCTAssertEqual(thread.rows.last?.choices?.map(\.value), ["decline", "accept", "acceptForSession"], "Deny first, as in the window")
        XCTAssertEqual(thread.box?.also, "Also send to #steve-pawsniak")
        XCTAssertEqual(thread.title, CatWords.threadTitle)
        XCTAssertEqual(thread.back, PhonePlace.key(.channel(.of(steve))))
        XCTAssertEqual(thread.backTitle, "#steve-pawsniak")
    }

    func testThreadsOnThePhoneListsWhatYouWroteInAndOpensEachOnItsOwnPage() throws {
        let book = book(sentBetween: true)
        let threads = PhoneView(PhonePlace("threads", in: book), in: book, now: noon)
        XCTAssertEqual(threads.rows.map(\.kind), ["digest"])
        let digest = try XCTUnwrap(threads.rows.first)
        XCTAssertEqual(digest.title, "#steve-pawsniak")
        XCTAssertEqual(digest.text, "How's it going?")
        XCTAssertEqual(digest.reply?.text, "Fine.")
        XCTAssertEqual(digest.open, PhonePlace.key(.thread("a", in: .threads)))
        XCTAssertNil(threads.box)
    }

    func testAQuestionIsAnsweredFromItsCardNotTheBox() {
        let form = AnswerForm(parts: [AnswerForm.Part(key: "why", text: "Why?", options: [], values: [], takesOwnWords: true)])
        let question = AgentQuestion(id: "q", threadID: "a", threadTitle: "Work", text: "Why?", form: form)
        var waiting = Waiting(questions: [question])
        waiting.owners["q"] = steve.id
        let book = book(waiting: waiting)
        let place = PhonePlace(PhonePlace.key(.thread("a", in: .channel(.of(steve)))), in: book)
        XCTAssertNil(place.target, "so every part goes at once")
        XCTAssertEqual(PhoneView(place, in: book, now: noon).rows.last?.parts, [PhoneView.Part(text: "Why?", choices: [], words: true)])
    }

    private static func kind(_ row: ChannelRow) -> String {
        switch row {
        case .day: return "day"
        case .parent: return "parent"
        case .message, .alsoSent: return "message"
        case .digest: return "digest"
        case .replies: return "replies"
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

// MARK: - Talking to the cat

extension PhoneTests {
    func testWhatYouAskedTheCatStaysOnTheMac() {
        let book = book()
        XCTAssertFalse(PhoneView(PhonePlace("home", in: book), in: book, now: Date()).places.contains { $0.key == PhonePlace.key(.channel(.shades)) }, "it can be about your screen")
        XCTAssertNil(PhonePlace(PhonePlace.key(.channel(.shades)), in: book).selection, "and a link to it is the list of places")
        XCTAssertNil(PhonePlace(PhonePlace.key(.thread("r", in: .channel(.shades))), in: book).selection)
        XCTAssertNil(PhonePlace("shades", in: book).selection)
    }
}
