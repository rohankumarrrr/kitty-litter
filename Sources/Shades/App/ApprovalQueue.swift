import Foundation
import ShadesCore

/// Requests waiting on you, oldest first. They arrive from two places, the reply streams
/// and the thread list, so this keeps them straight and doesn't ask anything twice.
struct ApprovalQueue {
    private(set) var pending: [ApprovalRequest] = []
    /// How many you've answered since the queue was last empty, for "2 of 3".
    private(set) var answered = 0
    private var answeredIDs: Set<String> = []
    private var listedIDs: Set<String> = []

    var isEmpty: Bool { pending.isEmpty }
    var first: ApprovalRequest? { pending.first }
    var position: Int { answered + 1 }
    var total: Int { answered + pending.count }

    /// Adds a request from a reply stream.
    @discardableResult
    mutating func add(_ request: ApprovalRequest) -> Bool {
        guard !answeredIDs.contains(request.id), !pending.contains(where: { $0.id == request.id }) else { return false }
        pending.append(request)
        pending.sort { $0.createdAt < $1.createdAt }
        return true
    }

    /// Catches up with the thread list. A request that was listed and no longer is got
    /// answered somewhere else, such as in T3 itself, so it goes away here too.
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

    /// You answered. Stale copies of the thread list can't bring it back.
    mutating func answer(_ id: String) {
        guard pending.contains(where: { $0.id == id }) else { return }
        pending.removeAll { $0.id == id }
        answeredIDs.insert(id)
        answered = pending.isEmpty ? 0 : answered + 1
    }

    /// The answer didn't get through, so it's still waiting.
    mutating func restore(_ request: ApprovalRequest) {
        answeredIDs.remove(request.id)
        answered = max(0, answered - 1)
        add(request)
    }
}

enum ApprovalPolicy {
    /// "Allow for this session" makes sense for repeatable actions, but not for one-off
    /// questions or broad permissions, which you should look at every time.
    static func offersSessionAllow(_ kind: ApprovalKind) -> Bool {
        switch kind {
        case .command, .fileRead, .fileChange: return true
        case .mcpElicitation, .permission: return false
        }
    }
}
