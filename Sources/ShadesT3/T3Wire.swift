import Foundation
import ShadesCore

/// Every shape T3 Code's server sends or expects, in one place. This is an internal beta API
/// that can change with any T3 release, so nothing outside this file knows what it looks like.
/// See docs/t3-integration.md.
enum T3Wire {
    /// The only orchestration protocol this client speaks. The server turns away anything else.
    static let protocolVersion = 2
    static let protocolQueryItem = URLQueryItem(name: "orchestrationProtocol", value: "2")
    static let scopes = ["orchestration:read", "orchestration:operate"]

    enum Route {
        static let environment = "/.well-known/t3/environment"
        static let session = "/api/auth/session"
        static let socket = "/ws"
    }

    enum Method {
        static let launchThread = "orchestration.launchThread"
        static let dispatchCommand = "orchestration.dispatchCommand"
        static let subscribeShell = "orchestration.subscribeShell"
        static let subscribeThread = "orchestration.subscribeThread"
        static let getTurnItem = "orchestration.getTurnItem"
        static let getThreadProjection = "orchestration.getThreadProjection"
        static let ensureScratch = "projects.ensureScratch"
        static let createUploadURL = "attachments.createUploadUrl"
    }

    /// Link that makes the desktop app show a thread.
    static func threadLink(environmentID: String, threadID: String) -> URL? {
        URL(string: "t3code://threads/\(encodeComponent(environmentID))/\(encodeComponent(threadID))")
    }

    static let maxImageBytes = 10 * 1024 * 1024
    static let imageTypes: Set<String> = ["image/gif", "image/jpeg", "image/png", "image/webp"]

    /// JavaScript's encodeURIComponent, which T3 builds its IDs with.
    static func encodeComponent(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: componentCharacters) ?? text
    }

    private static let componentCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()"
    )

    static func approvalItemID(requestID: String) -> String {
        "turn-item:runtime-request:\(encodeComponent(requestID))"
    }

    static func providerItemID(_ ref: TurnItem.NativeRef) -> String {
        "turn-item:provider:\(encodeComponent(ref.driver)):native-item:\(encodeComponent(ref.nativeId))"
    }

    // MARK: Decoding helpers

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = parseDate(text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a date"))
        }
        return decoder
    }

    static func parseDate(_ text: String) -> Date? {
        (try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
            ?? (try? Date(text, strategy: Date.ISO8601FormatStyle()))
    }

    static func encode(_ value: some Encodable) -> Data {
        // Only plain strings and numbers go in here, so encoding can't fail.
        (try? JSONEncoder().encode(value)) ?? Data("{}".utf8)
    }

    /// Skips anything a newer server sends that this client doesn't understand.
    struct Lossy<Value: Decodable>: Decodable {
        let value: Value?
        init(from decoder: Decoder) { value = try? Value(from: decoder) }
    }

    struct Ignored: Decodable {}

    // MARK: Discovery and HTTP

    struct RuntimeInfo: Decodable {
        let origin: String
    }

    struct Environment: Decodable {
        let environmentId: String
        let serverVersion: String
        let orchestrationProtocolVersion: Int?

        var isCompatible: Bool { orchestrationProtocolVersion == protocolVersion }
    }

    struct SessionState: Decodable {
        let authenticated: Bool
        let scopes: [String]?
        let expiresAt: Date?

        var isUsable: Bool {
            authenticated && Set(scopes ?? []).isSuperset(of: T3Wire.scopes)
        }
    }

    /// What `t3 auth session issue --json` prints.
    struct IssuedSession: Decodable {
        let sessionId: String
        let token: String
        let expiresAt: Date?
    }

    // MARK: RPC frames (Effect RPC with its JSON serialization)

    static func request(id: String, method: String, payload: Data) -> Data {
        var frame = Data(#"{"_tag":"Request","id":"#.utf8)
        frame.append(encode(id))
        frame.append(Data(#","tag":"#.utf8))
        frame.append(encode(method))
        frame.append(Data(#","payload":"#.utf8))
        frame.append(payload)
        frame.append(Data(#","headers":[]}"#.utf8))
        return frame
    }

    static func ack(requestID: String) -> Data { encode(Control(_tag: "Ack", requestId: requestID)) }
    static func interrupt(requestID: String) -> Data { encode(Control(_tag: "Interrupt", requestId: requestID)) }
    static let ping = Data(#"{"_tag":"Ping"}"#.utf8)

    private struct Control: Encodable {
        let _tag: String
        let requestId: String
    }

    /// One message off the socket, before anyone looks inside.
    struct FrameHeader: Decodable {
        let _tag: String
        let requestId: String?

        var isChunk: Bool { _tag == "Chunk" }
        var isExit: Bool { _tag == "Exit" }
    }

    /// The server sends one frame at a time today, but its serializer also allows a list.
    static func frames<Frame: Decodable>(_ type: Frame.Type, in data: Data) throws -> [Frame] {
        let decoder = decoder()
        if data.first == UInt8(ascii: "[") { return try decoder.decode([Frame].self, from: data) }
        return [try decoder.decode(Frame.self, from: data)]
    }

    struct ChunkFrame<Item: Decodable>: Decodable {
        let _tag: String
        let requestId: String?
        let values: [Lossy<Item>]?

        var items: [Item] { (values ?? []).compactMap(\.value) }
    }

    struct ExitFrame<Value: Decodable>: Decodable {
        let _tag: String
        let requestId: String?
        let exit: Exit<Value>?
    }

    struct Exit<Value: Decodable>: Decodable {
        let _tag: String
        let value: Value?
        let cause: [Cause]?

        var isSuccess: Bool { _tag == "Success" }
        /// Nothing failed. The server ended the stream, usually because it's shutting down.
        var isInterruptOnly: Bool {
            guard let cause, !cause.isEmpty else { return false }
            return cause.allSatisfy { $0._tag == "Interrupt" }
        }
        /// The server didn't recognize the method or the payload, so its protocol has moved on.
        var isProtocolMismatch: Bool {
            cause?.contains { cause in
                guard cause._tag == "Die", let defect = cause.defect?.value else { return false }
                return defect.hasPrefix("Unknown request tag") || defect.hasPrefix("Expected ")
            } ?? false
        }
        var failureMessage: String {
            cause?.lazy.compactMap(\.message).first ?? "T3 Code turned that down."
        }
    }

    struct Cause: Decodable {
        let _tag: String
        let error: CauseError?
        let defect: Lossy<String>?

        var message: String? {
            error?.detail ?? error?.message ?? error?._tag ?? defect?.value
        }
    }

    struct CauseError: Decodable {
        let _tag: String?
        let message: String?
        let detail: String?
    }

    // MARK: Requests

    struct Empty: Encodable {}

    struct ModelSelection: Codable, Equatable {
        struct Option: Codable, Equatable {
            let id: String
            let value: String
        }
        let instanceId: String
        let model: String
        var options: [Option]?

        init(_ choice: ModelChoice) {
            instanceId = choice.provider
            model = choice.model
            // Each provider names its effort option differently.
            let optionID = choice.provider.hasPrefix("codex") ? "reasoningEffort" : "effort"
            options = choice.effort.isEmpty ? nil : [Option(id: optionID, value: choice.effort)]
        }
    }

    struct ImageAttachment: Encodable {
        var type = "image"
        let id: String
        let name: String
        let mimeType: String
        let sizeBytes: Int
    }

    struct CreateUploadURL: Encodable {
        var type = "image"
        let name: String
        let mimeType: String
        let sizeBytes: Int
    }

    struct UploadTicket: Decodable {
        let attachmentId: String
        let relativeUrl: String
    }

    struct ScratchProject: Decodable {
        let projectId: String
    }

    struct LaunchThread: Encodable {
        struct Workspace: Encodable { var type = "root" }
        struct Message: Encodable {
            let messageId: String
            let text: String
            let attachments: [ImageAttachment]
        }

        let commandId: String
        let threadId: String
        let projectId: String
        let title: String
        let generateTitle: Bool
        let modelSelection: ModelSelection
        let runtimeMode: String
        var interactionMode = "default"
        var workspaceStrategy = Workspace()
        let initialMessage: Message
    }

    struct LaunchResult: Decodable {
        let threadId: String
        let projection: Projection
        let sequence: Int?
    }

    struct DispatchResult: Decodable {
        let sequence: Int
    }

    /// `start_immediately` without a delivery intent gives this message its own run: it starts now
    /// on an idle thread and queues behind an active one, and never steers a run already going.
    struct DispatchMessage: Encodable {
        struct Mode: Encodable { var type = "start_immediately" }

        var type = "message.dispatch"
        let commandId: String
        let threadId: String
        let messageId: String
        let text: String
        let attachments: [ImageAttachment]
        /// Left out, the thread carries on with the model it already has.
        let modelSelection: ModelSelection?
        var dispatchMode = Mode()
        var createdBy = "user"
        var creationSource = "web"
    }

    struct SetRuntimeMode: Encodable {
        var type = "thread.runtime-mode.set"
        let commandId: String
        let threadId: String
        let runtimeMode: String
    }

    struct RespondToRequest: Encodable {
        var type = "runtime-request.respond"
        let commandId: String
        let threadId: String
        let requestId: String
        let decision: String
    }

    struct ArchiveThread: Encodable {
        var type = "thread.archive"
        let commandId: String
        let threadId: String
    }

    struct SettleThread: Encodable {
        var type = "thread.settle"
        let commandId: String
        let threadId: String
    }

    struct SubscribeShell: Encodable {
        var requestCompletionMarker = true
        var omitIdleSubagents = true
        var omitOlderSettled = true

        /// Every thread that isn't archived, subagents and long-settled ones too.
        static let everything = SubscribeShell(omitIdleSubagents: false, omitOlderSettled: false)
    }

    struct SubscribeThread: Encodable {
        let threadId: String
        let afterSequence: Int?
        var acceptBoundedSnapshot = true

        /// Starts with the whole thread, rather than a window of its latest rows.
        static func whole(threadID: String) -> SubscribeThread {
            SubscribeThread(threadId: threadID, afterSequence: nil, acceptBoundedSnapshot: false)
        }
    }

    struct GetTurnItem: Encodable {
        let threadId: String
        let itemId: String
    }

    struct GetThreadProjection: Encodable {
        let threadId: String
    }

    struct TurnItemResult: Decodable {
        let item: TurnItem?
    }

    // MARK: The shell: every thread, kept up to date

    enum ShellItem: Decodable {
        case snapshot(threads: [ThreadShell], projects: [ProjectShell])
        case projectsOnly([ProjectShell])
        case threadUpdated(ThreadShell, isActive: Bool)
        case threadRemoved(id: String)
        case projectUpdated(ProjectShell)
        case projectRemoved(id: String)
        case other

        private enum Keys: String, CodingKey {
            case kind, snapshot, resolvedRepositoryIdentityRoots, location, thread, threadId, project, projectId
        }

        private struct Snapshot: Decodable {
            let threads: [Lossy<ThreadShell>]
            let projects: [Lossy<ProjectShell>]
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            switch try container.decode(String.self, forKey: .kind) {
            case "snapshot":
                let snapshot = try container.decode(Snapshot.self, forKey: .snapshot)
                let projects = snapshot.projects.compactMap(\.value)
                // These follow-up snapshots only refresh project details, and name no threads.
                if container.contains(.resolvedRepositoryIdentityRoots) {
                    self = .projectsOnly(projects)
                } else {
                    self = .snapshot(threads: snapshot.threads.compactMap(\.value), projects: projects)
                }
            case "thread.updated":
                let location = try container.decodeIfPresent(String.self, forKey: .location)
                self = .threadUpdated(try container.decode(ThreadShell.self, forKey: .thread), isActive: location != "archive")
            case "thread.removed":
                self = .threadRemoved(id: try container.decode(String.self, forKey: .threadId))
            case "project.updated":
                self = .projectUpdated(try container.decode(ProjectShell.self, forKey: .project))
            case "project.removed":
                self = .projectRemoved(id: try container.decode(String.self, forKey: .projectId))
            default:
                self = .other
            }
        }
    }

    struct ProjectShell: Decodable {
        let id: String
        let title: String
        let workspaceRoot: String
    }

    struct ThreadShell: Decodable {
        struct Lineage: Decodable {
            let parentThreadId: String?
            let relationshipToParent: String?
            let rootThreadId: String?
            let sideChat: Bool?
        }

        struct SelectedModel: Decodable {
            let model: String
        }

        struct PendingRequest: Decodable {
            let id: String
            let kind: String
            let createdAt: Date
            let blocking: Bool?
        }

        struct PullRequest: Decodable {
            struct Snapshot: Decodable {
                let state: String
            }
            let number: Int
            let snapshot: Snapshot
        }

        let id: String
        let projectId: String
        let title: String
        let status: String
        let runtimeMode: String?
        let modelSelection: SelectedModel
        let lineage: Lineage
        let pendingRuntimeRequest: PendingRequest?
        /// Shells and the like it left running when its turn ended. Only how many matters.
        let pendingBackgroundTasks: [Lossy<Ignored>]?
        let updatedAt: Date
        let archivedAt: Date?
        let deletedAt: Date?
        let settledAt: Date?
        let pullRequests: [Lossy<PullRequest>]?

        var latestPullRequest: ThreadPullRequest? {
            (pullRequests ?? []).compactMap(\.value).last.map { ThreadPullRequest(number: $0.number, state: $0.snapshot.state) }
        }

        /// Subagents and side chats live inside their parent, never in a thread list.
        var isListed: Bool {
            lineage.relationshipToParent != "subagent" && lineage.sideChat != true
                && archivedAt == nil && deletedAt == nil
        }

        var agentStatus: AgentStatus {
            if let pending = pendingRuntimeRequest, pending.blocking != false {
                if pending.kind == "user_input" { return .waitingForAnswer }
                if approvalKind(pending.kind) != nil { return .waitingForApproval }
            }
            switch status {
            case "preparing", "queued", "starting": return .starting
            case "running", "waiting": return .running
            case "completed": return .completed
            case "failed": return .failed
            case "interrupted", "cancelled", "rolled_back": return .interrupted
            default: return .idle
            }
        }
    }

    static func approvalKind(_ kind: String?) -> ApprovalKind? {
        switch kind {
        case "command": return .command
        case "file-read": return .fileRead
        case "file-change": return .fileChange
        case "mcp-elicitation": return .mcpElicitation
        case "permission": return .permission
        default: return nil
        }
    }

    // MARK: One thread's stream

    enum ThreadItem: Decodable {
        case snapshot(Projection, sequence: Int)
        case event(ThreadEvent, sequence: Int)
        case other

        private enum Keys: String, CodingKey {
            case kind, sequence, snapshotSequence, projection, event
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            switch try container.decode(String.self, forKey: .kind) {
            case "snapshot":
                self = .snapshot(
                    try container.decode(Projection.self, forKey: .projection),
                    sequence: try container.decode(Int.self, forKey: .snapshotSequence)
                )
            case "event":
                self = .event(
                    try container.decode(ThreadEvent.self, forKey: .event),
                    sequence: try container.decode(Int.self, forKey: .sequence)
                )
            default:
                self = .other
            }
        }
    }

    enum ThreadEvent: Decodable {
        case run(Run)
        case turnItem(TurnItem)
        case renamed(String)
        case other

        private enum Keys: String, CodingKey {
            case type, payload
        }

        private struct TitledThread: Decodable {
            let title: String
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            switch try container.decode(String.self, forKey: .type) {
            case "run.created", "run.updated":
                self = .run(try container.decode(Run.self, forKey: .payload))
            case "turn-item.updated":
                self = .turnItem(try container.decode(TurnItem.self, forKey: .payload))
            case "thread.metadata-updated":
                self = .renamed(try container.decode(TitledThread.self, forKey: .payload).title)
            default:
                self = .other
            }
        }
    }

    struct Projection: Decodable {
        struct Thread: Decodable {
            let title: String
            let runtimeMode: String?
        }

        let thread: Thread
        let runs: [Lossy<Run>]
        let turnItems: [Lossy<TurnItem>]
    }

    struct Run: Decodable {
        enum Outcome {
            case completed, failed, stopped
        }

        let id: String
        let userMessageId: String
        let status: String

        /// `waiting` isn't an ending: the run still has to save its checkpoint or finish background work.
        var outcome: Outcome? {
            switch status {
            case "completed": return .completed
            case "failed": return .failed
            case "interrupted", "cancelled", "rolled_back": return .stopped
            default: return nil
            }
        }
    }

    struct TurnItem: Decodable {
        struct Failure: Decodable {
            let message: String?
        }

        struct Question: Decodable {
            struct Option: Decodable {
                let label: String
            }
            let question: String
            let options: [Option]?
        }

        struct NativeRef: Decodable {
            let driver: String
            let nativeId: String
        }

        let id: String
        let type: String
        let status: String
        let runId: String?
        let parentItemId: String?
        /// The provider's own ID, which an approval shares with the command or file change it's about.
        let nativeItemRef: NativeRef?
        let startedAt: Date?
        let updatedAt: Date?
        let title: String?
        /// Assistant messages: the whole text so far, not a delta.
        let messageId: String?
        let text: String?
        /// Approval requests.
        let requestId: String?
        let requestKind: String?
        let prompt: String?
        let reason: String?
        let appName: String?
        /// Commands and file changes.
        let input: String?
        let fileName: String?
        /// Errors.
        let failure: Failure?
        /// Questions for the user.
        let questions: [Question]?
        /// User messages: who sent it. Agents' messages name the thread they came from.
        let createdBy: String?
        let senderThreadId: String?
        /// T3 writes these itself, some of them marked as coming from the user.
        let idleCompaction: Lossy<Ignored>?
        let workflowScript: Lossy<Ignored>?

        var isUserMessage: Bool { type == "user_message" }
        var isAssistantMessage: Bool { type == "assistant_message" }
        var isError: Bool { type == "error" }
        /// Claude's thinking comes through as assistant messages too, so it doesn't count as speech.
        var isSpoken: Bool {
            isAssistantMessage && !id.contains("thinking") && text?.contains(where: { !$0.isWhitespace }) == true
        }
        var isWrittenByT3: Bool { idleCompaction != nil || workflowScript != nil }
        /// Anything but these two is never put in a person's mouth.
        var isFromPerson: Bool { createdBy == nil || createdBy == "user" }
        var agentSenderThreadID: String? { createdBy == "agent" ? senderThreadId : nil }
        var when: Date { startedAt ?? updatedAt ?? .distantPast }
        var isCommandOrFileChange: Bool { type == "command_execution" || type == "file_change" }
        var isOpenApproval: Bool {
            type == "approval_request" && !["completed", "failed", "cancelled"].contains(status)
        }
    }

    /// T3 leaves this on the front of some of a person's messages.
    static let ultrathinkPrefix = "Ultrathink:"
    /// What T3 sends for a message that's only attachments.
    static let attachmentsOnly = "[User attached one or more files without additional text. Respond using the conversation context and the attached files.]"

    /// What the coding tool behind an imported thread wrote, which T3 marks as the user's. These are
    /// the tags found in real threads. Any hyphenated tag would do, but people write those too.
    static let toolTags = [
        "system-reminder", "task-notification", "scheduled-task", "ci-monitor-event", "side-sessions-event",
        "bash-input", "bash-stdout", "bash-stderr", "command-name", "command-message", "command-args",
        "local-command-[a-z]+", "artifact-view-context", "cross-session-message", "sandbox_violations",
    ].joined(separator: "|")

    static func withoutToolBlocks(_ text: String) -> String {
        Prompts.withoutBlocks(named: toolTags, in: text)
    }

    /// A thread's own items in time order. Subagents' items have a parent, so they're left out.
    static func ownItems(_ items: [TurnItem]) -> [TurnItem] {
        items.filter { $0.parentItemId == nil }.sorted { $0.when < $1.when }
    }

    /// What the agent last said in a thread, with any error it ended on first.
    static func finalReport(in items: [TurnItem]) -> String? {
        let ordered = ownItems(items)
        let message = ordered.last(where: \.isSpoken)
        let lastRun = ordered.last { $0.runId != nil }?.runId
        let error = ordered.last { $0.isError && $0.runId == lastRun }?.failure?.message
        let parts = [error.map { "Error: \($0)" }, message?.text].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    /// Plain words for the approval bubble. It comes from the agent, so it's only ever shown.
    ///
    /// Claude puts the command itself in `prompt`, but Codex puts its reason for asking there, so the
    /// real command or file comes from `related`, the item the approval is about.
    static func approvalSummary(kind: ApprovalKind, item: TurnItem?, related: TurnItem? = nil) -> String {
        let said = item?.prompt ?? item?.title ?? item?.reason
        switch kind {
        case .command:
            let command = related?.input.map(unwrappedCommand) ?? said
            return shortened(command).map { "Run: \($0)" } ?? "Run a command"
        case .fileChange:
            return shortened(related?.fileName ?? said).map { "Change: \($0)" } ?? "Change some files"
        case .fileRead:
            return shortened(said).map { "Read: \($0)" } ?? "Read a file"
        case .mcpElicitation:
            let asker = item?.appName ?? "A tool"
            return shortened(said).map { "\(asker) asks: \($0)" } ?? "\(asker) has a question"
        case .permission:
            return shortened(said) ?? "Get more permissions"
        }
    }

    /// Codex wraps commands as `/bin/zsh -lc '...'`. Anything quoted less simply is shown as it is.
    static func unwrappedCommand(_ input: String) -> String {
        let wrapped = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = wrapped.wholeMatch(of: #/(?:\S*\/)?(?:zsh|bash|sh) -l?c '((?s).*)'/#) else { return wrapped }
        let inner = String(match.1).replacingOccurrences(of: "'\\''", with: "\u{0}")
        guard !inner.contains("'") else { return wrapped }
        return inner.replacingOccurrences(of: "\u{0}", with: "'")
    }

    private static func shortened(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        guard trimmed.count > summaryLimit else { return trimmed }
        return String(trimmed.prefix(summaryLimit)) + "…"
    }

    private static let summaryLimit = 400
}
