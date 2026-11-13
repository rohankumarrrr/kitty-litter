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
            .activity, .threads, .channel(.of(pepper)), .channel(.of(steve)),
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
        XCTAssertNil(PhonePlace("t:@shades", in: book).selection)
        XCTAssertEqual(PhonePlace(PhonePlace.key(.thread("made-up", in: .channel(.of(steve)))), in: book).selection, .channel(.of(steve)), "a thread nothing leads to is its place")
        XCTAssertEqual(PhonePlace("needs", in: book).selection, .activity, "a page still open from before")
        for gone in ["general", "everyone"] {
            XCTAssertNil(PhonePlace(gone, in: book).selection, "#general went into the cat's conversation, which stays on the Mac")
        }
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
        let channel = try XCTUnwrap(ask("send", key: PhonePlace.key(.channel(.of(steve))), text: "New idea").action(in: book) { "sent-9" })
        XCTAssertEqual(channel.action, .startTopic("New idea", with: steve, id: "sent-9"), "a kitten's channel starts a new thread")
        XCTAssertEqual(channel.opens, PhonePlace.key(.thread("sent-9", in: .channel(.of(steve)))), "which the phone opens")

        let thread = try XCTUnwrap(ask("send", key: PhonePlace.key(.thread("a", in: .channel(.of(steve)))), text: "And then?").action(in: book) { "x" })
        XCTAssertEqual(thread.action, .send("And then?", to: .thread(id: "a", title: "Work"), shownIn: .of(steve)))

        var alsoSent = ask("send", key: PhonePlace.key(.thread("a", in: .threads)), text: "Keep the FAQ")
        alsoSent.also = true
        XCTAssertEqual(alsoSent.action(in: book) { "x" }?.action, .send("Keep the FAQ", to: .thread(id: "a", title: "Work"), shownIn: .of(steve), alsoSent: true), "Also send to its channel, from Threads too")
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
            ask("send", key: "general", text: "Hi"),
            ask("send", key: "general"),
            ask("send", text: "Hi"),
            ask("speak", key: "general", text: "Hi"),
        ]
        for ask in refused {
            XCTAssertNil(ask.action(in: book) { "x" }, "\(ask.act) \(ask.key ?? "nil") \(ask.text ?? "nil")")
        }
    }

    func testAPhoneOnlyReachesAThreadTheWindowLeadsTo() {
        // Some other project of yours: no kitten's, and not Shades' work. T3 lists it all the same.
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
            sent: [SentMessage(channel: .of(steve), message: failed, isReply: true), SentMessage(channel: .of(steve), message: sending)]
        )
        XCTAssertEqual(ask("retry", id: failed.id).action(in: book) { "x" }?.action, .tryAgain("sent-1"))
        XCTAssertNil(ask("retry", id: sending.id).action(in: book) { "x" }, "nothing to try again while it's on its way")
        XCTAssertNil(ask("retry", id: "e1:ask").action(in: book) { "x" }, "nor anything that got there")
        XCTAssertNil(ask("retry", id: "made-up").action(in: book) { "x" })

        let thread = PhoneView(PhonePlace(PhonePlace.key(.thread("a", in: .channel(.of(steve)))), in: book), in: book, now: noon)
        let shown = try XCTUnwrap(thread.rows.last { $0.kind == "message" })
        XCTAssertEqual(shown.failure, "I can't reach T3 Code. Open it and try again.")
        XCTAssertEqual(shown.retry, true)
        let channel = PhoneView(PhonePlace(PhonePlace.key(.channel(.of(steve))), in: book), in: book, now: noon)
        let hello = try XCTUnwrap(channel.rows.first { $0.kind == "message" })
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
            sent: [SentMessage(channel: .of(steve), message: sending)],
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
        let channel = PhoneView(PhonePlace(PhonePlace.key(.channel(.of(steve))), in: book), in: book, now: noon)
        XCTAssertNil(channel.rows.first { $0.kind == "message" }?.reactions)
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

    /// A phone's pure black, with words in white at the 100, 80 and 62% an Opal iPhone's widgets use, and Opal's light.
    func testThePageIsOpalOnAPhonesBlack() {
        for line in ["color-scheme: dark", "--page: #000000", "--white: #ffffff", "--body: rgba(255, 255, 255, 0.8)", "--secondary: rgba(255, 255, 255, 0.62)",
                     "--primary: #7458e8", "--lilac: #b9a6ff", "--selected: #1e1830"] {
            XCTAssertTrue(PhonePage.colors.contains(line), line)
        }
        XCTAssertFalse(PhonePage.style.contains("prefers-color-scheme"), "Opal is dark only, whatever the phone's set to")
    }

    func testEverythingThePageWritesInAColourReads() throws {
        let colors = try Self.colors()
        let words = try Self.words(in: colors)
        XCTAssertGreaterThan(words.count, 40, "every rule that colours words is measured")
        for (rule, words, under) in words {
            XCTAssertGreaterThanOrEqual(Opal.contrast(words, under), 4.5, rule)
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

    /// Opal's colours as the page has them, each white at an opacity as it comes to on what it's written on.
    private static func colors() throws -> [String: PageColor] {
        let sheet = PhonePage.colors
        let pattern = try NSRegularExpression(pattern: "--([a-z-]+): (#[0-9a-f]{6}|rgba\\([^)]*\\))")
        var colors: [String: PageColor] = [:]
        for match in pattern.matches(in: sheet, range: NSRange(sheet.startIndex..., in: sheet)) {
            colors[String(sheet[Range(match.range(at: 1), in: sheet)!])] = PageColor(String(sheet[Range(match.range(at: 2), in: sheet)!]))
        }
        return colors
    }

    /// A colour as the page writes it: solid, or see-through over whatever it's on.
    private struct PageColor {
        var color: UInt32
        var alpha: Double

        init?(_ text: String) {
            if text.hasPrefix("#") {
                let digits = text.dropFirst()
                guard let color = UInt32(digits.count == 3 ? digits.map { "\($0)\($0)" }.joined() : String(digits), radix: 16) else { return nil }
                (self.color, alpha) = (color, 1)
                return
            }
            let parts = text.drop { $0 != "(" }.dropFirst().prefix { $0 != ")" }.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 4 else { return nil }
            color = parts.prefix(3).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            alpha = parts[3]
        }

        func on(_ under: UInt32) -> UInt32 { Opal.mix(under, color, alpha) }
    }

    /// Each rule that colours words, with the colour they come to and the one they're on: the rule's own background,
    /// or the page.
    private static func words(in colors: [String: PageColor]) throws -> [(rule: String, words: UInt32, under: UInt32)] {
        func value(_ property: String, in body: String) -> PageColor? {
            guard let found = body.range(of: "(?<![-\\w])\(property): [^;}]+", options: .regularExpression) else { return nil }
            let value = body[found].dropFirst(property.count + 2).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("var(--") { return colors[String(value.dropFirst(6).prefix { $0 != ")" && $0 != "," })] }
            return PageColor(value)
        }
        let page = try XCTUnwrap(colors["page"], "the page's black").color
        return try rules().compactMap { rule in
            guard rule.selector != ":root", let words = value("color", in: rule.body) else { return nil }
            let under = value("background", in: rule.body)?.on(page) ?? page
            return (rule.selector, words.on(under), under)
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
        XCTAssertEqual(home.places.map(\.title), ["Activity", "Threads", "Steve Pawsniak", "Pepper"], "by name, as the sidebar writes them")
        XCTAssertEqual(home.places.map(\.group), [nil, nil, CatWords.kittensHeading, CatWords.kittensHeading])
        XCTAssertEqual(home.places[0].count, 1)
        XCTAssertEqual(home.places[2].count, 1, "Steve's channel has its badge")
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
        XCTAssertEqual(channel.box, PhoneView.Box(label: "Starts a new thread with Steve Pawsniak", placeholder: "Message Steve Pawsniak"))
        XCTAssertEqual(channel.back, "home")

        let thread = PhoneView(PhonePlace(PhonePlace.key(.thread("a", in: .channel(.of(steve)))), in: book), in: book, now: noon)
        XCTAssertEqual(thread.rows.map(\.kind), ChannelRows.thread("a", in: book).map(Self.kind))
        XCTAssertEqual(thread.rows.compactMap(\.text).filter { $0 == "Fine." || $0 == "How's it going?" }, ["How's it going?", "Fine."])
        XCTAssertEqual(thread.rows.last?.choices?.map(\.value), ["decline", "accept", "acceptForSession"], "Deny first, as in the window")
        XCTAssertEqual(thread.box?.also, "Also send to Steve Pawsniak")
        XCTAssertEqual(thread.title, CatWords.threadTitle)
        XCTAssertEqual(thread.back, PhonePlace.key(.channel(.of(steve))))
        XCTAssertEqual(thread.backTitle, "Steve Pawsniak")
    }

    func testThreadsOnThePhoneListsWhatYouWroteInAndOpensEachOnItsOwnPage() throws {
        let book = book(sentBetween: true)
        let threads = PhoneView(PhonePlace("threads", in: book), in: book, now: noon)
        XCTAssertEqual(threads.rows.map(\.kind), ["digest"])
        let digest = try XCTUnwrap(threads.rows.first)
        XCTAssertEqual(digest.title, "Steve Pawsniak")
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
        XCTAssertEqual(places.map(\.title), ["Activity", "Threads", "Steve Pawsniak", "Pepper"], "as the sidebar writes them, beside their icon or cat, and no kitten that's only planned")
        XCTAssertEqual(places.map(\.icon), ["activity", "threads", nil, nil])
        XCTAssertEqual(places.map(\.cat), [nil, nil, cat(.alert, steve), cat(.work, pepper)])
        XCTAssertEqual(places.map(\.dot), [nil, nil, Opal.hex(Opal.error), Opal.hex(Opal.lilac)], "needs you, then working")

        // The cat shows first among the kittens once you've shown some of its work here, on its own tile, as in the window.
        let fix = AgentThread(id: "fix", title: "Fix: the total", projectTitle: nil, status: .completed, model: "m", updatedAt: noon)
        let shown = ChannelBook.build(kittens: [steve, pepper, cali], threads: [fix, waiting], transcripts: ["fix": [Exchange(id: "f", asker: .you, askedAt: noon, ask: "Fix the total", reply: "Fixed.", repliedAt: noon)]], isReading: false, unreadable: 0, cantReachT3: false, catsWork: ["fix"], onPhone: ["fix"])
        let withCat = PhoneView(PhonePlace("home", in: shown), in: shown, now: noon).places
        XCTAssertEqual(withCat.map(\.title), ["Activity", "Threads", "Shades", "Steve Pawsniak", "Pepper"])
        XCTAssertEqual(withCat[2].cat, "sit/shades", "the cat in its own jacket, not a #")
        XCTAssertNil(withCat[2].icon)
        XCTAssertEqual(withCat[2].group, CatWords.kittensHeading)

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
            sent: [SentMessage(channel: .of(steve), message: ChannelMessage(exchangeID: "c", kind: .reply, speaker: .cat, text: "Hi.", at: noon, threadID: "", threadTitle: ""))]
        )
        let steves = PhoneView(PhonePlace(PhonePlace.key(.channel(.of(steve))), in: cats), in: cats, now: noon)
        XCTAssertEqual(steves.rows.first { $0.kind == "message" }?.cat, "sit/shades", "the cat speaks as itself, in its own jacket")
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
        let you = ChannelSpeakerLook(.you, in: book).bubble.map(Opal.hex)
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
        XCTAssertEqual(digest.color, ChannelSpeakerLook(.you, in: book).bubble.map(Opal.hex), "so it's your square")
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
        XCTAssertEqual(dots, ["Build": Opal.hex(Opal.lilac), "Deploy": Opal.hex(Opal.error)], "working, and failed")
        let cards = rows.filter { ["approval", "report"].contains($0.kind) }
        XCTAssertEqual(cards.map(\.cat), [cat(.alert, pepper), cat(.alert, pepper)], "a card's cat has its eyes lit")
        XCTAssertEqual(cards.map(\.choices), [
            [PhoneView.Choice(label: "Deny", value: "decline"), PhoneView.Choice(label: "Allow", value: "accept"), PhoneView.Choice(label: "Allow for this session", value: "acceptForSession")],
            [PhoneView.Choice(label: "Reply", value: "reply")],
        ], "the window's buttons, but Open in T3")
        XCTAssertEqual(cards.last?.done, true, "and Done on a decision")
    }

    func testThePageDrawsTheWindowsCatsAndIcons() {
        XCTAssertTrue(PhonePage.script.contains("node.src = '/cat/dark/' + key + '.png';"), "with the light outline the window draws on a dark page")
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
        XCTAssertTrue(html.contains(#"<dialog id="linksheet" class="sheet" aria-labelledby="linktitle">"#))
        let cancel = try XCTUnwrap(html.range(of: #"<button id="linkcancel" type="button" autofocus>Cancel</button>"#))
        XCTAssertLessThan(cancel.lowerBound, try XCTUnwrap(html.range(of: #"<a id="linkopen""#)).lowerBound)
        XCTAssertTrue(PhonePage.script.contains("$('linksheet').showModal();"))
        XCTAssertFalse(PhonePage.script.contains("$('linksheet').hidden"))
        XCTAssertTrue(PhonePage.style.contains("dialog::backdrop { background:"))
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
        let page = try Self.page(["el", "button", "lit", "card", "question", "chosen", "mark"])
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
            const document = { createElement: (tag) => ({ tag, children: [], dataset: {}, attributes: {}, classList: { toggle() {} },
              style: { props: {}, setProperty(name, value) { this.props[name] = value; }, removeProperty(name) { delete this.props[name]; } },
              get childElementCount() { return this.children.length; },
              append(...nodes) { this.children.push(...nodes); }, after(...nodes) { this.children.push(...nodes); }, addEventListener() {},
              setAttribute(name, value) { this.attributes[name] = value; }, querySelector() { return null; }, querySelectorAll() { return []; } }) };
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

// MARK: - Size, labels and reach

extension PhoneTests {
    /// The page's words grow with the phone's own text size, and with the Mac's on top of it, so none is written in
    /// pixels. The Mac's grows them as much as the window's 13 points grow.
    func testThePagesWordsGrowWithThePhonesTextSizeAndTheMacs() throws {
        let style = PhonePage.style
        let fixed = try NSRegularExpression(pattern: "font(-size)?: [\\d.]+px").matches(in: style, range: NSRange(style.startIndex..., in: style))
        XCTAssertEqual(fixed.map { String(style[Range($0.range, in: style)!]) }, [], "every size in em, from the phone's own")
        XCTAssertTrue(style.contains("font: -apple-system-body"), "which on an iPhone is its Text Size")
        XCTAssertTrue(style.contains("font-size: var(--size, 100%)"))
        XCTAssertEqual(PhonePage.size(.standard), "")
        XCTAssertTrue(PhonePage.size(.small).contains("--size: calc(100% * 12 / 13)"))
        XCTAssertTrue(PhonePage.size(.larger).contains("--size: calc(100% * 17 / 13)"))
    }

    /// Apple's 44 points for anything you tap, so a small one such as Search or Try again isn't missed. A reaction's
    /// pill is drawn smaller, and reaches past itself.
    func testEveryButtonIsBigEnoughToTap() throws {
        let rules = try Self.rules()
        XCTAssertTrue(rules.contains { $0.selector == "button" && $0.body.contains("min-width: 44px; min-height: 44px") })
        let drawnSmaller = rules.filter { $0.body.range(of: "min-height: ([1-9]|[1-3][0-9]|4[0-3])px", options: .regularExpression) != nil }
        XCTAssertEqual(drawnSmaller.map(\.selector), [".reactions button"])
        XCTAssertTrue(rules.contains { $0.selector == ".reactions button::after" && $0.body.contains("inset: -6px 0") })
    }

    /// Only a cat and a button you can't press are ever see-through. Faded words, such as a message on its way at 55%,
    /// read at little over 2:1.
    func testNothingThePageSaysIsSeeThrough() throws {
        for rule in try Self.rules() where rule.body.contains("opacity:") {
            XCTAssertTrue(rule.selector.hasSuffix(" .cat") || rule.selector.contains(":disabled"), rule.selector)
        }
    }

    /// A message still coming, or on its way, is drawn at 55% as in the window, with secondary words that still read.
    func testAMessageOnItsWayIsPalerInAColourItsWordsReadOn() throws {
        func said(_ speaker: Speaker, _ id: String, going: Bool = false, sending: Bool = false) -> SentMessage {
            SentMessage(channel: .of(steve), message: ChannelMessage(exchangeID: id, kind: speaker == .you ? .ask : .reply, speaker: speaker, text: "Words", at: noon, threadID: "", threadTitle: "", isStillGoing: going, isSending: sending))
        }
        let book = ChannelBook.build(
            kittens: [steve], threads: [], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false,
            sent: [said(.you, "sending", sending: true), said(.kitten(steve.id), "going", going: true), said(.cat, "cat", going: true), said(.you, "sent")]
        )
        let rows = PhoneView(PhonePlace(PhonePlace.key(.channel(.of(steve))), in: book), in: book, now: noon).rows.filter { $0.kind == "message" }
        XCTAssertEqual(rows.map(\.faded), [true, true, true, nil], "only what's still on its way")
        let rules = Dictionary(try Self.rules().map { ($0.selector, $0.body) }, uniquingKeysWith: { first, _ in first })
        XCTAssertEqual(rules[".mine .bubble.faded"]?.contains("var(--selected)) 55%, var(--page))"), true, "yours at 55%")
        XCTAssertEqual(rules[".bubble.lit.faded"]?.contains("var(--light) 55%, transparent)"), true, "and anyone else's light at 55%")
        let secondary = try XCTUnwrap(Self.colors()["secondary"])
        let yours = Opal.mix(0, Opal.selected, 0.55)
        XCTAssertGreaterThanOrEqual(Opal.contrast(secondary.on(yours), yours), 4.5, "secondary words on yours at 55%")
        XCTAssertGreaterThanOrEqual(Opal.contrast(secondary.on(Opal.cardTop), Opal.cardTop), 4.5, "and on a lit bubble's black glass")
    }

    /// What VoiceOver hears for each place is what it hears in the window's sidebar: its name, what its kitten is doing
    /// and what's waiting. A count says it needs you, so as in the sidebar the dot shows only without one.
    func testEachPlaceSaysWhatItsKittenIsDoingAndACountTakesTheDotsPlace() throws {
        let cali = Kitten(name: "Cali", role: "Scheduling", covers: "", folder: "/k/cali", planned: true)
        var working = thread("p", of: pepper)
        working.status = .running
        var waiting = thread("a", of: steve)
        waiting.status = .waitingForApproval
        let approval = ApprovalRequest(id: "ap", threadID: "a", threadTitle: "Work", kind: .command, summary: "Run: ls", createdAt: noon)
        let book = ChannelBook.build(
            kittens: [steve, pepper, cali], threads: [waiting, working], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false,
            waiting: Waiting(approvals: [approval], owners: ["ap": steve.id])
        )
        let places = PhoneView(PhonePlace("home", in: book), in: book, now: noon).places.filter { $0.icon == nil }
        XCTAssertEqual(places.map(\.state), ["Needs you", "Working"], "and no kitten that's only planned")
        XCTAssertEqual(places.map(\.count), [1, nil])
        XCTAssertEqual(places.map(\.dot), [nil, Opal.hex(Opal.lilac)], "Steve's count, with no dot beside it")
        let page = try Self.page(["el", "dot", "lit", "drift", "tile", "places"])
        let json = String(decoding: try JSONEncoder().encode(places), as: UTF8.self)
        let heard = page.evaluateScript("places(\(json)).filter((node) => node.tag === 'button').map((node) => node.attributes['aria-label'])")?.toArray() as? [String]
        XCTAssertEqual(heard, ["Steve Pawsniak, Needs you, 1 waiting", "Pepper, Working"])
    }

    /// Tapping what a message said offers its reactions, which a keyboard and VoiceOver can't, so React does the same.
    func testAKeyboardOrVoiceOverCanReactToo() {
        XCTAssertTrue(PhonePage.script.contains("node.append(button(words.react, () => react(item), 'react'));"))
        XCTAssertTrue(PhonePage.script.contains("$('marks').firstChild.focus();"), "and the keyboard goes to the marks it offers")
        XCTAssertTrue(PhonePage.style.contains(".react:not(:focus) { position: absolute;"), "out of sight until it has the keyboard")
    }
}

// MARK: - Opal, the way an iPhone does it

extension PhoneTests {
    private static func ruleBodies() throws -> [String: String] {
        Dictionary(try rules().map { ($0.selector, $0.body) }, uniquingKeysWith: { first, _ in first })
    }

    /// An iPhone's large title: 32 points, bold and white at the top of each page. Once it's scrolled up under the bar,
    /// the bar takes it, small, on its glass.
    func testEachPageHasALargeTitleThatFoldsIntoTheBar() throws {
        let rules = try Self.ruleBodies()
        XCTAssertEqual(rules["#title"]?.contains("color: var(--white); font-size: calc(32em / 17); font-weight: 700"), true)
        let page = try Self.page(["collapse"])
        page.evaluateScript("""
            const box = (top, bottom) => ({ getBoundingClientRect: () => ({ top, bottom }) });
            const parts = { top: { classList: { on: null, toggle(name, on) { this.on = on; } } }, head: { hidden: false }, bar: box(0, 44), title: box(60, 100) };
            const $ = (id) => parts[id];
            """)
        page.evaluateScript("collapse()")
        XCTAssertEqual(page.evaluateScript("parts.top.classList.on")?.toBool(), false, "over the large title, the bar is the page's black")
        page.evaluateScript("parts.title = box(30, 70); collapse()")
        XCTAssertEqual(page.evaluateScript("parts.top.classList.on")?.toBool(), true, "and it takes the title once it goes under")
        XCTAssertEqual(rules["#top.collapsed"]?.contains("background: var(--glass)"), true)
        XCTAssertEqual(rules["#top.collapsed #bartitle"]?.contains("visibility: visible"), true)
    }

    /// Search has the bar while it's open, with Cancel beside its field, as on an iPhone, and going anywhere, Back
    /// included, puts it away. Nothing of the page you left stays in the header while the next one comes.
    func testSearchHasTheBarAndGoingAnywherePutsItAway() throws {
        let html = PhonePage.html
        let form = try XCTUnwrap(html.range(of: #"<form id="search" hidden>"#))
        let end = try XCTUnwrap(html.range(of: "</form>", range: form.upperBound..<html.endIndex))
        XCTAssertTrue(html[form.lowerBound..<end.upperBound].contains(#"<button id="searchcancel" type="button">Cancel</button>"#))
        let page = try Self.page(["go"])
        page.evaluateScript("""
            const parts = {};
            const $ = (id) => parts[id] || (parts[id] = { hidden: false, textContent: 'from before', replaceChildren() {} });
            let key = 'c:steve', keptUnread = null, jumped = false, view = {}, closed = false;
            const history = { pushState() {} };
            function listen() {}
            function banner() {}
            function searching(open) { closed = !open; $('search').hidden = !open; }
            """)
        page.evaluateScript("go('home', false)")
        XCTAssertEqual(page.evaluateScript("closed")?.toBool(), true, "Back put Search away")
        XCTAssertEqual(page.evaluateScript("['title', 'subtitle', 'bartitle'].map((id) => $(id).textContent).join('')")?.toString(), "", "and the old title")
        XCTAssertEqual(page.evaluateScript("['back', 'headcat', 'link', 'unread'].every((id) => $(id).hidden)")?.toBool(), true, "and the old buttons")
    }

    /// The box is iMessage's: one + for a photo or a file, which on an iPhone offers the camera too, and the arrow inside
    /// the field, armed only once there's something to send. Return makes a new line, as its key says.
    func testTheBoxIsIMessagesAndSendIsArmedOnlyWithSomethingToSend() throws {
        let html = PhonePage.html
        XCTAssertTrue(html.contains(#"<textarea id="words" rows="1"></textarea>"#), "no Send on a key that only makes a new line")
        XCTAssertFalse(html.contains(#"id="camera""#), "the + offers the camera")
        XCTAssertEqual(html.components(separatedBy: #"type="file""#).count, 2, "one picker")
        XCTAssertTrue(html.contains(#"<span class="unseen">Send</span>"#), "what VoiceOver says for the arrow")
        let page = try Self.page(["sendable"])
        page.evaluateScript("""
            const parts = { send: { disabled: false }, words: { value: '' } };
            const $ = (id) => parts[id];
            let view = { box: { ready: true } }, uploading = false, attached = [];
            const armed = () => { sendable(); return !parts.send.disabled; };
            """)
        XCTAssertEqual(page.evaluateScript("armed()")?.toBool(), false, "nothing to send")
        XCTAssertEqual(page.evaluateScript("parts.words.value = '  '; armed()")?.toBool(), false, "only spaces")
        XCTAssertEqual(page.evaluateScript("parts.words.value = 'Hi'; armed()")?.toBool(), true)
        XCTAssertEqual(page.evaluateScript("uploading = true; armed()")?.toBool(), false, "while a photo goes up")
        XCTAssertEqual(page.evaluateScript("uploading = false; parts.words.value = ''; attached = [{}]; armed()")?.toBool(), true, "a photo on its own")
        XCTAssertEqual(page.evaluateScript("view.box.ready = false; armed()")?.toBool(), false, "a new thread that's still starting")
    }

    /// Reactions come up in a sheet from the foot, as Slack's do, so nothing on the page moves and nothing sits over
    /// the message. Every sheet has 24-point corners, the link's included.
    func testReactionsComeUpInASheetSoNothingOnThePageMoves() throws {
        XCTAssertTrue(PhonePage.html.contains(#"<dialog id="reactsheet" class="sheet" aria-label="React">"#))
        let script = PhonePage.script
        let start = try XCTUnwrap(script.range(of: "function react(item) {"))
        let react = String(script[start.upperBound..<(try XCTUnwrap(script.range(of: "\n}\n", range: start.upperBound..<script.endIndex))).lowerBound])
        XCTAssertTrue(react.contains("$('reactsheet').showModal();"))
        XCTAssertFalse(react.contains(".append("), "never into the page beside the message")
        XCTAssertFalse(script.contains("reactbar"))
        XCTAssertEqual(try Self.ruleBodies()[".sheet[open]"]?.contains("border-radius: 24px"), true)
    }

    /// A kitten's message is lit at its edge in its jacket's colour, as the window draws it, with body words on black
    /// glass, never dark words on a fill. Yours stays filled in your colour. The stylesheet alone says how each looks.
    func testAKittensMessageIsLitAtItsEdgeAndYoursIsFilled() throws {
        let page = try Self.page(["el", "button", "lit", "message"])
        page.evaluateScript("""
            let view = { marks: [] };
            const selecting = () => false, react = () => {}, ask = () => {}, markup = () => [];
            const bubbles = (node) => (node.children || []).flatMap((child) => (child.className || '').startsWith('bubble') ? [child] : bubbles(child));
            const look = (item) => { const b = bubbles(message(item))[0]; return b.className + ' ' + JSON.stringify(b.style.props); };
            """)
        XCTAssertEqual(page.evaluateScript("look({ kind: 'message', mine: true, color: '#1e1830', text: 'Hi', at: 0 })")?.toString(), ##"bubble {"--fill":"#1e1830"}"##)
        XCTAssertEqual(page.evaluateScript("look({ kind: 'message', name: 'Steve', cat: 'sit/56afb3', color: '#56afb3', text: 'Hi', at: 0 })")?.toString(), ##"bubble lit {"--light":"#56afb3"}"##)
        XCTAssertEqual(page.evaluateScript("look({ kind: 'message', name: 'Shades', cat: 'sit/shades', text: 'Hi', at: 0, faded: true })")?.toString(), "bubble lit faded {}", "the cat's own, in Shades' light")
        let rules = try Self.ruleBodies()
        XCTAssertEqual(rules[".card, .lit"]?.contains("linear-gradient(var(--card-top), var(--card-bottom))"), true, "black glass")
        XCTAssertEqual(rules[".card::after, .lit::after"]?.contains("linear-gradient(transparent 58%"), true, "its rim brightening into its bottom edge")
        XCTAssertEqual(rules[".bubble"]?.contains("color: var(--body)"), true, "with body words")
        XCTAssertFalse(PhonePage.script.contains("bubble.style.color"), "and never words of its own")
    }

    /// Every place is on a Rimlight tile, as an Opal Dock icon: a kitten's in its own light, and the rest drifting teal
    /// to pink down the list.
    func testEachPlaceIsOnATileInItsKittensLight() throws {
        let book = ChannelBook.build(kittens: [steve, pepper], threads: [], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false)
        let places = PhoneView(PhonePlace("home", in: book), in: book, now: noon).places
        let page = try Self.page(["el", "dot", "lit", "drift", "tile", "places"])
        page.evaluateScript("function icon() { return document.createElement('svg'); }")
        let json = String(decoding: try JSONEncoder().encode(places), as: UTF8.self)
        let tiles = page.evaluateScript("places(\(json)).filter((node) => node.tag === 'button').map((node) => node.children[0].className + ' ' + node.children[0].style.props['--light'])")?.toArray() as? [String]
        let jacket = { (kitten: Kitten) in "tile \(Opal.hex(ChannelSpeakerLook.color(of: kitten)!))" }
        XCTAssertEqual(tiles, ["tile hsl(172 100% 68%)", "tile hsl(344 100% 68%)", jacket(steve), jacket(pepper)])
    }

    /// Allow is the one primary on an approval's card, as on the cat's own, and the card is lit in its kitten's light.
    func testAllowIsTheOnePrimaryOnAnApprovalsCard() throws {
        let command = ApprovalRequest(id: "ap", threadID: "a", threadTitle: "Work", kind: .command, summary: "Run: ls", createdAt: noon)
        let book = book(waiting: Waiting(approvals: [command], owners: ["ap": steve.id]))
        let row = try XCTUnwrap(PhoneView(PhonePlace("activity", in: book), in: book, now: noon).rows.first { $0.kind == "approval" })
        let page = try Self.page(["el", "button", "lit", "card", "question", "chosen", "mark"])
        let json = String(decoding: try JSONEncoder().encode(row), as: UTF8.self)
        page.evaluateScript("const node = card(\(json)); const buttons = node.children.find((child) => child.className === 'buttons').children;")
        XCTAssertEqual(page.evaluateScript("buttons.map((b) => b.textContent + ':' + (b.className || 'quiet')).join(', ')")?.toString(), "Deny:quiet, Allow:go, Allow for this session:quiet")
        XCTAssertEqual(page.evaluateScript("node.style.props['--light']")?.toString(), Opal.hex(ChannelSpeakerLook.color(of: steve)!))
    }

    /// A picture comes in after the page is drawn, so opening a conversation with one in it landed above its newest
    /// message, behind the box. If you were at the foot, the picture keeps you there, as iMessage does, and it never
    /// pulls you down from where you'd scrolled to.
    func testAPictureThatComesInLateKeepsAConversationAtItsFoot() throws {
        let page = try Self.page(["el", "button", "lit", "message", "settle"])
        page.evaluateScript("""
            let view = { marks: [] }, atFoot = true, jumped = false, scrolledTo = null;
            const selecting = () => false, react = () => {}, ask = () => {}, markup = () => [];
            const window = { scrollTo(x, y) { scrolledTo = y; } };
            document.body = { scrollHeight: 1383 };
            const $ = () => ({ hidden: true });
            const photos = (node) => (node.children || []).flatMap((child) => child.className === 'picture' ? [child] : photos(child));
            const photo = photos(message({ kind: 'message', mine: true, color: '#1e1830', text: 'Here', at: 0, files: [{ name: 'photo.jpg', picture: 'data:image/jpeg;base64,' }] }))[0];
            """)
        page.evaluateScript("photo.onload()")
        XCTAssertEqual(page.evaluateScript("scrolledTo")?.toInt32(), 1383, "back to the foot once it's in")
        page.evaluateScript("scrolledTo = null; atFoot = false; photo.onload()")
        XCTAssertEqual(page.evaluateScript("scrolledTo === null")?.toBool(), true, "and never from where you'd scrolled to")

        let foot = try Self.page(["foot"])
        foot.evaluateScript("""
            let atFoot = false, footY = 0;
            const key = 'c:steve', conversation = () => true;
            const window = { innerHeight: 844, scrollY: 701 };
            document.body = { scrollHeight: 1545 };
            """)
        foot.evaluateScript("foot(); document.body.scrollHeight = 1672; foot()")
        XCTAssertEqual(foot.evaluateScript("atFoot")?.toBool(), true, "a picture growing the page under you leaves you at the foot")
        foot.evaluateScript("window.scrollY = 400; foot()")
        XCTAssertEqual(foot.evaluateScript("atFoot")?.toBool(), false, "scrolling up leaves it")
        foot.evaluateScript("window.scrollY = 828; foot()")
        XCTAssertEqual(foot.evaluateScript("atFoot")?.toBool(), true, "and scrolling back down comes back to it")
    }

    /// Your square in a reply bar has an edge, as in the window, since your colour is too close to the phone's black.
    func testYourSquareHasAnEdgeOnThePhonesBlack() throws {
        XCTAssertEqual(try Self.ruleBodies()[".face"]?.contains("box-shadow: inset 0 0 0 1px var(--dim)"), true)
        XCTAssertGreaterThanOrEqual(Opal.contrast(Opal.dim, 0), 3, "the 3:1 a shape needs")
        XCTAssertLessThan(Opal.contrast(Opal.selected, 0), 3, "which your colour alone isn't")
    }

    /// Added to the Home Screen, it opens on pure black under a status bar it draws behind, as an iPhone's own apps do.
    func testOnTheHomeScreenItOpensOnPureBlack() throws {
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(PhonePage.manifest.utf8)) as? [String: Any])
        XCTAssertEqual(manifest["background_color"] as? String, "#000000")
        XCTAssertEqual(manifest["theme_color"] as? String, "#000000")
        XCTAssertTrue(PhonePage.html.contains(#"<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">"#))
        XCTAssertTrue(PhonePage.html.contains(#"<meta name="color-scheme" content="dark">"#))
    }

    /// The horizon belongs to the wallpaper alone, so the page draws none: no arc at its foot, and no room kept at the
    /// end of a list to scroll clear of one.
    func testThePageDrawsNoHorizon() throws {
        let sheet = PhonePage.style + PhonePage.colors
        for part in ["html::after", "--horizon", "image/svg+xml", "#box[hidden]) main"] { XCTAssertFalse(sheet.contains(part), part) }
        XCTAssertEqual(try Self.ruleBodies()["main"]?.contains("24px calc(env(safe-area-inset-left) + 16px)"), true, "a list ends as any page does")
    }

    /// A pull request's state is in Opal's status colours rather than GitHub's fills, and an error sits on Opal's error
    /// surface rather than a block of rose.
    func testStatesAndErrorsAreInOpalsStatusColours() throws {
        let rules = try Self.ruleBodies()
        XCTAssertEqual(rules[".chip[data-state=open]"]?.contains("color: var(--good)"), true)
        XCTAssertEqual(rules[".chip[data-state=merged]"]?.contains("color: var(--lilac)"), true)
        XCTAssertEqual(rules[".chip[data-state=closed]"]?.contains("color: var(--error-text)"), true)
        XCTAssertFalse(PhonePage.style.contains("#1f883d") || PhonePage.style.contains("#8250df") || PhonePage.style.contains("#cf222e"))
        XCTAssertEqual(rules["#banner"]?.contains("color: var(--error-text); background: var(--error-surface)"), true)
    }
}
