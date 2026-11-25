import ShadesCore
@testable import ShadesT3
import TestSupport
import XCTest

final class RunFilingModelTests: XCTestCase {
    enum LeftRunning: Hashable { case awaited, leftover }

    struct World: Hashable {
        var running = false
        var run = 0
        var leftRunning: LeftRunning?
        var reviewerWorking = false
        var inbox: Data
        var filed: [Int: Int] = [:]
        var filedAsDoneWhileWaiting: Int?
    }

    static let runs = 2
    static let depth = 9
    static let kittenThread = "kitten-thread"

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    func testEveryRunAKittenEndsIsFiledOnceAndNeverAsDoneWhileItWaits() throws {
        let start = World(inbox: try Self.encoder.encode(Inbox(since: .distantPast)))
        let result = try explore(from: start, steps: Self.steps, upTo: Self.depth, checking: Self.problem)
        XCTAssertNil(result.counterexample, "\n\(result.counterexample.map(String.init(describing:)) ?? "")")
        XCTAssertTrue(result.reachedEveryState, "every state the model can reach was checked, not just the first \(Self.depth) steps")
    }

    static let steps: [Step<World>] = [
        Step("T3 starts a run") { world in
            guard !world.running, world.run < runs else { return nil }
            var world = world
            world.running = true
            world.run += 1
            world.leftRunning = nil
            return world
        },
        Step("the run starts a reviewer") { world in
            guard world.running, !world.reviewerWorking else { return nil }
            var world = world
            world.reviewerWorking = true
            return world
        },
        Step("the reviewer hands back") { world in
            guard world.reviewerWorking else { return nil }
            var world = world
            world.reviewerWorking = false
            return world
        },
        Step("the turn ends with nothing left running") { world in endTurn(world, leaving: nil) },
        Step("the turn ends watching its pull request") { world in endTurn(world, leaving: .awaited) },
        Step("the turn ends leaving a dev server listed") { world in endTurn(world, leaving: .leftover) },
        Step("what it left running stops") { world in
            guard world.leftRunning != nil else { return nil }
            var world = world
            world.leftRunning = nil
            return world
        },
        Step("Shades reads the thread list and files what the inbox is owed") { world in try fileWhatsOwed(world) },
    ]

    static func endTurn(_ world: World, leaving: LeftRunning?) -> World? {
        guard world.running else { return nil }
        var world = world
        world.running = false
        world.leftRunning = leaving
        return world
    }

    static func fileWhatsOwed(_ world: World) throws -> World? {
        var world = world
        var inbox = try JSONDecoder().decode(Inbox.self, from: world.inbox)
        guard let thread = try listed(world), inbox.owes(thread), !(thread.status.isActive && !thread.turnEnded) else { return nil }
        let waiting = world.leftRunning == .awaited || world.reviewerWorking
        if !thread.turnEnded, waiting { world.filedAsDoneWhileWaiting = world.run }
        inbox.file(SortedReport(note: "Run \(world.run)"), from: thread, startedBy: .you, at: .distantPast, id: { "entry-\(world.run)" })
        world.filed[world.run, default: 0] += 1
        world.inbox = try encoder.encode(inbox)
        return world
    }

    static func problem(_ world: World) -> String? {
        if let run = world.filed.first(where: { $0.value > 1 })?.key {
            return "run \(run) was filed \(world.filed[run]!) times"
        }
        if let run = world.filedAsDoneWhileWaiting {
            return "run \(run) was filed as done while what it waits on still worked"
        }
        let settled = (try? fileWhatsOwed(world)) == nil
        if settled, !world.running, world.run > 0, world.filed[world.run] == nil {
            return "run \(world.run) ended, and Shades read the list, but its report never reached the inbox"
        }
        return nil
    }

    static func listed(_ world: World) throws -> AgentThread? {
        var list = T3ThreadList()
        var shells = [shell(id: kittenThread, status: world.running ? "running" : "completed", run: world.run, leftRunning: world.leftRunning)]
        if world.reviewerWorking {
            shells.append(shell(id: "reviewer", status: "running", run: 1, parent: kittenThread))
        }
        let projects = T3Fixtures.projectTemplate
            .replacingOccurrences(of: "__ID__", with: "project-1")
            .replacingOccurrences(of: "__TITLE__", with: "Kitten")
            .replacingOccurrences(of: "__ROOT__", with: "/k/kitten")
        let snapshot = #"{"kind":"snapshot","snapshot":{"schemaVersion":2,"snapshotSequence":1,"threads":[\#(shells.joined(separator: ","))],"archivedThreads":[],"projects":[\#(projects)]}}"#
        list.apply(try T3Wire.decoder().decode(T3Wire.ShellItem.self, from: Data(snapshot.utf8)))
        return list.agentThreads(summaries: [:]).first { $0.id == kittenThread }
    }

    static func shell(id: String, status: String, run: Int, leftRunning: LeftRunning? = nil, parent: String? = nil) -> String {
        let tasks = switch leftRunning {
        case .awaited: #"[{"taskId":"pull-request-watch:github.com/owner/repo#12","description":"Watching pull request #12","kind":"monitor","awaited":true}]"#
        case .leftover: #"[{"taskId":"dev-server","description":"npm run dev","kind":"command","awaited":false}]"#
        case nil: "[]"
        }
        return T3Fixtures.threadTemplate
            .replacingOccurrences(of: "__ID__", with: id)
            .replacingOccurrences(of: "__PROJECT__", with: "project-1")
            .replacingOccurrences(of: "__TITLE__", with: "Thread \(id)")
            .replacingOccurrences(of: "__STATUS__", with: status)
            .replacingOccurrences(of: "__UPDATED__", with: "2026-11-05T04:00:00.000Z")
            .replacingOccurrences(of: #""__PENDING__""#, with: "null")
            .replacingOccurrences(of: #""__PARENT__""#, with: parent.map { #""\#($0)""# } ?? "null")
            .replacingOccurrences(of: #""__RELATIONSHIP__""#, with: parent == nil ? "null" : #""subagent""#)
            .replacingOccurrences(of: #""__ARCHIVED__""#, with: "null")
            .replacingOccurrences(of: #""latestRunId":null"#, with: run == 0 ? #""latestRunId":null"# : #""latestRunId":"run-\#(run)""#)
            .replacingOccurrences(of: #""pendingBackgroundTasks":[]"#, with: #""pendingBackgroundTasks":\#(tasks)"#)
    }
}
