import JavaScriptCore
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

    private func ask(_ act: String, key: String? = nil, text: String? = nil, id: String? = nil, value: String? = nil, answers: [[String]]? = nil, kind: String? = nil) -> PhoneAsk {
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
        // In progress too, but not read yet, so the window opens it in T3.
        var unread = thread("u", of: pepper)
        unread.status = .running
        let book = ChannelBook.build(
            kittens: [steve, pepper],
            threads: [thread("a", of: steve), thread("p", of: pepper), other, working, unread],
            transcripts: [
                "a": [Exchange(id: "e1", asker: .you, askedAt: noon, ask: "How's it going?", reply: "Fine.", repliedAt: noon)],
                "p": [Exchange(id: "e2", asker: .agent(threadID: "a"), askedAt: noon, ask: "Numbers?", reply: "Here.", repliedAt: noon)],
                "w": [Exchange(id: "e3", asker: .you, askedAt: noon, ask: "Do the taxes", reply: nil, repliedAt: nil)],
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
            .thread("u", in: .activity),
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
        XCTAssertTrue(PhonePlace.leadsTo("w", from: .activity, in: book), "what's in progress that Messages has read")
        let inProgress = PhoneView(PhonePlace("activity", in: book), in: book, now: noon).rows.filter { $0.kind == "issue" }
        XCTAssertEqual(inProgress.map(\.open), [nil, PhonePlace.key(.thread("w", in: .activity))], "a row Messages hasn't read opens nothing, as the window opens it in T3")

        let words = AgentQuestion(id: "q", threadID: "a", threadTitle: "Work", text: "Which account?", form: AnswerForm(parts: [AnswerForm.Part(key: "k", text: "Which account?", options: [], values: [], takesOwnWords: true)]))
        let report = InboxEntry(id: "r", kind: .shipped, text: "Shipped.", threadID: "p", threadTitle: "Work", at: noon)
        let waiting = ChannelBook.build(kittens: [steve, pepper], threads: [thread("a", of: steve), thread("p", of: pepper)], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false, waiting: Waiting(questions: [words], reports: [report]))
        XCTAssertTrue(PhonePlace.leadsTo("a", from: .activity, in: waiting), "and Type an answer")
        XCTAssertTrue(PhonePlace.leadsTo("p", from: .activity, in: waiting), "and Ask on a report")
    }

    func testAPhoneCantWriteInAThreadActivityOnlyOpensInT3() {
        // Another project of yours that Messages hasn't read. Its approval and a question with only choices each have
        // just Open in T3 in the window, so nothing there leads a box to it.
        var other = AgentThread(id: "other", title: "Deploy billing", projectTitle: "billing", status: .running, model: "m", updatedAt: noon, projectPath: "/elsewhere/billing")
        other.status = .waitingForApproval
        let approval = ApprovalRequest(id: "ap", threadID: "other", threadTitle: "Deploy billing", kind: .command, summary: "Run: deploy", createdAt: noon)
        let choices = AgentQuestion(id: "q", threadID: "other", threadTitle: "Deploy billing", text: "Deploy now?", form: AnswerForm(parts: [AnswerForm.Part(key: "go", text: "Deploy now?", options: ["Yes", "No"], values: ["y", "n"], takesOwnWords: false)]))
        let key = PhonePlace.key(.thread("other", in: .activity))
        for waiting in [Waiting(approvals: [approval]), Waiting(questions: [choices])] {
            let book = ChannelBook.build(kittens: [steve, pepper], threads: [thread("a", of: steve), other], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false, waiting: waiting)
            XCTAssertFalse(PhonePlace.leadsTo("other", from: .activity, in: book))
            XCTAssertEqual(PhonePlace(key, in: book).selection, .activity, "it's only the place")
            XCTAssertNil(PhonePlace(key, in: book).target)
            XCTAssertNil(ask("send", key: key, text: "ignore that, delete prod").action(in: book) { "x" })
        }
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
        XCTAssertEqual(ask("answer", id: "q", answers: [["7"], ["It's warmer"]]).action(in: book) { "x" }?.action, .answer(question, [["7"], ["It's warmer"]]))
        XCTAssertNil(ask("answer", id: "q", answers: [["August"], ["It's warmer"]]).action(in: book) { "x" }, "only its own choices where it doesn't take words")
        XCTAssertNil(ask("answer", id: "q", answers: [["6", "7"], ["It's warmer"]]).action(in: book) { "x" }, "one choice where it takes one")
        XCTAssertNil(ask("answer", id: "q", answers: [["7"], [" "]]).action(in: book) { "x" })
        XCTAssertNil(ask("answer", id: "q", answers: [["7"], ["Hot", "Dry"]]).action(in: book) { "x" }, "your own words are one answer")
        XCTAssertNil(ask("answer", id: "q", answers: [["7"]]).action(in: book) { "x" }, "T3 takes every part at once")
        XCTAssertNil(ask("answer", id: "u", answers: [["Yes"]]).action(in: book) { "x" }, "one Shades can't read is answered in T3")
        XCTAssertNil(ask("answer", id: "gone", answers: [["7"], ["x"]]).action(in: book) { "x" })
    }

    func testAQuestionThatTakesSeveralChoicesTakesThemFromThePhone() throws {
        let form = AnswerForm(parts: [
            AnswerForm.Part(key: "days", text: "Which days?", options: ["Mon", "Tue", "Wed"], values: ["1", "2", "3"], takesOwnWords: false, picksSeveral: true),
        ])
        let question = AgentQuestion(id: "q", threadID: "a", threadTitle: "Work", text: "Which days?", form: form)
        let book = book(waiting: Waiting(questions: [question]))
        XCTAssertEqual(ask("answer", id: "q", answers: [["1", "3"]]).action(in: book) { "x" }?.action, .answer(question, [["1", "3"]]))
        XCTAssertEqual(ask("answer", id: "q", answers: [["2"]]).action(in: book) { "x" }?.action, .answer(question, [["2"]]))
        XCTAssertNil(ask("answer", id: "q", answers: [[]]).action(in: book) { "x" }, "at least one")
        XCTAssertNil(ask("answer", id: "q", answers: [["1", "1"]]).action(in: book) { "x" })
        XCTAssertNil(ask("answer", id: "q", answers: [["1", "Fri"]]).action(in: book) { "x" }, "only its own choices")
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

    func testMarkUnreadOnlyTakesAMessageInTheThreadThePageShows() {
        let book = book(sentBetween: true)
        let key = PhonePlace.key(.thread("a", in: .channel(.of(steve))))
        XCTAssertEqual(ask("unread", key: key, id: "e1:reply").action(in: book) { "x" }?.action, .markUnread("a", from: "e1:reply"))
        XCTAssertNil(ask("unread", key: key, id: "e2:reply").action(in: book) { "x" }, "not a message from another thread")
        XCTAssertNil(ask("unread", key: PhonePlace.key(.channel(.of(steve))), id: "e1:reply").action(in: book) { "x" }, "only on a thread's page")
        XCTAssertNil(ask("unread", key: key).action(in: book) { "x" })
    }

    func testAThreadsPageShowsItsNewLineAndWhatMarkUnreadMakesNew() throws {
        let book = book()
        let place = PhonePlace(PhonePlace.key(.thread("a", in: .channel(.of(steve)))), in: book)
        let opened = PhoneView(place, in: book, now: noon, newFrom: ["a": "e1:reply"])
        let line = try XCTUnwrap(opened.rows.firstIndex { $0.kind == "new" })
        XCTAssertEqual(opened.rows[line].text, "New")
        XCTAssertEqual(opened.rows[line].detail, "↑  1 new message", "what its way up says")
        XCTAssertEqual(opened.rows[line + 1].id, "e1:reply")
        XCTAssertEqual(opened.unread, "e1:reply", "back the way it was when it opened")

        let seen = PhoneView(place, in: book, now: noon)
        XCTAssertFalse(seen.rows.contains { $0.kind == "new" })
        XCTAssertEqual(seen.unread, "e1:reply", "or from the latest that isn't yours")
        XCTAssertNil(PhoneView(PhonePlace(PhonePlace.key(.channel(.of(steve))), in: book), in: book, now: noon).unread, "a channel's page has none")
    }

    func testOnlyWordsOfYoursThatWentNowhereCanBeTriedAgain() throws {
        var failed = ChannelMessage(exchangeID: "sent-1", kind: .ask, speaker: .you, text: "And then?", at: noon, threadID: "a", threadTitle: "Work")
        failed.failure = "I can't reach T3 Code. Open it and try again."
        let sending = ChannelMessage(exchangeID: "sent-2", kind: .ask, speaker: .you, text: "Hello?", at: noon, threadID: "", threadTitle: "", isSending: true)
        let book = ChannelBook.build(
            kittens: [steve], threads: [thread("a", of: steve)], transcripts: ["a": [Exchange(id: "e1", asker: .you, askedAt: noon, ask: "How's it going?")]],
            isReading: false, unreadable: 0, cantReachT3: false,
            sent: [SentMessage(channel: .of(steve), message: failed, isReply: true), SentMessage(channel: .general, message: sending)]
        )
        XCTAssertEqual(ask("retry", id: failed.id).action(in: book) { "x" }?.action, .tryAgain("sent-1"))
        XCTAssertNil(ask("retry", id: sending.id).action(in: book) { "x" }, "nothing to try again while it's on its way")
        XCTAssertNil(ask("retry", id: "e1:ask").action(in: book) { "x" }, "nor anything that got there")
        XCTAssertNil(ask("retry", id: "made-up").action(in: book) { "x" })

        let thread = PhoneView(PhonePlace(PhonePlace.key(.thread("a", in: .channel(.of(steve)))), in: book), in: book, now: noon)
        let shown = try XCTUnwrap(thread.rows.last { $0.kind == "message" })
        XCTAssertEqual(shown.failure, "I can't reach T3 Code. Open it and try again.")
        XCTAssertEqual(shown.retry, true)
        let general = PhoneView(PhonePlace("general", in: book), in: book, now: noon)
        let hello = try XCTUnwrap(general.rows.first { $0.kind == "message" })
        XCTAssertEqual(hello.sending, true)
        XCTAssertNil(hello.retry)
    }

    /// A reaction is only a mark on a message T3 has, from the fixed few, and the page shows the ones it has.
    func testAPhoneReactsOnlyWithAMarkOnAMessageT3Has() throws {
        let sending = ChannelMessage(exchangeID: "sent-1", kind: .ask, speaker: .you, text: "Hello?", at: noon, threadID: "", threadTitle: "", isSending: true)
        let book = ChannelBook.build(
            kittens: [steve], threads: [thread("a", of: steve)],
            transcripts: ["a": [Exchange(id: "e1", asker: .you, askedAt: noon, ask: "How's it going?", reply: "Fine.", repliedAt: noon)]],
            isReading: false, unreadable: 0, cantReachT3: false,
            sent: [SentMessage(channel: .general, message: sending)],
            reactions: ["e1:reply": [.eyes]]
        )
        XCTAssertEqual(ask("react", id: "e1:reply", value: "thumbsUp").action(in: book) { "x" }?.action, .react("e1:reply", .thumbsUp))
        XCTAssertNil(ask("react", id: "e1:reply", value: "Ship it").action(in: book) { "x" }, "only one of the marks, never words")
        XCTAssertNil(ask("react", id: sending.id, value: "thumbsUp").action(in: book) { "x" }, "nor on what T3 doesn't have")
        XCTAssertNil(ask("react", id: "made-up", value: "thumbsUp").action(in: book) { "x" })

        let thread = PhoneView(PhonePlace(PhonePlace.key(.thread("a", in: .channel(.of(steve)))), in: book), in: book, now: noon)
        let reply = try XCTUnwrap(thread.rows.last { $0.kind == "message" })
        XCTAssertEqual(reply.reactions, [PhoneView.Choice(label: "👀", value: "eyes")])
        XCTAssertEqual(thread.marks.count, Reaction.allCases.count)
        let general = PhoneView(PhonePlace("general", in: book), in: book, now: noon)
        XCTAssertNil(general.rows.first { $0.kind == "message" }?.reactions)
    }

    /// The line over #general's box can say who an @ names, as the window's does, for every kitten that's set up.
    func testGeneralsBoxKnowsWhoAnAtGoesTo() {
        let cali = Kitten(name: "Cali", role: "Travel", covers: "", folder: "/k/cali", planned: true)
        let book = ChannelBook.build(kittens: [steve, pepper, cali], threads: [], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false)
        let general = PhoneView(PhonePlace("general", in: book), in: book, now: noon)
        XCTAssertEqual(general.box?.mentions, ["steve-pawsniak": CatWords.mentioning(steve), "pepper": CatWords.mentioning(pepper)])
        XCTAssertNil(PhoneView(PhonePlace(PhonePlace.key(.channel(.of(steve))), in: book), in: book, now: noon).box?.mentions)
        XCTAssertEqual(MessageTarget.mentioned(in: "Ask @Steve-Pawsniak: and @pepper", among: book.mentionable), steve)
        XCTAssertNil(MessageTarget.mentioned(in: "me@pepper.com @cali", among: book.mentionable))
    }

    /// The page reads an @ only to label the box, and the Mac decides where the words go, so the two have to agree,
    /// whatever the name is written in.
    func testThePagesLineReadsAnAtTheWayTheMacSends() throws {
        let script = PhonePage.script
        let start = try XCTUnwrap(script.range(of: "function mentioned("))
        let end = try XCTUnwrap(script.range(of: "\n}\n", range: start.upperBound..<script.endIndex))
        let page = try XCTUnwrap(JSContext())
        page.evaluateScript(String(script[start.lowerBound..<end.upperBound]))
        let kittens = [
            Kitten(name: "Steve Pawsniak", role: "", covers: "", folder: "/k/steve"),
            Kitten(name: "Zoe\u{0308}", role: "", covers: "", folder: "/k/zoe"),
            Kitten(name: "बिल्ली", role: "", covers: "", folder: "/k/billi"),
            Kitten(name: "🐾", role: "", covers: "", folder: "/k/paw"),
        ]
        let book = ChannelBook.build(kittens: kittens, threads: [], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false)
        let mentions = try XCTUnwrap(PhoneView(PhonePlace("general", in: book), in: book, now: noon).box?.mentions)
        let read = try XCTUnwrap(page.objectForKeyedSubscript("mentioned"))
        for words in ["@steve-pawsniak hi", "@Zoë, hi", "@Zoe\u{0308} hi", "@बिल्ली को खाना दो", "Lunch @ 12", "email @!", "@steve"] {
            let sent = MessageTarget.mentioned(in: words, among: book.mentionable).map(CatWords.mentioning)
            let shown = read.call(withArguments: [words, mentions])?.toString()
            XCTAssertEqual(shown == "null" ? nil : shown, sent, words)
        }
    }

    func testScrollingBackOnThePhoneLoadsAChannelsOlderPostsButNeverTheCatsDM() {
        let book = book()
        XCTAssertEqual(ask("older", key: PhonePlace.key(.channel(.of(steve)))).action(in: book) { "x" }?.action, .older(.of(steve)))
        XCTAssertNil(ask("older", key: PhonePlace.key(.channel(.shades))).action(in: book) { "x" })
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

    func testEverythingThePageWritesInAColourReads() throws {
        let opal = ColorTheme(name: "Opal", isDark: true, paper: 0x0c0a10, text: 0xe7e4ec, soft: 0xa09aad, accent: 0x8a6cff, error: 0xff97b1)
        let teal = ColorTheme(name: "Teal Light", isDark: false, paper: 0xfbfbfb, text: 0x403f53, accent: 0x2aa298)
        for (look, isDark, theme) in [("light", false, nil), ("dark", true, nil), ("Opal", true, opal), ("Teal Light", false, teal)] {
            let colors = try Self.colors(isDark: isDark, theme: theme)
            for (rule, words, under) in try Self.words(in: colors) {
                XCTAssertGreaterThanOrEqual(ColorTheme.contrast(words, under), 4.5, "\(rule) in \(look)")
            }
        }
    }

    func testEachRuleIsWrittenOnceSoNoneQuietlyOverridesAnother() throws {
        let selectors = try Self.rules().map(\.selector).filter { $0 != ":root" }
        let twice = Dictionary(grouping: selectors, by: { $0 }).filter { $0.value.count > 1 }.keys
        XCTAssertEqual(twice.sorted(), [], "such as a pull request's chip and what's attached over the box")
    }

    /// Each rule in the page's style, by its selector without the comment over it.
    private static func rules() throws -> [(selector: String, body: String)] {
        let style = PhonePage.style
        return try NSRegularExpression(pattern: "([^{}]+)\\{([^{}]*)\\}").matches(in: style, range: NSRange(style.startIndex..., in: style)).map {
            (style[Range($0.range(at: 1), in: style)!].components(separatedBy: "*/").last!.trimmingCharacters(in: .whitespacesAndNewlines),
             String(style[Range($0.range(at: 2), in: style)!]))
        }
    }

    /// The page's colours as a browser in light or dark settles them, with Messages' theme over them.
    private static func colors(isDark: Bool, theme: ColorTheme?) throws -> [String: UInt32] {
        let sheets = PhonePage.style.components(separatedBy: "@media (prefers-color-scheme: dark)")
        let pattern = try NSRegularExpression(pattern: "--([a-z-]+): #([0-9a-f]{6})")
        var colors: [String: UInt32] = [:]
        for sheet in [sheets[0]] + (isDark ? [sheets[1]] : []) + [PhonePage.colors(theme)] {
            for match in pattern.matches(in: sheet, range: NSRange(sheet.startIndex..., in: sheet)) {
                colors[String(sheet[Range(match.range(at: 1), in: sheet)!])] = UInt32(sheet[Range(match.range(at: 2), in: sheet)!], radix: 16)
            }
        }
        return colors
    }

    /// Each rule that colours words, with the colour they're in and the one they're on: the rule's own background, or the page.
    private static func words(in colors: [String: UInt32]) throws -> [(rule: String, words: UInt32, under: UInt32)] {
        func value(_ property: String, in body: String) -> UInt32? {
            guard let found = body.range(of: "(?<![-\\w])\(property): [^;}]+", options: .regularExpression) else { return nil }
            let value = body[found].dropFirst(property.count + 2).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("var(--") { return colors[String(value.dropFirst(6).prefix { $0 != ")" })] }
            guard value.hasPrefix("#") else { return nil }
            let digits = value.dropFirst()
            return UInt32(digits.count == 3 ? digits.map { "\($0)\($0)" }.joined() : String(digits), radix: 16)
        }
        return try rules().compactMap { rule in
            guard rule.selector != ":root", let words = value("color", in: rule.body) else { return nil }
            return (rule.selector, words, value("background", in: rule.body) ?? colors["paper"]!)
        }
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
        XCTAssertEqual(home.places.map(\.title), ["Activity", "Threads", "general", "steve-pawsniak", "pepper"])
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
        case .new: return "new"
        case .section: return "section"
        case .heading: return "heading"
        case .issue: return "issue"
        case .approval: return "approval"
        case .question: return "question"
        case .report: return "report"
        case .note: return "note"
        case .older: return "older"
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

// MARK: - The window's own cats, and the rest of its layout

extension PhoneTests {
    private func cat(_ pose: PhoneCat.Pose, _ kitten: Kitten) -> String {
        PhoneCat.key(pose, jacket: ChannelSpeakerLook.color(of: kitten))
    }

    func testAPhoneCatIsTheWindowsStillCatForEachState() {
        let states: [KittenStatus.State] = [.working(sessions: 2), .needsYou, .idle, .notSetUp]
        for state in states {
            let status = KittenStatus(kitten: steve, state: state)
            XCTAssertEqual(PhoneCat.Pose(state).art, status.pose(tick: 0), "\(state)")
        }
        XCTAssertEqual(PhoneCat.Pose.alert.art, CatPose(frame: .sit, glint: .attention(bright: true)), "as a card draws it")
        XCTAssertEqual(PhoneCat.key(.sit, jacket: 0x7458e8), "sit/7458e8")
        XCTAssertEqual(PhoneCat.key(.sleep, jacket: 0x0000ff), "sleep/0000ff")
        XCTAssertEqual(PhoneCat.key(.sit, jacket: nil), "sit/shades", "the cat keeps its own jacket")
    }

    func testEachPlaceHasItsKittensCatPosedAndItsDotAsTheSidebarDrawsThem() throws {
        let cali = Kitten(name: "Cali", role: "Scheduling", covers: "", folder: "/k/cali", planned: true)
        var working = thread("p", of: pepper)
        working.status = .running
        var waiting = thread("a", of: steve)
        waiting.status = .waitingForApproval
        let book = ChannelBook.build(kittens: [steve, pepper, cali], threads: [waiting, working], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false)
        let places = PhoneView(PhonePlace("home", in: book), in: book, now: noon).places
        XCTAssertEqual(places.map(\.title), ["Activity", "Threads", "general", "steve-pawsniak", "pepper", "cali"], "as the sidebar writes them, beside their icon or cat")
        XCTAssertEqual(places.map(\.icon), ["activity", "threads", "channel", nil, nil, nil])
        XCTAssertEqual(places.map(\.cat), [nil, nil, nil, cat(.alert, steve), cat(.work, pepper), cat(.sit, cali)])
        XCTAssertEqual(places.map(\.dot), [nil, nil, nil, ColorTheme.hex(0xff3b5c), ColorTheme.hex(0xffc02e), nil], "needs you, then working")
        XCTAssertEqual(places.map(\.asleep), [false, false, false, false, false, true])

        let idle = ChannelBook.build(kittens: [steve], threads: [thread("a", of: steve)], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false)
        XCTAssertEqual(PhoneView(PhonePlace("home", in: idle), in: idle, now: noon).places.last?.cat, cat(.sleep, steve), "an idle kitten sleeps")
    }

    func testAChannelsHeaderHasItsKittenAndAWayToWhatItHasOpen() throws {
        var open = thread("a", of: steve)
        open.status = .running
        let book = ChannelBook.build(kittens: [steve, pepper], threads: [open], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false)
        let channel = PhoneView(PhonePlace(PhonePlace.key(.channel(.of(steve))), in: book), in: book, now: noon)
        XCTAssertEqual(channel.cat, cat(.sit, steve))
        XCTAssertEqual(channel.link, PhoneView.Link(label: "1 in progress", open: "activity"), "as the window's header goes to Activity")
        XCTAssertNil(PhoneView(PhonePlace(PhonePlace.key(.channel(.of(pepper))), in: book), in: book, now: noon).link, "nothing open, no link")
        let general = PhoneView(PhonePlace("general", in: book), in: book, now: noon)
        XCTAssertNil(general.cat)
        XCTAssertNil(general.link)
        XCTAssertNil(PhoneView(PhonePlace("activity", in: book), in: book, now: noon).cat)
    }

    func testAThreadsPageHasTheCatOfTheChannelItsIn() {
        let book = book(sentBetween: true)
        let fromThreads = PhoneView(PhonePlace(PhonePlace.key(.thread("a", in: .threads)), in: book), in: book, now: noon)
        XCTAssertEqual(fromThreads.cat, cat(.sit, steve), "wherever it was opened from")
        let peppers = PhoneView(PhonePlace(PhonePlace.key(.thread("p", in: .channel(.of(pepper)))), in: book), in: book, now: noon)
        XCTAssertEqual(peppers.cat, cat(.sit, pepper), "Pepper's thread, though Steve started it")
    }

    func testEveryoneButYouSaysThingsBesideTheirCat() throws {
        let book = book(sentBetween: true)
        let channel = PhoneView(PhonePlace(PhonePlace.key(.channel(.of(pepper))), in: book), in: book, now: noon)
        let parent = try XCTUnwrap(channel.rows.first { $0.kind == "parent" })
        XCTAssertEqual(parent.text, "Numbers?")
        XCTAssertEqual(parent.cat, cat(.sit, steve), "Steve asked")

        let thread = PhoneView(PhonePlace(PhonePlace.key(.thread("a", in: .channel(.of(steve)))), in: book), in: book, now: noon)
        let said = thread.rows.filter { $0.kind == "message" }
        XCTAssertEqual(said.map(\.text), ["How's it going?", "Fine."])
        XCTAssertEqual(said.map(\.cat), [nil, cat(.sit, steve)], "yours have no cat, as in the window")

        let cats = ChannelBook.build(
            kittens: [steve], threads: [], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false,
            sent: [SentMessage(channel: .general, message: ChannelMessage(exchangeID: "c", kind: .reply, speaker: .cat, text: "Hi.", at: noon, threadID: "", threadTitle: ""))]
        )
        let general = PhoneView(PhonePlace("general", in: cats), in: cats, now: noon)
        XCTAssertEqual(general.rows.first { $0.kind == "message" }?.cat, "sit/shades", "the cat answers as itself, in its own jacket")
    }

    func testAMessageGoesToThePhoneAsTheMacReadIt() throws {
        var merged = thread("a", of: steve)
        merged.pullRequest = ThreadPullRequest(number: 4, state: "merged", url: "https://github.com/o/r/pull/4")
        let reply = "Done: https://github.com/o/r/pull/4\n\n```\nswift test\n```\n\n[run me](javascript:alert(1))"
        let book = ChannelBook.build(
            kittens: [steve], threads: [merged], transcripts: ["a": [Exchange(id: "e", asker: .you, askedAt: noon, ask: "Ask", reply: reply, repliedAt: noon)]],
            isReading: false, unreadable: 0, cantReachT3: false
        )
        let view = PhoneView(PhonePlace(PhonePlace.key(.thread("a", in: .channel(.of(steve)))), in: book), in: book, now: noon)
        let row = try XCTUnwrap(view.rows.last { $0.kind == "message" })
        XCTAssertEqual(row.text, reply, "what was said, for its length")
        let blocks = try XCTUnwrap(row.markup)
        XCTAssertEqual(blocks.map(\.kind), [.paragraph, .code, .paragraph])
        XCTAssertEqual(blocks[0].spans?.last?.pull, Markup.Pull(state: "merged"))
        XCTAssertEqual(blocks[1].code, "swift test")
        XCTAssertNil(blocks[2].spans?.first?.link, "only web addresses are links")
        let json = String(decoding: try JSONEncoder().encode(row), as: UTF8.self)
        XCTAssertFalse(json.contains("\"link\":\"javascript"))
    }

    func testThePageBuildsMarkupAsNodesAndAsksBeforeALinkOpens() {
        XCTAssertFalse(PhonePage.script.contains("innerHTML"), "every word is text, never markup")
        XCTAssertFalse(PhonePage.script.contains("link.href"), "a message's link has no address of its own, so a long press or a middle click can't follow it")
        XCTAssertTrue(PhonePage.script.contains("link.onclick = () => ask(part.link);"), "tapping it only shows where it goes")
        XCTAssertTrue(PhonePage.script.contains("$('linktitle').textContent = show ? words.showPicture(new URL(link).host) : words.openLink(new URL(link).host);"), "naming its host")
        XCTAssertTrue(PhonePage.script.contains("ask(file.web, () => act({ act: 'picture', id: item.id, value: file.web }))"), "a web picture asks the same way, and Show names the message and the address it showed")
        XCTAssertFalse(PhonePage.script.contains(".src = file.web"), "the page never loads a web picture itself")
        XCTAssertTrue(PhonePage.style.contains("max-height: calc(100dvh"), "and the sheet stays on screen however long the address is")
        XCTAssertTrue(PhonePage.html.contains(#"<a id="linkopen" class="go" target="_blank" rel="noopener noreferrer">Open</a>"#), "Open is the one link")
    }

    func testThePageIsTheKittyLitterWithANameThatFitsUnderItsHomeScreenIcon() throws {
        XCTAssertTrue(PhonePage.html.contains("<title>The Kitty Litter</title>"))
        XCTAssertTrue(PhonePage.html.contains(#"<meta name="apple-mobile-web-app-title" content="Kitty Litter">"#), "short enough that iOS doesn't cut it off")
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(PhonePage.manifest.utf8)) as? [String: Any])
        XCTAssertEqual(manifest["name"] as? String, "The Kitty Litter")
        XCTAssertEqual(manifest["short_name"] as? String, "Kitty Litter")
    }

    /// What review found: a phone that lost its pairing kept what Search had found on the pairing screen, and a thread
    /// that finished behind Search's results was marked seen.
    func testSearchLeavesNothingBehindAndCoveringAThreadDoesntMarkItSeen() throws {
        let script = PhonePage.script
        let pairing = try XCTUnwrap(script.range(of: "function pairing() {").map { String(script[$0.upperBound...].prefix(600)) })
        XCTAssertTrue(pairing.contains("$('found').replaceChildren();"), "what kittens said goes with the pairing")
        XCTAssertTrue(pairing.contains("'search', 'found']) $(id).hidden = true;"))
        XCTAssertEqual(script.components(separatedBy: "act({ act: 'seen'").count, 2, "every way of marking seen goes through one place")
        let seen = try XCTUnwrap(script.range(of: "function seen() {").map { String(script[$0.upperBound...].prefix(300)) })
        XCTAssertTrue(seen.contains("$('search').hidden"), "and it waits while Search covers the conversation")
    }

    func testAReplyBarHasWhoRepliedAsTheWindowDrawsThemAndWhenTheLastWas() throws {
        let earlier = noon.addingTimeInterval(-86_400 * 3)
        let book = ChannelBook.build(
            kittens: [steve, pepper],
            threads: [thread("a", of: steve)],
            transcripts: ["a": [
                Exchange(id: "e1", asker: .you, askedAt: earlier, ask: "How's it going?", reply: "Fine.", repliedAt: earlier),
                Exchange(id: "e2", asker: .agent(threadID: nil), askedAt: earlier, ask: "And the numbers?", reply: "Here.", repliedAt: earlier),
                Exchange(id: "e3", asker: .you, askedAt: earlier, ask: "Thanks", reply: nil, repliedAt: nil),
            ]],
            isReading: false, unreadable: 0, cantReachT3: false
        )
        let parent = try XCTUnwrap(PhoneView(PhonePlace(PhonePlace.key(.channel(.of(steve))), in: book), in: book, now: noon).rows.first { $0.kind == "parent" })
        let you = ChannelSpeakerLook(.you, in: book).bubble.map(ColorTheme.hex)
        XCTAssertEqual(parent.faces, [
            PhoneView.Face(cat: cat(.sit, steve), color: nil),
            PhoneView.Face(cat: PhoneCat.key(.sit, jacket: ChannelSpeakerLook.otherJacket), color: nil),
            PhoneView.Face(cat: nil, color: you),
        ], "each one's cat, and you as a square in your colour")
        XCTAssertEqual(parent.lastReply, CatWords.lastReply(earlier, now: noon), "with its day, since it wasn't today")
        XCTAssertTrue(parent.lastReply?.hasPrefix("Last reply ") == true)
        XCTAssertFalse(parent.lastReply == "Last reply \(earlier.formatted(date: .omitted, time: .shortened))")
    }

    func testYourPictureComesWithEachPlaceYouSayThingsIn() {
        let book = book(sentBetween: true)
        let steveKey = PhonePlace.key(.channel(.of(steve)))
        XCTAssertNil(PhoneView(PhonePlace(steveKey, in: book), in: book, now: noon).you, "with none, yours are as they were")
        MessagesInk.picture = DemoPicture.jpeg
        defer { MessagesInk.picture = nil }
        XCTAssertEqual(PhoneView(PhonePlace(steveKey, in: book), in: book, now: noon).you, "data:image/jpeg;base64,\(DemoPicture.jpeg.base64EncodedString())")
        XCTAssertNil(PhoneView(PhonePlace("home", in: book), in: book, now: noon).you, "the list of places has nothing of yours to put it by")
        XCTAssertTrue(PhonePage.script.contains("node.src = view.you"), "the page draws it from what it was sent")
        XCTAssertTrue(PhonePage.script.contains("if (view.you) return you(true);"), "and in place of your square")
    }

    func testThreadsHasEachOnesCat() throws {
        let book = book(sentBetween: true)
        let digest = try XCTUnwrap(PhoneView(PhonePlace("threads", in: book), in: book, now: noon).rows.first)
        XCTAssertNil(digest.cat, "you asked")
        XCTAssertEqual(digest.color, ChannelSpeakerLook(.you, in: book).bubble.map(ColorTheme.hex), "so it's your square")
        XCTAssertEqual(digest.reply?.cat, cat(.sit, steve))
    }

    func testActivityHasEachKittensCatAsItIsAndEachIssuesDot() throws {
        var working = thread("w", of: pepper)
        working.status = .running
        working.title = "Build"
        var failed = thread("f", of: pepper)
        failed.status = .failed
        failed.title = "Deploy"
        let approval = ApprovalRequest(id: "ap", threadID: "w", threadTitle: "Work", kind: .command, summary: "Run: ls", createdAt: noon)
        let report = InboxEntry(id: "r", kind: .decision, text: "Ship it?", threadID: "w", threadTitle: "Work", at: noon)
        let book = ChannelBook.build(
            kittens: [steve, pepper], threads: [working, failed], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false,
            waiting: Waiting(approvals: [approval], owners: ["ap": pepper.id], reports: [report])
        )
        let rows = PhoneView(PhonePlace("activity", in: book), in: book, now: noon).rows
        let headings = Dictionary(uniqueKeysWithValues: rows.filter { $0.kind == "heading" }.map { ($0.name ?? "", $0.cat) })
        XCTAssertEqual(headings, ["Pepper": cat(.work, pepper), "Steve Pawsniak": cat(.sleep, steve)], "as each one's row in the window draws it")
        let dots = Dictionary(uniqueKeysWithValues: rows.filter { $0.kind == "issue" }.map { ($0.title ?? "", $0.dot) })
        XCTAssertEqual(dots, ["Build": ColorTheme.hex(0xffc02e), "Deploy": ColorTheme.hex(0xff3b30)], "working, and failed")
        let cards = rows.filter { ["approval", "report"].contains($0.kind) }
        XCTAssertEqual(cards.map(\.cat), [cat(.alert, pepper), cat(.alert, pepper)], "a card's cat has its eyes lit")
        XCTAssertEqual(cards.map(\.choices), [
            [PhoneView.Choice(label: "Deny", value: "decline"), PhoneView.Choice(label: "Allow", value: "accept"), PhoneView.Choice(label: "Allow for this session", value: "acceptForSession")],
            [PhoneView.Choice(label: "Reply", value: "reply")],
        ], "the window's buttons, but Open in T3")
        XCTAssertEqual(cards.last?.done, true, "and Done on a decision")
    }

    func testThePageDrawsTheWindowsCatsAndIcons() {
        XCTAssertTrue(PhonePage.script.contains("'/cat/' + scheme() + '/' + key + '.png'"))
        XCTAssertTrue(PhonePage.style.contains("--cats: light") && PhonePage.style.contains("--cats: dark"), "light or dark, as the page is")
        XCTAssertTrue(PhonePage.colors(ColorTheme(name: "Opal", isDark: true, paper: 0x0c0a10, text: 0xe7e4ec, accent: 0x7458e8)).contains("--cats: dark"), "and as the theme is")
        for emoji in ["🔔", "💬"] { XCTAssertFalse(PhonePage.script.contains(emoji), "drawn to match the window instead") }
    }
}

// MARK: - Errors, the link sheet and questions

extension PhoneTests {
    /// A conversation is read from its bottom, so anything above it is out of sight. An error goes at the bottom of the
    /// header, which stays at the top of the screen.
    func testAnErrorShowsInTheHeaderWhereverYouAreAndIsReadOut() throws {
        let html = PhonePage.html
        let start = try XCTUnwrap(html.range(of: #"<header id="top">"#))
        let end = try XCTUnwrap(html.range(of: "</header>", range: start.upperBound..<html.endIndex))
        XCTAssertTrue(html[start.lowerBound..<end.upperBound].contains(#"<div id="banner" role="status"></div>"#), "always there, empty, so VoiceOver reads what it comes to say")
        XCTAssertTrue(PhonePage.style.contains("#top { position: sticky; top: 0;"))
        XCTAssertFalse(PhonePage.script.contains("$('banner').hidden"), "never hidden, which would leave nothing to read out")
        XCTAssertFalse(PhonePage.script.contains("'banner', "), "nor with what pairing hides")
    }

    /// What the helper reported: everything the Mac sent took away whatever the page had said, such as a file being
    /// too big, before you'd seen it. What comes in by itself only shows the Mac can be reached.
    func testOnlyWhatYouDoTakesAnErrorAway() throws {
        let page = try Self.page(["banner", "reached"])
        page.evaluateScript("let writes = 0, shown = ''; const strip = { get textContent() { return shown; }, set textContent(text) { writes += 1; shown = text; } }; const $ = () => strip;")
        page.evaluateScript("banner(words.tooBig); reached();")
        XCTAssertEqual(page.evaluateScript("shown")?.toString(), "That's too big to send. Try something under 10 MB.")
        page.evaluateScript("banner(words.unreachable); banner(words.unreachable);")
        XCTAssertEqual(page.evaluateScript("writes")?.toInt32(), 2, "trying again every few seconds doesn't say it again")
        page.evaluateScript("reached();")
        XCTAssertEqual(page.evaluateScript("shown")?.toString(), "", "until the Mac answers")
        XCTAssertTrue(PhonePage.script.contains("if (line.startsWith('data: ')) { reached();"), "what the Mac sends")
        XCTAssertTrue(PhonePage.script.contains("if (quiet) reached(); else banner('');"), "and what the page marks seen by itself")
    }

    /// The sheet a link shows is a real one: over a dimmed page that can't be reached until it's gone, which Escape puts
    /// away, with the keyboard on Cancel, never on Open, so a held Enter can't open what you haven't read.
    func testALinksSheetIsModalOverADimmedPageWithTheKeyboardOnCancel() throws {
        let html = PhonePage.html
        XCTAssertTrue(html.contains(#"<dialog id="linksheet" aria-labelledby="linktitle">"#))
        let cancel = try XCTUnwrap(html.range(of: #"<button id="linkcancel" type="button" autofocus>Cancel</button>"#))
        XCTAssertLessThan(cancel.lowerBound, try XCTUnwrap(html.range(of: #"<a id="linkopen""#)).lowerBound)
        XCTAssertTrue(PhonePage.script.contains("$('linksheet').showModal();"))
        XCTAssertFalse(PhonePage.script.contains("$('linksheet').hidden"))
        XCTAssertTrue(PhonePage.style.contains("#linksheet::backdrop { background:"))
        XCTAssertTrue(PhonePage.script.contains("if (event.key === 'Enter') { event.preventDefault(); ask(part.link); }"), "the Enter that shows it goes no further")
    }

    /// A question's text is its first part's, so the card says it once, numbered, as the window's card does.
    func testAQuestionCardAsksEachPartOnce() throws {
        let font = AnswerForm.Part(key: "font", text: "Which font?", options: ["Silkscreen", "System"], values: ["s", "y"], takesOwnWords: false)
        let pages = AnswerForm.Part(key: "pages", text: "Which pages?", options: ["Home", "Blog"], values: ["h", "b"], takesOwnWords: false, picksSeveral: true)
        let book = book(waiting: Waiting(questions: [
            AgentQuestion(id: "two", threadID: "a", threadTitle: "Work", text: "Which font?", form: AnswerForm(parts: [font, pages])),
            AgentQuestion(id: "one", threadID: "a", threadTitle: "Work", text: "Which font?", form: AnswerForm(parts: [font])),
            AgentQuestion(id: "t3", threadID: "a", threadTitle: "Work", text: "Which font?", form: nil),
        ]))
        let page = try Self.page(["el", "button", "card", "question", "chosen", "mark"])
        var said: [String: [String]] = [:]
        for row in PhoneView(PhonePlace("activity", in: book), in: book, now: noon).rows where row.kind == "question" {
            let json = String(decoding: try JSONEncoder().encode(row), as: UTF8.self)
            said[row.id ?? ""] = page.evaluateScript("said(card(\(json)))")?.toArray() as? [String]
        }
        XCTAssertEqual(said["two"]?.filter { $0.contains("Which") }, ["1 of 2: Which font?", "2 of 2: Which pages?"])
        XCTAssertEqual(said["one"]?.filter { $0.contains("Which") }, ["Which font?"])
        XCTAssertEqual(said["t3"]?.filter { $0.contains("Which") }, ["Which font?"], "and one answered in T3 still says it")
    }

    /// The page's `words` and its functions with these names, with just enough of a document to build nodes and read
    /// back what they say.
    private static func page(_ names: [String]) throws -> JSContext {
        let script = PhonePage.script
        func cut(from start: String, to end: String) throws -> String {
            let from = try XCTUnwrap(script.range(of: start), start)
            return String(script[from.lowerBound..<(try XCTUnwrap(script.range(of: end, range: from.upperBound..<script.endIndex))).upperBound])
        }
        let document = """
            const document = { createElement: (tag) => ({ tag, children: [], dataset: {}, classList: { toggle() {} },
              append(...nodes) { this.children.push(...nodes); }, setAttribute() {}, querySelectorAll() { return []; } }) };
            const cat = () => document.createElement('img'), time = () => '', act = () => Promise.resolve(null), answers = new Map();
            const said = (node) => [node.textContent, ...node.children.flatMap(said)].filter((text) => text);
            """
        let page = try XCTUnwrap(JSContext())
        page.exceptionHandler = { _, error in XCTFail(error?.toString() ?? "") }
        let functions = try names.map { try cut(from: "function \($0)(", to: "\n}\n") }
        page.evaluateScript(([document, try cut(from: "const words = {", to: "\n};\n")] + functions).joined(separator: "\n"))
        return page
    }
}
