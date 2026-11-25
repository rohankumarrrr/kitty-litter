import XCTest
@testable import Shades
@testable import ShadesCore
import ShadesContext
import AppKit

@MainActor
final class ScreenBoundaryTests: XCTestCase {
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
    static let dropped = ScreenSnapshot(
        url: URL(fileURLWithPath: "/files/statement-5ad1.pdf"),
        pageText: "Statement-5ad1",
        screenshotJPEG: Data("Picture-5ad1".utf8),
        droppedNames: ["statement-5ad1.pdf"]
    )

    static let attached: Drop = picture(named: "statement-5ad1.png")
    static let attachedFiles = [attached, picture(named: "receipt-5ad1.png")]

    private static func picture(named name: String) -> Drop {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return .bytes(bitmap.representation(using: .png, properties: [:])!, name: name)
    }

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

    func testALaunchedThreadsReportReachesItsLauncherOnlyWhereYourScreenCouldGo() async {
        var reachedAllowed = 0
        var relayed = 0
        let launchers: [String: Bool] = ["c": true, "m": true, "h": false]
        for clawdeProject in [nil, "/code/shades"] {
            for folder in Destination.Folder.allCases {
                for starter in [Destination.Starter.clawdeThread, .threadNamedForClawde, .twoDeepFromClawde, .someoneClear] {
                    for route in [Pass.askThread, .threadReply, .dropThread] {
                        let clawde = Kitten(name: "Clawde", role: "The system", covers: "Shades itself", folder: "/k/clawde", project: clawdeProject, seesScreen: false)
                        let destination = Destination(mode: .autoAcceptEdits, folder: folder, namedForClawde: false, startedBy: starter)
                        let world = World(kittens: [clawde])
                        world.add(destination, clawde: clawde)
                        await world.run(route)
                        await world.endLaunchedTurn()
                        relayed += world.relays
                        let scene = "\(route) to \(destination), then its report to its launcher, Clawde in \(clawde.project)"
                        reachedAllowed += world.check(scene, threads: launchers.merging(["w": destination.mightBeScreenless]) { $1 })
                    }
                }
            }
        }
        XCTAssertGreaterThan(relayed, 0, "no launcher ever heard, so this can't tell where a report goes")
        XCTAssertGreaterThan(reachedAllowed, 0, "the screen never reached anything it may, so this can't tell when it's there")
    }

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

    // Outside the repo: Claude Code's Monitor tool runs shell commands, so it can read files too.
    func testTheRouterCantReadYourFiles() throws {
        let (denied, turnedAway) = try Self.routerRules()
        for tool in ["Read", "Glob", "Grep", "Monitor"] {
            XCTAssertTrue(turnedAway(tool), "\(tool) gets past the router's hook")
            XCTAssertTrue(denied.contains { Self.denies($0, tool) }, "\(tool) isn't denied outright, so it's open if hooks are off")
        }
    }

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

    static let waysToAnotherThread = [
        "mcp__t3-code__t3_thread_send", "mcp__t3-code__t3_thread_send_attachments", "mcp__t3-code__t3_thread_launch",
        "mcp__t3-code__create_threads", "mcp__t3-code__delegate_task", "mcp__t3-code__t3_queue",
        "mcp__t3-code__t3_thread_transfer", "mcp__t3-code__t3_pending_request", "mcp__t3-code__t3_worktree_handoff",
        "mcp__t3-code__schedule_task", "mcp__t3-code__run_scheduled_task_now", "mcp__t3-code__write_pull_request_guides",
        "SendMessage", "RemoteTrigger", "CronCreate", "Bash", "Monitor", "Write", "Edit", "NotebookEdit",
        "Agent", "Task", "Skill", "WebFetch",
        "mcp__t3-code__t3_thread_reply", "mcp__t3__t3_thread_send", "mcp__t3code__thread_send", "SomethingNew",
    ]

    static let onlyRead: Set = ["WebSearch", "ToolSearch"]

    static func routerRules() throws -> (denied: [String], turnedAway: (String) -> Bool) {
        let settings = try XCTUnwrap(JSONSerialization.jsonObject(with: RouterBlock.settings) as? [String: Any])
        let denied = try XCTUnwrap((settings["permissions"] as? [String: Any])?["deny"] as? [String])
        let rule = try XCTUnwrap(((settings["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]])?.first)
        let hook = try NSRegularExpression(pattern: try XCTUnwrap(rule["matcher"] as? String))
        return (denied, { tool in hook.firstMatch(in: tool, range: NSRange(tool.startIndex..., in: tool)) != nil })
    }

    // Outside the repo: a Claude Code deny rule names one tool, or `mcp__<server>` for every tool on that server.
    static func denies(_ rule: String, _ tool: String) -> Bool {
        rule == tool || (rule.hasPrefix("mcp__") && !rule.dropFirst(5).contains("__") && tool.hasPrefix(rule + "__"))
    }

    static func carriesScreen(_ prompt: AgentPrompt) -> Bool {
        prompt.text.contains(mark) || prompt.title?.contains(mark) == true || prompt.text.contains(FakeContext.savedPath)
            || prompt.attachments.contains { String(decoding: $0.data, as: UTF8.self).contains(mark) || $0.name.contains(mark) || attachedPictures.contains($0.data) }
    }

    private static let attachedPictures = Set(attachedFiles.compactMap { $0.snapshot()?.screenshotJPEG })
}

private enum Give: CaseIterable {
    case askKitten
    case shadesKitten
    case newThread
    case handOff
    case fix
    case dropKitten
    case dropHandOff
    case shadesHandOff
    case attachKitten
    case attachTopic
    case attachHandOff
    case mentionKitten
    case attachMention
    case lockdownAsk
    case lockdownAskAgain
    case lockdownShades
    case lockdownAttach
    case lockdownDrop
    case lockdownFix

    var picksAKitten: Bool { ![.handOff, .fix, .dropHandOff, .shadesHandOff, .attachHandOff].contains(self) }
}

private enum Pass: CaseIterable {
    case askThread
    case shadesThread
    case threadReply
    case threadReplyAlsoSent
    case inboxReply
    case answerQuestion
    case dropThread
    case attachThread
    case attachShadesThread
    case lockdownThread
    case lockdownShadesThread
    case lockdownDropThread
}

private struct Destination: CustomStringConvertible {
    enum Folder: CaseIterable { case clawdeFolder, clawdeProject, elsewhere, noProject }
    enum Starter: CaseIterable { case you, clawdeThread, threadNamedForClawde, twoDeepFromClawde, someoneClear, unknown, unreadable, loop }

    var mode: RuntimeMode?
    var folder: Folder
    var namedForClawde: Bool
    var startedBy: Starter

    var mightBeScreenless: Bool {
        folder == .clawdeFolder || folder == .clawdeProject || namedForClawde || ![.you, .someoneClear].contains(startedBy)
    }

    var description: String {
        "a thread in \(folder)\(namedForClawde ? " titled Clawde:" : ""), started by \(startedBy), mode \(mode.map { "\($0)" } ?? "unknown")"
    }
}

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

@MainActor
private final class World {
    struct Send {
        var place: Place
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
    private var added: AgentThread?

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
        added = AgentThread(id: "w", title: title, projectTitle: nil, status: .completed, model: "m", updatedAt: clock.addingTimeInterval(-60), runtimeMode: destination.mode, projectPath: path)
        controller.threadsChanged([added!])
    }

    func endLaunchedTurn() async {
        let gotScreen = sends.contains { $0.place == .thread("w") && ScreenBoundaryTests.carriesScreen($0.prompt) }
        backend.reports["w"] = gotScreen ? "Worked on the page that said Page-5ad1." : "Worked on the page."
        guard var thread = added else { return }
        thread.startedByAgent = true
        thread.lastRunID = "run-launched"
        thread.lastRunStartedAt = clock.addingTimeInterval(-30)
        thread.status = .running
        controller.threadsChanged([thread])
        thread.status = .completed
        controller.threadsChanged([thread])
        await settle()
    }

    var relays: Int {
        backend.sent.filter { $0.mode == .forward && $0.prompt.text.hasPrefix("---\nThe Kitty Litter wrote this") }.count
    }

    func run(_ route: Give, to target: String) async {
        let number = kittens.firstIndex { $0.name == target }.map { $0 + 1 } ?? 0
        switch route {
        case .askKitten:
            await ask("this one", routerSays: "KITTEN: \(number)")
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
            await messages("this one", to: .router, routerSays: "KITTEN: \(number)", files: ScreenBoundaryTests.attachedFiles)
        case .attachTopic:
            controller.messagesAction(.startTopic("this one", with: kittens[number - 1], id: "sent-topic", files: ScreenBoundaryTests.attachedFiles))
            await settle()
        case .attachHandOff:
            await messages("this one", to: .router, routerSays: "HANDOFF: Do what Statement-5ad1 says", files: ScreenBoundaryTests.attachedFiles)
        case .mentionKitten:
            await ask("what's this?", routerSays: "It's Page-5ad1.")
            await mention("@\(ChannelBook.slug(target)) this one")
        case .attachMention:
            await mention("@\(ChannelBook.slug(target)) this one", files: ScreenBoundaryTests.attachedFiles)
        case .lockdownAsk:
            controller.lockdownPicked(kittens[number - 1])
            await ask("this one", routerSays: "It's Page-5ad1.")
        case .lockdownAskAgain:
            controller.lockdownPicked(kittens[number - 1])
            await ask("this one", routerSays: "It's Page-5ad1.")
            await ask("and that part?", routerSays: "It's Page-5ad1.")
        case .lockdownShades:
            await ask("what's this?", routerSays: "It's Page-5ad1.")
            controller.lockdownPicked(kittens[number - 1])
            await messages("this one", to: .router, routerSays: "It's Page-5ad1.")
        case .lockdownAttach:
            controller.lockdownPicked(kittens[number - 1])
            await messages("this one", to: .router, routerSays: "It's Page-5ad1.", files: ScreenBoundaryTests.attachedFiles)
        case .lockdownDrop:
            controller.lockdownPicked(kittens[number - 1])
            await drop("this one", routerSays: "It's Page-5ad1.")
        case .lockdownFix:
            controller.lockdownPicked(kittens[number - 1])
            controller.sendFix("the total is wrong", snapshot: ScreenBoundaryTests.screen)
            await settle()
        }
    }

    func run(_ route: Pass) async {
        switch route {
        case .askThread:
            await ask("and that part?", routerSays: "SEND TO: 1")
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
            await messages("and that part?", to: .thread(id: "w", title: "Fix routing"), files: ScreenBoundaryTests.attachedFiles)
        case .attachShadesThread:
            await messages("and that part?", to: .router, routerSays: "SEND TO: 1", files: ScreenBoundaryTests.attachedFiles)
        case .lockdownThread:
            lockDown(carryingOnIn: "w")
            await ask("and that part?", routerSays: "It's Page-5ad1.")
        case .lockdownShadesThread:
            await ask("what's this?", routerSays: "It's Page-5ad1.")
            lockDown(carryingOnIn: "w")
            await messages("and that part?", to: .router, routerSays: "It's Page-5ad1.")
        case .lockdownDropThread:
            lockDown(carryingOnIn: "w")
            await drop("and that part?", routerSays: "It's Page-5ad1.")
        }
    }

    private func lockDown(carryingOnIn thread: String) {
        var settings = controller.settings
        settings.lockdown = Lockdown(kitten: kittens[0].id, thread: thread)
        controller.apply(settings)
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

    private func mention(_ words: String, files: [Drop] = []) async {
        guard let kitten = MessageTarget.mentioned(in: words, among: kittens.filter { !$0.planned }) else { return XCTFail("no kitten in \(words)") }
        controller.messagesAction(.startTopic(words, with: kitten, id: "sent-mention", files: files))
        await settle()
    }

    private func messages(_ words: String, to target: MessageTarget, in channel: ChannelID = .shades, alsoSent: Bool = false, routerSays: String? = nil, files: [Drop] = []) async {
        if let routerSays { backend.routerSays[words] = routerSays }
        controller.messagesAction(.send(words, to: target, shownIn: channel, alsoSent: alsoSent, files: files))
        await settle()
    }

    private func settle() async {
        for _ in 0..<3 {
            await controller.attachTask?.value
            await controller.flow?.value
            await controller.replyTask?.value
            await controller.messagesTurn?.value
            await controller.lockdownTurn?.value
            await controller.frontierTask?.value
            await controller.forwardTask?.value
            await controller.reportTask?.value
            for _ in 0..<20 { await Task.yield() }
        }
    }

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
