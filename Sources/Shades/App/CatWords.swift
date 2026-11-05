import Foundation
import ShadesCore

/// Everything the cat says, in one place, so it keeps one voice: friendly and brief.
enum CatWords {
    enum Doing {
        case agents, seeing, listening, typing, keys
    }

    static let askPlaceholder = "Ask me anything"
    static let listening = "listening"
    static let cantReachT3 = "Can't reach T3 Code"
    static let privateApp = "This app is private, so I didn't look."
    static let needsScreenRecording = "I can't see your screen. Turn on Screen Recording for me in System Settings."
    static let noReply = "Hm, nothing came back. Try again?"
    static let didntCatch = "I didn't catch that."
    static let tellMeWhatsWrong = "I can't see this one, so tell me what's wrong."
    static let cantSeeScreen = "I can't see your screen just now, but ask away."
    static let approvalFailed = "That answer didn't go through. It's still waiting."

    static let setUp = "Turn those on in System Settings, then choose Restart from my menu."
    static let globeTip = "To dictate with Fn, set Press 🌐 key to Do Nothing in Keyboard Settings."

    static func fetchingEars(_ fraction: Double) -> String { "Fetching my ears: \(Int(fraction * 100))%" }
    static func shortcutTaken(_ label: String) -> String { "Another app has \(label), so use the menu bar for that one." }

    static func looking(at snapshot: ScreenSnapshot) -> String? {
        guard let app = snapshot.appName else { return nil }
        return "Looking at \(app)"
    }

    static func fixPlaceholder(talkKey: HoldKey) -> String {
        talkKey == .off ? "What's wrong? Or just press Return" : "What's wrong? Say it, or just press Return"
    }

    static func fixCaption(modelName: String) -> String { "\(modelName) will take a look." }
    static func handingOff(modelName: String) -> String { "Passing it to \(modelName)..." }
    static func onIt(modelName: String) -> String { "On it. \(modelName) has this." }
    static func finishedCaption(_ thread: AgentThread) -> String { "Done: \(thread.title)" }
    static func failedCaption(_ thread: AgentThread) -> String { "Hit a snag: \(thread.title)" }
    static func questionCaption(_ question: AgentQuestion) -> String { "Asking: \(question.threadTitle)" }
    static let finishedWithoutReport = "It's finished, but didn't leave a report."
    static let failedWithoutReport = "It stopped before it could say why."

    /// The question and what you can say to it. Answering happens in T3.
    static func question(_ question: AgentQuestion) -> String {
        guard !question.text.isEmpty else { return "It has a question for you." }
        var parts = [question.text]
        if !question.options.isEmpty { parts.append(question.options.map { "• \($0)" }.joined(separator: "\n")) }
        if question.moreCount == 1 { parts.append("And 1 more question.") }
        if question.moreCount > 1 { parts.append("And \(question.moreCount) more questions.") }
        return parts.joined(separator: "\n\n")
    }

    static func asks(_ kind: ApprovalKind) -> String {
        switch kind {
        case .command: return "Wants to run this:"
        case .fileRead: return "Wants to read this:"
        case .fileChange: return "Wants to change this:"
        case .mcpElicitation: return "Wants to ask you:"
        case .permission: return "Wants permission:"
        }
    }

    static func status(_ thread: AgentThread) -> String {
        if !thread.pendingApprovals.isEmpty { return "Needs you" }
        switch thread.status {
        case .idle: return "Idle"
        case .starting: return "Starting"
        case .running: return "Working"
        case .waitingForApproval: return "Needs you"
        case .waitingForAnswer: return "Has a question"
        case .completed: return "Done"
        case .failed: return "Failed"
        case .interrupted: return "Stopped"
        }
    }

    /// One short helpful line for something going wrong. A module can give its own by
    /// being a `LocalizedError`; otherwise the line depends on what the cat was doing.
    static func problem(_ error: Error, while doing: Doing) -> String {
        if let own = (error as? LocalizedError)?.errorDescription, !own.isEmpty, own.count <= 120 {
            return own
        }
        let words = String(describing: error).lowercased()
        switch doing {
        case .agents:
            return "I can't reach T3 Code. Is it running?"
        case .seeing:
            return needsScreenRecording
        case .listening:
            if words.contains("download") || words.contains("model") || words.contains("preparing") {
                return "Still fetching my ears. Try again in a minute."
            }
            if words.contains("permission") || words.contains("denied") || words.contains("microphone") {
                return "I can't hear you. Turn on the Microphone for me in System Settings."
            }
            return "My ears aren't working just now. Try again?"
        case .typing:
            return "I couldn't type that here. Turn on Accessibility for me in System Settings."
        case .keys:
            return "I can't feel your hold keys. Turn on Input Monitoring for me in System Settings."
        }
    }
}

/// Friendly names for whatever model is configured.
enum ModelNames {
    static func friendly(_ choice: ModelChoice) -> String {
        friendly(model: choice.model)
    }

    static func friendly(model: String) -> String {
        let parts = model.split(separator: "-").map(String.init)
        guard let first = parts.first?.lowercased() else { return model }
        // claude-opus-5-5 is Opus.
        if first == "claude", parts.count > 1 { return parts[1].capitalized }
        // gpt-6.1-sol is GPT-6.1 Sol.
        if first == "gpt", parts.count > 1 {
            let rest = parts.dropFirst(2).map(\.capitalized).joined(separator: " ")
            return "GPT-\(parts[1])" + (rest.isEmpty ? "" : " \(rest)")
        }
        return model
    }
}
