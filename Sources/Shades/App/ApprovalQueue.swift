import Foundation
import ShadesCore

struct ApprovalQueue {
    private(set) var pending: [ApprovalRequest] = []
    private(set) var answered = 0
    private var answeredIDs: Set<String> = []
    private var listedIDs: Set<String> = []

    var isEmpty: Bool { pending.isEmpty }
    var first: ApprovalRequest? { pending.first }
    var position: Int { answered + 1 }
    var total: Int { answered + pending.count }

    @discardableResult
    mutating func add(_ request: ApprovalRequest) -> Bool {
        guard !answeredIDs.contains(request.id), !pending.contains(where: { $0.id == request.id }) else { return false }
        pending.append(request)
        pending.sort { $0.createdAt < $1.createdAt }
        return true
    }

    mutating func sync(with threads: [AgentThread]) {
        let listed = threads.flatMap(\.pendingApprovals)
        let ids = Set(listed.map(\.id))
        let gone = listedIDs.subtracting(ids)
        pending.removeAll { gone.contains($0.id) }
        answeredIDs.subtract(gone)
        listedIDs = ids
        for request in listed { add(request) }
        if pending.isEmpty { answered = 0 }
    }

    mutating func answer(_ id: String) {
        guard pending.contains(where: { $0.id == id }) else { return }
        pending.removeAll { $0.id == id }
        answeredIDs.insert(id)
        answered = pending.isEmpty ? 0 : answered + 1
    }

    mutating func runEnded(asking ids: Set<String>) -> Bool {
        let ended = pending.filter { ids.contains($0.id) }.map(\.id)
        pending.removeAll { ids.contains($0.id) }
        answeredIDs.formUnion(ended)
        if pending.isEmpty { answered = 0 }
        return !ended.isEmpty
    }

    mutating func restore(_ request: ApprovalRequest) {
        answeredIDs.remove(request.id)
        answered = max(0, answered - 1)
        add(request)
    }
}

enum ApprovalPolicy {
    static func offersSessionAllow(_ kind: ApprovalKind) -> Bool {
        switch kind {
        case .command, .fileRead, .fileChange: return true
        case .mcpElicitation, .permission: return false
        }
    }
}
