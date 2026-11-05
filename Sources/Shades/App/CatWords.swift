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
    static let fullAccessLeavesScreenOut = "Agents with full access don't get your screen, so tell me what's wrong."
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
    static func onIt(modelName: String) -> String { "\(modelName) has this." }
    static func finishedCaption(_ thread: AgentThread, kitten: Kitten? = nil) -> String {
        guard let kitten else { return "Done: \(thread.title)" }
        let prefix = "\(kitten.name):"
        return thread.title.hasPrefix(prefix) ? thread.title : "\(prefix) \(thread.title)"
    }
    static func failedCaption(_ thread: AgentThread) -> String { "Hit a snag: \(thread.title)" }
    static func questionCaption(_ question: AgentQuestion) -> String { "Asking: \(question.threadTitle)" }
    static func kittenState(_ state: KittenStatus.State) -> String {
        switch state {
        case .working(let sessions): return sessions == 1 ? "Working" : "Working on \(sessions) things"
        case .needsYou: return "Needs you"
        case .idle: return "Idle"
        case .notSetUp: return "Not set up yet"
        }
    }

    static let messagesTitle = "Messages"
    static let needsYouTitle = "Needs you"
    static let needsYouSubtitle = "What's waiting on you, and what each kitten is on"
    static let nothingNeedsYou = "Nothing needs you."
    static let inProgress = "In progress"
    static let everyone = "Everyone"
    static let everyoneSubtitle = "Goes to whoever it's for"
    static let everyoneEmpty = "Say something and it goes to whoever it's for."
    static let shades = "Shades"
    static let newTopic = "New topic"
    static let answerInWords = "Type an answer"
    static let didntStart = "That didn't start. Try again?"
    static let answerInT3 = "This one's answered in T3."
    static func part(_ index: Int, of count: Int, _ text: String) -> String { count > 1 ? "\(index + 1) of \(count): \(text)" : text }
    static let unreadableQuestion = "They asked something I couldn't read."
    static let directMessages = "Direct messages"
    static let betweenKittens = "Between kittens"
    static let you = "You"
    static let someoneElse = "Someone else"
    static let readingMessages = "Reading their messages..."
    static let nothingOpen = "Nothing open."
    static let olderMessages = "Older messages are in T3."
    static let cantReachT3Yet = "I can't reach T3 Code. Open it and I'll catch up."
    static let stillGoing = "Still working on it..."
    static func haventTalked(_ names: [String]) -> String { "\(names.joined(separator: " and ")) haven't talked yet." }
    static func notSetUpYet(_ kitten: Kitten) -> String { "\(kitten.name) isn't set up yet." }
    static func couldntRead(_ count: Int) -> String { "Couldn't read \(count) \(count == 1 ? "thread" : "threads"). I'll try again." }
    static func earlierNotes(_ count: Int) -> String { "\(count) earlier \(count == 1 ? "note" : "notes")" }
    static func issues(_ count: Int) -> String { "\(count) open" }
    static func reportsTitle(_ kind: InboxEntry.Kind) -> String { kind == .shipped ? "Shipped" : "Also" }

    /// The line over the box, saying where what you type goes.
    static func target(_ target: MessageTarget) -> String {
        switch target {
        case .router: return "To whoever it's for"
        case .newThread(let kitten): return "New topic with \(kitten.name)"
        case .thread(_, let title): return "In \(title)"
        case .starting(let kitten): return "Starting a new topic with \(kitten.name)..."
        case .question(let question): return answering(question.text)
        }
    }

    static func answering(_ text: String) -> String { "Answering: \(text.isEmpty ? "their question" : text)" }

    static func placeholder(_ target: MessageTarget) -> String {
        switch target {
        case .router: return "Message everyone"
        case .newThread, .thread, .starting: return "Message"
        case .question: return "Your answer"
        }
    }
    static func pullRequest(_ pullRequest: ThreadPullRequest) -> String { "PR #\(pullRequest.number) \(pullRequest.state)" }

    static func day(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let style = Date.FormatStyle(calendar: calendar).weekday(.wide).month(.abbreviated).day()
        return date.formatted(calendar.isDate(date, equalTo: now, toGranularity: .year) ? style : style.year())
    }

    static func age(of date: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        switch minutes {
        case ..<1: return "just now"
        case ..<60: return "\(minutes)m ago"
        case ..<1440: return "\(minutes / 60)h ago"
        default: return "\(minutes / 1440)d ago"
        }
    }

    static let allGood = "All good. I checked my signature, permissions, T3 Code and the kittens."
    static let selfCheckCaption = "Self-check"
    static func finding(_ finding: HealthFinding) -> String {
        [finding.problem, finding.fix].compactMap { $0 }.joined(separator: " ")
    }

    static func notSetUp(_ kitten: Kitten) -> String {
        "\(kitten.name) isn't a T3 project yet. Add \(kitten.workspace) in T3 and try again."
    }
    static let lostTheSession = "I lost track of which session that was for. Try asking again?"
    static func sentTo(_ thread: AgentThread) -> String { sentTo(thread.title) }
    static func sentTo(_ title: String) -> String { "Sent that to \(title)." }
    static func passedOn(to title: String?) -> String {
        title.map { "Work's started in a new session: \($0)." } ?? "Work's started in a new session."
    }

    /// A session's state and how long ago that was, for the router to read.
    static func sessionStatus(_ thread: AgentThread, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(thread.updatedAt) / 60)
        let when: String
        switch minutes {
        case ..<1: when = "just now"
        case 1: when = "1 minute ago"
        case ..<60: when = "\(minutes) minutes ago"
        case 60..<120: when = "1 hour ago"
        default: when = "\(minutes / 60) hours ago"
        }
        return "\(status(thread)), \(when)"
    }

    static let finishedWithoutReport = "It's finished, but didn't leave a report."
    static let failedWithoutReport = "It stopped before it could say why."
    static func failedRow(_ opening: String) -> String { "Hit a snag: \(opening)" }

    static let inboxCaption = "Inbox"
    static let inboxEmpty = "All clear. Nothing shipped or waiting on you."
    static let inboxSent = "Sent. Waiting to hear back."
    static let replyFirst = "Click Reply on the one you mean, then talk."

    static func replyPlaceholder(talkKey: HoldKey) -> String {
        talkKey == .off ? "Type your reply" : "Type your reply, or say it"
    }

    static func inboxHeadline(_ entries: [InboxEntry]) -> String {
        let decisions = entries.filter(\.needsYou).count
        let shipped = entries.filter { $0.kind == .shipped }.count
        var parts: [String] = []
        if decisions > 0 { parts.append(decisions == 1 ? "1 decision" : "\(decisions) decisions") }
        if shipped > 0 { parts.append("\(shipped) shipped") }
        return parts.joined(separator: ", ")
    }

    /// Notes don't count toward the headline, so this only says one's there when it's brought up the bubble
    /// by itself, which takes it being the answer to something you asked.
    static func inboxBubble(_ entries: [InboxEntry]) -> String {
        let headline = inboxHeadline(entries)
        if !headline.isEmpty { return headline }
        let notes = entries.filter { $0.kind == .note }.count
        return notes == 0 ? "" : notes == 1 ? "1 note" : "\(notes) notes"
    }

    /// What the menu says next to Inbox. What needs you comes first, since that's what it's for.
    static func inboxSummary(_ entries: [InboxEntry]) -> String? {
        let decisions = entries.filter(\.needsYou).count
        if decisions > 0 { return decisions == 1 ? "1 needs you" : "\(decisions) need you" }
        let shipped = entries.filter { $0.kind == .shipped }.count
        return shipped > 0 ? "\(shipped) shipped" : nil
    }

    static func ago(_ date: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        switch minutes {
        case ..<1: return "just now"
        case ..<60: return "\(minutes)m ago"
        case ..<(24 * 60): return "\(minutes / 60)h ago"
        default: return "\(minutes / (24 * 60))d ago"
        }
    }

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
