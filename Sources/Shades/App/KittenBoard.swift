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

enum KittenBoard {
    /// A thread belongs to a kitten if it's in the kitten's project, or carries its name from
    /// working in another project, the way a code change does.
    static func belongs(_ thread: AgentThread, to kitten: Kitten) -> Bool {
        thread.projectTitle == kitten.name || thread.title.hasPrefix("\(kitten.name):")
    }

    /// Who a thread counts as, when more than one could. Carrying a kitten's name beats being in its project.
    static func owner(of thread: AgentThread, among kittens: [Kitten]) -> Kitten? {
        kittens.first { thread.title.hasPrefix("\($0.name):") } ?? kittens.first { belongs(thread, to: $0) }
    }

    static func needsYou(_ thread: AgentThread) -> Bool {
        !thread.pendingApprovals.isEmpty || thread.pendingQuestion != nil || thread.status == .waitingForApproval || thread.status == .waitingForAnswer
    }

    /// Kittens that are taking work come first, and otherwise they stay put, so you can find one at a glance.
    static func statuses(kittens: [Kitten], threads: [AgentThread]) -> [KittenStatus] {
        let working = kittens.filter { !$0.planned }.map { status(of: $0, among: kittens, threads: threads) }
        let planned = kittens.filter(\.planned).map { KittenStatus(kitten: $0, state: .notSetUp) }
        return working + planned
    }

    private static func status(of kitten: Kitten, among kittens: [Kitten], threads: [AgentThread]) -> KittenStatus {
        let own = threads
            .filter { owner(of: $0, among: kittens) == kitten }
            .sorted { $0.updatedAt > $1.updatedAt }
        let waiting = own.filter(needsYou)
        let active = own.filter(\.status.isActive)

        if let first = waiting.first {
            return KittenStatus(kitten: kitten, state: .needsYou, threadID: first.id)
        }
        if let first = active.first {
            return KittenStatus(kitten: kitten, state: .working(sessions: active.count), threadID: first.id)
        }
        return KittenStatus(kitten: kitten, state: .idle, threadID: own.first?.id)
    }
}
