import Foundation

/// Which model a thread runs, in T3 Code's own terms.
public struct ModelChoice: Codable, Sendable, Hashable {
    public var provider: String
    public var model: String
    public var effort: String

    public init(provider: String, model: String, effort: String) {
        self.provider = provider
        self.model = model
        self.effort = effort
    }

    /// Answers quick questions about the screen.
    public static let quick = ModelChoice(provider: "codex", model: "gpt-6.1-sol", effort: "medium")
    /// Takes on anything that needs real work.
    public static let frontier = ModelChoice(provider: "claudeAgent", model: "claude-opus-5-5", effort: "xhigh")
    /// Sums up how a session went.
    public static let summary = ModelChoice(provider: "codex", model: "gpt-6.1-sol", effort: "low")
}

/// T3 Code's permission modes, narrowest first.
public enum RuntimeMode: String, Codable, Sendable, CaseIterable {
    case approvalRequired = "approval-required"
    case autoAcceptEdits = "auto-accept-edits"
    case auto
    case fullAccess = "full-access"
}

public enum AgentStatus: String, Codable, Sendable {
    case idle, starting, running, waitingForApproval, waitingForAnswer, completed, failed, interrupted

    /// Whether the agent is still going, including when it's stopped to ask you something.
    public var isActive: Bool {
        switch self {
        case .starting, .running, .waitingForApproval, .waitingForAnswer: return true
        case .idle, .completed, .failed, .interrupted: return false
        }
    }
}

public struct AgentAttachment: Sendable, Hashable {
    public var name: String
    public var mimeType: String
    public var data: Data

    public init(name: String, mimeType: String, data: Data) {
        self.name = name
        self.mimeType = mimeType
        self.data = data
    }
}

/// One message to an agent, starting a new thread or following up on one.
public struct AgentPrompt: Sendable {
    public var title: String?
    public var text: String
    public var attachments: [AgentAttachment]
    public var model: ModelChoice
    public var runtimeMode: RuntimeMode
    /// A T3 project to bind the thread to. `nil` starts a thread with no project.
    public var projectID: String?

    public init(
        title: String? = nil,
        text: String,
        attachments: [AgentAttachment] = [],
        model: ModelChoice,
        runtimeMode: RuntimeMode,
        projectID: String? = nil
    ) {
        self.title = title
        self.text = text
        self.attachments = attachments
        self.model = model
        self.runtimeMode = runtimeMode
        self.projectID = projectID
    }
}

/// What happens during one agent turn, in order.
public enum AgentReplyEvent: Sendable, Equatable {
    case started(threadID: String)
    /// Text so far is the concatenation of every delta.
    case text(delta: String)
    case needsApproval(ApprovalRequest)
    case finished(fullText: String)
    case failed(message: String)
}

public enum ApprovalKind: String, Codable, Sendable {
    case command, fileRead, fileChange, mcpElicitation, permission
}

public enum ApprovalDecision: String, Codable, Sendable {
    case accept, acceptForSession, decline
}

/// An agent has stopped and is asking permission to do something.
public struct ApprovalRequest: Identifiable, Sendable, Hashable {
    public var id: String
    public var threadID: String
    public var threadTitle: String
    public var kind: ApprovalKind
    /// Plain words for the bubble, such as the command it wants to run.
    public var summary: String
    public var createdAt: Date

    public init(id: String, threadID: String, threadTitle: String, kind: ApprovalKind, summary: String, createdAt: Date) {
        self.id = id
        self.threadID = threadID
        self.threadTitle = threadTitle
        self.kind = kind
        self.summary = summary
        self.createdAt = createdAt
    }
}

/// An agent has stopped to ask you something.
public struct AgentQuestion: Identifiable, Sendable, Hashable {
    /// The request this belongs to. It stays the same until you answer.
    public var id: String
    public var threadID: String
    public var threadTitle: String
    /// Empty if the words couldn't be read.
    public var text: String
    public var options: [String]
    /// How many more questions came with this one.
    public var moreCount: Int

    public init(id: String, threadID: String, threadTitle: String, text: String, options: [String] = [], moreCount: Int = 0) {
        self.id = id
        self.threadID = threadID
        self.threadTitle = threadTitle
        self.text = text
        self.options = options
        self.moreCount = moreCount
    }
}

/// A thread as the dashboard shows it.
public struct AgentThread: Identifiable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var projectTitle: String?
    public var status: AgentStatus
    public var model: String
    public var updatedAt: Date
    public var pendingApprovals: [ApprovalRequest]
    public var pendingQuestion: AgentQuestion?

    public init(
        id: String,
        title: String,
        projectTitle: String?,
        status: AgentStatus,
        model: String,
        updatedAt: Date,
        pendingApprovals: [ApprovalRequest] = [],
        pendingQuestion: AgentQuestion? = nil
    ) {
        self.id = id
        self.title = title
        self.projectTitle = projectTitle
        self.status = status
        self.model = model
        self.updatedAt = updatedAt
        self.pendingApprovals = pendingApprovals
        self.pendingQuestion = pendingQuestion
    }
}

/// Everything the cat needs from whatever runs its agents.
public protocol AgentBackend: AnyObject, Sendable {
    /// Connects, signing in the first time if needed.
    func connect() async throws
    /// Starts a new thread and streams its first turn.
    func start(_ prompt: AgentPrompt) -> AsyncThrowingStream<AgentReplyEvent, Error>
    /// Sends another message to an existing thread and streams that turn.
    func followUp(threadID: String, _ prompt: AgentPrompt) -> AsyncThrowingStream<AgentReplyEvent, Error>
    /// The current threads, sent again whenever anything changes.
    func watchThreads() -> AsyncStream<[AgentThread]>
    func respond(to request: ApprovalRequest, with decision: ApprovalDecision) async throws
    /// Shows the thread in T3 Code.
    func open(threadID: String)
    /// Takes a thread out of T3 Code's lists. It can still be read there.
    func archive(threadID: String) async throws
    /// Marks a finished thread as dealt with, without hiding it.
    func settle(threadID: String) async throws
    /// What the agent last said in this thread, or `nil` if it can't be read.
    func finalReport(threadID: String) async -> String?
}

public extension AgentBackend {
    func archive(threadID: String) async throws {}
    func settle(threadID: String) async throws {}
    func finalReport(threadID: String) async -> String? { nil }
}
