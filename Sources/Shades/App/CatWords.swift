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
    static let rewriteCopied = "I couldn't swap it in, so it's copied. Paste it where you want it."
    static let didntCatch = "I didn't catch that."
    static let tellMeWhatsWrong = "I can't see this one, so tell me what's wrong."
    static let cantSeeScreen = "I can't see your screen just now, but ask away."
    static let overHere = "Over here."
    static let cantPoint = "I couldn't find it on screen to point at."
    static let approvalFailed = "That answer didn't go through. It's still waiting."
    static let frontDoorNoFolder = "I can't get the folder I answer from ready, so I can't take questions. Choose Check Myself from my menu."
    static let frontDoorNotClaude = "My front door model isn't Claude, so nothing would stop it passing your screen on. Pick a Claude one in my settings."

    static let setUp = "Turn those on in System Settings, then choose Restart from my menu."
    static let globeTip = "To dictate with Fn, set Press 🌐 key to Do Nothing in Keyboard Settings."

    static func fetchingEars(_ fraction: Double) -> String { "Fetching my ears: \(Int(fraction * 100))%" }
    static func shortcutTaken(_ label: String) -> String { "Another app has \(label), so use the menu bar for that one." }

    static func looking(at snapshot: ScreenSnapshot) -> String? {
        guard let app = snapshot.droppedNames.first ?? snapshot.appName else { return nil }
        return "Looking at \(app)"
    }

    static let askAboutDrop = "Ask about it, or just press Return"
    static let summarize = "Summarize this."
    static let cantReadThat = "I can only read PDFs, pictures and links."
    static let answersTakeNoFiles = "An answer to a question can only be words."
    static func remove(_ name: String) -> String { "Remove \(name)" }
    static let attach = "Attach"
    static let attachRecent = "Attach a recent file"
    static let noRecentFiles = "No recent pictures or PDFs"
    static let dropAFile = "Or drop one onto the box"
    static let aFile = "a file"
    static func attached(_ name: String) -> String { "Attached: \(name)" }
    static func cantTakeFiles(_ name: String) -> String {
        "\(name) can't take files. Put a link or the text in your message instead."
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
    static func notification(_ alert: NeedsYouAlert) -> String {
        let who = alert.who ?? "An agent"
        switch alert.kind {
        case .approval: return "\(who) needs an approval"
        case .question: return "\(who) has a question"
        case .decision: return "\(who) needs a decision"
        case .finished: return "\(who) finished"
        }
    }
    static func kittenState(_ state: KittenStatus.State) -> String {
        switch state {
        case .working(let sessions): return sessions == 1 ? "Working" : "Working on \(sessions) things"
        case .needsYou: return "Needs you"
        case .idle: return "Idle"
        case .notSetUp: return "Not set up yet"
        }
    }

    static let pairTitle = "Pair your phone"
    static let pairPicture = "QR code to pair your phone"
    static func pairHow(_ address: String?) -> String {
        let open = address.map { "Scan this with your phone's camera, or open \($0) and type the code." } ?? "Open the page on your phone and type the code."
        return open + " It works once, for the next 10 minutes. Your phone needs Tailscale on, and your Mac awake with me running."
    }
    static let phonePaired = "Your phone's paired. \(appName) is there now."
    static func phoneProblem(_ error: Error) -> String { "\(appName) on your phone isn't working. \(error.localizedDescription)" }

    /// The app's name, which is also its window's. The cat is still Shades.
    static let appName = "The Kitty Litter"
    static let activityTitle = "Activity"
    static let activitySubtitle = "What's waiting on you, and what each kitten is on"
    static let waitingOnYou = "Waiting on you"
    static let nothingNeedsYou = "Nothing needs you."
    static let inProgress = "In progress"
    static let threadsTitle = "Threads"
    static let threadsSubtitle = "Every thread you've written in"
    static let threadsEmpty = "Threads you write in show up here."
    static let channelsHeading = "Channels"
    static let general = "general"
    static let generalSubtitle = "Goes to whoever it's for"
    static let generalEmpty = "Say something and it goes to whoever it's for."
    static let shadesSubtitle = "What you've asked me"
    static let shadesOnPhone = "Work you chose to show here"
    static let shadesEmpty = "Say something, or ask me anywhere, and it shows up here."
    static func handedOff(_ task: String) -> String { "I started on that: \(task)" }
    static let passedOnToSession = "I passed that on to the work it carries on from."
    static let passedOnToKitten = "I passed that to the kitten it's for."
    static let passedOnCorrection = "I passed that correction on."
    static let shades = "Shades"
    /// What VoiceOver calls the cat: what pressing it does, then what it is.
    static let catLabel = "Ask \(shades)"
    static let catHelp = "A cat in sunglasses. Pressing it takes one look at your screen and opens the Ask box. Its menu has everything else."
    static let themeButton = "Theme"
    static let plainTheme = appName
    static let noThemesFound = "No themes from T3 Code, Cursor, VS Code or iTerm2"
    static let dropATheme = "Or drop a theme file onto \(appName)"
    static let themeUnreadable = "That isn't a theme I can read. Try one from T3 Code, VS Code, Cursor or iTerm2."
    static let themeNotSaved = "I couldn't save that theme, so it's only until I restart."
    static let shadesRole = "Work I started for you"
    static let threadTitle = "Thread"
    static let newThread = "New thread"
    static let openInT3 = "Open in T3"
    static let showOnPhone = "Show on phone"
    static let hideFromPhone = "Hide from phone"
    static let viewThread = "View thread"
    static let closeThread = "Close"
    static let quietThread = "Its messages are in T3."
    static let threadNotListed = "It's archived or deleted in T3, so I can't read it here."
    /// Under a thread's title: where it is and how it's going.
    static func threadDetails(_ thread: AgentThread) -> String {
        [thread.projectTitle, status(thread), thread.pullRequest.map(pullRequest)].compactMap { $0 }.joined(separator: " · ")
    }
    static func replies(_ count: Int) -> String { count == 1 ? "1 reply" : "\(count) replies" }
    static func lastReply(_ date: Date, now: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        return Calendar.current.isDate(date, inSameDayAs: now) ? "Last reply \(time)" : "Last reply \(day(date, now: now)) at \(time)"
    }
    static let workingOnIt = "Working on it"
    static let needsYouLabel = "Needs you"
    static func repliedToThread(_ parent: String) -> String { "replied to a thread: \(parent)" }
    static func moreReplies(_ count: Int) -> String { count == 1 ? "1 more reply" : "\(count) more replies" }
    static let new = "New"
    static func newMessages(_ count: Int) -> String { count == 1 ? "1 new message" : "\(count) new messages" }
    /// The way up to the New line, when it's above what you can see.
    static func jumpToNew(_ count: Int) -> String { "↑  \(newMessages(count))" }
    static let markUnread = "Mark unread"
    static func alsoSendTo(_ channel: String) -> String { "Also send to \(channel)" }
    static let answerInWords = "Type an answer"
    static let didntStart = "That didn't start. Try again?"
    static let sending = "Sending..."
    static let answerInT3 = "This one's answered in T3."
    static let picksSeveral = "Pick as many as you like."
    static let sendPicked = "Send"
    static let nextPart = "Next"
    static let heldDraft = "That question was answered meanwhile, so this won't send"
    static func part(_ index: Int, of count: Int, _ text: String) -> String { count > 1 ? "\(index + 1) of \(count): \(text)" : text }
    static let unreadableQuestion = "They asked something I couldn't read."
    static let directMessages = "Direct messages"
    static let shortcutsButton = "⌘/ Shortcuts"
    static let settingsButton = "Settings"
    static let allFonts = "All fonts"
    static let shortcutsTitle = "Keyboard shortcuts"
    static let jumpTitle = "Jump to"
    static let jumpPlaceholder = "Jump to a place or thread"
    static let jumpNothing = "Nothing by that name."
    static let searchTitle = "Search"
    static let searchPlaceholder = "Search messages"
    static let searchHint = "Type a word or two from the message."
    static let searchNothing = "No messages with those words."
    static let searchingT3 = "Looking through older threads in T3..."
    static func searchMore(_ count: Int) -> String { "The newest \(count). Add a word to narrow it down." }
    /// What ⌘/ lists, grouped as Slack's list is. The keys are T3 Code's, the Claude app's and Slack's own.
    static let shortcutGroups: [(title: String, rows: [(keys: String, does: String)])] = [
        ("Moving around", [
            ("⌥↑  ⌥↓", "Place above or below"),
            ("⌥⇧↑  ⌥⇧↓", "Unread channel above or below"),
            ("⌘1 … ⌘9", "That row of the sidebar"),
            ("⌘[  ⌘]", "Back and forward"),
            ("⌘K", "Jump to a place or thread"),
            ("⌘F", "Search messages"),
            ("⌘⇧T", "Threads"),
            ("⌘⇧M", "Activity"),
        ]),
        ("Threads", [
            ("⌘⇧[  ⌘⇧]", "Thread above or below"),
            ("Esc", "Close the thread"),
        ]),
        (appName, [
            ("⌘N", "Write here"),
            ("⌘W", "Close \(appName)"),
            ("⌘,", "Settings"),
            ("⌘/", "These shortcuts"),
        ]),
    ]
    static let you = "You"
    static let someoneElse = "Someone else"
    static let readingMessages = "Reading their messages..."
    static let nothingOpen = "Nothing open."
    static let loadOlder = "Load older messages"
    static let loadingOlder = "Loading older messages..."
    static let olderReplies = "Older replies are in T3."
    /// What T3Error.notRunning says, so the bubble and Messages name it the same way.
    static let cantReachT3Yet = "I can't reach T3 Code. Open it and try again."
    static let stillGoing = "Still working on it..."
    static func noThreadsYet(_ name: String) -> String { "You and \(name) haven't started a thread yet." }
    static func notSetUpYet(_ kitten: Kitten) -> String { "\(kitten.name) isn't set up yet." }
    static func couldntRead(_ count: Int) -> String { "Couldn't read \(count) \(count == 1 ? "thread" : "threads"). I'll try again." }
    static func earlierNotes(_ count: Int) -> String { "\(count) earlier \(count == 1 ? "note" : "notes")" }
    static func issues(_ count: Int) -> String { "\(count) open" }
    static func reportsTitle(_ kind: InboxEntry.Kind) -> String { kind == .shipped ? "Shipped" : "Also" }

    /// The line over the box, saying where what you type goes.
    static func target(_ target: MessageTarget, in channel: ChannelID? = nil) -> String {
        switch target {
        case .router: return channel == .shades ? "To me, without looking at your screen" : "To whoever it's for"
        case .newThread(let kitten): return "Starts a new thread with \(kitten.name)"
        case .thread(_, let title, _): return title.isEmpty ? "Replies in this thread" : "Replies in \(title)"
        case .starting(let kitten): return "Starting a new thread with \(kitten.name)..."
        case .question(let question): return answering(question.text)
        }
    }

    static func answering(_ text: String) -> String { "Answering: \(text.isEmpty ? "their question" : text)" }
    /// The line over #general's box once your words @ a kitten.
    static func mentioning(_ kitten: Kitten) -> String { "Straight to \(kitten.name), in a new thread here" }
    static let react = "React"

    /// `name` is the channel's, as the sidebar writes it.
    static func placeholder(_ target: MessageTarget, in channel: ChannelID? = nil, name: String? = nil) -> String {
        switch target {
        case .router: return channel == .shades ? "Message Shades" : "Message #\(name ?? general)"
        case .newThread(let kitten): return "Message #\(name ?? kitten.name)"
        case .thread, .starting: return "Reply..."
        case .question: return "Your answer"
        }
    }
    static func pullRequest(_ pullRequest: ThreadPullRequest) -> String { "PR #\(pullRequest.number) \(pullRequest.state)" }
    static func openLink(to host: String) -> String { "Open a link to \(host)?" }
    static let openLink = "Open"
    static func showPicture(from host: String) -> String { "Show a picture from \(host)?" }
    static let showPicture = "Show"
    static func pictureFrom(_ host: String) -> String { "Picture from \(host)" }
    static let couldntShow = "Couldn't show it"

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
    static let correctionCaption = "Your correction"
    static func correctionSent(to name: String) -> String { "\(name) has it." }
    static let lostTheCorrection = "I spotted a correction, but lost track of whose it was. Mind saying it again?"
    static let earlierMessageCaption = "An earlier message"
    static let earlierMessageFailed = "It didn't get through. Mind saying it again?"
    static func sentTo(_ thread: AgentThread) -> String { sentTo(thread.title) }
    static func sentTo(_ title: String) -> String { "Sent that to \(title)." }
    static let sendTheLink = "It can't see your screen, so send the link or paste the text."
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

    static let inboxCaption = appName
    static let inboxSent = "Sent. Waiting to hear back."

    static let doNotDisturb = "Do Not Disturb"
    static let doNotDisturbOn = "Do Not Disturb is on"
    static let whileAwayTitle = "While you were away"

    static let notifications = "Notifications"
    static let muted = "Muted"
    static let mute = "Mute"

    static func notifyOn(_ device: NotifyDevice) -> String {
        device == .mac ? "On this Mac" : "On your phone"
    }

    static func notifyLevel(_ level: NotifyLevel) -> String {
        switch level {
        case .everything: "Everything"
        case .needsYou: "Only when it needs you"
        case .nothing: "Nothing"
        }
    }

    /// What came in while Do Not Disturb was on, by kind, for the one bubble once it's off.
    static func whileAway(_ missed: [Missed]) -> String {
        var threads = 0, approvals = 0, questions = 0, lines = 0
        for item in missed {
            switch item {
            case .thread: threads += 1
            case .approval: approvals += 1
            case .question: questions += 1
            case .line: lines += 1
            }
        }
        let parts = [
            threads == 0 ? nil : replies(threads),
            approvals == 0 ? nil : approvals == 1 ? "1 approval" : "\(approvals) approvals",
            questions == 0 ? nil : questions == 1 ? "1 question" : "\(questions) questions",
            lines == 0 ? nil : lines == 1 ? "1 note from me" : "\(lines) notes from me",
        ]
        return "\(whileAwayTitle): \(parts.compactMap { $0 }.joined(separator: ", "))."
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

    static func inboxSummary(_ entries: [InboxEntry]) -> String? {
        let decisions = entries.filter(\.needsYou).count
        if decisions > 0 { return decisions == 1 ? "1 needs you" : "\(decisions) need you" }
        let shipped = entries.filter { $0.kind == .shipped }.count
        return shipped > 0 ? "\(shipped) shipped" : nil
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
            return cantReachT3Yet
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
