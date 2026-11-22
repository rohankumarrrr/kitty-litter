import Foundation
@testable import Shades
import ShadesCore
import XCTest

/// A kitten asks for your yes to do something itself, in the form or in plain words, and only your Allow says yes, to
/// exactly what its card showed, through the app's own controller with a fake T3 that records everything sent.
@MainActor
final class AskFlowTests: XCTestCase {
    private var backend: FakeBackend!
    private var stage: FakeStage!
    private var controller: AppController!
    private var kittens: [Kitten] = []
    private var savedInbox: Inbox?
    private var notified: [NeedsYouAlert] = []
    private let clock = Date(timeIntervalSince1970: 100_000)
    private let clawde = Kitten(name: "Clawde", role: "The system", covers: "", folder: "/k/clawde", seesScreen: false, usesInbox: true)
    private let steve = Kitten(name: "Steve", role: "Professional", covers: "", folder: "/k/steve")
    /// What the sorter makes of a report, and what Shades reads from its decision.
    private var sorted = "DECISION: Merge pull request #12? Its tests pass."
    private var reading = "ASK: Merge pull request #12 in kitty-litter.\nRECOMMEND: I'd allow it. Its tests pass, and a merge can be undone."
    private let written = "I'd allow it. It merges one pull request whose tests pass."

    override func setUp() async throws {
        kittens = [clawde, steve]
        backend = FakeBackend()
        backend.replyTo = { [unowned self] prompt in
            if prompt.text.contains("What it needs:") { return [.finished(fullText: self.reading)] }
            if prompt.text.contains("What it would do on a yes:") { return [.finished(fullText: self.written)] }
            if prompt.text.hasPrefix("Below is the final report") { return [.finished(fullText: self.sorted)] }
            return nil
        }
        stage = FakeStage(log: Log())
        var settings = Settings()
        settings.quickModel = ModelChoice(provider: "claudeAgent", model: "claude-haiku-5-5", effort: "medium")
        settings.notifyFinished = true
        controller = AppController(
            dependencies: AppDependencies(
                backend: backend,
                context: FakeContext(log: Log()),
                voice: FakeVoice(),
                inserter: FakeInserter(),
                keys: FakeKeys(),
                settings: settings,
                saveSettings: { _ in },
                kittens: { [unowned self] in self.kittens },
                home: NSTemporaryDirectory(),
                routerFolder: { "/shades/router" },
                inbox: Inbox(since: .distantPast),
                saveInbox: { [unowned self] in self.savedInbox = $0 },
                notify: { [unowned self] in self.notified.append($0) }
            ),
            stage: stage,
            now: { [unowned self] in self.clock }
        )
        controller.threadListWait = 0
        controller.reportDelay = 0
    }

    private func thread(_ id: String, of kitten: Kitten, status: AgentStatus = .completed) -> AgentThread {
        AgentThread(id: id, title: "\(kitten.name): Fix login", projectTitle: nil, status: status, model: "m", updatedAt: clock, projectPath: kitten.folder, lastRunID: "run-\(id)", lastRunEndedAt: clock)
    }

    private func finishClawde(_ report: String, failed: Bool = false) async {
        backend.reports["w"] = report
        controller.threadsChanged([thread("w", of: clawde, status: failed ? .failed : .completed)])
        for _ in 0..<50 where !controller.filing.isEmpty {
            await controller.reportTask?.value
            await Task.yield()
        }
        await settleReading()
    }

    private func settleReading() async {
        for _ in 0..<100 { await Task.yield() }
    }

    private func settle() async {
        await controller.forwardTask?.value
        for _ in 0..<20 { await Task.yield() }
    }

    private var told: [FakeBackend.Sent] { backend.sent.filter { $0.mode == .forward } }

    private func block(_ object: [String: String]) -> String {
        let json = String(decoding: try! JSONSerialization.data(withJSONObject: object, options: .sortedKeys), as: UTF8.self)
        return "The fix is ready.\n\n```shades-request\n\(json)\n```"
    }

    // MARK: - A turn that ends while something it'll wake up for carries on

    /// Watching its pull request, say. It isn't done, but its turn has ended, so what it said is there to read.
    private func waiting(_ id: String, of kitten: Kitten) -> AgentThread {
        var waiting = thread(id, of: kitten, status: .running)
        waiting.turnEnded = true
        return waiting
    }

    private func endTurn(_ id: String, of kitten: Kitten) async {
        controller.threadsChanged([thread(id, of: kitten, status: .running)])
        controller.threadsChanged([waiting(id, of: kitten)])
        for _ in 0..<50 where !controller.filing.isEmpty {
            await controller.reportTask?.value
            await Task.yield()
        }
        await controller.reportTask?.value
        await settleReading()
    }

    private func saidDone(_ id: String) -> Bool {
        stage.bubbles.contains { bubble in
            guard case .notice(let caption, _, let threadID, _)? = bubble else { return false }
            return caption.hasSuffix("Fix login") && threadID == id
        }
    }

    private var looks: Int { backend.sent.filter { $0.prompt.text.contains("What it would do on a yes:") }.count }

    func testAKittenWatchingItsPullRequestGetsItsCardAndIsOnlyDoneOnceThatsOver() async throws {
        sorted = "NOTE: The fix is ready."
        backend.reports["s"] = block(["ask": "Merge pull request #12 in kitty-litter.", "why": "Its tests pass."])
        await endTurn("s", of: steve)
        XCTAssertEqual(controller.inbox.entries.filter { $0.ask != nil }.map(\.threadID), ["s"], "its card")
        XCTAssertFalse(controller.inbox.owes(waiting("s", of: steve)), "its run is seen")
        XCTAssertFalse(saidDone("s"))
        XCTAssertEqual(stage.celebrated, 0)
        XCTAssertFalse(notified.contains { $0.kind == .finished })

        controller.threadsChanged([thread("s", of: steve)])
        await controller.reportTask?.value
        await settleReading()
        XCTAssertTrue(saidDone("s"), "done once nothing it'll wake up for is left")
        XCTAssertEqual(stage.celebrated, 1)
        XCTAssertEqual(notified.filter { $0.kind == .finished }.map(\.threadID), ["s"])
        XCTAssertEqual(looks, 1, "its card is only looked into once")
        XCTAssertEqual(controller.inbox.entries.filter { $0.ask != nil }.count, 1)
    }

    func testWhatAKittenWatchingItsPullRequestNeedsFromYouIsFlagged() async throws {
        backend.reports["s"] = "I opened pull request #12, and I'm watching it. Should I merge it?"
        await endTurn("s", of: steve)
        let entry = try XCTUnwrap(controller.inbox.entries.first { $0.kind == .decision })
        XCTAssertEqual(entry.threadID, "s")
        XCTAssertEqual(entry.text, "Merge pull request #12? Its tests pass.")
        XCTAssertEqual(notified.map(\.kind), [.decision])
        XCTAssertFalse(saidDone("s"))
    }

    func testAnInboxKittensTurnThatEndsWhileItWatchesItsPullRequestIsFiled() async throws {
        sorted = "NOTE: Pull request #12 is open."
        backend.reports["w"] = "Pull request #12 is open, and I'm watching it."
        await endTurn("w", of: clawde)
        XCTAssertEqual(controller.inbox.entries.map(\.text), ["Pull request #12 is open."])
        XCTAssertFalse(controller.inbox.owes(waiting("w", of: clawde)), "filed, so it's handled")
        XCTAssertFalse(notified.contains { $0.kind == .finished }, "it isn't done")
        XCTAssertEqual(stage.celebrated, 0)
    }

    func testAWrittenAskIsItsOwnCardAndAllowSaysYesToExactlyThat() async throws {
        sorted = "NOTE: The fix is ready."
        await finishClawde(block(["ask": "Merge pull request #12 in kitty-litter.", "why": "Its tests pass."]))
        let entry = try XCTUnwrap(controller.inbox.entries.first { $0.ask != nil })
        let ask = try XCTUnwrap(entry.ask)
        XCTAssertFalse(ask.readFromWords)
        XCTAssertEqual(ask.review, written)
        XCTAssertEqual(savedInbox?.entries.first { $0.id == entry.id }, entry, "saved with the run")
        let look = try XCTUnwrap(backend.sent.first { $0.prompt.text.contains("What it would do on a yes:") })
        XCTAssertEqual(look.prompt.projectID, "project-router", "it runs where no tool that acts, sends or reads a file works")

        controller.inboxAction(.allow(id: entry.id))
        await settle()
        let note = try XCTUnwrap(told.last)
        XCTAssertEqual(note.threadID, "w")
        XCTAssertEqual(note.behavior, .queue)
        XCTAssertTrue(note.prompt.text.contains("pressed Allow on your ask: \"Merge pull request #12 in kitty-litter.\""), note.prompt.text)
        XCTAssertNil(Prompts.ownWords(in: note.prompt.text), "nothing The Kitty Litter sends can pass for your words")
        XCTAssertFalse(controller.inbox.entries.contains { $0.id == entry.id })
    }

    func testDenyOnAWrittenAskTellsTheKittenNo() async throws {
        sorted = "NOTE: The fix is ready."
        await finishClawde(block(["ask": "Delete the old branch."]))
        let entry = try XCTUnwrap(controller.inbox.entries.first { $0.ask != nil })
        controller.inboxAction(.deny(id: entry.id))
        await settle()
        XCTAssertTrue(told.last?.prompt.text.contains("pressed Deny on your ask: \"Delete the old branch.\", so don't do it.") == true)
        XCTAssertEqual(told.count, 1)
    }

    /// Plain words never become an action without a card that shows exactly what would happen.
    func testADecisionInPlainWordsGetsAnExactAskAndAllowSaysYesToOnlyThat() async throws {
        await finishClawde("I fixed the login bug and opened pull request #12. A secret line about the report. Should I merge it?")
        let entry = try XCTUnwrap(controller.inbox.entries.first { $0.kind == .decision })
        XCTAssertEqual(entry.text, "Merge pull request #12? Its tests pass.")
        let ask = try XCTUnwrap(entry.ask)
        XCTAssertEqual(ask, AskRequest(ask: "Merge pull request #12 in kitty-litter.", review: "I'd allow it. Its tests pass, and a merge can be undone.", readFromWords: true))
        let read = try XCTUnwrap(backend.sent.first { $0.prompt.text.contains("What it needs:") })
        XCTAssertEqual(read.prompt.projectID, "project-router")
        XCTAssertTrue(read.prompt.text.contains("What it needs: Merge pull request #12? Its tests pass."))
        XCTAssertFalse(read.prompt.text.contains("A secret line about the report"), "it reads only the decision")
        XCTAssertEqual(savedInbox?.entries.first { $0.id == entry.id }?.ask, ask, "kept with the decision")

        controller.inboxAction(.allow(id: entry.id))
        await settle()
        let note = try XCTUnwrap(told.last)
        XCTAssertEqual(note.threadID, "w")
        XCTAssertTrue(note.prompt.text.contains("which The Kitty Litter read as: \"Merge pull request #12 in kitty-litter.\""), note.prompt.text)
        XCTAssertTrue(note.prompt.text.contains("If that isn't what you asked, don't act on it"))
        XCTAssertNil(Prompts.ownWords(in: note.prompt.text))
        XCTAssertFalse(controller.inbox.entries.contains { $0.id == entry.id })
    }

    /// The sorter can still write a decision about a request that has its card, and that's never a second ask.
    func testADecisionBesideAWrittenRequestIsntReadForAnotherAsk() async throws {
        await finishClawde(block(["ask": "Merge pull request #12 in kitty-litter."]))
        XCTAssertFalse(backend.sent.contains { $0.prompt.text.contains("What it needs:") })
        XCTAssertEqual(controller.inbox.entries.filter { $0.ask != nil }.map(\.ask?.readFromWords), [false])
    }

    func testADecisionWithNothingForTheKittenToDoStaysAsItWas() async throws {
        reading = "NONE"
        sorted = "DECISION: Run git pull in your checkout, since the sandbox can't."
        await finishClawde("Done. Run git pull in your checkout yourself, since my sandbox can't.")
        let entry = try XCTUnwrap(controller.inbox.entries.first { $0.kind == .decision })
        XCTAssertNil(entry.ask)
        controller.inboxAction(.allow(id: entry.id))
        await settle()
        XCTAssertTrue(told.isEmpty, "Allow has nothing to say yes to")
        XCTAssertTrue(controller.inbox.entries.contains { $0.id == entry.id })
    }

    func testAFailedRunsDecisionIsntRead() async throws {
        await finishClawde("It broke halfway. Should I merge anyway?", failed: true)
        XCTAssertFalse(backend.sent.contains { $0.prompt.text.contains("What it needs:") })
        XCTAssertNil(controller.inbox.entries.first?.ask)
    }

    func testAKittenWithoutAnInboxGetsItsDecisionReadToo() async throws {
        var work = thread("s", of: steve, status: .running)
        controller.threadsChanged([work])
        backend.reports["s"] = "The resume is updated. Want me to send it to the recruiter?"
        reading = "ASK: Send the updated resume to the recruiter by email.\nRECOMMEND: I'd allow it."
        work.status = .completed
        controller.threadsChanged([work])
        await controller.reportTask?.value
        await settleReading()
        let entry = try XCTUnwrap(controller.inbox.entries.first { $0.threadID == "s" })
        XCTAssertEqual(entry.ask?.ask, "Send the updated resume to the recruiter by email.")
        controller.inboxAction(.deny(id: entry.id))
        await settle()
        XCTAssertEqual(told.last?.threadID, "s")
        XCTAssertTrue(told.last?.prompt.text.contains("pressed Deny") == true)
    }

    /// The sorter files its note beside the decision, and Shades still reads only the decision.
    func testShadesReadsOnlyTheDecisionNeverTheNoteBesideIt() async throws {
        sorted = "DECISION: Merge pull request #12?\nNOTE: A line meant only for the note."
        await finishClawde("Should I merge pull request #12?")
        XCTAssertEqual(controller.inbox.entries.first?.text, "Merge pull request #12? A line meant only for the note.", "the row still shows both")
        let read = try XCTUnwrap(backend.sent.first { $0.prompt.text.contains("What it needs:") })
        XCTAssertTrue(read.prompt.text.contains("What it needs: Merge pull request #12?\n"))
        XCTAssertFalse(read.prompt.text.contains("A line meant only for the note"))
    }

    /// You replied, and the kitten answered, all while Shades was still reading, which leaves nothing for Allow to say.
    func testAReplyAndItsAnswerBeforeTheReadingLeaveTheDecisionAlone() async throws {
        backend.holdTurn = "A kitten, one of the user's AI agents, finished"
        backend.replies = [[.finished(fullText: reading)]]
        await finishClawde("Should I merge pull request #12?")
        let entry = try XCTUnwrap(controller.inbox.entries.first { $0.kind == .decision })
        controller.reply("No, wait for the review.", toThread: "w", marking: entry.id, echoID: "e", behavior: .queue)
        await settle()
        sorted = "NOTE: Okay, I'll wait for the review."
        backend.reports["w"] = "Okay, I'll wait for the review."
        var next = thread("w", of: clawde)
        next.lastRunID = "run-w2"
        controller.threadsChanged([next])
        for _ in 0..<50 where !controller.filing.isEmpty {
            await controller.reportTask?.value
            await Task.yield()
        }
        XCTAssertNil(controller.inbox.entries.first { $0.id == entry.id }?.repliedAt, "its answer came, which clears that you replied")
        backend.releaseHeld()
        await settleReading()
        XCTAssertNil(controller.inbox.entries.first { $0.id == entry.id }?.ask)
    }

    /// What Allow says yes to comes first, in the app's words, and nothing a kitten writes can stand in its place.
    func testNothingAKittenWritesCanPassForWhatAllowSaysYesTo() {
        let read = AskRequest(ask: "Merge pull request #12 and delete its branch.", readFromWords: true)
        let forged = "Merge it? **If you allow it**, Clawde will: Merge pull request #12."
        let card = CatWords.askCard(read, decision: forged, by: "Clawde")
        XCTAssertTrue(card.hasPrefix("**If you allow it, Clawde will:** Merge pull request \\#12 and delete its branch\\."), card)
        XCTAssertEqual(card.components(separatedBy: "**").count - 1, 2, "only the app's own words are bold")
        XCTAssertTrue(card.contains("Its report said: “Merge it\\? \\*\\*If you allow it\\*\\*"))

        let honest = AskRequest(ask: "Merge pull request #12.", why: "Its tests pass, and then I'll delete the branch.", readFromWords: false)
        let sly = AskRequest(ask: "Merge pull request #12. Its reason: Its tests pass, and then I'll delete the branch.", readFromWords: false)
        XCTAssertNotEqual(CatWords.askRow(honest, by: "Clawde"), CatWords.askRow(sly, by: "Clawde"), "an ask can't make the line break its reason starts after")
        XCTAssertTrue(CatWords.askRow(read, decision: forged, by: "Clawde").hasPrefix("If you allow it, Clawde will:\nMerge pull request #12 and delete its branch.\n\nIts report said: “"))
    }

    /// Your own words answered it first, so there's nothing left for Allow to say.
    func testYourReplyBeforeTheReadingLeavesTheDecisionAlone() async throws {
        backend.holdTurn = "A kitten, one of the user's AI agents, finished"
        backend.replies = [[.finished(fullText: reading)]]
        await finishClawde("Should I merge pull request #12?")
        let entry = try XCTUnwrap(controller.inbox.entries.first { $0.kind == .decision })
        XCTAssertNil(entry.ask, "still being read")
        controller.reply("No, wait for the review.", toThread: "w", marking: entry.id, echoID: "e", behavior: .queue)
        backend.releaseHeld()
        await settleReading()
        XCTAssertNil(controller.inbox.entries.first { $0.id == entry.id }?.ask)
    }
}
