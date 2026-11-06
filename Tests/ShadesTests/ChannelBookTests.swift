@testable import Shades
import ShadesCore
import XCTest

final class ChannelBookTests: XCTestCase {
    private let at = Date(timeIntervalSince1970: 1_000_000)
    private let steve = Kitten(name: "Steve", role: "Professional", covers: "", folder: "/k/steve")
    private let pepper = Kitten(name: "Pepper", role: "Finance", covers: "", folder: "/k/pepper")
    private let cali = Kitten(name: "Cali", role: "Scheduling", covers: "", folder: "/k/cali", planned: true)

    private func thread(_ id: String, project: String? = "Steve", title: String = "Work", status: AgentStatus = .completed, settled: Bool = false, age: TimeInterval = 0) -> AgentThread {
        AgentThread(id: id, title: title, projectTitle: project, status: status, model: "m", updatedAt: at.addingTimeInterval(-age), isSettled: settled, projectPath: project.map { "/k/\($0.lowercased())" })
    }

    private func exchange(_ id: String, asker: Exchange.Asker = .you, ask: String? = "Ask", reply: String? = "Reply", asked: TimeInterval = 0, replied: TimeInterval? = nil) -> Exchange {
        Exchange(
            id: id,
            asker: asker,
            askedAt: at.addingTimeInterval(asked),
            ask: ask,
            reply: reply,
            repliedAt: reply == nil ? nil : at.addingTimeInterval(replied ?? asked + 1)
        )
    }

    private func book(kittens: [Kitten]? = nil, threads: [AgentThread] = [], transcripts: [String: [Exchange]] = [:]) -> ChannelBook {
        ChannelBook.build(kittens: kittens ?? [steve, pepper], threads: threads, transcripts: transcripts, isReading: false, unreadable: 0, cantReachT3: false)
    }

    private func direct(_ kitten: Kitten, in book: ChannelBook) -> Channel? {
        book.channel(.direct(kitten))
    }

    func testEveryKittenHasADMWithNothingSaidAndANewOneJoinsOnTheNextBuild() {
        XCTAssertEqual(book(kittens: [steve]).directs.map(\.messages), [[]])
        let more = book(kittens: [steve, pepper, cali])
        XCTAssertEqual(more.directs.map(\.id), [.direct(steve), .direct(pepper), .direct(cali)])
        XCTAssertEqual(more.between, [])
    }

    func testYourMessageAndItsReplyGoInTheDM() throws {
        let built = book(threads: [thread("t")], transcripts: ["t": [exchange("e")]])
        let messages = try XCTUnwrap(direct(steve, in: built)).messages
        XCTAssertEqual(messages.map(\.speaker), [.you, .kitten(steve.id)])
        XCTAssertEqual(messages.map(\.text), ["Ask", "Reply"])
        XCTAssertEqual(messages.map(\.threadID), ["t", "t"])
        XCTAssertEqual(direct(pepper, in: built)?.messages, [])
    }

    func testBothDirectionsShareAChannel() throws {
        let toSteve = thread("to-steve", project: "Steve")
        let toPepper = thread("to-pepper", project: "Pepper")
        let built = book(threads: [toSteve, toPepper], transcripts: [
            "to-steve": [exchange("a", asker: .agent(threadID: toPepper.id), asked: 0)],
            "to-pepper": [exchange("b", asker: .agent(threadID: toSteve.id), asked: 10)],
        ])
        XCTAssertEqual(built.between.count, 1)
        let pair = try XCTUnwrap(ChannelID(.kitten(pepper.id), .kitten(steve.id)))
        XCTAssertEqual(built.between.first?.id, pair)
        XCTAssertEqual(built.channel(try XCTUnwrap(ChannelID(.kitten(steve.id), .kitten(pepper.id))))?.messages.count, 4)
        XCTAssertEqual(built.title(of: pair), "Steve, Pepper")
        XCTAssertEqual(direct(steve, in: built)?.messages, [])
    }

    func testAKittenTalkingToItselfShowsOnlyItsReportInItsDM() {
        let started = thread("worker", project: "site", title: "Steve: Build it")
        let brief = exchange("e", asker: .agent(threadID: "main"), ask: "A long brief")
        let built = book(threads: [started, thread("main")], transcripts: ["worker": [brief], "main": []])
        XCTAssertEqual(direct(steve, in: built)?.messages.map(\.text), ["Reply"])
        XCTAssertEqual(direct(steve, in: built)?.messages.map(\.threadTitle), ["Build it"])
        XCTAssertEqual(built.between, [])
    }

    func testAKittenTalkingToItselfWithNoReplyYetHasNoRow() {
        let working = thread("worker", status: .running)
        let built = book(threads: [working, thread("main")], transcripts: ["worker": [exchange("e", asker: .agent(threadID: "main"), reply: nil)], "main": []])
        XCTAssertEqual(direct(steve, in: built)?.messages, [])
    }

    func testAnUnknownSenderStaysOutOfYourDM() throws {
        let built = book(threads: [thread("t"), thread("x", project: "Not a kitten")], transcripts: ["t": [
            exchange("archived", asker: .agent(threadID: nil), asked: 0),
            exchange("nobodys", asker: .agent(threadID: "x"), asked: 5),
        ]])
        XCTAssertEqual(direct(steve, in: built)?.messages, [])
        let channel = try XCTUnwrap(built.between.first)
        XCTAssertEqual(channel.id, ChannelID(.someoneElse, .kitten(steve.id)))
        XCTAssertEqual(channel.messages.map(\.speaker), [.someoneElse, .kitten(steve.id), .someoneElse, .kitten(steve.id)])
        XCTAssertEqual(built.title(of: channel.id), "Steve, someone else")
    }

    func testAReplyNeverPartsFromItsAsk() {
        let built = book(threads: [thread("a"), thread("b")], transcripts: [
            "a": [exchange("long", asked: 0, replied: 100)],
            "b": [exchange("short", asked: 10, replied: 20)],
        ])
        XCTAssertEqual(direct(steve, in: built)?.messages.map(\.id), ["short:ask", "short:reply", "long:ask", "long:reply"])
    }

    func testARunningExchangeDoesntMoveAndAFinishedOneGoesToTheBottom() {
        func order(status: AgentStatus) -> [String]? {
            let built = book(threads: [thread("a", status: status), thread("b")], transcripts: [
                "a": [exchange("running", asked: 0, replied: 100)],
                "b": [exchange("other", asked: 10, replied: 20)],
            ])
            return direct(steve, in: built)?.messages.map(\.id)
        }
        XCTAssertEqual(order(status: .running), ["running:ask", "running:reply", "other:ask", "other:reply"])
        XCTAssertEqual(order(status: .completed), ["other:ask", "other:reply", "running:ask", "running:reply"])
    }

    func testOnlyTheLastExchangeOfAnActiveThreadIsStillGoing() throws {
        let built = book(threads: [thread("t", status: .running)], transcripts: ["t": [
            exchange("first", asked: 0, replied: 1),
            exchange("second", reply: nil, asked: 5),
        ]])
        let messages = try XCTUnwrap(direct(steve, in: built)).messages
        XCTAssertEqual(messages.map(\.id), ["first:ask", "first:reply", "second:ask", "second:reply"])
        XCTAssertEqual(messages.map(\.isStillGoing), [false, false, false, true])
        XCTAssertNil(messages[3].text)
    }

    func testAThreadWaitingOnYouIsntStillGoing() throws {
        for status in [AgentStatus.waitingForAnswer, .waitingForApproval] {
            let built = book(threads: [thread("t", status: status)], transcripts: ["t": [exchange("e")]])
            let reply = try XCTUnwrap(direct(steve, in: built)?.messages.last)
            XCTAssertEqual(reply.text, "Reply")
            XCTAssertFalse(reply.isStillGoing)
        }
        let quiet = book(threads: [thread("t", status: .waitingForAnswer)], transcripts: ["t": [exchange("e", reply: nil)]])
        XCTAssertEqual(direct(steve, in: quiet)?.messages.map(\.text), ["Ask"])
    }

    func testASubagentAskingYouSomethingIsntStillGoing() throws {
        var asking = thread("t", status: .running)
        asking.pendingQuestion = AgentQuestion(id: "q", threadID: "child", threadTitle: "Work", text: "")
        let built = book(threads: [asking], transcripts: ["t": [exchange("e")]])
        XCTAssertEqual(direct(steve, in: built)?.messages.last?.isStillGoing, false)
        XCTAssertEqual(built.statuses.first?.state, .needsYou)
        XCTAssertEqual(built.issues.first?.threads.first?.status, .waitingForAnswer, "its row says so too, however the thread was listed")
    }

    func testWhatsWrongNowComesBeforeOlderMessages() {
        let lost = ChannelBook.build(kittens: [steve], threads: [thread("t")], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: true)
        XCTAssertEqual(ChannelRows.rows(.channel(.direct(steve)), in: lost), [.note(CatWords.cantReachT3Yet)])
        let failed = ChannelBook.build(kittens: [steve], threads: [thread("t")], transcripts: [:], isReading: false, unreadable: 1, cantReachT3: false)
        XCTAssertEqual(ChannelRows.rows(.channel(.direct(steve)), in: failed), [.note(CatWords.couldntRead(1))])

        let threads = [thread("read"), thread("missing")]
        let said = ["read": [exchange("e")]]
        func notes(unreadable: Int, cantReachT3: Bool) -> [String] {
            let built = ChannelBook.build(kittens: [steve], threads: threads, transcripts: said, isReading: false, unreadable: unreadable, cantReachT3: cantReachT3)
            return ChannelRows.rows(.channel(.direct(steve)), in: built).compactMap { if case .note(let text) = $0 { return text } else { return nil } }
        }
        XCTAssertEqual(notes(unreadable: 1, cantReachT3: false), [CatWords.couldntRead(1)])
        XCTAssertEqual(notes(unreadable: 0, cantReachT3: true), [CatWords.cantReachT3Yet])
        XCTAssertEqual(notes(unreadable: 0, cantReachT3: false), [CatWords.olderMessages], "and once it's only that they're old, it says so")
    }

    func testALaterAskInAThreadNeverSitsAboveAnEarlierOne() {
        let built = book(threads: [thread("t", status: .running)], transcripts: ["t": [
            exchange("first", ask: "First", reply: "Still narrating", asked: 0, replied: 50),
            exchange("queued", ask: "Queued", reply: nil, asked: 10),
        ]])
        XCTAssertEqual(direct(steve, in: built)?.messages.compactMap(\.text), ["First", "Still narrating", "Queued"])
    }

    func testWhoSentItIsLookedUpWhenItsShown() throws {
        let sender = thread("sender", project: "site", title: "Work")
        let transcripts = ["t": [exchange("e", asker: .agent(threadID: "sender"))], "sender": []]
        let before = book(threads: [thread("t"), sender], transcripts: transcripts)
        XCTAssertEqual(before.between.first?.id, ChannelID(.someoneElse, .kitten(steve.id)))

        var renamed = sender
        renamed.title = "Pepper: Work"
        let after = book(threads: [thread("t"), renamed], transcripts: transcripts)
        XCTAssertEqual(after.between.map(\.id), [try XCTUnwrap(ChannelID(.kitten(pepper.id), .kitten(steve.id)))])
    }

    func testAThreadThatWasntReadDoesntMakeADMClaimYouveNeverTalked() throws {
        let built = book(threads: [thread("old")])
        let channel = try XCTUnwrap(direct(steve, in: built))
        XCTAssertTrue(channel.isCut)
        XCTAssertEqual(ChannelRows.rows(.channel(channel.id), in: built), [.note(CatWords.olderMessages)])
        XCTAssertFalse(try XCTUnwrap(direct(pepper, in: built)).isCut)

        let reading = ChannelBook.build(kittens: [steve], threads: [thread("old")], transcripts: [:], isReading: true, unreadable: 0, cantReachT3: false)
        XCTAssertEqual(reading.channel(.direct(steve))?.isCut, false)
    }

    func testAThreadCarryingAnotherKittensNameCountsOnlyForThatKitten() {
        var waiting = thread("t", project: "Steve", title: "Pepper: Work", status: .waitingForAnswer)
        waiting.title = "Pepper: Work"
        let built = book(threads: [waiting], transcripts: ["t": [exchange("e")]])
        XCTAssertEqual(built.statuses.map(\.state), [.idle, .needsYou])
        XCTAssertEqual(built.issues.map(\.threads.count), [0, 1])
    }

    func testASettledThreadThatNeedsYouIsAnIssue() {
        var waiting = thread("t", settled: true)
        waiting.pendingQuestion = AgentQuestion(id: "q", threadID: "child", threadTitle: "Work", text: "")
        XCTAssertEqual(book(threads: [waiting]).issueCount, 1)
    }

    func testAPlannedKittensDMWithUnreadThreadsPointsAtT3() {
        let built = book(kittens: [steve, cali], threads: [thread("t", project: "Cali", status: .completed)])
        XCTAssertEqual(ChannelRows.rows(.channel(.direct(cali)), in: built), [.note(CatWords.olderMessages)])
    }

    func testAPlannedKittensOpenThreadIsAnIssue() {
        let built = book(kittens: [steve, cali], threads: [thread("t", project: "Cali", status: .running)])
        XCTAssertEqual(built.issues.map(\.kitten), [steve, cali])
        XCTAssertEqual(built.issueCount, 1)
        XCTAssertEqual(book(kittens: [steve, cali]).issues.map(\.kitten), [steve])
    }

    func testAFailureGetsARowWithOrWithoutAReply() {
        var failed = exchange("e", reply: nil)
        failed.failure = "Ran out of quota"
        let built = book(threads: [thread("t")], transcripts: ["t": [failed]])
        XCTAssertEqual(direct(steve, in: built)?.messages.last?.failure, "Ran out of quota")
        XCTAssertNil(direct(steve, in: built)?.messages.last?.text)
    }

    func testAnExchangeWithNothingToShowHasNoRow() {
        let built = book(threads: [thread("t")], transcripts: ["t": [exchange("e", ask: nil, reply: nil)]])
        XCTAssertEqual(direct(steve, in: built)?.messages, [])
    }

    func testNarrationCountComesAlong() {
        var narrated = exchange("e")
        narrated.earlierNotes = 2
        let built = book(threads: [thread("t")], transcripts: ["t": [narrated]])
        XCTAssertEqual(direct(steve, in: built)?.messages.map(\.earlierNotes), [0, 2])
    }

    func testEachChannelKeepsItsNewestExchanges() throws {
        let many = (0..<203).map { exchange("e\($0)", asked: TimeInterval($0)) }
        let channel = try XCTUnwrap(direct(steve, in: book(threads: [thread("t")], transcripts: ["t": many])))
        XCTAssertTrue(channel.isCut)
        XCTAssertEqual(channel.messages.count, 400)
        XCTAssertEqual(channel.messages.first?.id, "e3:ask")
        XCTAssertEqual(channel.messages.last?.id, "e202:reply")

        let few = try XCTUnwrap(direct(steve, in: book(threads: [thread("t")], transcripts: ["t": Array(many.prefix(200))])))
        XCTAssertFalse(few.isCut)
    }

    func testBetweenChannelsAreNewestFirst() {
        let onSteve = thread("s", project: "Steve")
        let onPepper = thread("p", project: "Pepper")
        let built = book(threads: [onSteve, onPepper], transcripts: [
            "s": [exchange("old", asker: .agent(threadID: nil), asked: 0)],
            "p": [exchange("new", asker: .agent(threadID: nil), asked: 50)],
        ])
        XCTAssertEqual(built.between.map(\.id), [ChannelID(.someoneElse, .kitten(pepper.id)), ChannelID(.someoneElse, .kitten(steve.id))])
    }

    func testANameOnTheTitleBeatsTheProject() {
        let titled = thread("t", project: "Pepper", title: "Steve: Fix the site")
        XCTAssertEqual(KittenBoard.owner(of: titled, among: [pepper, steve]), steve)
        XCTAssertEqual(KittenBoard.owner(of: thread("t", project: "Pepper"), among: [pepper, steve]), pepper)
        XCTAssertNil(KittenBoard.owner(of: thread("t", project: "site"), among: [pepper, steve]))
    }

    func testAnIssueIsAnOpenThreadAndAFinishedOneIsDoneWhetherOrNotItsSettled() throws {
        let built = book(kittens: [steve], threads: [
            thread("done-unsettled", status: .completed, age: 1),
            thread("done-settled", status: .completed, settled: true, age: 2),
            thread("failed-unsettled", status: .failed),
            thread("failed-settled", status: .failed, settled: true, age: 3),
            thread("working-settled", status: .running, settled: true),
            thread("someone-elses", project: "site", status: .running),
        ])
        let steves = try XCTUnwrap(built.issues.first)
        XCTAssertEqual(Set(steves.threads.map(\.id)), ["failed-unsettled", "working-settled"])
        XCTAssertEqual(steves.done.map(\.id), ["done-unsettled", "done-settled", "failed-settled"], "newest first")
        XCTAssertEqual(built.issueCount, 2)
    }

    func testIssuesPutWhatNeedsYouFirstThenWorkingThenNewest() throws {
        var approving = thread("approving", status: .running, age: 40)
        approving.pendingApprovals = [ApprovalRequest(id: "r", threadID: "approving", threadTitle: "Work", kind: .command, summary: "x", createdAt: at)]
        let built = book(kittens: [steve], threads: [
            thread("old-stopped", status: .interrupted, age: 30),
            thread("new-stopped", status: .interrupted, age: 1),
            thread("working", status: .running, age: 20),
            thread("asking", status: .waitingForAnswer, age: 50),
            approving,
        ])
        XCTAssertEqual(try XCTUnwrap(built.issues.first).threads.map(\.id), ["approving", "asking", "working", "new-stopped", "old-stopped"])
    }

    func testIssuesCoverEveryKittenThatsSetUpWithTheirNameTakenOff() throws {
        let built = book(kittens: [steve, pepper, cali], threads: [thread("t", project: "site", title: "Steve: Fix the site", status: .running)])
        XCTAssertEqual(built.issues.map(\.kitten), [steve, pepper])
        XCTAssertEqual(built.issues[0].threads.map(\.title), ["Fix the site"])
        XCTAssertEqual(built.issues[1].threads, [])
    }

    // MARK: - Messages

    private func echo(_ text: String, at offset: TimeInterval = 0, in channel: ChannelID) -> SentMessage {
        SentMessage(channel: channel, message: ChannelMessage(exchangeID: "sent-\(text)", kind: .ask, speaker: .you, text: text, at: at.addingTimeInterval(offset), threadID: "", threadTitle: ""))
    }

    func testEveryoneHoldsEveryDMInOrderAndNothingBetweenKittens() {
        let built = book(
            threads: [thread("s"), thread("p", project: "Pepper"), thread("b")],
            transcripts: [
                "s": [exchange("s1", ask: "Steve?", asked: 0)],
                "p": [exchange("p1", ask: "Pepper?", asked: 10)],
                "b": [exchange("b1", asker: .agent(threadID: "p"), ask: "From Pepper", asked: 20)],
            ]
        )
        let said = built.everyone.messages.compactMap(\.text)
        XCTAssertEqual(said, ["Steve?", "Reply", "Pepper?", "Reply"])
        XCTAssertEqual(built.title(of: .everyone), "Everyone")
        XCTAssertFalse(built.between.contains { $0.id == .everyone })
    }

    func testWhatYouSentShowsAtOnceAndGoesOnceT3HasIt() {
        let waitingForT3 = ChannelBook.build(
            kittens: [steve, pepper], threads: [thread("s")], transcripts: ["s": []],
            isReading: false, unreadable: 0, cantReachT3: false,
            sent: [echo("Tidy it", in: .direct(steve)), echo("Anyone?", in: .everyone)]
        )
        XCTAssertEqual(direct(steve, in: waitingForT3)?.messages.compactMap(\.text), ["Tidy it"])
        XCTAssertEqual(Set(waitingForT3.everyone.messages.compactMap(\.text)), ["Tidy it", "Anyone?"])

        let heard = ChannelBook.build(
            kittens: [steve, pepper], threads: [thread("s"), thread("p", project: "Pepper")],
            transcripts: ["s": [exchange("s1", ask: "Tidy it", reply: nil, asked: 1)], "p": [exchange("p1", ask: "Anyone?", reply: nil, asked: 2)]],
            isReading: false, unreadable: 0, cantReachT3: false,
            sent: [echo("Tidy it", in: .direct(steve)), echo("Anyone?", in: .everyone)]
        )
        XCTAssertEqual(direct(steve, in: heard)?.messages.compactMap(\.text), ["Tidy it"], "said once, by T3")
        XCTAssertEqual(heard.everyone.messages.filter { $0.speaker == .you }.count, 2, "the router's choice of kitten counts as having it")
    }

    func testAnOldMessageWithTheSameWordsDoesntHideANewOne() {
        let built = ChannelBook.build(
            kittens: [steve, pepper], threads: [thread("s")], transcripts: ["s": [exchange("s1", ask: "ok", asked: -600)]],
            isReading: false, unreadable: 0, cantReachT3: false,
            sent: [echo("ok", in: .direct(steve))]
        )
        XCTAssertEqual(direct(steve, in: built)?.messages.filter { $0.speaker == .you }.count, 2)
    }

    func testTheCatsOwnAnswerStaysInEveryone() {
        let answer = SentMessage(channel: .everyone, message: ChannelMessage(exchangeID: "cat-1", kind: .reply, speaker: .cat, text: "It's Tuesday.", at: at, threadID: "", threadTitle: ""))
        let built = ChannelBook.build(kittens: [steve], threads: [], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false, sent: [answer])
        XCTAssertEqual(built.everyone.messages.map(\.speaker), [.cat])
        XCTAssertEqual(built.name(of: .cat), "Shades")
    }

    func testAKittenIsUnreadWhenAnyOfItsThreadsIs() {
        let built = ChannelBook.build(
            kittens: [steve, pepper], threads: [thread("s"), thread("p", project: "Pepper"), thread("nobody", project: nil)],
            transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false,
            isUnread: { $0.id != "p" }
        )
        XCTAssertEqual(built.unread, [steve.id])
    }

    func testWaitingItemsKnowTheirKittenAndReportsAreTracedThroughTheirThread() {
        let waiting = Waiting(
            approvals: [ApprovalRequest(id: "a", threadID: "s", threadTitle: "Work", kind: .command, summary: "Run: ls", createdAt: at)],
            owners: ["a": steve.id],
            reports: [InboxEntry(id: "r", kind: .decision, text: "Merged. Say ship it.", threadID: "p", threadTitle: "Plans", at: at)]
        )
        let built = ChannelBook.build(
            kittens: [steve, pepper], threads: [thread("s"), thread("p", project: "Pepper")], transcripts: [:],
            isReading: false, unreadable: 0, cantReachT3: false, waiting: waiting
        )
        XCTAssertEqual(built.kitten(of: "a"), steve)
        XCTAssertEqual(built.kitten(of: "r"), pepper)
        XCTAssertEqual(built.waiting.count, 2)
    }
}
