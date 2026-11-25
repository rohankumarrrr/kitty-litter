import Foundation
import ShadesCore

struct KittenStatus: Equatable, Identifiable {
    enum State: Equatable {
        case working(sessions: Int)
        case needsYou
        case idle
        case notSetUp
    }

    var kitten: Kitten
    var state: State
    var threadID: String?

    var id: String { kitten.id }

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
    static let shades = Kitten(name: CatWords.shades, role: CatWords.shadesRole, covers: "", folder: "")

    static func shadesStatus(_ work: [AgentThread]) -> KittenStatus {
        let active = work.filter(\.status.isActive)
        if let waiting = work.first(where: needsYou) { return KittenStatus(kitten: shades, state: .needsYou, threadID: waiting.id) }
        if let first = active.first { return KittenStatus(kitten: shades, state: .working(sessions: active.count), threadID: first.id) }
        return KittenStatus(kitten: shades, state: .idle, threadID: work.first?.id)
    }

    static func belongs(_ thread: AgentThread, to kitten: Kitten) -> Bool {
        belongs(title: thread.title, projectPath: thread.projectPath, to: kitten)
    }

    static func belongs(title: String, projectPath: String?, to kitten: Kitten) -> Bool {
        let standard = { URL(fileURLWithPath: $0).standardizedFileURL.path }
        let inFolder = projectPath.map { [kitten.folder, kitten.project].map(standard).contains(standard($0)) }
        return inFolder == true || title.hasPrefix("\(kitten.name):")
    }

    static func isInFolder(_ projectPath: String?, of kitten: Kitten) -> Bool {
        projectPath.map {
            URL(fileURLWithPath: $0).standardizedFileURL.path == URL(fileURLWithPath: kitten.folder).standardizedFileURL.path
        } == true
    }

    static func owner(of thread: AgentThread, among kittens: [Kitten]) -> Kitten? {
        Owners(kittens).of(thread)
    }

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

    static func statuses(kittens: [Kitten], threads: [AgentThread]) -> [KittenStatus] {
        let owners = Owners(kittens)
        return statuses(kittens: kittens, byOwner: Dictionary(grouping: threads) { owners.of($0)?.id })
    }

    static func statuses(kittens: [Kitten], byOwner: [String?: [AgentThread]]) -> [KittenStatus] {
        let working = kittens.filter { !$0.planned }.map { status(of: $0, own: byOwner[$0.id] ?? []) }
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
