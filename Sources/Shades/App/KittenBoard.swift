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
    /// The cat itself, for its own work in Messages. It has no folder, so no thread is ever counted as its by that.
    static let shades = Kitten(name: CatWords.shades, role: CatWords.shadesRole, covers: "", folder: "")

    static func shadesStatus(_ work: [AgentThread]) -> KittenStatus {
        let active = work.filter(\.status.isActive)
        if let waiting = work.first(where: needsYou) { return KittenStatus(kitten: shades, state: .needsYou, threadID: waiting.id) }
        if let first = active.first { return KittenStatus(kitten: shades, state: .working(sessions: active.count), threadID: first.id) }
        return KittenStatus(kitten: shades, state: .idle, threadID: work.first?.id)
    }

    /// A thread belongs to a kitten if it's in the kitten's folder or project, or carries its
    /// name from working in another project, the way a code change does.
    static func belongs(_ thread: AgentThread, to kitten: Kitten) -> Bool {
        belongs(title: thread.title, projectPath: thread.projectPath, to: kitten)
    }

    static func belongs(title: String, projectPath: String?, to kitten: Kitten) -> Bool {
        let standard = { URL(fileURLWithPath: $0).standardizedFileURL.path }
        let inFolder = projectPath.map { [kitten.folder, kitten.project].map(standard).contains(standard($0)) }
        return inFolder == true || title.hasPrefix("\(kitten.name):")
    }

    /// Only a thread in a kitten's own folder keeps its notes, so "Name: ..." or the app project it works in doesn't count.
    static func isInFolder(_ projectPath: String?, of kitten: Kitten) -> Bool {
        projectPath.map {
            URL(fileURLWithPath: $0).standardizedFileURL.path == URL(fileURLWithPath: kitten.folder).standardizedFileURL.path
        } == true
    }

    /// Who a thread counts as, when more than one could. Carrying a kitten's name beats being in its project.
    static func owner(of thread: AgentThread, among kittens: [Kitten]) -> Kitten? {
        Owners(kittens).of(thread)
    }

    /// `owner(of:among:)` for many threads. Standardizing a path is slow, so each kitten's are standardized once here,
    /// and each folder threads are in once, however many threads are in it.
    final class Owners {
        private let kittens: [Kitten]
        private let folders: [[String]]
        private var byFolder: [String: Kitten?] = [:]

        init(_ kittens: [Kitten]) {
            self.kittens = kittens
            folders = kittens.map { [$0.folder, $0.project].map(KittenBoard.standard) }
        }

        func of(_ thread: AgentThread) -> Kitten? {
            if let named = kittens.first(where: { thread.title.hasPrefix("\($0.name):") }) { return named }
            guard let folder = thread.projectPath else { return nil }
            if let known = byFolder[folder] { return known }
            let path = KittenBoard.standard(folder)
            let owner = zip(kittens, folders).first { $0.1.contains(path) }?.0
            byFolder[folder] = owner
            return owner
        }
    }

    private static func standard(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    static func needsYou(_ thread: AgentThread) -> Bool {
        !thread.pendingApprovals.isEmpty || thread.pendingQuestion != nil || thread.status == .waitingForApproval || thread.status == .waitingForAnswer
    }

    /// Kittens that are taking work come first, and otherwise they stay put, so you can find one at a glance.
    static func statuses(kittens: [Kitten], threads: [AgentThread]) -> [KittenStatus] {
        let owners = threads.map(Owners(kittens).of)
        let working = kittens.filter { !$0.planned }.map { kitten in
            status(of: kitten, own: zip(threads, owners).filter { $0.1 == kitten }.map(\.0))
        }
        let planned = kittens.filter(\.planned).map { KittenStatus(kitten: $0, state: .notSetUp) }
        return working + planned
    }

    private static func status(of kitten: Kitten, own threads: [AgentThread]) -> KittenStatus {
        let own = threads.sorted { $0.updatedAt > $1.updatedAt }
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
