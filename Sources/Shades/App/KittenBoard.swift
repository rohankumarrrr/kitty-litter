import Foundation
import ShadesCore

/// One kitten and how it's doing, for the view you get by Shift-clicking the cat.
struct KittenStatus: Equatable, Identifiable {
    enum State: Equatable {
        case working(sessions: Int)
        case needsYou
        case idle
        /// Its folder exists, but it isn't taking work yet.
        case notSetUp
    }

    var kitten: Kitten
    var state: State
    /// What clicking on it opens: whatever most needs looking at, if it's ever done anything.
    var threadID: String?
    /// How much is on its list.
    var things = 0

    var id: String { kitten.id }

    /// How it looks right now, at this tick of a timer running five times a second.
    func pose(tick: Int) -> CatPose {
        switch state {
        case .working:
            return CatPose(frame: tick % 2 == 0 ? .run1 : .run2, glint: .thinking(bright: tick % 4 < 2))
        case .needsYou:
            return CatPose(frame: .sit, glint: .attention(bright: tick % 4 < 2))
        case .idle:
            return CatPose(frame: tick % 12 < 6 ? .sleep1 : .sleep2, z: tick / 3)
        case .notSetUp:
            return CatPose(frame: .sit)
        }
    }
}

/// How the work in a thread came to an end, if it has.
enum ThreadEnding: Equatable {
    case report(AgentThread, failed: Bool)
    case stopped
}

enum KittenBoard {
    /// A new thread may not be listed yet, and a forwarded one may still show its last turn. It's
    /// a range because a kitten can write a future date, which mustn't hold a slot forever.
    private static let justChanged: ClosedRange<TimeInterval> = 0...60

    /// A thread belongs to a kitten if it's in the kitten's project, or carries its name from
    /// working in another project, the way a code change does.
    static func belongs(_ thread: AgentThread, to kitten: Kitten) -> Bool {
        belongs(title: thread.title, projectPath: thread.projectPath, to: kitten)
    }

    static func belongs(title: String, projectPath: String?, to kitten: Kitten) -> Bool {
        let inFolder = projectPath.map {
            URL(fileURLWithPath: $0).standardizedFileURL.path == URL(fileURLWithPath: kitten.folder).standardizedFileURL.path
        }
        return inFolder == true || title.hasPrefix("\(kitten.name):")
    }

    /// Kittens that are taking work come first, and otherwise they stay put, so you can find one at a glance.
    static func statuses(kittens: [Kitten], threads: [AgentThread], things: (Kitten) -> Int = { _ in 0 }) -> [KittenStatus] {
        let working = kittens.filter { !$0.planned }.map { kitten -> KittenStatus in
            var status = status(of: kitten, threads: threads)
            status.things = things(kitten)
            return status
        }
        let planned = kittens.filter(\.planned).map { KittenStatus(kitten: $0, state: .notSetUp) }
        return working + planned
    }

    private static func status(of kitten: Kitten, threads: [AgentThread]) -> KittenStatus {
        let own = threads
            .filter { belongs($0, to: kitten) }
            .sorted { $0.updatedAt > $1.updatedAt }
        let waiting = own.filter { !$0.pendingApprovals.isEmpty || $0.status == .waitingForApproval || $0.status == .waitingForAnswer }
        let active = own.filter(\.status.isActive)

        if let first = waiting.first {
            return KittenStatus(kitten: kitten, state: .needsYou, threadID: first.id)
        }
        if let first = active.first {
            return KittenStatus(kitten: kitten, state: .working(sessions: active.count), threadID: first.id)
        }
        return KittenStatus(kitten: kitten, state: .idle, threadID: own.first?.id)
    }

    /// How many more things this kitten can start. Waiting on you doesn't count, so an unanswered
    /// question can't stall a queue.
    static func room(for kitten: Kitten, list: WorkList, threads: [AgentThread], now: Date) -> Int {
        let working = list.items.filter { $0.state == .working }
        let running = threads.filter { thread in
            (thread.status == .starting || thread.status == .running)
                && (belongs(thread, to: kitten) || working.contains { $0.threadID == thread.id })
        }
        let notListedYet = working.filter { item in
            !threads.contains { $0.id == item.threadID } && justChanged.contains(now.timeIntervalSince(item.changedAt))
        }
        return WorkList.slots - running.count - notListedYet.count
    }

    /// Worked out from the thread list each time, so it holds for anything that happened while the app wasn't watching.
    static func ending(of item: WorkItem, threads: [AgentThread], now: Date) -> ThreadEnding? {
        guard item.state == .working, !justChanged.contains(now.timeIntervalSince(item.changedAt)) else { return nil }
        guard let thread = threads.first(where: { $0.id == item.threadID }) else { return .stopped }
        switch thread.status {
        case .starting, .running, .waitingForApproval, .waitingForAnswer: return nil
        case .completed: return .report(thread, failed: false)
        case .failed: return .report(thread, failed: true)
        case .interrupted, .idle: return .stopped
        }
    }
}
