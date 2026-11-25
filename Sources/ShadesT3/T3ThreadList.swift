import Foundation
import ShadesCore

public struct T3Project: Identifiable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var path: String

    public init(id: String, title: String, path: String) {
        self.id = id
        self.title = title
        self.path = path
    }
}

struct T3ThreadList {
    // Outside the repo: T3 names a delegate_task child thread this way, and tells its parent itself when it's done.
    static let delegatedThreadPrefix = "thread:delegated-task:"

    struct PendingApproval: Equatable {
        let requestID: String
        let threadID: String
        let kind: ApprovalKind
    }

    struct PendingQuestion: Equatable {
        let requestID: String
        let threadID: String
    }

    struct QuestionWords: Equatable {
        var text: String
        var options: [String]
        var moreCount: Int
        var form: AnswerForm? = nil
    }

    let scratchRoot: String?
    private(set) var isLoaded = false
    private var threads: [String: T3Wire.ThreadShell] = [:]
    private var projectsByID: [String: T3Wire.ProjectShell] = [:]

    init(scratchRoot: String? = nil) {
        self.scratchRoot = scratchRoot
    }

    mutating func apply(_ item: T3Wire.ShellItem) {
        switch item {
        case let .snapshot(threads, projects):
            self.threads = Dictionary(threads.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
            projectsByID = Dictionary(projects.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
            isLoaded = true
        case let .projectsOnly(projects):
            for project in projects { projectsByID[project.id] = project }
        case let .threadUpdated(thread, isActive):
            threads[thread.id] = isActive ? thread : nil
        case let .threadRemoved(id):
            threads[id] = nil
        case let .projectUpdated(project):
            projectsByID[project.id] = project
        case let .projectRemoved(id):
            projectsByID[id] = nil
        case .other:
            break
        }
    }

    func runtimeMode(of threadID: String) -> String? {
        threads[threadID]?.runtimeMode
    }

    var projects: [T3Project] {
        projectsByID.values
            .filter { !isScratch($0) }
            .map { T3Project(id: $0.id, title: $0.title, path: $0.workspaceRoot) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var pendingApprovals: [PendingApproval] {
        threads.values.compactMap { thread in
            guard let pending = thread.pendingRuntimeRequest, let kind = T3Wire.approvalKind(pending.kind) else { return nil }
            return PendingApproval(requestID: pending.id, threadID: thread.id, kind: kind)
        }
    }

    var pendingQuestions: [PendingQuestion] {
        threads.values.compactMap { thread in
            guard let pending = thread.pendingRuntimeRequest, pending.kind == "user_input" else { return nil }
            return PendingQuestion(requestID: pending.id, threadID: thread.id)
        }
    }

    func agentThreads(summaries: [String: String], questions: [String: QuestionWords] = [:]) -> [AgentThread] {
        var approvalsByListedThread: [String: [ApprovalRequest]] = [:]
        var questionsByListedThread: [String: AgentQuestion] = [:]
        for thread in threads.values {
            guard let pending = thread.pendingRuntimeRequest,
                  pending.kind == "user_input",
                  let words = questions[pending.id],
                  let owner = listedOwner(of: thread)
            else { continue }
            questionsByListedThread[owner.id] = AgentQuestion(
                id: pending.id,
                threadID: thread.id,
                threadTitle: owner.title,
                text: words.text,
                options: words.options,
                moreCount: words.moreCount,
                form: words.form,
                askedAt: pending.createdAt
            )
        }
        for thread in threads.values {
            guard let pending = thread.pendingRuntimeRequest,
                  let kind = T3Wire.approvalKind(pending.kind),
                  let summary = summaries[pending.id],
                  let owner = listedOwner(of: thread)
            else { continue }
            approvalsByListedThread[owner.id, default: []].append(ApprovalRequest(
                id: pending.id,
                threadID: thread.id,
                threadTitle: owner.title,
                kind: kind,
                summary: summary,
                createdAt: pending.createdAt
            ))
        }

        return threads.values
            .filter(\.isListed)
            .map { thread in
                let approvals = (approvalsByListedThread[thread.id] ?? []).sorted { $0.createdAt < $1.createdAt }
                let waiting = isWaitingOnWork(thread)
                return AgentThread(
                    id: thread.id,
                    title: thread.title,
                    projectTitle: projectsByID[thread.projectId].flatMap { isScratch($0) ? nil : $0.title },
                    status: !approvals.isEmpty ? .waitingForApproval : waiting ? .running : thread.agentStatus,
                    turnEnded: waiting,
                    model: thread.modelSelection.model,
                    updatedAt: thread.updatedAt,
                    pendingApprovals: approvals,
                    pendingQuestion: questionsByListedThread[thread.id],
                    runtimeMode: thread.runtimeMode.flatMap(RuntimeMode.init(rawValue:)),
                    settledAt: thread.settledAt,
                    pullRequest: thread.latestPullRequest,
                    projectPath: projectsByID[thread.projectId].flatMap { isScratch($0) ? nil : $0.workspaceRoot },
                    lastRunID: thread.latestRunId,
                    lastRunEndedAt: thread.latestRunCompletedAt,
                    lastVisitedAt: thread.lastVisitedAt,
                    startedByAgent: thread.createdBy == "agent",
                    isDelegated: thread.id.hasPrefix(Self.delegatedThreadPrefix),
                    lastRunStartedAt: thread.latestRunStartedAt,
                    lastWordsFromYouAt: thread.latestUserAuthoredMessageAt,
                    lastMessageAt: thread.latestUserMessageAt
                )
            }
            .sorted { ($0.updatedAt, $0.id) > ($1.updatedAt, $1.id) }
    }

    var threadsWithoutWords: [AgentThread] {
        let summaries = Dictionary(pendingApprovals.map { ($0.requestID, "") }, uniquingKeysWith: { first, _ in first })
        let questions = Dictionary(
            pendingQuestions.map { ($0.requestID, QuestionWords(text: "", options: [], moreCount: 0)) },
            uniquingKeysWith: { first, _ in first }
        )
        return agentThreads(summaries: summaries, questions: questions)
    }

    func listedThreadID(of id: String) -> String? {
        threads[id].flatMap(listedOwner)?.id
    }

    private func isWaitingOnWork(_ thread: T3Wire.ThreadShell) -> Bool {
        guard thread.agentStatus == .completed else { return false }
        let awaited = thread.pendingBackgroundTasks?.contains { $0.value?.awaited == true } == true
        let childWorking = threads.values.contains { child in
            child.lineage.parentThreadId == thread.id && child.agentStatus.isActive
        }
        return awaited || childWorking
    }

    private func listedOwner(of thread: T3Wire.ThreadShell) -> T3Wire.ThreadShell? {
        var current = thread
        var seen: Set<String> = []
        while !current.isListed {
            guard seen.insert(current.id).inserted,
                  let next = (current.lineage.parentThreadId ?? current.lineage.rootThreadId).flatMap({ threads[$0] })
            else { return nil }
            current = next
        }
        return current
    }

    private func isScratch(_ project: T3Wire.ProjectShell) -> Bool {
        guard let scratchRoot else { return false }
        return URL(fileURLWithPath: project.workspaceRoot).standardizedFileURL.path == scratchRoot
    }
}
