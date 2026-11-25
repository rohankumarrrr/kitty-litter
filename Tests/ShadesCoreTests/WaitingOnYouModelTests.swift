import Foundation
@testable import ShadesCore
import XCTest

final class WaitingOnYouModelTests: XCTestCase {
    static let depth = 5

    func testEveryOrderOfEventsKeepsWaitingOnYouTrue() {
        var explored = 0
        var failures: [String] = []
        func walk(_ world: World, _ left: Int) {
            explored += 1
            if let broken = world.broken() {
                failures.append("\(world.trace.joined(separator: ", ")): \(broken)")
                return
            }
            guard left > 0, failures.count < 3 else { return }
            for event in world.enabled {
                var next = world
                next.apply(event)
                walk(next, left - 1)
            }
        }
        walk(World(), Self.depth)
        XCTAssertEqual(failures, [], "after \(explored) states")
        XCTAssertGreaterThan(explored, 10_000, "it explored too little to mean anything")
    }

    func testTheReRaiseFromTheAuditIsCaught() {
        var world = World()
        for event: Event in [.end(.a, .decision), .replyInApp(.a), .sendLands(.a), .end(.a, .note), .wake(.a), .end(.a, .note)] {
            world.apply(event)
            XCTAssertNil(world.broken(), world.trace.joined(separator: ", "))
        }
        XCTAssertEqual(world.inbox.entries.filter(\.needsYou), [], "a note from a turn you didn't start isn't an answer to you")
    }

    func testAWakeAfterYourTurnSaidNothingIsntAnAnswerToYou() {
        var world = World()
        for event: Event in [.end(.a, .decision), .youWrite(.a), .end(.a, .silent), .wake(.a), .end(.a, .note)] {
            world.apply(event)
            XCTAssertNil(world.broken(), world.trace.joined(separator: ", "))
        }
        XCTAssertEqual(world.inbox.entries.filter(\.needsYou), [])
    }

    func testAStaleRowFromTheAuditIsCaught() {
        var world = World()
        for event: Event in [.end(.a, .decisionHeld), .merge(.a)] { world.apply(event) }
        XCTAssertEqual(world.inbox.entries.filter(\.needsYou), [], "its pull request merged without you")
        XCTAssertEqual(world.inbox.record.visits.map(\.exit), [.pullRequestMerged])
        XCTAssertEqual(world.inbox.record.visits.map(\.held), [true])
    }
}

private enum Worker: String, CaseIterable {
    case a, b
}

private enum Ending: String {
    case decision, decisionHeld, note, shipped, failed, silent
}

private enum Event: CustomStringConvertible {
    case end(Worker, Ending)
    case wake(Worker)
    case youWrite(Worker)
    case replyInApp(Worker)
    case sendLands(Worker)
    case sendFails(Worker)
    case settle(Worker)
    case merge(Worker)
    case archive(Worker)
    case done(Worker)

    var description: String {
        switch self {
        case .end(let thread, let ending): "\(thread) ends with \(ending)"
        case .wake(let thread): "\(thread) is woken by something else"
        case .youWrite(let thread): "you write to \(thread) in T3"
        case .replyInApp(let thread): "you reply to \(thread)'s row"
        case .sendLands(let thread): "your reply reaches \(thread)"
        case .sendFails(let thread): "your reply to \(thread) fails"
        case .settle(let thread): "\(thread) settles"
        case .merge(let thread): "\(thread)'s pull request merges"
        case .archive(let thread): "\(thread) is archived"
        case .done(let thread): "you press Done on \(thread)'s row"
        }
    }
}

private struct Expected {
    var asking = false
    var repliedRow = false
    var runIsYours = false
}

private struct World {
    var inbox = Inbox(since: .distantPast)
    var threads: [Worker: AgentThread] = [:]
    var running: Set<Worker> = [.a, .b]
    var sending: Worker?
    var sendingRow: String?
    var expected: [Worker: Expected] = [.a: Expected(), .b: Expected()]
    var clock = Date(timeIntervalSince1970: 1_000)
    var runs = 0
    var trace: [String] = []

    init() {
        for thread in Worker.allCases {
            threads[thread] = AgentThread(
                id: thread.rawValue,
                title: "Work \(thread)",
                projectTitle: nil,
                status: .running,
                model: "m",
                updatedAt: clock,
                pullRequest: thread == .a ? ThreadPullRequest(number: 1, state: "open", watched: true) : nil,
                lastRunStartedAt: clock
            )
        }
    }

    var enabled: [Event] {
        if let sending { return [.sendLands(sending), .sendFails(sending)] }
        var events: [Event] = []
        for thread in Worker.allCases where threads[thread] != nil {
            if running.contains(thread) {
                let endings: [Ending] = thread == .a ? [.decision, .decisionHeld, .note, .shipped, .failed, .silent] : [.decision]
                events += endings.map { .end(thread, $0) }
            } else {
                events.append(.wake(thread))
                if thread == .a { events += [.youWrite(.a), .replyInApp(.a), .done(.a)] }
            }
            if thread == .a { events += [.settle(.a), .merge(.a), .archive(.a)] }
        }
        return events
    }

    mutating func apply(_ event: Event) {
        trace.append(event.description)
        clock = clock.addingTimeInterval(10)
        switch event {
        case .end(let thread, let ending):
            runs += 1
            var shown = threads[thread]!
            shown.lastRunID = "run-\(runs)"
            shown.lastRunEndedAt = clock
            shown.status = ending == .failed ? .failed : ending == .decisionHeld ? .running : .completed
            shown.turnEnded = ending == .decisionHeld
            threads[thread] = shown
            running.remove(thread)
            follow()
            let sorted: SortedReport = switch ending {
            case .decision, .decisionHeld: SortedReport(decision: "Pick one?")
            case .failed: SortedReport(decision: "Hit a snag.")
            case .note: SortedReport(note: "By the way.")
            case .shipped: SortedReport(shipped: "It's live.")
            case .silent: SortedReport()
            }
            let runs = runs
            if ending == .silent {
                inbox.skip(shown)
            } else {
                inbox.file(sorted, from: shown, startedBy: .you, at: clock) { "row-\(runs)" }
            }
            var hope = expected[thread]!
            switch ending {
            case .decision, .decisionHeld, .failed:
                hope.asking = true
                hope.repliedRow = false
            case .shipped:
                hope.asking = false
                hope.repliedRow = false
            case .note:
                hope.asking = hope.repliedRow && hope.runIsYours
                hope.repliedRow = false
            case .silent:
                break
            }
            expected[thread] = hope
        case .wake(let thread):
            start(thread, yours: false)
        case .youWrite(let thread):
            start(thread, yours: true)
        case .replyInApp(let thread):
            if let row = inbox.entries.last(where: { $0.threadID == thread.rawValue && $0.followsItsThread && $0.repliedAt == nil }) {
                inbox.markReplied(row.id, at: clock)
                sendingRow = row.id
            }
            sending = thread
        case .sendLands(let thread):
            sending = nil
            sendingRow = nil
            start(thread, yours: true)
        case .sendFails:
            sending = nil
            if let row = sendingRow { inbox.markReplied(row, at: nil) }
            sendingRow = nil
        case .settle(let thread):
            threads[thread]?.settledAt = clock
            follow()
            expected[thread] = Expected(runIsYours: expected[thread]!.runIsYours)
        case .merge(let thread):
            let open = threads[thread]?.pullRequest?.isOpen == true
            threads[thread]?.pullRequest?.state = "merged"
            follow()
            if open { expected[thread] = Expected(runIsYours: expected[thread]!.runIsYours) }
        case .archive(let thread):
            threads[thread] = nil
            running.remove(thread)
            follow()
            expected[thread] = Expected()
        case .done(let thread):
            if let row = inbox.entries.last(where: { $0.threadID == thread.rawValue && $0.followsItsThread }) {
                inbox.remove(row.id, because: .done, at: clock)
            }
            expected[thread] = Expected(runIsYours: expected[thread]!.runIsYours)
        }
    }

    private mutating func start(_ thread: Worker, yours: Bool) {
        if yours { threads[thread]?.lastWordsFromYouAt = clock }
        threads[thread]?.lastMessageAt = clock
        threads[thread]?.lastRunStartedAt = clock.addingTimeInterval(1)
        threads[thread]?.status = .running
        threads[thread]?.turnEnded = false
        running.insert(thread)
        follow()
        var hope = expected[thread]!
        if yours {
            hope.repliedRow = hope.asking || hope.repliedRow
        } else {
            hope.repliedRow = false
        }
        hope.asking = false
        hope.runIsYours = yours
        expected[thread] = hope
    }

    private mutating func follow() {
        inbox.follow(Array(threads.values), at: clock)
    }

    func broken() -> String? {
        for thread in Worker.allCases {
            let waiting = inbox.entries.filter { $0.threadID == thread.rawValue && $0.followsItsThread && $0.needsYou }.count
            let hope = expected[thread]!
            if sending == thread { continue }
            if waiting != (hope.asking ? 1 : 0) {
                return "\(thread) has \(waiting) rows waiting on you, but it's \(hope.asking ? "" : "not ")stopped on you"
            }
        }
        let open = inbox.record.visits.filter(\.isOpen).map(\.row)
        if Set(open).count != open.count { return "a row is in the record twice at once" }
        let waitingRows = Set(inbox.entries.filter(\.needsYou).map(\.id))
        if Set(open) != waitingRows { return "the record says \(open.sorted()) wait on you, the inbox says \(waitingRows.sorted())" }
        if inbox.record.visits.contains(where: { ($0.leftAt ?? $0.enteredAt) < $0.enteredAt }) { return "a row left before it came" }
        return nil
    }
}
