import Foundation
@testable import Shades
import ShadesCore
import TestSupport
import XCTest

@MainActor
final class WaitingOnYouTests: XCTestCase {
    private var backend: FakeBackend!
    private var controller: AppController!
    private var savedInbox: Inbox?
    private var health: [[HealthFinding]] = []
    private var sorts: [String: String] = [:]
    private var clock = Date(timeIntervalSince1970: 100_000)
    private let clawde = Kitten(name: "Clawde", role: "The system", covers: "", folder: "/k/clawde", seesScreen: false, usesInbox: true)
    private let site = Kitten(name: "Steve", role: "The website", covers: "", folder: "/k/steve", usesInbox: true)

    override func setUp() async throws {
        backend = FakeBackend()
        backend.replyTo = { [unowned self] prompt in
            guard prompt.text.hasPrefix("Below is the final report") else { return nil }
            let sorted = self.sorts.first { prompt.text.contains($0.key) }?.value ?? "Not sorted."
            return [.finished(fullText: sorted)]
        }
        controller = makeController(inbox: Inbox(since: .distantPast))
    }

    private func makeController(inbox: Inbox) -> AppController {
        let controller = AppController(
            dependencies: AppDependencies(
                backend: backend,
                context: FakeContext(log: Log()),
                voice: FakeVoice(),
                inserter: FakeInserter(),
                keys: FakeKeys(),
                settings: Settings(),
                saveSettings: { _ in },
                kittens: { [unowned self] in [self.clawde, self.site] },
                home: NSTemporaryDirectory(),
                routerFolder: { "/shades/router" },
                reportHealth: { [unowned self] findings, _ in self.health.append(findings) },
                inbox: inbox,
                saveInbox: { [unowned self] in self.savedInbox = $0 }
            ),
            stage: FakeStage(log: Log()),
            now: { [unowned self] in self.clock }
        )
        controller.threadListWait = 0
        controller.reportDelay = 0
        return controller
    }

    private func work(
        _ id: String,
        of kitten: Kitten,
        launchedBy launcher: String? = nil,
        held: Bool = false,
        pullRequest: ThreadPullRequest? = nil
    ) -> AgentThread {
        if let launcher { backend.origins[id] = ThreadOrigin(title: "\(kitten.name): Work", projectPath: kitten.folder, startedBy: .thread(launcher)) }
        var thread = AgentThread(
            id: id,
            title: "\(kitten.name): Work \(id)",
            projectTitle: nil,
            status: held ? .running : .completed,
            model: "m",
            updatedAt: clock,
            pullRequest: pullRequest,
            projectPath: kitten.folder,
            lastRunID: "run-\(id)",
            lastRunEndedAt: clock,
            startedByAgent: launcher != nil,
            lastRunStartedAt: clock.addingTimeInterval(-300)
        )
        thread.turnEnded = held
        return thread
    }

    private var listed: [AgentThread] = []

    private func show(_ threads: [AgentThread]) {
        listed = threads
        controller.threadsChanged(threads)
    }

    private func endTurn(_ thread: AgentThread, report: String?, sorted: String? = nil) async {
        backend.reports[thread.id] = report
        if let report, let sorted { sorts[String(report.prefix(40))] = sorted }
        var running = thread
        running.status = .running
        running.turnEnded = false
        show(listed.filter { $0.id != thread.id } + [running])
        show(listed.filter { $0.id != thread.id } + [thread])
        let filed = await until { !self.controller.inbox.owes(thread) && self.controller.filing.isEmpty }
        XCTAssertTrue(filed, "it never got filed")
    }

    private var waiting: [InboxEntry] { controller.inboxEntries.filter(\.needsYou) }
    private var relays: [FakeBackend.Sent] { backend.sent.filter { $0.mode == .forward && $0.prompt.text.hasPrefix("---\nThe Kitty Litter wrote this") } }
    private var sortsRun: Int { backend.sent.filter { $0.prompt.text.hasPrefix("Below is the final report") }.count }

    func testNoneOfTheFiveRowsFromTheAuditReachesWaitingOnYou() async {
        let watching = { (number: Int, checks: String) in ThreadPullRequest(number: number, state: "open", checks: checks, watched: true) }
        let audit: [(thread: AgentThread, report: String, sorted: String)] = [
            (work("setup", of: site, launchedBy: "lead", held: true, pullRequest: watching(3, "pending")),
             "I'll fast-forward the checkout once it lands. Merge PR #3 yourself or allow the merge in this session.",
             "Not sorted."),
            (work("footer", of: site, launchedBy: "lead", held: true, pullRequest: watching(16, "pending")),
             "PR #16 waits on its preview and two reviewers. Decide on a build-time footer date when you like.",
             "DECISION: Decide on a build-time footer date."),
            (work("holes", of: clawde, launchedBy: "main", held: true, pullRequest: watching(33, "pending")),
             "#33 waits on CI. Decide later whether to fix the two holes it lists.",
             "DECISION: Decide later whether to fix the two holes."),
            (work("blocks", of: clawde, launchedBy: "main"),
             "Done with the review. Raise Block 1 and Block 3 from your thread.",
             "DECISION: Raise Block 1 and Block 3 from your thread."),
            (work("ff", of: clawde, launchedBy: "main"),
             "Merged. Run git merge --ff-only origin/main and push in your checkout.",
             "DECISION: Run git merge --ff-only and push in your checkout."),
        ]
        for row in audit {
            await endTurn(row.thread, report: row.report, sorted: row.sorted)
            XCTAssertEqual(waiting, [], row.report)
        }
        XCTAssertEqual(controller.inbox.entries, [], "nothing under Also either, since each reported to the agent that launched it")
        XCTAssertEqual(controller.inbox.record.visits, [])
        XCTAssertEqual(sortsRun, 0, "a report to another agent isn't sorted for you")
        XCTAssertEqual(relays.map(\.threadID), ["lead", "lead", "main", "main", "main"], "each launcher heard")
        XCTAssertTrue(relays[0].prompt.text.contains("Merge PR #3 yourself"))
        XCTAssertTrue(relays.allSatisfy { Prompts.ownWords(in: $0.prompt.text) == nil }, "none of it reads as your words")
    }

    func testALauncherThatAlreadyHeardIsntToldAgain() async {
        let thread = work("w", of: clawde, launchedBy: "main")
        backend.said["main"] = [Exchange(id: "m", asker: .agent(threadID: "w"), askedAt: clock.addingTimeInterval(-10), ask: "Done, PR #4 is up.")]
        await endTurn(thread, report: "Done, PR #4 is up.")
        XCTAssertTrue(relays.isEmpty)
        XCTAssertEqual(waiting, [])

        backend.said["main"] = [Exchange(id: "m", asker: .agent(threadID: "w"), askedAt: clock.addingTimeInterval(-900), ask: "Starting.")]
        var again = thread
        again.lastRunID = "run-2"
        await endTurn(again, report: "Done, PR #5 is up.")
        XCTAssertEqual(relays.map(\.threadID), ["main"], "what it said in an earlier run doesn't count")
    }

    func testATurnAnotherKittenStartedReportsBackToItNotYou() async {
        backend.said["b"] = [
            Exchange(id: "yours", asker: .you, askedAt: clock.addingTimeInterval(-900), ask: "Look after the site."),
            Exchange(id: "asked", asker: .agent(threadID: "a"), askedAt: clock.addingTimeInterval(-310), ask: "Which branch has the footer?"),
        ]
        await endTurn(work("b", of: site), report: "The footer is on main. Do you want me to move it?", sorted: "DECISION: Move the footer?")
        XCTAssertEqual(waiting, [], "it was answering the kitten that asked")
        XCTAssertEqual(sortsRun, 0)
        XCTAssertEqual(relays.map(\.threadID), ["a"], "and that kitten hears")

        backend.said["c"] = [
            Exchange(id: "asked", asker: .agent(threadID: "a"), askedAt: clock.addingTimeInterval(-900), ask: "Which branch?"),
            Exchange(id: "yours", asker: .you, askedAt: clock.addingTimeInterval(-310), ask: "Should it move?"),
        ]
        await endTurn(work("c", of: site), report: "Move it to the left or the right?", sorted: "DECISION: Left or right?")
        XCTAssertEqual(waiting.map(\.text), ["Left or right?"], "a turn your words started is yours")
    }

    func testAThreadYouStartedStillReportsToYouWhenItsOwnWorkerWokeIt() async {
        backend.origins["worker"] = ThreadOrigin(title: "Clawde: The change", projectPath: "/k/app", startedBy: .thread("clawde"))
        backend.said["clawde"] = [
            Exchange(id: "yours", asker: .you, askedAt: clock.addingTimeInterval(-900), ask: "Make the reports go to whoever launched them."),
            Exchange(id: "relay", asker: .agent(threadID: "worker"), askedAt: clock.addingTimeInterval(-310), ask: "Report relay: merged, and CI on main passes."),
        ]
        await endTurn(work("clawde", of: clawde), report: "It's merged. Install main now, or wait for the other worker?", sorted: "DECISION: Install main now, or wait?")
        XCTAssertEqual(waiting.map(\.text), ["Install main now, or wait?"], "a worker reporting to the thread that launched it doesn't make that thread's turn the worker's")
        XCTAssertTrue(relays.isEmpty, "the worker doesn't get its launcher's report")
    }

    func testAThreadAnAgentStartedStillReportsToItsStarterWhenItsOwnWorkerWokeIt() async {
        backend.origins["part"] = ThreadOrigin(title: "Clawde: Part one", projectPath: "/k/clawde", startedBy: .thread("w"))
        backend.said["w"] = [
            Exchange(id: "launch", asker: .agent(threadID: "main"), askedAt: clock.addingTimeInterval(-900), ask: "Do both parts."),
            Exchange(id: "part", asker: .agent(threadID: "part"), askedAt: clock.addingTimeInterval(-310), ask: "Report relay: part one is done."),
        ]
        await endTurn(work("w", of: clawde, launchedBy: "main"), report: "Both parts are done. Merge them?", sorted: "DECISION: Merge both parts?")
        XCTAssertEqual(relays.map(\.threadID), ["main"], "its starter hears, not the worker that woke it")
        XCTAssertEqual(waiting, [])
    }

    func testALaunchedThreadYouTookOverStillAnswersYouWhenItsOwnWorkerWokeIt() async {
        backend.origins["part"] = ThreadOrigin(title: "Clawde: Part", projectPath: "/k/clawde", startedBy: .thread("w"))
        backend.said["w"] = [
            Exchange(id: "launch", asker: .agent(threadID: "main"), askedAt: clock.addingTimeInterval(-900), ask: "Do it."),
            Exchange(id: "yours", asker: .you, askedAt: clock.addingTimeInterval(-600), ask: "Use plan B instead."),
            Exchange(id: "part", asker: .agent(threadID: "part"), askedAt: clock.addingTimeInterval(-310), ask: "Report relay: plan B needs a key."),
        ]
        await endTurn(work("w", of: clawde, launchedBy: "main"), report: "Plan B needs a paid key. Buy one, or stay on A?", sorted: "DECISION: Buy a key, or stay on A?")
        XCTAssertEqual(waiting.map(\.text), ["Buy a key, or stay on A?"], "your words opened its work before its own worker wrote back")
        XCTAssertTrue(relays.isEmpty)
    }

    func testAnotherKittensAskAnsweredOnceTheThreadsOwnWorkerReportedGoesBackToThatKitten() async {
        backend.origins["helper"] = ThreadOrigin(title: "Steve: Look it up", projectPath: "/k/steve", startedBy: .thread("b"))
        backend.said["b"] = [
            Exchange(id: "yours", asker: .you, askedAt: clock.addingTimeInterval(-900), ask: "Look after the site."),
            Exchange(id: "asked", asker: .agent(threadID: "a"), askedAt: clock.addingTimeInterval(-600), ask: "Which branch has the footer?"),
            Exchange(id: "helper", asker: .agent(threadID: "helper"), askedAt: clock.addingTimeInterval(-310), ask: "Report relay: it's on main."),
        ]
        await endTurn(work("b", of: site), report: "The footer is on main. Do you want me to move it?", sorted: "DECISION: Move the footer?")
        XCTAssertEqual(relays.map(\.threadID), ["a"], "the kitten that asked hears, past the thread's own worker")
        XCTAssertEqual(waiting, [])
    }

    func testAWriterThatCantBeTracedLeavesTheReportWithYou() async {
        for (index, traced) in [false, true].enumerated() {
            let worker = "worker-\(index)"
            if traced {
                backend.origins[worker] = ThreadOrigin(title: "Clawde: The change", projectPath: "/k/app", startedBy: .unknown)
            } else {
                backend.untraceable.insert(worker)
            }
            let id = "clawde-\(index)"
            backend.said[id] = [
                Exchange(id: "yours", asker: .you, askedAt: clock.addingTimeInterval(-900), ask: "Make the reports go to whoever launched them."),
                Exchange(id: "relay", asker: .agent(threadID: worker), askedAt: clock.addingTimeInterval(-310), ask: "Report relay: merged."),
            ]
            await endTurn(work(id, of: clawde), report: "It's merged. Install main now, or wait? \(index)", sorted: "DECISION: Install main now, or wait? \(index)")
            XCTAssertTrue(waiting.contains { $0.text == "Install main now, or wait? \(index)" }, traced ? "a writer whose starter is unknown" : "a writer T3 couldn't read")
            XCTAssertTrue(relays.isEmpty, "a false alarm beats a report lost to a worker")
        }
    }

    func testAWorkersOwnWorkerWritingBackLeavesTheReportWithYou() async {
        backend.origins["worker"] = ThreadOrigin(title: "Clawde: The change", projectPath: "/k/app", startedBy: .thread("clawde"))
        backend.origins["reviewer"] = ThreadOrigin(title: "Review the change", projectPath: "/k/app", startedBy: .thread("worker"))
        backend.said["clawde"] = [
            Exchange(id: "yours", asker: .you, askedAt: clock.addingTimeInterval(-900), ask: "Make the reports go to whoever launched them."),
            Exchange(id: "review", asker: .agent(threadID: "reviewer"), askedAt: clock.addingTimeInterval(-310), ask: "Review done, no findings."),
        ]
        await endTurn(work("clawde", of: clawde), report: "Reviewed and merged. Install now?", sorted: "DECISION: Install now?")
        XCTAssertEqual(waiting.map(\.text), ["Install now?"], "a worker's own worker is still this thread's work")
        XCTAssertTrue(relays.isEmpty)
    }

    func testTheKittyLittersOwnNoteNeverDecidesWhoseATurnIs() async {
        backend.said["w"] = [
            Exchange(id: "launch", asker: .agent(threadID: "main"), askedAt: clock.addingTimeInterval(-900), ask: "Do both parts."),
            Exchange(id: "note", asker: .you, askedAt: clock.addingTimeInterval(-310)),
        ]
        await endTurn(work("w", of: clawde, launchedBy: "main"), report: "Both parts are done. Merge them?", sorted: "DECISION: Merge both parts?")
        XCTAssertEqual(relays.map(\.threadID), ["main"], "a note passing on its worker's report doesn't make the turn yours")
        XCTAssertEqual(waiting, [])

        backend.said["v"] = [
            Exchange(id: "launch", asker: .agent(threadID: "main"), askedAt: clock.addingTimeInterval(-900), ask: "Do it."),
            Exchange(id: "yours", asker: .you, askedAt: clock.addingTimeInterval(-600), ask: "Use plan B instead."),
            Exchange(id: "note", asker: .you, askedAt: clock.addingTimeInterval(-310)),
        ]
        await endTurn(work("v", of: clawde, launchedBy: "main"), report: "Plan B needs a paid key. Buy one?", sorted: "DECISION: Buy a key?")
        XCTAssertEqual(waiting.map(\.text), ["Buy a key?"], "a note after your words leaves the turn yours")
        XCTAssertEqual(relays.map(\.threadID), ["main"])
    }

    func testTwoThreadsThatOnceWroteToEachOtherDontPassReportsBackAndForthForever() async {
        backend.said["m"] = [
            Exchange(id: "launch", asker: .agent(threadID: "main"), askedAt: clock.addingTimeInterval(-900), ask: "Fix the routing."),
            Exchange(id: "theirs", asker: .agent(threadID: "w"), askedAt: clock.addingTimeInterval(-600), ask: "Agreed, my branch is gone."),
            Exchange(id: "note", asker: .you, askedAt: clock.addingTimeInterval(-310)),
        ]
        await endTurn(work("m", of: clawde, launchedBy: "main"), report: "Nothing to do here, and I'm not replying.", sorted: "NOTE: Nothing to do.")
        XCTAssertEqual(relays.map(\.threadID), ["main"], "a turn The Kitty Litter's note opened goes to the thread's own launcher, not back to the thread whose report the note passed on")

        backend.said["y"] = [
            Exchange(id: "yours", asker: .you, askedAt: clock.addingTimeInterval(-900), ask: "Look after the site."),
            Exchange(id: "theirs", asker: .agent(threadID: "w"), askedAt: clock.addingTimeInterval(-600), ask: "Which branch?"),
            Exchange(id: "note", asker: .you, askedAt: clock.addingTimeInterval(-310)),
        ]
        await endTurn(work("y", of: site), report: "Saw the other thread's report. Merge it?", sorted: "DECISION: Merge it?")
        XCTAssertEqual(waiting.map(\.text), ["Merge it?"], "in a thread you started it comes to you")
        XCTAssertEqual(relays.map(\.threadID), ["main"])
    }

    func testAWorkerTheCatsThreadLaunchedIsYoursEvenBeforeItPassesWorkOn() async {
        var inbox = Inbox(since: .distantPast)
        inbox.startedForYou("cats", at: clock)
        controller = makeController(inbox: inbox)
        await endTurn(work("w", of: clawde, launchedBy: "cats"), report: "Pick A or B?", sorted: "DECISION: Pick A or B?")
        XCTAssertEqual(waiting.map(\.text), ["Pick A or B?"])
        XCTAssertTrue(relays.isEmpty)
    }

    func testALaunchedThreadYouWroteToAnswersYou() async {
        backend.said["w"] = [
            Exchange(id: "launch", asker: .agent(threadID: "main"), askedAt: clock.addingTimeInterval(-900), ask: "Do it."),
            Exchange(id: "yours", asker: .you, askedAt: clock.addingTimeInterval(-310), ask: "Use plan B instead."),
        ]
        await endTurn(work("w", of: clawde, launchedBy: "main"), report: "Plan B needs a paid key. Buy one, or stay on A?", sorted: "DECISION: Buy a key, or stay on A?")
        XCTAssertEqual(waiting.map(\.text), ["Buy a key, or stay on A?"])
        XCTAssertTrue(relays.isEmpty)
    }

    func testAReportThatCantBeReadIsntPassedOnAsNoReport() async {
        let quiet = Kitten(name: "Quinn", role: "", covers: "", folder: "/k/quinn")
        backend.readFails = true
        let thread = work("q", of: quiet, launchedBy: "main")
        var running = thread
        running.status = .running
        show([running])
        show([thread])
        let read = await until { self.controller.readRuns["q"] != nil && self.controller.filing.isEmpty }
        await controller.reportTask?.value
        XCTAssertTrue(read)
        XCTAssertTrue(relays.isEmpty, "it can't say there was no report")
    }

    func testAQuietKittensRowFiledWhileItsThreadIsWokenGoesAtOnce() async {
        let quiet = Kitten(name: "Quinn", role: "", covers: "", folder: "/k/quinn")
        controller = AppController(
            dependencies: AppDependencies(
                backend: backend, context: FakeContext(log: Log()), voice: FakeVoice(), inserter: FakeInserter(), keys: FakeKeys(),
                settings: Settings(), saveSettings: { _ in }, kittens: { [quiet] }, home: NSTemporaryDirectory(),
                routerFolder: { "/shades/router" }, inbox: Inbox(since: .distantPast), saveInbox: { [unowned self] in self.savedInbox = $0 }
            ),
            stage: FakeStage(log: Log()),
            now: { [unowned self] in self.clock }
        )
        controller.threadListWait = 0
        controller.reportDelay = 0
        let thread = work("q", of: quiet)
        backend.reports["q"] = "Pick A or B?"
        sorts["Pick A or B?"] = "DECISION: Pick A or B?"
        backend.whileReadingAReport = { @MainActor [unowned self] in
            var woken = thread
            woken.status = .running
            woken.lastRunStartedAt = self.clock.addingTimeInterval(5)
            self.controller.latestThreads = [woken]
            self.clock = self.clock.addingTimeInterval(10)
        }
        var running = thread
        running.status = .running
        show([running])
        show([thread])
        let read = await until { self.controller.readRuns["q"] != nil && self.sortsRun > 0 && self.controller.reportTask != nil }
        await controller.reportTask?.value
        XCTAssertTrue(read)
        XCTAssertEqual(controller.inbox.entries.filter(\.needsYou), [], "its checks woke it before the row was filed")
        XCTAssertEqual(controller.inbox.record.visits.map(\.exit), [.turnWithoutYou])
    }

    func testADelegatedThreadIsntToldToItsParentTwice() async {
        var delegated = work("thread:delegated-task:c1", of: clawde, launchedBy: "main")
        delegated.isDelegated = true
        await endTurn(delegated, report: "Pick A or B?", sorted: "DECISION: Pick A or B?")
        XCTAssertTrue(relays.isEmpty, "T3 tells the parent itself")
        XCTAssertEqual(waiting, [])
    }

    func testALaunchedThreadNoKittenOwnsIsLeftAsItWas() async {
        let loose = Kitten(name: "Nobody", role: "", covers: "", folder: "/k/nobody")
        let thread = work("w", of: loose, launchedBy: "main")
        backend.reports["w"] = "All done."
        var running = thread
        running.status = .running
        show([running])
        show([thread])
        let read = await until { self.controller.readRuns["w"] != nil && self.controller.filing.isEmpty }
        await controller.reportTask?.value
        XCTAssertTrue(read)
        XCTAssertTrue(relays.isEmpty, "no thread the app doesn't own gets a note")
    }

    func testTheLaunchersRowGoesWhenTheAppPassesItAReport() async throws {
        await endTurn(work("main", of: clawde), report: "Pick plan A or plan B?", sorted: "DECISION: Pick plan A or plan B?")
        XCTAssertEqual(waiting.count, 1)
        clock = clock.addingTimeInterval(60)
        await endTurn(work("w", of: clawde, launchedBy: "main"), report: "PR #4 is up.")
        XCTAssertEqual(relays.map(\.threadID), ["main"])
        XCTAssertEqual(waiting, [], "another thread wrote to it, so it's moved on")
        XCTAssertEqual(controller.inbox.record.visits.first?.exit, .turnWithoutYou)

        var main = try XCTUnwrap(listed.first { $0.id == "main" })
        main.lastWordsFromYouAt = clock
        main.lastRunStartedAt = clock.addingTimeInterval(1)
        main.lastRunID = "run-main-2"
        main.lastRunEndedAt = clock.addingTimeInterval(30)
        await endTurn(main, report: "The worker's PR #4 waits on CI.", sorted: "NOTE: The worker's PR #4 waits on CI.")
        XCTAssertEqual(waiting, [], "the note isn't an answer to you")
    }

    func testARowFiledWhileItsThreadIsWokenAgainGoesAtOnce() async {
        let thread = work("w", of: clawde, held: true, pullRequest: ThreadPullRequest(number: 2, state: "open", watched: true))
        backend.whileReadingAReport = { @MainActor [unowned self] in
            var woken = thread
            woken.turnEnded = false
            woken.lastRunStartedAt = self.clock.addingTimeInterval(5)
            self.controller.latestThreads = [woken]
            self.clock = self.clock.addingTimeInterval(10)
        }
        await endTurn(thread, report: "Pick A or B?", sorted: "DECISION: Pick A or B?")
        XCTAssertEqual(waiting, [], "its checks woke it before the row was filed")
        XCTAssertEqual(controller.inbox.record.visits.map(\.exit), [.turnWithoutYou])
    }

    func testIfTheLauncherCantBeReachedTheReportComesToYou() async {
        backend.forwardError = URLError(.badServerResponse)
        await endTurn(work("w", of: clawde, launchedBy: "gone"), report: "Pick A or B?", sorted: "DECISION: Pick A or B?")
        XCTAssertEqual(waiting.map(\.text), ["Pick A or B?"])
        XCTAssertEqual(controller.inbox.record.visits.map(\.startedBy), [.agent])
    }

    func testAThreadTheCatPassedWorkToStillReportsToYou() async {
        controller.dispatchers.insert("w")
        await endTurn(work("w", of: clawde, launchedBy: "cats"), report: "Pick A or B?", sorted: "DECISION: Pick A or B?")
        XCTAssertEqual(waiting.map(\.text), ["Pick A or B?"])
        XCTAssertTrue(relays.isEmpty)
        XCTAssertEqual(controller.inbox.record.visits.map(\.startedBy), [.passedOn])

        var inbox = Inbox(since: .distantPast)
        inbox.startedForYou("v", at: clock)
        controller = makeController(inbox: inbox)
        await endTurn(work("v", of: clawde, launchedBy: "cats"), report: "Pick C or D?", sorted: "DECISION: Pick C or D?")
        XCTAssertEqual(waiting.map(\.text), ["Pick C or D?"], "even after a restart")
    }

    func testWhatGenuinelyNeedsYouStillReachesIt() async throws {
        await endTurn(work("pick", of: clawde), report: "Two ways to do it. A is faster, B is cheaper. Which?", sorted: "DECISION: Pick A (faster) or B (cheaper)?")
        XCTAssertEqual(waiting.map(\.text), ["Pick A (faster) or B (cheaper)?"])

        let pull = ThreadPullRequest(number: 7, state: "open", checks: "passing", review: "review-required", watched: true)
        await endTurn(work("approve", of: site, held: true, pullRequest: pull), report: "PR #7 needs your approval before I can merge it.", sorted: "DECISION: Approve PR #7 so it can merge?")
        XCTAssertEqual(waiting.map(\.text).sorted(), ["Approve PR #7 so it can merge?", "Pick A (faster) or B (cheaper)?"])
        let sort = try XCTUnwrap(backend.sent.last { $0.prompt.text.contains("PR #7 needs your approval") })
        XCTAssertTrue(sort.prompt.text.contains("It's still watching pull request #7, and T3 will wake it by itself"))

        let card = "Need one setting.\n\n```shades-request\n{\"ask\": \"Merge pull request #9.\"}\n```"
        await endTurn(work("card", of: clawde, launchedBy: "main"), report: card)
        let carded = await until { self.controller.inbox.entries.contains { $0.ask != nil } }
        XCTAssertTrue(carded)
        XCTAssertTrue(waiting.contains { $0.ask?.ask == "Merge pull request #9." }, "only you can answer a card, whoever started the thread")

        var asking = work("question", of: clawde, launchedBy: "main")
        asking.status = .waitingForAnswer
        asking.pendingQuestion = AgentQuestion(id: "q", threadID: "question", threadTitle: asking.title, text: "Which one?", options: ["A", "B"])
        show(listed + [asking])
        XCTAssertTrue(waiting.contains { $0.questionID == "q" }, "nor can anyone else answer T3's question")

        XCTAssertEqual(controller.inbox.record.visits.map(\.threadID), ["pick", "approve", "card"])
        XCTAssertEqual(controller.inbox.record.visits.map(\.held), [false, true, false])
        XCTAssertEqual(controller.inbox.record.visits.map(\.source), [.sorter, .sorter, .requestCard])
        XCTAssertEqual(controller.inbox.record.visits.map(\.startedBy), [.you, .you, .agent])
        XCTAssertEqual(savedInbox?.record, controller.inbox.record, "kept with the inbox")
    }

    func testARowGoesWhenItsThreadMovesOnWithoutYou() async throws {
        let pull = ThreadPullRequest(number: 2, state: "open", checks: "pending", watched: true)
        for id in ["woken", "merged", "settled", "archived", "yours"] {
            await endTurn(work(id, of: clawde, held: true, pullRequest: pull), report: "Pick A or B for \(id)?", sorted: "DECISION: Pick A or B for \(id)?")
        }
        XCTAssertEqual(waiting.count, 5)

        clock = clock.addingTimeInterval(60)
        var threads = listed
        func change(_ id: String, _ edit: (inout AgentThread) -> Void) {
            let index = threads.firstIndex { $0.id == id }!
            edit(&threads[index])
        }
        change("woken") { $0.lastRunStartedAt = self.clock; $0.turnEnded = false }
        change("merged") { $0.pullRequest?.state = "merged" }
        change("settled") { $0.settledAt = self.clock }
        threads.removeAll { $0.id == "archived" }
        change("yours") { $0.lastWordsFromYouAt = self.clock; $0.lastRunStartedAt = self.clock.addingTimeInterval(1); $0.turnEnded = false }
        show(threads)

        XCTAssertEqual(waiting, [])
        XCTAssertEqual(controller.inbox.entries.map(\.threadID), ["yours"], "the one you answered in T3 stays, dimmed")
        let exits = Dictionary(uniqueKeysWithValues: controller.inbox.record.visits.map { ($0.threadID, $0.exit) })
        XCTAssertEqual(exits, ["woken": .turnWithoutYou, "merged": .pullRequestMerged, "settled": .settled, "archived": .archived, "yours": .replied])
        XCTAssertEqual(savedInbox?.entries, controller.inbox.entries)
    }

    func testCheckMyselfSaysSoWhenMostRowsLeftWithoutYou() async throws {
        for id in ["a", "b", "c", "d"] {
            await endTurn(work(id, of: clawde), report: "Pick one for \(id)?", sorted: "DECISION: Pick one for \(id)?")
        }
        await controller.runHealthCheck()
        XCTAssertEqual(health.last?.first { $0.check == "waiting on you" }?.ok, true, "none has left yet")

        controller.inboxAction(.done(id: try XCTUnwrap(waiting.first { $0.threadID == "a" }).id))
        clock = clock.addingTimeInterval(60)
        show(listed.filter { $0.id == "a" })
        await controller.runHealthCheck()
        let finding = try XCTUnwrap(health.last?.first { $0.check == "waiting on you" })
        XCTAssertFalse(finding.ok)
        XCTAssertEqual(finding.problem, "3 of the 4 things that left Waiting on you this week went without you, so it's asking you about things that sort themselves out.")
    }
}
