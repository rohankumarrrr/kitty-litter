@testable import Shades
import ShadesCore
import XCTest

final class ChannelBookTests: XCTestCase {
    private let at = Date(timeIntervalSince1970: 1_000_000)
    private let steve = Kitten(name: "Steve", role: "Professional", covers: "", folder: "/k/steve")
    private let pepper = Kitten(name: "Pepper", role: "Finance", covers: "", folder: "/k/pepper")
    private let cali = Kitten(name: "Cali", role: "Scheduling", covers: "", folder: "/k/cali", planned: true)

    private func thread(_ id: String, project: String? = "Steve", title: String = "Work", status: AgentStatus = .completed, settled: Bool = false, age: TimeInterval = 0) -> AgentThread {
        AgentThread(id: id, title: title, projectTitle: project, status: status, model: "m", updatedAt: at.addingTimeInterval(-age), isSettled: settled)
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
            "to-steve": [exchange("a", asker: .agent(toPepper), asked: 0)],
            "to-pepper": [exchange("b", asker: .agent(toSteve), asked: 10)],
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
        let brief = exchange("e", asker: .agent(thread("main")), ask: "A long brief")
        let built = book(threads: [started], transcripts: ["worker": [brief]])
        XCTAssertEqual(direct(steve, in: built)?.messages.map(\.text), ["Reply"])
        XCTAssertEqual(direct(steve, in: built)?.messages.map(\.threadTitle), ["Build it"])
        XCTAssertEqual(built.between, [])
    }

    func testAKittenTalkingToItselfWithNoReplyYetHasNoRow() {
        let working = thread("worker", status: .running)
        let built = book(threads: [working], transcripts: ["worker": [exchange("e", asker: .agent(thread("main")), reply: nil)]])
        XCTAssertEqual(direct(steve, in: built)?.messages, [])
    }

    func testAnUnknownSenderStaysOutOfYourDM() throws {
        let built = book(threads: [thread("t")], transcripts: ["t": [
            exchange("archived", asker: .agent(nil), asked: 0),
            exchange("nobodys", asker: .agent(thread("x", project: "Not a kitten")), asked: 5),
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
            "s": [exchange("old", asker: .agent(nil), asked: 0)],
            "p": [exchange("new", asker: .agent(nil), asked: 50)],
        ])
        XCTAssertEqual(built.between.map(\.id), [ChannelID(.someoneElse, .kitten(pepper.id)), ChannelID(.someoneElse, .kitten(steve.id))])
    }

    func testANameOnTheTitleBeatsTheProject() {
        let titled = thread("t", project: "Pepper", title: "Steve: Fix the site")
        XCTAssertEqual(KittenBoard.owner(of: titled, among: [pepper, steve]), steve)
        XCTAssertEqual(KittenBoard.owner(of: thread("t", project: "Pepper"), among: [pepper, steve]), pepper)
        XCTAssertNil(KittenBoard.owner(of: thread("t", project: "site"), among: [pepper, steve]))
    }

    // MARK: Issues

    func testAnIssueIsAnOpenThread() throws {
        let built = book(kittens: [steve], threads: [
            thread("done-unsettled", status: .completed),
            thread("done-settled", status: .completed, settled: true),
            thread("working-settled", status: .running, settled: true),
            thread("someone-elses", project: "site", status: .running),
        ])
        XCTAssertEqual(Set(try XCTUnwrap(built.issues.first).threads.map(\.id)), ["done-unsettled", "working-settled"])
        XCTAssertEqual(built.issueCount, 2)
    }

    func testIssuesPutWhatNeedsYouFirstThenWorkingThenNewest() throws {
        var approving = thread("approving", status: .running, age: 40)
        approving.pendingApprovals = [ApprovalRequest(id: "r", threadID: "approving", threadTitle: "Work", kind: .command, summary: "x", createdAt: at)]
        let built = book(kittens: [steve], threads: [
            thread("old-done", age: 30),
            thread("new-done", age: 1),
            thread("working", status: .running, age: 20),
            thread("asking", status: .waitingForAnswer, age: 50),
            approving,
        ])
        XCTAssertEqual(try XCTUnwrap(built.issues.first).threads.map(\.id), ["approving", "asking", "working", "new-done", "old-done"])
    }

    func testIssuesCoverEveryKittenThatsSetUpWithTheirNameTakenOff() throws {
        let built = book(kittens: [steve, pepper, cali], threads: [thread("t", project: "site", title: "Steve: Fix the site")])
        XCTAssertEqual(built.issues.map(\.kitten), [steve, pepper])
        XCTAssertEqual(built.issues[0].threads.map(\.title), ["Fix the site"])
        XCTAssertEqual(built.issues[1].threads, [])
    }
}
