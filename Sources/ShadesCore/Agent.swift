import Foundation

public struct ModelChoice: Codable, Sendable, Hashable {
    public var provider: String
    public var model: String
    public var effort: String

    public init(provider: String, model: String, effort: String) {
        self.provider = provider
        self.model = model
        self.effort = effort
    }

    public static let quick = ModelChoice(provider: "claudeAgent", model: "claude-opus-5-5", effort: "xhigh")
    public static let frontier = ModelChoice(provider: "claudeAgent", model: "claude-opus-5-5", effort: "xhigh")
    public static let summary = ModelChoice(provider: "codex", model: "gpt-6.1-sol", effort: "low")
}

public enum RuntimeMode: String, Codable, Sendable, CaseIterable {
    case approvalRequired = "approval-required"
    case autoAcceptEdits = "auto-accept-edits"
    case auto
    case fullAccess = "full-access"
}

public enum AgentStatus: String, Codable, Sendable {
    case idle, starting, running, waitingForApproval, waitingForAnswer, completed, failed, interrupted

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

public struct AgentPrompt: Sendable {
    public var title: String?
    public var text: String
    public var attachments: [AgentAttachment]
    public var model: ModelChoice
    public var runtimeMode: RuntimeMode
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

public enum AgentReplyEvent: Sendable, Equatable {
    case started(threadID: String)
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

public struct ApprovalRequest: Identifiable, Sendable, Hashable {
    public var id: String
    public var threadID: String
    public var threadTitle: String
    public var kind: ApprovalKind
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

public struct AgentQuestion: Identifiable, Sendable, Hashable {
    public var id: String
    public var threadID: String
    public var threadTitle: String
    public var text: String
    public var options: [String]
    public var moreCount: Int
    public var form: AnswerForm?
    public var askedAt: Date?

    public init(
        id: String,
        threadID: String,
        threadTitle: String,
        text: String,
        options: [String] = [],
        moreCount: Int = 0,
        form: AnswerForm? = nil,
        askedAt: Date? = nil
    ) {
        self.id = id
        self.threadID = threadID
        self.threadTitle = threadTitle
        self.text = text
        self.options = options
        self.moreCount = moreCount
        self.form = form
        self.askedAt = askedAt
    }
}

public struct AnswerForm: Sendable, Hashable {
    public struct Part: Sendable, Hashable {
        public var key: String
        public var text: String
        public var options: [String]
        public var values: [String]
        public var takesOwnWords: Bool
        public var picksSeveral: Bool

        public init(key: String, text: String, options: [String], values: [String], takesOwnWords: Bool, picksSeveral: Bool = false) {
            self.key = key
            self.text = text
            self.options = options
            self.values = values
            self.takesOwnWords = takesOwnWords
            self.picksSeveral = picksSeveral
        }

        public func takes(_ answer: [String]) -> Bool {
            if answer.count == 1, takesOwnWords, !answer[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
            return !answer.isEmpty && (answer.count == 1 || picksSeveral) && Set(answer).count == answer.count && answer.allSatisfy(values.contains)
        }
    }

    public var parts: [Part]

    public init(parts: [Part]) {
        self.parts = parts
    }
}

public struct ThreadPullRequest: Sendable, Hashable {
    public var number: Int
    public var state: String
    public var url: String?
    public var checks: String?
    public var review: String?
    public var watched: Bool

    public init(number: Int, state: String, url: String? = nil, checks: String? = nil, review: String? = nil, watched: Bool = false) {
        self.number = number
        self.state = state
        self.url = url
        self.checks = checks
        self.review = review
        self.watched = watched
    }

    public var isOpen: Bool { state == "open" }
}

public struct AgentThread: Identifiable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var projectTitle: String?
    public var projectPath: String?
    public var status: AgentStatus
    public var turnEnded: Bool
    public var model: String
    public var updatedAt: Date
    public var pendingApprovals: [ApprovalRequest]
    public var pendingQuestion: AgentQuestion?
    public var runtimeMode: RuntimeMode?
    public var settledAt: Date?
    public var isSettled: Bool { settledAt != nil }
    public var pullRequest: ThreadPullRequest?
    public var startedByAgent: Bool
    public var isDelegated: Bool
    public var lastRunStartedAt: Date?
    public var lastWordsFromYouAt: Date?
    public var lastMessageAt: Date?
    public var isLiveTest: Bool { Self.isLiveTest(title: title) }
    public static func isLiveTest(title: String) -> Bool { title.hasPrefix("Shades test:") }
    public var wasSeenInT3: Bool {
        guard let visited = lastVisitedAt, let ended = lastRunEndedAt else { return false }
        return visited >= ended
    }
    public var lastRunID: String?
    public var lastRunEndedAt: Date?
    public var lastVisitedAt: Date?

    public init(
        id: String,
        title: String,
        projectTitle: String?,
        status: AgentStatus,
        turnEnded: Bool = false,
        model: String,
        updatedAt: Date,
        pendingApprovals: [ApprovalRequest] = [],
        pendingQuestion: AgentQuestion? = nil,
        runtimeMode: RuntimeMode? = nil,
        isSettled: Bool = false,
        settledAt: Date? = nil,
        pullRequest: ThreadPullRequest? = nil,
        projectPath: String? = nil,
        lastRunID: String? = nil,
        lastRunEndedAt: Date? = nil,
        lastVisitedAt: Date? = nil,
        startedByAgent: Bool = false,
        isDelegated: Bool = false,
        lastRunStartedAt: Date? = nil,
        lastWordsFromYouAt: Date? = nil,
        lastMessageAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.projectTitle = projectTitle
        self.projectPath = projectPath
        self.status = status
        self.turnEnded = turnEnded
        self.model = model
        self.updatedAt = updatedAt
        self.pendingApprovals = pendingApprovals
        self.pendingQuestion = pendingQuestion
        self.runtimeMode = runtimeMode
        self.lastRunID = lastRunID
        self.lastRunEndedAt = lastRunEndedAt
        self.lastVisitedAt = lastVisitedAt
        self.settledAt = settledAt ?? (isSettled ? .distantPast : nil)
        self.pullRequest = pullRequest
        self.startedByAgent = startedByAgent
        self.isDelegated = isDelegated
        self.lastRunStartedAt = lastRunStartedAt
        self.lastWordsFromYouAt = lastWordsFromYouAt
        self.lastMessageAt = lastMessageAt
    }
}

public struct Exchange: Sendable, Equatable, Identifiable {
    public enum Asker: Sendable, Equatable {
        case you
        case agent(threadID: String?)
        case schedule
    }

    public var id: String
    public var asker: Asker
    public var askedAt: Date
    public var ask: String?
    public var reply: String?
    public var repliedAt: Date?
    public var earlierNotes: Int
    public var failure: String?
    public var files: [ExchangeFile]

    public init(
        id: String,
        asker: Asker,
        askedAt: Date,
        ask: String? = nil,
        reply: String? = nil,
        repliedAt: Date? = nil,
        earlierNotes: Int = 0,
        failure: String? = nil,
        files: [ExchangeFile] = []
    ) {
        self.id = id
        self.asker = asker
        self.askedAt = askedAt
        self.ask = ask
        self.reply = reply
        self.repliedAt = repliedAt
        self.earlierNotes = earlierNotes
        self.failure = failure
        self.files = files
    }

    public var isTheKittyLittersOwnNote: Bool { asker == .you && ask == nil && files.isEmpty }
}

public struct ExchangeFile: Sendable, Equatable {
    public var name: String
    public var attachmentID: String?

    public init(name: String, attachmentID: String? = nil) {
        self.name = name
        self.attachmentID = attachmentID
    }
}

public struct ThreadOrigin: Sendable, Equatable {
    public enum Starter: Sendable, Equatable {
        case person
        case thread(String)
        case unknown
    }

    public var title: String
    public var projectPath: String?
    public var startedBy: Starter

    public init(title: String, projectPath: String?, startedBy: Starter) {
        self.title = title
        self.projectPath = projectPath
        self.startedBy = startedBy
    }
}

public protocol AgentBackend: AnyObject, Sendable {
    func connect() async throws
    func start(_ prompt: AgentPrompt) -> AsyncThrowingStream<AgentReplyEvent, Error>
    func followUp(threadID: String, _ prompt: AgentPrompt) -> AsyncThrowingStream<AgentReplyEvent, Error>
    func forward(threadID: String, text: String, attachments: [AgentAttachment], behavior: FollowUpBehavior) -> AsyncThrowingStream<AgentReplyEvent, Error>
    func watchThreads() -> AsyncStream<[AgentThread]>
    func respond(to request: ApprovalRequest, with decision: ApprovalDecision) async throws
    func answer(_ question: AgentQuestion, with answers: [[String]]) async throws
    func open(threadID: String) async throws
    func environmentID() async -> String?
    func projectID(atPath path: String) async -> String?
    func addProject(atPath path: String, title: String) async throws -> String
    func archive(threadID: String) async throws
    func settle(threadID: String) async throws
    func report(threadID: String, run: String?) async throws -> String?
    func allThreads() async -> [AgentThread]?
    func exchanges(threadID: String) async -> [Exchange]?
    func origin(of threadID: String) async -> ThreadOrigin?
    func deliver(threadID: String, text: String) async throws
    func threads(matching words: String) async -> [String]?
    func picture(attachmentID: String) async -> Data?
    func picture(threadID: String, path: String) async -> Data?
}

public extension AgentBackend {
    func forward(threadID: String, text: String, attachments: [AgentAttachment], behavior: FollowUpBehavior) -> AsyncThrowingStream<AgentReplyEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func projectID(atPath path: String) async -> String? { nil }
    func environmentID() async -> String? { nil }
    func addProject(atPath path: String, title: String) async throws -> String { throw CocoaError(.featureUnsupported) }
    func archive(threadID: String) async throws {}
    func settle(threadID: String) async throws {}
    func answer(_ question: AgentQuestion, with answers: [[String]]) async throws {}
    func allThreads() async -> [AgentThread]? { nil }
    func exchanges(threadID: String) async -> [Exchange]? { nil }
    func report(threadID: String, run: String?) async throws -> String? { nil }
    func finalReport(threadID: String) async -> String? { (try? await report(threadID: threadID, run: nil)) ?? nil }
    func origin(of threadID: String) async -> ThreadOrigin? { nil }
    func deliver(threadID: String, text: String) async throws { throw CocoaError(.featureUnsupported) }
    func threads(matching words: String) async -> [String]? { nil }
    func picture(attachmentID: String) async -> Data? { nil }
    func picture(threadID: String, path: String) async -> Data? { nil }
}
