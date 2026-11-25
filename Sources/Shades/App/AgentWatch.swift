import Foundation
import ShadesCore

struct AgentWatch {
    enum Event: Equatable {
        case finished(AgentThread)
        case turnEnded(AgentThread)
        case failed(AgentThread)
        case hasQuestion(AgentQuestion)
    }

    static let recentWindow: TimeInterval = 15 * 60
    private static let maxRows = 12

    private var last: [String: AgentThread] = [:]
    private var quickThreads: Set<String> = []
    private var announcedQuestions: Set<String> = []
    private(set) var threads: [AgentThread] = []

    mutating func markQuick(_ threadID: String) {
        quickThreads.insert(threadID)
    }

    func isQuick(_ threadID: String) -> Bool {
        quickThreads.contains(threadID)
    }

    mutating func update(_ threads: [AgentThread]) -> [Event] {
        let work = threads.filter { !quickThreads.contains($0.id) }
        var events: [Event] = []
        for thread in work {
            if let question = thread.pendingQuestion, announcedQuestions.insert(question.id).inserted {
                events.append(.hasQuestion(question))
            }
            guard let before = last[thread.id], before.status.isActive else { continue }
            if thread.status == .completed { events.append(.finished(thread)) }
            if thread.status == .failed { events.append(.failed(thread)) }
            if thread.turnEnded && (!before.turnEnded || before.lastRunID != thread.lastRunID) { events.append(.turnEnded(thread)) }
        }
        last = Dictionary(work.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        self.threads = work
        return events
    }

    var runningCount: Int { threads.filter(\.status.isActive).count }
    var needsYouCount: Int {
        threads.filter { !$0.pendingApprovals.isEmpty || $0.status == .waitingForApproval || $0.status == .waitingForAnswer }.count
    }
    var isBusy: Bool { runningCount > 0 }

    func rows(at now: Date) -> [AgentThread] {
        let order: (AgentThread) -> Int = { thread in
            if !thread.pendingApprovals.isEmpty || thread.status == .waitingForApproval || thread.status == .waitingForAnswer { return 0 }
            return thread.status.isActive ? 1 : 2
        }
        return threads
            .filter { $0.status.isActive || ($0.status != .idle && now.timeIntervalSince($0.updatedAt) < Self.recentWindow) }
            .sorted { (order($0), $1.updatedAt) < (order($1), $0.updatedAt) }
            .prefix(Self.maxRows)
            .map { $0 }
    }

    var summary: String {
        if needsYouCount == 1 { return "Something needs you" }
        if needsYouCount > 1 { return "\(needsYouCount) things need you" }
        if runningCount == 1 { return "1 agent working" }
        if runningCount > 1 { return "\(runningCount) agents working" }
        return "Napping"
    }
}
