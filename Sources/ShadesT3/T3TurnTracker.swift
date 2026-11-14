import Foundation
import ShadesCore

/// Turns one thread's stream into the events of one turn. Pure, so it can be tested on recordings.
struct T3TurnTracker {
    let threadID: String
    let messageID: String
    private(set) var threadTitle: String
    private(set) var runID: String?
    private(set) var isFinished = false

    private var messages: [(id: String, text: String)] = []
    private var askedRequests: Set<String> = []
    private var commandsAndFileChanges: [String: T3Wire.TurnItem] = [:]
    private var lastError: String?

    init(threadID: String, messageID: String, threadTitle: String, runID: String? = nil) {
        self.threadID = threadID
        self.messageID = messageID
        self.threadTitle = threadTitle
        self.runID = runID
    }

    mutating func apply(_ item: T3Wire.ThreadItem) -> [AgentReplyEvent] {
        guard !isFinished else { return [] }
        switch item {
        case let .snapshot(projection, _):
            threadTitle = projection.thread.title
            var events: [AgentReplyEvent] = []
            let runs = projection.runs.compactMap(\.value)
            if let run = runs.first(where: { $0.userMessageId == messageID }) { runID = run.id }
            for turnItem in projection.turnItems.compactMap(\.value) { events += apply(turnItem) }
            if let run = runs.first(where: { $0.id == runID }) { events += apply(run) }
            return events
        case let .event(.run(run), _):
            return apply(run)
        case let .event(.turnItem(turnItem), _):
            return apply(turnItem)
        case let .event(.renamed(title), _):
            threadTitle = title
            return []
        case .event(.other, _), .other:
            return []
        }
    }

    private mutating func apply(_ run: T3Wire.Run) -> [AgentReplyEvent] {
        guard run.userMessageId == messageID || run.id == runID else { return [] }
        runID = run.id
        switch run.outcome {
        case .completed:
            isFinished = true
            return [.finished(fullText: fullText)]
        case .failed:
            isFinished = true
            return [.failed(message: lastError ?? "The agent ran into a problem.")]
        case .stopped:
            isFinished = true
            return [.failed(message: lastError ?? "The agent was stopped.")]
        case nil:
            return []
        }
    }

    private mutating func apply(_ item: T3Wire.TurnItem) -> [AgentReplyEvent] {
        // A steer joins a run another message started, and only its own words say which.
        if runID == nil, item.isUserMessage, item.messageId == messageID, let run = item.runId {
            runID = run
            return []
        }
        guard let runID, item.runId == runID else { return [] }

        if item.isAssistantMessage, item.parentItemId == nil, let id = item.messageId, let text = item.text {
            return applyMessage(id: id, text: text)
        }
        if item.isError {
            lastError = item.failure?.message ?? lastError
            return []
        }
        if item.isCommandOrFileChange, let nativeID = item.nativeItemRef?.nativeId {
            commandsAndFileChanges[nativeID] = item
            return []
        }
        if item.isOpenApproval, let requestID = item.requestId,
           let kind = T3Wire.approvalKind(item.requestKind), askedRequests.insert(requestID).inserted {
            return [.needsApproval(ApprovalRequest(
                id: requestID,
                threadID: threadID,
                threadTitle: threadTitle,
                kind: kind,
                summary: T3Wire.approvalSummary(
                    kind: kind,
                    item: item,
                    related: item.nativeItemRef.flatMap { commandsAndFileChanges[$0.nativeId] }
                ),
                createdAt: item.startedAt ?? item.updatedAt ?? Date()
            ))]
        }
        return []
    }

    /// Each update carries the whole message so far, which is why a replay after a reconnect is harmless.
    private mutating func applyMessage(id: String, text: String) -> [AgentReplyEvent] {
        guard let index = messages.firstIndex(where: { $0.id == id }) else {
            guard !text.isEmpty else { return [] }
            let separator = messages.isEmpty ? "" : Self.messageSeparator
            messages.append((id, text))
            return [.text(delta: separator + text)]
        }
        let known = messages[index].text
        guard !known.hasPrefix(text) else { return [] }
        messages[index].text = text
        // A rewrite can't be sent as a delta. The finished event still carries the right text.
        guard text.hasPrefix(known) else { return [] }
        return [.text(delta: String(text.dropFirst(known.count)))]
    }

    private var fullText: String {
        messages.map(\.text).joined(separator: Self.messageSeparator)
    }

    private static let messageSeparator = "\n\n"
}
