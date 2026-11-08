import XCTest
@testable import Shades
@testable import ShadesCore
import ShadesContext
import AppKit

/// The promise: nothing that came from your screen reaches the thread of a kitten with `seesScreen: false`.
/// Each test runs the real flows over every route and kitten setting in its scope, then reads everything Shades
/// sent. How to run it, read it and keep it true: `.agents/skills/verify-screen-boundary/SKILL.md`.
@MainActor
final class ScreenBoundaryTests: XCTestCase {
    /// Every part of this screen carries a word that can't turn up by chance, so a prompt with it got it from the screen.
    static let mark = "5ad1"
    static let screen = ScreenSnapshot(
        appName: "App-5ad1",
        windowTitle: "Window-5ad1",
        url: URL(string: "https://page-5ad1.example"),
        selectedText: "Selected-5ad1",
        pageText: "Page-5ad1",
        screenshotJPEG: Data("Picture-5ad1".utf8),
        screenshotArea: CGRect(x: 0, y: 0, width: 1440, height: 900),
        elements: [ScreenElement(role: "button", label: "Element-5ad1", frame: CGRect(x: 10, y: 10, width: 80, height: 24))]
    )
    /// A file dropped onto the cat, which could as well be a screenshot, so it's held to the same promise.
    static let dropped = ScreenSnapshot(
        url: URL(fileURLWithPath: "/files/statement-5ad1.pdf"),
        pageText: "Statement-5ad1",
        screenshotJPEG: Data("Picture-5ad1".utf8),
        droppedName: "statement-5ad1.pdf"
    )

    /// A picture attached in Messages, from the Mac or a phone, which is held to the same promise. Its name carries the
    /// mark, and so does whatever goes with it.
    static let attached: Drop = {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return .bytes(bitmap.representation(using: .png, properties: [:])!, name: "statement-5ad1.png")
    }()

    // MARK: - Your words, wherever they go

    /// Every way your words reach a kitten's new thread, for every way two kittens can share a folder.
    func testNoNewThreadOfAScreenlessKittenGetsYourScreen() async {
        var reachedAllowed = 0
        for clawdeProject in [nil, "/code/shades"] {
            for steveSees in [true, false] {
                for steveProject in [nil, "/code/site", "/k/clawde", "/code/shades"] {
                    for frontierMode in [RuntimeMode.autoAcceptEdits, .fullAccess] {
                        for route in Give.allCases {
                            for target in ["Clawde", "Steve Pawsniak"] where route.picksAKitten || target == "Clawde" {
                                let clawde = Kitten(name: "Clawde", role: "The system", covers: "Shades itself", folder: "/k/clawde", project: clawdeProject, seesScreen: false)
                                let steve = Kitten(name: "Steve Pawsniak", role: "Professional", covers: "their career", folder: "/k/steve", project: steveProject, seesScreen: steveSees)
                                let world = World(kittens: [clawde, steve], frontierMode: frontierMode)
                                await world.run(route, to: target)
                                let scene = "\(route) to \(target), Clawde in \(clawde.project), Steve in \(steve.project) seeing \(steveSees), frontier \(frontierMode)"
                                reachedAllowed += world.check(scene, threads: [:])
                            }
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(reachedAllowed, 0, "the screen never reached anything it may, so this can't tell when it's there")
    }

    /// Every way your words reach a thread that already exists, whoever's it is or might be.
    func testNoThreadThatIsOrMightBeAScreenlessKittensGetsYourScreen() async {
        var reachedAllowed = 0
        for clawdeProject in [nil, "/code/shades"] {
            for mode in RuntimeMode.allCases.map(Optional.some) + [nil] {
                for folder in Destination.Folder.allCases {
                    for named in [false, true] {
                        for starter in Destination.Starter.allCases {
                            for route in Pass.allCases {
                                let clawde = Kitten(name: "Clawde", role: "The system", covers: "Shades itself", folder: "/k/clawde", project: clawdeProject, seesScreen: false)
                                let destination = Destination(mode: mode, folder: folder, namedForClawde: named, startedBy: starter)
                                let world = World(kittens: [clawde])
                                world.add(destination, clawde: clawde)
                                await world.run(route)
                                reachedAllowed += world.check("\(route) to \(destination), Clawde in \(clawde.project)", threads: ["w": destination.mightBeScreenless])
                            }
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(reachedAllowed, 0, "the screen never reached anything it may, so this can't tell when it's there")
    }

    // MARK: - Sessions that only reply

    /// The router reads your screen before anyone else does. A page can try to steer it, so nothing it can call may
    /// put text where another thread reads it. This is the way the leak that led to its folder went.
    func testTheRouterHasNoToolThatReachesAnotherThread() throws {
        let (denied, turnedAway) = try Self.routerRules()
        for tool in Self.waysToAnotherThread {
            XCTAssertTrue(turnedAway(tool), "\(tool) gets past the router's hook")
            if tool.hasPrefix("mcp__t3-code__") {
                XCTAssertTrue(denied.contains { Self.denies($0, tool) }, "\(tool) isn't denied outright, so it's open if hooks are off")
            }
        }
        for tool in RouterBlock.allowed {
            XCTAssertFalse(turnedAway(tool), "\(tool) is meant to stay")
            XCTAssertTrue(Self.onlyRead.contains(tool), "\(tool) is let through, and nothing here says it only reads")
        }
    }

    /// Files anything running as you can read hold secrets in plain text, such as Claude Code's prompt history,
    /// `~/.git-credentials`, `~/.ssh` and Notes' store. A page could steer the router into reading one and carrying
    /// it out in a search, and it needs no file, since your screen comes in its message. `Monitor` is the shell too.
    func testTheRouterCantReadYourFiles() throws {
        let (denied, turnedAway) = try Self.routerRules()
        for tool in ["Read", "Glob", "Grep", "Monitor"] {
            XCTAssertTrue(turnedAway(tool), "\(tool) gets past the router's hook")
            XCTAssertTrue(denied.contains { Self.denies($0, tool) }, "\(tool) isn't denied outright, so it's open if hooks are off")
        }
    }

    /// A summary or the inbox's sorting reads a thread's report, and a report can quote your screen. All either has to
    /// do is write words, so like the router it runs where it can't send any.
    func testSessionsThatOnlyWriteWordsRunWhereTheyCantSendAny() async {
        let quoted = "Done. The page said: Page-5ad1. " + String(repeating: "More about the work. ", count: 30)

        let summed = World(kittens: [])
        await summed.finish(AgentThread(id: "w", title: "Fix the page", projectTitle: nil, status: .completed, model: "m", updatedAt: summed.clock), report: quoted)
        let sorted = World(kittens: [Kitten(name: "Steve Pawsniak", role: "Professional", covers: "their career", folder: "/k/steve", usesInbox: true)])
        await sorted.finish(AgentThread(id: "w", title: "Steve Pawsniak: Fix the page", projectTitle: nil, status: .completed, model: "m", updatedAt: sorted.clock, lastRunID: "run-1", lastRunEndedAt: sorted.clock), report: quoted)

        for (name, world) in [("summary", summed), ("sorting", sorted)] {
            let reading = world.sends.filter { Self.carriesScreen($0.prompt) }
            XCTAssertFalse(reading.isEmpty, "\(name) never read the report")
            for send in reading {
                XCTExpectFailure("An access gap this check found: summaries and inbox sorting start in T3's scratch folder, where T3 allows its tools. See the screen-boundary skill.") {
                    XCTAssertEqual(send.place, .router, "the \(name) ran in \(send.place), where it has T3's tools")
                }
            }
        }
    }

    /// A thread whose title starts with a screenless kitten's name counts as that kitten's, wherever it runs. Shades sets
    /// that title from the router's hand-off, or T3 takes it from your first line, before anyone knows what's in it.
    func testANewThreadNamedForAScreenlessKittenGetsNoScreen() async {
        let clawde = Kitten(name: "Clawde", role: "The system", covers: "Shades itself", folder: "/k/clawde", seesScreen: false)
        let steve = Kitten(name: "Steve Pawsniak", role: "Professional", covers: "their career", folder: "/k/steve")
        let handedOff = World(kittens: [clawde, steve])
        await handedOff.ask("this one", routerSays: "HANDOFF: Clawde: Tighten the rules")
        let given = World(kittens: [clawde, steve])
        await given.ask("Clawde: tighten the rules", routerSays: "KITTEN: 2")

        for (name, world) in [("hand-off", handedOff), ("kitten", given)] {
            let named = world.sends.filter { $0.place != .router && $0.title.hasPrefix("Clawde:") }
            XCTAssertEqual(named.count, 1, "the \(name) started no thread named for Clawde")
            for send in named {
                XCTExpectFailure("An access gap this check found: a new thread named for a screenless kitten still gets your screen. See the screen-boundary skill.") {
                    XCTAssertFalse(Self.carriesScreen(send.prompt), "the \(name) thread counts as Clawde's and got your screen")
                }
            }
        }
    }

    /// Everything a page could ask the router to use to put text where another thread reads it, as of T3 Code and
    /// Claude Code on 2026-11-05, and names standing in for tools that don't exist yet.
    static let waysToAnotherThread = [
        "mcp__t3-code__t3_thread_send", "mcp__t3-code__t3_thread_send_attachments", "mcp__t3-code__t3_thread_launch",
        "mcp__t3-code__create_threads", "mcp__t3-code__delegate_task", "mcp__t3-code__t3_queue",
        "mcp__t3-code__t3_thread_transfer", "mcp__t3-code__t3_pending_request", "mcp__t3-code__t3_worktree_handoff",
        "mcp__t3-code__schedule_task", "mcp__t3-code__run_scheduled_task_now", "mcp__t3-code__write_pull_request_guides",
        "SendMessage", "RemoteTrigger", "CronCreate", "Bash", "Monitor", "Write", "Edit", "NotebookEdit",
        "Agent", "Task", "Skill", "WebFetch",
        "mcp__t3-code__t3_thread_reply", "mcp__t3__t3_thread_send", "mcp__t3code__thread_send", "SomethingNew",
    ]

    /// Tools that only read, and no file, so a page that steers the router can't make them put text anywhere a thread reads.
    static let onlyRead: Set = ["WebSearch", "ToolSearch"]

    /// What the router's settings deny outright, and whether its hook turns a tool away.
    static func routerRules() throws -> (denied: [String], turnedAway: (String) -> Bool) {
        let settings = try XCTUnwrap(JSONSerialization.jsonObject(with: RouterBlock.settings) as? [String: Any])
        let denied = try XCTUnwrap((settings["permissions"] as? [String: Any])?["deny"] as? [String])
        let rule = try XCTUnwrap(((settings["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]])?.first)
        let hook = try NSRegularExpression(pattern: try XCTUnwrap(rule["matcher"] as? String))
        return (denied, { tool in hook.firstMatch(in: tool, range: NSRange(tool.startIndex..., in: tool)) != nil })
    }

    /// How Claude Code reads a deny rule: a tool's own name, or `mcp__<server>` for every tool that server has.
    static func denies(_ rule: String, _ tool: String) -> Bool {
        rule == tool || (rule.hasPrefix("mcp__") && !rule.dropFirst(5).contains("__") && tool.hasPrefix(rule + "__"))
    }

    static func carriesScreen(_ prompt: AgentPrompt) -> Bool {
        prompt.text.contains(mark) || prompt.title?.contains(mark) == true || prompt.text.contains(FakeContext.savedPath)
            || prompt.attachments.contains { String(decoding: $0.data, as: UTF8.self).contains(mark) }
    }
}

// MARK: - Routes

/// Ways your words start a new thread.
private enum Give: CaseIterable {
    /// Ask, and the router picks a kitten.
    case askKitten
    /// #general in Messages, and the router picks a kitten.
    case generalKitten
    /// The cat's DM in Messages, which goes through the router the same way, and it picks a kitten.
    case shadesKitten
    /// The box under a kitten's channel in Messages, which starts a new thread.
    case newThread
    /// Ask, and the router hands it to the frontier agent, with its own reading of the page as the task.
    case handOff
    /// Point at something broken.
    case fix
    /// Drop a file onto the cat, and the router picks a kitten.
    case dropKitten
    /// Drop a file onto the cat, and the router hands it to the frontier agent.
    case dropHandOff
    /// The cat's DM in Messages, and the router hands it to the frontier agent.
    case shadesHandOff
    /// A file attached in #general, and the router picks a kitten.
    case attachKitten
    /// A file attached in the box under a kitten's channel, which starts a new thread.
    case attachTopic
    /// A file attached in #general, and the router hands it to the frontier agent.
    case attachHandOff

    var picksAKitten: Bool { ![.handOff, .fix, .dropHandOff, .shadesHandOff, .attachHandOff].contains(self) }
}

/// Ways your words reach a thread that's already there.
private enum Pass: CaseIterable {
    /// Ask, and the router says it carries on from that thread.
    case askThread
    /// #general in Messages, and the router says the same.
    case generalThread
    /// The cat's DM in Messages, and the router says the same.
    case shadesThread
    /// Typing in a thread's pane in Messages, opened from its channel, Threads, Activity or Reply on a message.
    case threadReply
    /// The same, with "Also send to #channel" ticked, which only changes what Messages shows.
    case threadReplyAlsoSent
    /// Reply or Ask on an inbox row, which opens its thread with the box ready.
    case inboxReply
    /// Answering a question that thread asked, in Messages.
    case answerQuestion
    /// Drop a file onto the cat, and the router says it carries on from that thread.
    case dropThread
    /// A file attached in a thread's pane in Messages.
    case attachThread
    /// A file attached in #general, and the router says it carries on from that thread.
    case attachGeneralThread
}

/// A thread your words can be passed to, described by what decides whose it is.
private struct Destination: CustomStringConvertible {
    enum Folder: CaseIterable { case clawdeFolder, clawdeProject, elsewhere, noProject }
    enum Starter: CaseIterable { case you, clawdeThread, threadNamedForClawde, twoDeepFromClawde, someoneClear, unknown, unreadable, loop }

    var mode: RuntimeMode?
    var folder: Folder
    var namedForClawde: Bool
    var startedBy: Starter

    /// Worked out from how it was set up, not by asking the app, so the app can't mark its own homework.
    var mightBeScreenless: Bool {
        folder == .clawdeFolder || folder == .clawdeProject || namedForClawde || ![.you, .someoneClear].contains(startedBy)
    }

    var description: String {
        "a thread in \(folder)\(namedForClawde ? " titled Clawde:" : ""), started by \(startedBy), mode \(mode.map { "\($0)" } ?? "unknown")"
    }
}

/// Where something Shades sent ends up.
private enum Place: Equatable, CustomStringConvertible {
    case router, scratch
    case project(String)
    case thread(String)

    var description: String {
        switch self {
        case .router: return "the router's folder"
        case .scratch: return "T3's scratch folder"
        case .project(let path): return path
        case .thread(let id): return "thread \(id)"
        }
    }
}

// MARK: - The app, faked

@MainActor
private final class World {
    struct Send {
        var place: Place
        /// The title of the thread it went to, which is how far T3 has got when it starts: the one Shades gave, or the first line.
        var title: String
        var prompt: AgentPrompt
    }

    let clock = Date(timeIntervalSince1970: 100_000)
    let log = Log()
    let backend = FakeBackend()
    let stage: FakeStage
    let context: FakeContext
    let controller: AppController
    let kittens: [Kitten]
    private var asks = 0
    private var askedIn: [String: String] = [:]

    init(kittens: [Kitten], frontierMode: RuntimeMode = .autoAcceptEdits) {
        self.kittens = kittens
        stage = FakeStage(log: log)
        context = FakeContext(log: log)
        context.snapshotValue = ScreenBoundaryTests.screen
        for kitten in kittens {
            for path in [kitten.folder, kitten.project] { backend.projects[path] = "p:\(path)" }
        }
        var settings = Settings()
        settings.quickModel = ModelChoice(provider: "claudeAgent", model: "claude-haiku-5-5", effort: "medium")
        settings.quickMode = .approvalRequired
        settings.frontierMode = frontierMode
        let clock = clock
        controller = AppController(
            dependencies: AppDependencies(
                backend: backend,
                context: context,
                voice: FakeVoice(),
                inserter: FakeInserter(),
                keys: FakeKeys(),
                settings: settings,
                saveSettings: { _ in },
                kittens: { kittens },
                routerFolder: { "/shades/router" }
            ),
            stage: stage,
            now: { clock }
        )
        controller.threadListWait = 0
        controller.reportDelay = 0
    }

    func add(_ destination: Destination, clawde: Kitten) {
        let path: String? = switch destination.folder {
        case .clawdeFolder: clawde.folder
        case .clawdeProject: clawde.project
        case .elsewhere: "/code/site"
        case .noProject: nil
        }
        let title = destination.namedForClawde ? "Clawde: Fix routing" : "Fix routing"
        let own = { (starter: ThreadOrigin.Starter) in ThreadOrigin(title: title, projectPath: path, startedBy: starter) }
        switch destination.startedBy {
        case .you:
            backend.origins["w"] = own(.person)
        case .clawdeThread:
            backend.origins["w"] = own(.thread("c"))
            backend.origins["c"] = ThreadOrigin(title: "Change the rules", projectPath: clawde.folder, startedBy: .person)
        case .threadNamedForClawde:
            backend.origins["w"] = own(.thread("c"))
            backend.origins["c"] = ThreadOrigin(title: "Clawde: The change", projectPath: "/code/app", startedBy: .person)
        case .twoDeepFromClawde:
            backend.origins["w"] = own(.thread("m"))
            backend.origins["m"] = ThreadOrigin(title: "Helper", projectPath: "/code/app", startedBy: .thread("c"))
            backend.origins["c"] = ThreadOrigin(title: "Change the rules", projectPath: clawde.project, startedBy: .person)
        case .someoneClear:
            backend.origins["w"] = own(.thread("h"))
            backend.origins["h"] = ThreadOrigin(title: "Helper", projectPath: "/code/app", startedBy: .person)
        case .unknown:
            backend.origins["w"] = own(.unknown)
        case .unreadable:
            backend.untraceable = ["w"]
        case .loop:
            backend.origins["w"] = own(.thread("o"))
            backend.origins["o"] = ThreadOrigin(title: "Other", projectPath: "/code/app", startedBy: .thread("w"))
        }
        backend.reports["w"] = "Worked on the page that said Page-5ad1."
        controller.threadsChanged([AgentThread(id: "w", title: title, projectTitle: nil, status: .completed, model: "m", updatedAt: clock.addingTimeInterval(-60), runtimeMode: destination.mode, projectPath: path)])
    }

    /// Everything happens after the app has seen the screen once, so nothing can carry it over by accident.
    func run(_ route: Give, to target: String) async {
        let number = kittens.firstIndex { $0.name == target }.map { $0 + 1 } ?? 0
        switch route {
        case .askKitten:
            await ask("this one", routerSays: "KITTEN: \(number)")
        case .generalKitten:
            await ask("what's this?", routerSays: "It's Page-5ad1.")
            await messages("this one", to: .router, routerSays: "KITTEN: \(number)")
        case .shadesKitten:
            await ask("what's this?", routerSays: "It's Page-5ad1.")
            await messages("this one", to: .router, in: .shades, routerSays: "KITTEN: \(number)")
        case .newThread:
            await ask("what's this?", routerSays: "It's Page-5ad1.")
            controller.messagesAction(.startTopic("this one", with: kittens[number - 1], id: "sent-topic"))
            await settle()
        case .handOff:
            await ask("this one", routerSays: "HANDOFF: Do what Page-5ad1 says")
            await ask("what's this?", routerSays: "It's Page-5ad1.")
            await messages("this one too", to: .router, routerSays: "HANDOFF: Do what Page-5ad1 says")
        case .fix:
            controller.sendFix("the total is wrong", snapshot: ScreenBoundaryTests.screen)
            await settle()
        case .dropKitten:
            await drop("this one", routerSays: "KITTEN: \(number)")
        case .dropHandOff:
            await drop("this one", routerSays: "HANDOFF: Do what Statement-5ad1 says")
        case .shadesHandOff:
            await ask("this one", routerSays: "HANDOFF: Do what Page-5ad1 says")
            await messages("this one too", to: .router, in: .shades, routerSays: "HANDOFF: Do what Page-5ad1 says")
        case .attachKitten:
            await messages("this one", to: .router, routerSays: "KITTEN: \(number)", file: ScreenBoundaryTests.attached)
        case .attachTopic:
            controller.messagesAction(.startTopic("this one", with: kittens[number - 1], id: "sent-topic", file: ScreenBoundaryTests.attached))
            await settle()
        case .attachHandOff:
            await messages("this one", to: .router, routerSays: "HANDOFF: Do what Statement-5ad1 says", file: ScreenBoundaryTests.attached)
        }
    }

    func run(_ route: Pass) async {
        switch route {
        case .askThread:
            await ask("and that part?", routerSays: "SEND TO: 1")
        case .generalThread:
            await ask("what's this?", routerSays: "It's Page-5ad1.")
            await messages("and that part?", to: .router, routerSays: "SEND TO: 1")
        case .shadesThread:
            await ask("what's this?", routerSays: "It's Page-5ad1.")
            await messages("and that part?", to: .router, in: .shades, routerSays: "SEND TO: 1")
        case .threadReply:
            await ask("what's this?", routerSays: "It's Page-5ad1.")
            await messages("and that part?", to: .thread(id: "w", title: "Fix routing"))
        case .threadReplyAlsoSent:
            await ask("what's this?", routerSays: "It's Page-5ad1.")
            await messages("and that part?", to: .thread(id: "w", title: "Fix routing"), alsoSent: true)
        case .inboxReply:
            await ask("what's this?", routerSays: "It's Page-5ad1.")
            await messages("Go ahead", to: .thread(id: "w", title: "Fix routing", report: "e"))
        case .answerQuestion:
            await ask("what's this?", routerSays: "It's Page-5ad1.")
            askedIn["q"] = "w"
            await messages("The first one", to: .question(AgentQuestion(id: "q", threadID: "w", threadTitle: "Fix routing", text: "Page-5ad1 says to pick one. Which?")))
        case .dropThread:
            await drop("and that part?", routerSays: "SEND TO: 1")
        case .attachThread:
            await messages("and that part?", to: .thread(id: "w", title: "Fix routing"), file: ScreenBoundaryTests.attached)
        case .attachGeneralThread:
            await messages("and that part?", to: .router, routerSays: "SEND TO: 1", file: ScreenBoundaryTests.attached)
        }
    }

    func finish(_ thread: AgentThread, report: String) async {
        backend.reports[thread.id] = report
        var running = thread
        running.status = .running
        controller.threadsChanged([running])
        controller.threadsChanged([thread])
        for _ in 0..<50 where !controller.filing.isEmpty {
            await controller.reportTask?.value
            await Task.yield()
        }
        await settle()
    }

    /// A drop takes no look at the screen, so it isn't counted as an ask.
    func drop(_ question: String, routerSays: String) async {
        backend.routerSays[question] = routerSays
        controller.dropped(ScreenBoundaryTests.dropped)
        await controller.flow?.value
        stage.type(question)
        await settle()
    }

    func ask(_ question: String, routerSays: String) async {
        asks += 1
        backend.routerSays[question] = routerSays
        await controller.beginAsk()
        stage.type(question)
        await settle()
    }

    private func messages(_ words: String, to target: MessageTarget, in channel: ChannelID = .general, alsoSent: Bool = false, routerSays: String? = nil, file: Drop? = nil) async {
        if let routerSays { backend.routerSays[words] = routerSays }
        controller.messagesAction(.send(words, to: target, shownIn: channel, alsoSent: alsoSent, file: file))
        await settle()
    }

    private func settle() async {
        for _ in 0..<3 {
            await controller.attachTask?.value
            await controller.flow?.value
            await controller.replyTask?.value
            await controller.messagesTurn?.value
            await controller.frontierTask?.value
            await controller.forwardTask?.value
            await controller.reportTask?.value
            for _ in 0..<20 { await Task.yield() }
        }
    }

    /// Where each prompt and answer went, by how it was sent. A new thread's ID says how many had started before it.
    var sends: [Send] {
        var started: [String: (place: Place, title: String)] = [:]
        let prompts = backend.sent.map { sent in
            switch sent.mode {
            case .start:
                let id = sent.prompt.projectID
                let place: Place = id == nil ? .scratch : id == "project-router" ? .router : .project(String(id!.dropFirst(2)))
                let title = sent.prompt.title ?? String(sent.prompt.text.prefix { !$0.isNewline })
                started["thread-\(started.count + 1)"] = (place, title)
                return Send(place: place, title: title, prompt: sent.prompt)
            case .followUp, .forward:
                let thread = started[sent.threadID ?? ""] ?? (.thread(sent.threadID ?? ""), "")
                return Send(place: thread.place, title: thread.title, prompt: sent.prompt)
            }
        }
        let answers = backend.answers.map { id, words in
            Send(place: .thread(askedIn[id] ?? id), title: "", prompt: AgentPrompt(text: words.joined().joined(separator: "\n"), attachments: [], model: .quick, runtimeMode: .auto))
        }
        return prompts + answers
    }

    /// Fails for anything from the screen in a place that is, or might be, a screenless kitten's. `threads` says which
    /// existing threads might be, from how they were set up. Gives back how many places the screen reached that may see it.
    func check(_ scene: String, threads: [String: Bool], file: StaticString = #filePath, line: UInt = #line) -> Int {
        let screenless = Set(kittens.filter { !$0.seesScreen }.flatMap { [$0.folder, $0.project] })
        let names = kittens.filter { !$0.seesScreen }.map { "\($0.name):" }
        var reachedAllowed = 0
        XCTAssertEqual(context.options.count, asks, "\(scene): something other than Ask looked at the screen", file: file, line: line)
        for send in sends {
            if send.prompt.text.hasPrefix("You are Shades,") {
                XCTAssertEqual(send.place, .router, "\(scene): the router ran in \(send.place)", file: file, line: line)
            }
            guard ScreenBoundaryTests.carriesScreen(send.prompt) else { continue }
            let named = names.contains { send.title.hasPrefix($0) }
            let mightBeScreenless: Bool = switch send.place {
            case .router: false
            case .scratch: named
            case .project(let path): screenless.contains(path) || named
            case .thread(let id): threads[id] ?? true
            }
            XCTAssertFalse(mightBeScreenless, "\(scene): the screen reached \(send.place)", file: file, line: line)
            if !mightBeScreenless, send.place != .router { reachedAllowed += 1 }
        }
        return reachedAllowed
    }
}
