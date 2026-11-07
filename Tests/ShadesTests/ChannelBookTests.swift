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

    private func book(
        kittens: [Kitten]? = nil,
        threads: [AgentThread] = [],
        transcripts: [String: [Exchange]] = [:],
        waiting: Waiting = Waiting(),
        sent: [SentMessage] = [],
        isUnread: @escaping (AgentThread) -> Bool = { _ in false },
        inGeneral: [String: Date] = [:]
    ) -> ChannelBook {
        ChannelBook.build(
            kittens: kittens ?? [steve, pepper], threads: threads, transcripts: transcripts, isReading: false, unreadable: 0, cantReachT3: false,
            waiting: waiting, sent: sent, isUnread: isUnread, inGeneral: inGeneral
        )
    }

    private func said(_ thread: ChannelThread?) -> [String] {
        thread?.messages.map { "\($0.speaker == .you ? "you" : $0.speaker == .cat ? "cat" : $0.speaker == .someoneElse ? "someone" : "kitten"): \($0.text ?? "-")" } ?? []
    }

    func testThePlacesAreGeneralAChannelForEachKittenAndTheCatsDM() {
        XCTAssertEqual(book(kittens: [steve]).channels.map(\.id), [.general, .kitten(steve.id), .shades])
        let more = book(kittens: [steve, pepper, cali])
        XCTAssertEqual(more.channels.map(\.id), [.general, .of(steve), .of(pepper), .of(cali), .shades])
        XCTAssertTrue(more.channels.allSatisfy(\.posts.isEmpty))
    }

    /// A thread that carries a kitten's name from working in another project, before any of its words are read.
    func testAListedThreadNothingsBeenReadOfLivesWithTheKittenItsTitleNames() {
        let elsewhere = thread("fix", project: "Shades", title: "Steve: Fix login")
        let built = book(threads: [elsewhere])
        XCTAssertEqual(built.listed["fix"]?.title, "Fix login")
        XCTAssertEqual(built.home(ofThread: "fix"), .of(steve), "so Also send names #steve, not #general")
        XCTAssertEqual(book(threads: [elsewhere], inGeneral: ["fix": at]).home(ofThread: "fix"), .general, "unless it was started in #general")
    }

    func testAChannelIsNamedTheWaySlackNamesOne() {
        let named = Kitten(name: "Steve Pawsniak", role: "", covers: "", folder: "/k/sp")
        let built = book(kittens: [named, Kitten(name: "Dr. Mew  2", role: "", covers: "", folder: "/k/m")])
        XCTAssertEqual(built.name(of: .of(named)), "steve-pawsniak")
        XCTAssertEqual(built.title(of: .of(named)), "#steve-pawsniak")
        XCTAssertEqual(built.name(of: ChannelID.kitten("/k/m")), "dr-mew-2")
        XCTAssertEqual(built.title(of: .general), "#general")
        XCTAssertEqual(built.title(of: .shades), "Shades")
    }

    func testEachSessionIsAThreadWhoseParentIsYourAskAndTheRestAreReplies() throws {
        let built = book(threads: [thread("t")], transcripts: ["t": [exchange("a", ask: "Tidy it", reply: "Tidied.", asked: 0), exchange("b", ask: "And the logo?", reply: "Smaller now.", asked: 10)]])
        let thread = try XCTUnwrap(built.threads["t"])
        XCTAssertEqual(thread.parent.text, "Tidy it")
        XCTAssertEqual(thread.replies.compactMap(\.text), ["Tidied.", "And the logo?", "Smaller now."], "oldest first")
        XCTAssertEqual(thread.home, .of(steve))
        XCTAssertEqual(thread.owner, steve.id)
        XCTAssertEqual(built.channel(.of(steve))?.posts, [.thread("t")], "the channel shows only its parent")
        XCTAssertEqual(built.channel(.general)?.posts, [])
    }

    func testAMessageFromAnotherKittenIsAReplyInTheSessionsThreadNotAPairOfKittens() throws {
        let fromPepper = thread("p", project: "Pepper")
        let built = book(threads: [thread("s"), fromPepper], transcripts: [
            "s": [exchange("a", ask: "Tidy it", asked: 0), exchange("b", asker: .agent(threadID: "p"), ask: "Numbers?", reply: "Here.", asked: 10)],
            "p": [exchange("c", asked: 5)],
        ])
        let steves = try XCTUnwrap(built.threads["s"])
        XCTAssertEqual(steves.replies.map(\.speaker), [.kitten(steve.id), .kitten(pepper.id), .kitten(steve.id)])
        XCTAssertEqual(steves.repliers, [.kitten(steve.id), .kitten(pepper.id)])
        XCTAssertEqual(built.channels.map(\.id), [.general, .of(steve), .of(pepper), .shades], "no channel for the pair")
    }

    func testASessionAnotherKittenStartedHasItsAskAsTheParentInTheOwnersChannel() throws {
        let built = book(threads: [thread("s"), thread("p", project: "Pepper")], transcripts: [
            "s": [exchange("a", asker: .agent(threadID: "p"), ask: "Are the names final?", reply: "Yes.")],
            "p": [],
        ])
        let thread = try XCTUnwrap(built.threads["s"])
        XCTAssertEqual(thread.parent.speaker, .kitten(pepper.id))
        XCTAssertEqual(thread.parent.text, "Are the names final?")
        XCTAssertEqual(thread.home, .of(steve))
    }

    func testASessionAKittenStartedItselfHasItsFirstReplyAsTheParent() throws {
        let started = thread("worker", project: "site", title: "Steve: Build it")
        let brief = exchange("e", asker: .agent(threadID: "main"), ask: "A long brief", reply: "Built.")
        let built = book(threads: [started, thread("main")], transcripts: ["worker": [brief, exchange("f", asker: .agent(threadID: "main"), ask: "Another brief", reply: "Tested.", asked: 5)], "main": []])
        let thread = try XCTUnwrap(built.threads["worker"])
        XCTAssertEqual(thread.parent.text, "Built.")
        XCTAssertEqual(thread.replies.compactMap(\.text), ["Tested."], "talking to itself, its briefs get no rows")
        XCTAssertEqual(thread.title, "Build it")
    }

    func testAKittenTalkingToItselfWithNoReplyYetHasNoThread() {
        let working = thread("worker", status: .running)
        let built = book(threads: [working, thread("main")], transcripts: ["worker": [exchange("e", asker: .agent(threadID: "main"), reply: nil)], "main": []])
        XCTAssertNil(built.threads["worker"])
    }

    func testAnUnknownSenderIsSomeoneElseInTheThread() throws {
        let built = book(threads: [thread("t"), thread("x", project: "Not a kitten")], transcripts: ["t": [
            exchange("archived", asker: .agent(threadID: nil), asked: 0),
            exchange("nobodys", asker: .agent(threadID: "x"), asked: 5),
        ]])
        XCTAssertEqual(try XCTUnwrap(built.threads["t"]).messages.map(\.speaker), [.someoneElse, .kitten(steve.id), .someoneElse, .kitten(steve.id)])
    }

    func testAThreadSitsWhereItsParentWasSaidAsInSlack() {
        let built = book(threads: [thread("a"), thread("b")], transcripts: [
            "a": [exchange("first", asked: 0, replied: 100)],
            "b": [exchange("second", asked: 10, replied: 20)],
        ])
        XCTAssertEqual(built.channel(.of(steve))?.posts, [.thread("a"), .thread("b")], "a later reply doesn't move a thread")
    }

    func testOnlyTheLastExchangeOfAnActiveThreadIsStillGoing() throws {
        let built = book(threads: [thread("t", status: .running)], transcripts: ["t": [
            exchange("first", asked: 0, replied: 1),
            exchange("second", reply: nil, asked: 5),
        ]])
        let thread = try XCTUnwrap(built.threads["t"])
        XCTAssertEqual(thread.messages.map(\.id), ["first:ask", "first:reply", "second:ask", "second:reply"])
        XCTAssertEqual(thread.messages.map(\.isStillGoing), [false, false, false, true])
        XCTAssertTrue(thread.isGoing)
        XCTAssertEqual(thread.replyCount, 2, "the reply bar doesn't count what hasn't been said yet")
    }

    func testAThreadWaitingOnYouIsntStillGoing() throws {
        for status in [AgentStatus.waitingForAnswer, .waitingForApproval] {
            let built = book(threads: [thread("t", status: status)], transcripts: ["t": [exchange("e")]])
            let reply = try XCTUnwrap(built.threads["t"]?.latest)
            XCTAssertEqual(reply.text, "Reply")
            XCTAssertFalse(reply.isStillGoing)
        }
        let quiet = book(threads: [thread("t", status: .waitingForAnswer)], transcripts: ["t": [exchange("e", reply: nil)]])
        XCTAssertEqual(said(quiet.threads["t"]), ["you: Ask"])
    }

    func testASubagentAskingYouSomethingIsntStillGoing() throws {
        var asking = thread("t", status: .running)
        asking.pendingQuestion = AgentQuestion(id: "q", threadID: "child", threadTitle: "Work", text: "")
        let built = book(threads: [asking], transcripts: ["t": [exchange("e")]])
        XCTAssertEqual(built.threads["t"]?.latest.isStillGoing, false)
        XCTAssertEqual(built.statuses.first?.state, .needsYou)
        XCTAssertEqual(built.issues.first?.threads.first?.status, .waitingForAnswer, "its row says so too, however the thread was listed")
    }

    func testWhatsWrongNowComesBeforeOlderMessages() {
        let lost = ChannelBook.build(kittens: [steve], threads: [thread("t")], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: true)
        XCTAssertEqual(ChannelRows.rows(.channel(.of(steve)), in: lost), [.note(CatWords.cantReachT3Yet)])
        let failed = ChannelBook.build(kittens: [steve], threads: [thread("t")], transcripts: [:], isReading: false, unreadable: 1, cantReachT3: false)
        XCTAssertEqual(ChannelRows.rows(.channel(.of(steve)), in: failed), [.note(CatWords.couldntRead(1))])

        let threads = [thread("read"), thread("missing")]
        let said = ["read": [exchange("e")]]
        func notes(unreadable: Int, cantReachT3: Bool) -> [String] {
            let built = ChannelBook.build(kittens: [steve], threads: threads, transcripts: said, isReading: false, unreadable: unreadable, cantReachT3: cantReachT3)
            return ChannelRows.rows(.channel(.of(steve)), in: built).compactMap { if case .note(let text) = $0 { return text } else { return nil } }
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
        XCTAssertEqual(built.threads["t"]?.messages.compactMap(\.text), ["First", "Still narrating", "Queued"])
    }

    func testWhoSentItIsLookedUpWhenItsShown() throws {
        let sender = thread("sender", project: "site", title: "Work")
        let transcripts = ["t": [exchange("e", asker: .agent(threadID: "sender"))], "sender": []]
        let before = book(threads: [thread("t"), sender], transcripts: transcripts)
        XCTAssertEqual(before.threads["t"]?.parent.speaker, .someoneElse)

        var renamed = sender
        renamed.title = "Pepper: Work"
        let after = book(threads: [thread("t"), renamed], transcripts: transcripts)
        XCTAssertEqual(after.threads["t"]?.parent.speaker, .kitten(pepper.id))
    }

    func testAThreadThatWasntReadDoesntMakeAChannelClaimYouveNeverTalked() throws {
        let built = book(threads: [thread("old")])
        let channel = try XCTUnwrap(built.channel(.of(steve)))
        XCTAssertTrue(channel.isCut)
        XCTAssertEqual(ChannelRows.rows(.channel(channel.id), in: built), [.note(CatWords.olderMessages)])
        XCTAssertFalse(try XCTUnwrap(built.channel(.of(pepper))).isCut)

        let reading = ChannelBook.build(kittens: [steve], threads: [thread("old")], transcripts: [:], isReading: true, unreadable: 0, cantReachT3: false)
        XCTAssertEqual(reading.channel(.of(steve))?.isCut, false)
    }

    func testAThreadCarryingAnotherKittensNameCountsOnlyForThatKitten() {
        var waiting = thread("t", project: "Steve", title: "Pepper: Work", status: .waitingForAnswer)
        waiting.title = "Pepper: Work"
        let built = book(threads: [waiting], transcripts: ["t": [exchange("e")]])
        XCTAssertEqual(built.statuses.map(\.state), [.idle, .needsYou])
        XCTAssertEqual(built.issues.map(\.threads.count), [0, 1])
        XCTAssertEqual(built.threads["t"]?.home, .of(pepper))
    }

    func testASettledThreadThatNeedsYouIsAnIssue() {
        var waiting = thread("t", settled: true)
        waiting.pendingQuestion = AgentQuestion(id: "q", threadID: "child", threadTitle: "Work", text: "")
        XCTAssertEqual(book(threads: [waiting]).issueCount, 1)
    }

    func testAPlannedKittensChannelWithUnreadThreadsPointsAtT3() {
        let built = book(kittens: [steve, cali], threads: [thread("t", project: "Cali", status: .completed)])
        XCTAssertEqual(ChannelRows.rows(.channel(.of(cali)), in: built), [.note(CatWords.olderMessages)])
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
        XCTAssertEqual(built.threads["t"]?.latest.failure, "Ran out of quota")
        XCTAssertNil(built.threads["t"]?.latest.text)
    }

    func testAnExchangeWithNothingToShowHasNoThread() {
        let built = book(threads: [thread("t")], transcripts: ["t": [exchange("e", ask: nil, reply: nil)]])
        XCTAssertNil(built.threads["t"])
        XCTAssertEqual(built.channel(.of(steve))?.posts, [])
    }

    func testNarrationCountComesAlong() {
        var narrated = exchange("e")
        narrated.earlierNotes = 2
        let built = book(threads: [thread("t")], transcripts: ["t": [narrated]])
        XCTAssertEqual(built.threads["t"]?.messages.map(\.earlierNotes), [0, 2])
    }

    func testEachChannelKeepsItsNewestPosts() throws {
        let threads = (0..<203).map { thread("t\($0)", age: TimeInterval(203 - $0)) }
        let transcripts = Dictionary(uniqueKeysWithValues: (0..<203).map { ("t\($0)", [exchange("e\($0)", asked: TimeInterval($0))]) })
        let channel = try XCTUnwrap(book(threads: threads, transcripts: transcripts).channel(.of(steve)))
        XCTAssertTrue(channel.isCut)
        XCTAssertEqual(channel.posts.count, 200)
        XCTAssertEqual(channel.posts.first, .thread("t3"))
        XCTAssertEqual(channel.posts.last, .thread("t202"))
    }

    func testALongThreadKeepsItsParent() throws {
        // The feed keeps a thread's first exchange and its newest, so the one that started it is never lost.
        let many = (0..<ChannelBook.keptExchanges).map { exchange("e\($0)", ask: $0 == 0 ? "Start here" : "More", asked: TimeInterval($0)) }
        let thread = try XCTUnwrap(book(threads: [thread("t")], transcripts: ["t": many]).threads["t"])
        XCTAssertEqual(thread.parent.text, "Start here")
        XCTAssertTrue(thread.isCut)
        XCTAssertEqual(ChannelRows.thread("t", in: book(threads: [self.thread("t")], transcripts: ["t": many])).prefix(3), [.message(thread.parent), .replies(thread.replyCount), .note(CatWords.olderReplies)])
    }

    func testANameOnTheTitleBeatsTheProject() {
        let titled = thread("t", project: "Pepper", title: "Steve: Fix the site")
        XCTAssertEqual(KittenBoard.owner(of: titled, among: [pepper, steve]), steve)
        XCTAssertEqual(KittenBoard.owner(of: thread("t", project: "Pepper"), among: [pepper, steve]), pepper)
        XCTAssertNil(KittenBoard.owner(of: thread("t", project: "site"), among: [pepper, steve]))
    }

    func testAFolderCountsHoweverItsPathIsWritten() {
        let worker = Kitten(name: "Worker", role: "", covers: "", folder: "/k/worker", project: "/code/site")
        let at = { (path: String) in AgentThread(id: "t", title: "Work", projectTitle: nil, status: .completed, model: "m", updatedAt: self.at, projectPath: path) }
        XCTAssertEqual(KittenBoard.owner(of: at("/k/worker/"), among: [steve, worker]), worker)
        XCTAssertEqual(KittenBoard.owner(of: at("/k/steve/../worker"), among: [steve, worker]), worker)
        XCTAssertEqual(KittenBoard.owner(of: at("/code/site"), among: [steve, worker]), worker, "its project counts too")
        XCTAssertNil(KittenBoard.owner(of: at("/code/site/more"), among: [steve, worker]))
    }

    func testBuildingTheBookWorksOutEachThreadsOwnerOnce() throws {
        // Standardizing a thread's folder is slow, and a build used to ask every thread's owner again at each step.
        let kittens = (0..<6).map { Kitten(name: "Kitten \($0)", role: "", covers: "", folder: "/k/\($0)") }
        let threads = (0..<800).map { thread("\($0)", project: "elsewhere-\($0 % 30)") }
        func best(_ work: () -> Void) -> TimeInterval {
            (0..<3).map { _ in
                let start = Date()
                work()
                return Date().timeIntervalSince(start)
            }.min() ?? 0
        }
        let askingEachOnce = best { for thread in threads { _ = KittenBoard.owner(of: thread, among: kittens) } }
        let building = best { _ = book(kittens: kittens, threads: threads) }
        XCTAssertLessThan(building, askingEachOnce * 2, "a build takes \(building)s, and asking each thread once takes \(askingEachOnce)s")
    }

    func testAnIssueIsAnOpenThreadAndAFinishedOneIsntWhetherOrNotItsSettled() throws {
        let built = book(kittens: [steve], threads: [
            thread("done-unsettled", status: .completed, age: 1),
            thread("done-settled", status: .completed, settled: true, age: 2),
            thread("failed-unsettled", status: .failed),
            thread("failed-settled", status: .failed, settled: true, age: 3),
            thread("working-settled", status: .running, settled: true),
            thread("someone-elses", project: "site", status: .running),
        ])
        XCTAssertEqual(Set(try XCTUnwrap(built.issues.first).threads.map(\.id)), ["failed-unsettled", "working-settled"])
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

    // MARK: - Home channels

    func testAThreadStartedFromGeneralLivesThereAndOtherwiseInItsKittensChannel() throws {
        let built = book(
            threads: [thread("from-general"), thread("own"), thread("cats", project: nil)],
            transcripts: ["from-general": [exchange("a")], "own": [exchange("b")], "cats": [exchange("c", ask: nil, reply: "Done.")]],
            inGeneral: ["from-general": at, "cats": at]
        )
        XCTAssertEqual(built.threads["from-general"]?.home, .general)
        XCTAssertEqual(built.threads["from-general"]?.owner, steve.id, "still its kitten's work")
        XCTAssertEqual(built.threads["own"]?.home, .of(steve))
        XCTAssertEqual(built.threads["cats"]?.home, .general, "the cat's own work no kitten owns")
        XCTAssertEqual(built.threads["cats"]?.parent.speaker, .cat)
        XCTAssertEqual(built.channel(.general)?.posts, [.thread("from-general"), .thread("cats")])
        XCTAssertEqual(built.channel(.of(steve))?.posts, [.thread("own")])
    }

    func testTheCatsOwnWorkOnlyShowsIfMessagesPassedYourWordsToIt() {
        let built = book(threads: [thread("ask-box", project: nil)], transcripts: ["ask-box": [exchange("a")]])
        XCTAssertNil(built.threads["ask-box"], "anything else the cat started can hold your screen")
    }

    func testWorkTheCatPassedOnFromGeneralSpeaksAsTheCat() throws {
        let built = book(
            threads: [thread("dispatcher", project: nil), thread("worker", project: "Pepper")],
            transcripts: ["worker": [exchange("w", asker: .agent(threadID: "dispatcher"), ask: "Check the budget", reply: "It's fine.")]],
            inGeneral: ["dispatcher": at, "worker": at]
        )
        XCTAssertEqual(try XCTUnwrap(built.threads["worker"]).parent.speaker, .cat)
        XCTAssertEqual(built.threads["worker"]?.home, .general)
    }

    func testYourWordsStartAThreadTheyGoToEvenBeforeT3HasIt() throws {
        let sent = echo("Find a flight", in: .general, thread: "handed")
        let waiting = book(threads: [], sent: [sent], inGeneral: ["handed": at])
        let thread = try XCTUnwrap(waiting.threads["handed"])
        XCTAssertEqual(thread.parent.text, "Find a flight")
        XCTAssertEqual(thread.home, .general)
        XCTAssertEqual(waiting.channel(.general)?.posts, [.thread("handed")])

        // The frontier agent's prompt carries no words of yours, so what you said stays its parent.
        let read = book(
            threads: [self.thread("handed", project: nil)],
            transcripts: ["handed": [exchange("h", ask: nil, reply: "Found one for $212.", asked: 5)]],
            sent: [sent], inGeneral: ["handed": at]
        )
        XCTAssertEqual(said(read.threads["handed"]), ["you: Find a flight", "cat: Found one for $212."])
    }

    func testANewTopicIsAThreadOfItsOwnUntilT3HasOne() throws {
        let topic = SentMessage(channel: .of(steve), message: ChannelMessage(exchangeID: "sent-topic", kind: .ask, speaker: .you, text: "Tidy it", at: at, threadID: "", threadTitle: ""), startsThread: true)
        let starting = book(sent: [topic])
        XCTAssertEqual(starting.threads["sent-topic"]?.isStarting, true)
        XCTAssertEqual(starting.threads["sent-topic"]?.home, .of(steve))
        XCTAssertEqual(starting.channel(.of(steve))?.posts, [.thread("sent-topic")])

        var started = topic
        started.message.threadID = "t"
        let read = book(threads: [thread("t")], transcripts: ["t": [exchange("e", ask: "Tidy it", asked: 1)]], sent: [started])
        XCTAssertEqual(read.started["sent-topic"], "t")
        XCTAssertEqual(said(read.threads["t"]), ["you: Tidy it", "kitten: Reply"], "said once, by T3")
        XCTAssertNil(read.threads["sent-topic"])
    }

    // MARK: - Also send to #channel

    private func echo(_ text: String, at offset: TimeInterval = 0, in channel: ChannelID, thread: String = "", alsoSent: Bool = false, speaker: Speaker = .you) -> SentMessage {
        SentMessage(
            channel: channel,
            message: ChannelMessage(exchangeID: "sent-\(text)", kind: speaker == .you ? .ask : .reply, speaker: speaker, text: text, at: at.addingTimeInterval(offset), threadID: thread, threadTitle: ""),
            alsoSent: alsoSent
        )
    }

    func testAReplyAlsoSentToTheChannelShowsThereAndInItsThread() throws {
        let reply = echo("Keep the FAQ", at: 10, in: .of(steve), thread: "t", alsoSent: true)
        let waiting = book(threads: [thread("t")], transcripts: ["t": [exchange("e", ask: "Rewrite it", asked: 0)]], sent: [reply])
        XCTAssertEqual(waiting.threads["t"]?.latest.text, "Keep the FAQ", "in the thread at once")
        var shown = reply.message
        shown.threadTitle = "Work"
        XCTAssertEqual(waiting.channel(.of(steve))?.posts, [.thread("t"), .alsoSent(shown, thread: "t")])

        let heard = book(threads: [thread("t")], transcripts: ["t": [exchange("e", ask: "Rewrite it", asked: 0), exchange("f", ask: "Keep the FAQ", reply: nil, asked: 11)]], sent: [reply])
        let echoed = try XCTUnwrap(heard.threads["t"]?.latest)
        XCTAssertEqual(echoed.id, "f:ask", "once T3 has it, it's T3's copy")
        XCTAssertEqual(heard.channel(.of(steve))?.posts, [.thread("t"), .alsoSent(echoed, thread: "t")], "and it stays in the channel")
        XCTAssertEqual(heard.threads["t"]?.messages.filter { $0.text == "Keep the FAQ" }.count, 1)
    }

    func testAReplyThatsntAlsoSentStaysInItsThread() {
        let reply = echo("Keep the FAQ", at: 10, in: .of(steve), thread: "t")
        let built = book(threads: [thread("t")], transcripts: ["t": [exchange("e", asked: 0)]], sent: [reply])
        XCTAssertEqual(built.channel(.of(steve))?.posts, [.thread("t")])
        XCTAssertEqual(built.threads["t"]?.latest.text, "Keep the FAQ")
    }

    func testAReplyToAThreadMessagesHasntReadOnlyShowsInItsThreadUnlessItsAlsoSent() throws {
        var reply = echo("Ship it", at: 10, in: .of(steve), thread: "t")
        reply.isReply = true
        let built = book(threads: [thread("t")], sent: [reply])
        XCTAssertEqual(built.channel(.of(steve))?.posts, [], "the channel gets no new post")
        XCTAssertEqual(try XCTUnwrap(built.threads["t"]).messages.map(\.text), ["Ship it"], "and the thread shows just what you sent there")
        XCTAssertEqual(built.home(ofThread: "t"), .of(steve))

        reply.alsoSent = true
        XCTAssertEqual(book(threads: [thread("t")], sent: [reply]).channel(.of(steve))?.posts.count, 1, "ticked, it shows in the channel too")
    }

    func testWhatYouSentShowsAtOnceAndGoesOnceT3HasIt() {
        let waitingForT3 = book(threads: [thread("s")], transcripts: ["s": []], sent: [echo("Anyone?", in: .general)])
        XCTAssertEqual(waitingForT3.channel(.general)?.posts.count, 1)
        XCTAssertEqual(waitingForT3.channel(.general)?.posts.first, .message(echo("Anyone?", in: .general).message))
    }

    func testAnOldMessageWithTheSameWordsDoesntHideANewOne() {
        let built = book(threads: [thread("s")], transcripts: ["s": [exchange("s1", ask: "ok", asked: -600)]], sent: [echo("ok", in: .of(steve), thread: "s")])
        XCTAssertEqual(built.threads["s"]?.messages.filter { $0.speaker == .you }.count, 2)
    }

    func testTheCatsOwnAnswerInGeneralIsAPlainMessageAfterYours() {
        let built = book(sent: [echo("What day is it?", in: .general), echo("It's Tuesday.", at: 2, in: .general, speaker: .cat)])
        XCTAssertEqual(built.channel(.general)?.posts.map { post -> Speaker? in if case .message(let message) = post { message.speaker } else { nil } }, [.you, .cat])
        XCTAssertTrue(built.threads.isEmpty)
        XCTAssertEqual(built.name(of: .cat), "Shades")
    }

    // MARK: - Unread and badges

    func testAKittenIsUnreadWhenAnyOfItsThreadsIs() {
        let built = book(threads: [thread("s"), thread("p", project: "Pepper"), thread("nobody", project: nil)], transcripts: ["s": [exchange("e")]], isUnread: { $0.id != "p" })
        XCTAssertEqual(built.unread, [steve.id])
        XCTAssertTrue(built.isUnread(.of(steve)))
        XCTAssertFalse(built.isUnread(.of(pepper)))
        XCTAssertEqual(built.unreadThreads, ["s"], "only threads that are shown")
        XCTAssertFalse(built.isUnread(.general))
    }

    func testGeneralIsUnreadWhenAThreadThatLivesThereIs() {
        let built = book(threads: [thread("s")], transcripts: ["s": [exchange("e")]], isUnread: { _ in true }, inGeneral: ["s": at])
        XCTAssertTrue(built.isUnread(.general))
        XCTAssertTrue(built.isUnread(.of(steve)), "and its kitten has a run you haven't seen")
    }

    func testAChannelsBadgeCountsWhatItsKittenIsWaitingOnYouFor() {
        let waiting = Waiting(
            approvals: [ApprovalRequest(id: "a", threadID: "s", threadTitle: "Work", kind: .command, summary: "Run: ls", createdAt: at)],
            questions: [AgentQuestion(id: "q", threadID: "s", threadTitle: "Work", text: "Which?")],
            owners: ["a": steve.id, "q": steve.id],
            reports: [
                InboxEntry(id: "d", kind: .decision, text: "Merged. Say ship it.", threadID: "p", threadTitle: "Plans", at: at),
                InboxEntry(id: "n", kind: .shipped, text: "Shipped.", threadID: "p", threadTitle: "Plans", at: at),
            ]
        )
        let built = book(threads: [thread("s"), thread("p", project: "Pepper")], waiting: waiting)
        XCTAssertEqual(built.badge(of: .of(steve)), 2)
        XCTAssertEqual(built.badge(of: .of(pepper)), 1, "a decision counts and something shipped doesn't")
        XCTAssertEqual(built.badge(of: .general), 0)
        XCTAssertEqual(built.waiting.count, 3, "Activity's total")
        let items = ChannelSidebarItem.groups(in: built).flatMap(\.items)
        XCTAssertEqual(items.map(\.badge), [3, 0, 0, 2, 1, 0])
    }

    func testWaitingItemsKnowTheirKittenAndReportsAreTracedThroughTheirThread() {
        let waiting = Waiting(
            approvals: [ApprovalRequest(id: "a", threadID: "s", threadTitle: "Work", kind: .command, summary: "Run: ls", createdAt: at)],
            owners: ["a": steve.id],
            reports: [InboxEntry(id: "r", kind: .decision, text: "Merged. Say ship it.", threadID: "p", threadTitle: "Plans", at: at)]
        )
        let built = book(threads: [thread("s"), thread("p", project: "Pepper")], waiting: waiting)
        XCTAssertEqual(built.kitten(of: "a"), steve)
        XCTAssertEqual(built.kitten(of: "r"), pepper)
        XCTAssertEqual(built.waiting.count, 2)
    }

    // MARK: - Threads

    func testThreadsAreEveryThreadYouWroteInWithUnreadFirstThenNewest() {
        let built = book(
            threads: [thread("yours-old"), thread("yours-new"), thread("unread"), thread("not-yours")],
            transcripts: [
                "yours-old": [exchange("a", asked: 0)],
                "yours-new": [exchange("b", asked: 50)],
                "unread": [exchange("c", asked: 10)],
                "not-yours": [exchange("d", asker: .agent(threadID: nil), asked: 60)],
            ],
            isUnread: { $0.id == "unread" }
        )
        XCTAssertEqual(built.yours.map(\.id), ["unread", "yours-new", "yours-old"])
    }
}

// MARK: - Talking to the cat

extension ChannelBookTests {
    private func talk(_ id: String, title: String = "Which plan is cheapest here?", status: AgentStatus = .completed) -> AgentThread {
        AgentThread(id: id, title: title, projectTitle: "Shades router", status: status, model: "m", updatedAt: at, projectPath: "/shades/router")
    }

    func testWhatYouAskedTheCatIsAThreadInItsDM() throws {
        let built = ChannelBook.build(
            kittens: [steve, pepper],
            threads: [talk("r"), thread("t")],
            transcripts: [
                "r": [
                    exchange("1", ask: "Which plan is cheapest here?", reply: "Starter, at $8 a month."),
                    exchange("2", ask: "And the fonts?", reply: "\(Prompts.kittenMarker) 1", asked: 10),
                    exchange("3", ask: "Compare the fonts", reply: "\(Prompts.handoffMarker) Compare pixel fonts", asked: 20),
                    exchange("4", ask: "It's 12 people, not 20", reply: "\(Prompts.correctionMarker) 2", asked: 30),
                    exchange("5", ask: "Hello?", reply: "\(Prompts.routeMarker) 3", asked: 40),
                ],
                "t": [exchange("e")],
            ],
            isReading: false, unreadable: 0, cantReachT3: false,
            withShades: ["r"]
        )
        XCTAssertEqual(said(built.threads["r"]), [
            "you: Which plan is cheapest here?", "cat: Starter, at $8 a month.",
            "you: And the fonts?", "cat: \(CatWords.passedOnToKitten)",
            "you: Compare the fonts", "cat: \(CatWords.handedOff("Compare pixel fonts"))",
            "you: It's 12 people, not 20", "cat: \(CatWords.passedOnCorrection)",
            "you: Hello?", "cat: \(CatWords.passedOnToSession)",
        ])
        XCTAssertEqual(built.threads["r"]?.home, .shades)
        XCTAssertEqual(built.channel(.shades)?.posts, [.thread("r")])
        XCTAssertEqual(built.channel(.general)?.posts, [], "#general is the kittens, not the cat's own threads")
        XCTAssertFalse(built.yours.contains { $0.id == "r" }, "and Threads leaves talks in the DM")
    }

    func testALiveTestOfTheCatIsntShown() {
        let built = ChannelBook.build(kittens: [steve], threads: [talk("r", title: "Shades test: ask")], transcripts: ["r": [exchange("1")]], isReading: false, unreadable: 0, cantReachT3: false, withShades: ["r"])
        XCTAssertNil(built.threads["r"])
        XCTAssertEqual(built.channel(.shades)?.posts, [])
    }

    func testWhatYouSaidInGeneralStaysThereWhenTheRouterHasIt() {
        let sent = echo("What day is it?", in: .general)
        let built = ChannelBook.build(
            kittens: [steve], threads: [talk("r")], transcripts: ["r": [exchange("1", ask: "What day is it?", reply: "Friday.")]],
            isReading: false, unreadable: 0, cantReachT3: false, sent: [sent], withShades: ["r"]
        )
        XCTAssertEqual(built.channel(.general)?.posts, [.message(sent.message)], "the router's copy is in the cat's DM, not #general's")
    }

    func testWhatYouSaidToTheCatAndItsAnswerKeepShowingInItsDMOnceTheRouterHasThem() throws {
        let asked = echo("What day is it?", at: 20, in: .shades, thread: "r", alsoSent: true)
        let answered = echo("Friday.", at: 22, in: .shades, thread: "r", alsoSent: true, speaker: .cat)
        let waiting = ChannelBook.build(kittens: [steve], threads: [], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false, sent: [asked, answered])
        XCTAssertEqual(waiting.channel(.shades)?.posts, [.message(asked.message), .message(answered.message)], "it shows at once")

        let read = ChannelBook.build(
            kittens: [steve], threads: [talk("r")],
            transcripts: ["r": [exchange("1", ask: "Earlier", reply: "Earlier answer."), exchange("2", ask: "What day is it?", reply: "Friday.", asked: 21)]],
            isReading: false, unreadable: 0, cantReachT3: false, sent: [asked, answered], withShades: ["r"]
        )
        let thread = try XCTUnwrap(read.threads["r"])
        XCTAssertEqual(thread.messages.compactMap(\.text), ["Earlier", "Earlier answer.", "What day is it?", "Friday."], "once T3 has it, only T3's copy")
        XCTAssertEqual(read.channel(.shades)?.posts, [.thread("r"), .alsoSent(thread.replies[1], thread: "r"), .alsoSent(thread.replies[2], thread: "r")])
    }
}

extension ChannelBook {
    /// Everything said in the cat's DM, talk by talk, for tests that read it as one conversation.
    var shadesMessages: [ChannelMessage] {
        threads(in: .shades).flatMap { threads[$0]?.messages ?? [] }
    }
}
