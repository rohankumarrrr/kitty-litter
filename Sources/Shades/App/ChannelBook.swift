import Foundation
import ShadesCore

enum Speaker: Hashable {
    case you
    /// A `Kitten.id`.
    case kitten(String)
    /// Shades itself, answering in #general, its DM, or its own work.
    case cat
    case someoneElse
}

/// Where something's posted, as in Slack: #general, a channel for each kitten, or your DM with the cat.
enum ChannelID: Hashable {
    /// What you write here goes through the router, and work it starts for you lives here.
    case general
    /// A kitten's own channel, by `Kitten.id`, where its sessions live.
    case kitten(String)
    /// What you've asked the cat itself, from the Ask box, out loud, in #general or here.
    case shades

    static func of(_ kitten: Kitten) -> ChannelID { .kitten(kitten.id) }
}

struct ChannelMessage: Equatable, Identifiable {
    enum Kind: String {
        case ask, reply
    }

    var exchangeID: String
    var kind: Kind
    var speaker: Speaker
    /// `nil` for a reply that hasn't come yet, or never will because of a failure.
    var text: String?
    var at: Date
    /// Only ever from T3's record, never parsed from text.
    var threadID: String
    /// Without the owner's "Name:" prefix.
    var threadTitle: String
    var earlierNotes = 0
    var isStillGoing = false
    var failure: String?

    var id: String { "\(exchangeID):\(kind.rawValue)" }
}

/// One T3 session, the way Slack shows a thread: the message that started it, then every reply, oldest first.
struct ChannelThread: Equatable, Identifiable {
    var id: String
    /// Without the owner's "Name:" prefix. Empty for a new thread T3 hasn't started yet.
    var title: String
    var home: ChannelID
    /// The kitten whose session it is, or `nil` for the cat's own.
    var owner: String?
    /// Your ask, another kitten's ask, or for a session a kitten started itself, its first reply.
    var parent: ChannelMessage
    var replies: [ChannelMessage]
    /// Some older replies were left out, though never the parent.
    var isCut = false

    var latest: ChannelMessage { replies.last ?? parent }
    var messages: [ChannelMessage] { [parent] + replies }
    /// What the reply bar counts: everything after the parent, except a reply that hasn't said anything yet.
    var replyCount: Int { replies.filter { !($0.isStillGoing && $0.text == nil) }.count }
    var isGoing: Bool { latest.isStillGoing }
    /// Who replied, each once, in the order they first did. Slack shows these as small avatars.
    var repliers: [Speaker] {
        var seen: Set<Speaker> = []
        return replies.compactMap { seen.insert($0.speaker).inserted ? $0.speaker : nil }
    }
    var hasYou: Bool { messages.contains { $0.speaker == .you } }
    /// A new topic you started that T3 hasn't made a thread for yet.
    var isStarting: Bool { parent.threadID.isEmpty }
}

/// One thing a channel shows, in the order it was said.
enum ChannelPost: Equatable {
    /// A thread's parent, with its reply bar under it.
    case thread(String)
    /// A message in no thread, such as the cat answering you itself in #general.
    case message(ChannelMessage)
    /// A reply that was also sent here, as Slack's "Also send to #channel" does.
    case alsoSent(ChannelMessage, thread: String)
}

struct Channel: Equatable, Identifiable {
    var id: ChannelID
    var posts: [ChannelPost]
    /// Some older posts were left out.
    var isCut: Bool
}

/// Something said in Messages that T3 doesn't have yet, or never will, like the cat's own answer. It's kept in memory
/// only, and never written to disk.
struct SentMessage: Equatable {
    var channel: ChannelID
    var message: ChannelMessage
    /// A new thread of its own, named by its exchange ID until T3 has one.
    var startsThread = false
    /// A reply that also shows in `channel`, as Slack's "Also send to #channel" does.
    var alsoSent = false
}

/// What's waiting on you right now. It comes from the live thread list and the inbox, never from what was said.
struct Waiting: Equatable {
    var approvals: [ApprovalRequest] = []
    var questions: [AgentQuestion] = []
    /// The kitten each approval, question or report is for, by its ID.
    var owners: [String: String] = [:]
    /// The listed thread each approval or question holds up, by its ID. A subagent's own thread isn't listed.
    var listed: [String: String] = [:]
    var reports: [InboxEntry] = []
    /// Work the cat started outside any kitten, while it's going or just finished. It's what each kitten is on, for Shades.
    var shadesWork: [AgentThread] = []

    var count: Int { approvals.count + questions.count + reports.filter(\.needsYou).count }
}

struct KittenIssues: Equatable {
    var kitten: Kitten
    /// Their titles are without the owner's "Name:" prefix.
    var threads: [AgentThread]
}

/// Everything the Messages window shows, worked out from scratch each time, so nothing gets synced or merged.
struct ChannelBook: Equatable {
    static let keptExchanges = 200

    var statuses: [KittenStatus]
    /// #general, then a channel for each kitten, then your DM with the cat.
    var channels: [Channel]
    var threads: [String: ChannelThread]
    var issues: [KittenIssues]
    var waiting: Waiting
    /// Kittens with a finished run you haven't looked at.
    var unread: Set<String>
    /// Threads with a finished run you haven't looked at.
    var unreadThreads: Set<String>
    /// Every thread T3 listed, by ID, with its title as shown.
    var listed: [String: AgentThread]
    /// The thread each new topic you started became, by the ID of what you sent.
    var started: [String: String]
    /// The router's own threads. Nothing goes straight into one, since the app acts on what the router says.
    var talks: Set<String>
    var isReading: Bool
    var unreadable: Int
    var cantReachT3: Bool

    private struct Gathered {
        var title: String
        var home: ChannelID
        var owner: String?
        var messages: [ChannelMessage]
        var isCut = false
    }

    private struct Placed {
        var position: Date
        var sequence: Int
        var post: ChannelPost
    }

    static func build(
        kittens: [Kitten],
        threads: [AgentThread],
        transcripts: [String: [Exchange]],
        isReading: Bool,
        unreadable: Int,
        cantReachT3: Bool,
        waiting: Waiting = Waiting(),
        sent: [SentMessage] = [],
        isUnread: (AgentThread) -> Bool = { _ in false },
        inGeneral: [String: Date] = [:],
        withShades: Set<String> = [],
        said: (String) -> String? = ChannelBook.said
    ) -> ChannelBook {
        // A talk with the cat is titled with your question, which can start with a kitten's name, so it's kept apart
        // from everything worked out about kittens.
        let talkThreads = threads.filter { withShades.contains($0.id) }
        // A subagent's question holds up the thread above it, even if that one's turn has ended.
        let threads = threads.filter { !withShades.contains($0.id) }.map { thread -> AgentThread in
            guard thread.pendingQuestion != nil else { return thread }
            var waiting = thread
            waiting.status = .waitingForAnswer
            return waiting
        }
        let threadsByID = Dictionary(threads.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Each thread's owner is worked out once, since everything below asks.
        let lookup = KittenBoard.Owners(kittens)
        let owners = Dictionary(threads.map { ($0.id, lookup.of($0)) }, uniquingKeysWith: { first, _ in first })
        let ownerOf = { (thread: AgentThread) in owners[thread.id] ?? nil }
        let statuses = KittenBoard.statuses(kittens: kittens, threads: threads)
        let channelIDs = [ChannelID.general] + statuses.map { .of($0.kitten) } + [.shades]

        var gathered: [String: Gathered] = [:]
        var order: [String] = []
        var leftOut: Set<String> = []
        func gather(_ id: String, _ thread: Gathered) {
            if gathered[id] == nil { order.append(id) }
            gathered[id] = thread
        }
        for thread in talkThreads where !thread.isLiveTest {
            guard let exchanges = transcripts[thread.id] else { continue }
            gather(thread.id, Gathered(title: thread.title, home: .shades, messages: talk(in: thread, exchanges, said: said), isCut: exchanges.count >= keptExchanges))
        }
        for thread in threads {
            let owner = ownerOf(thread)
            // The cat's own work only shows if Messages passed your words to it, since anything else can hold your screen.
            guard owner != nil || inGeneral[thread.id] != nil else { continue }
            guard let exchanges = transcripts[thread.id] else {
                if let owner { leftOut.insert(owner.id) }
                continue
            }
            let replier = owner.map { Speaker.kitten($0.id) } ?? .cat
            let title = owner.map { Self.title(of: thread, owner: $0) } ?? thread.title
            var messages: [ChannelMessage] = []
            for (index, exchange) in exchanges.enumerated() {
                let asker = speaker(of: exchange.asker, replier: replier, threads: threadsByID, owner: ownerOf, inGeneral: inGeneral)
                // Waiting on you isn't working, so what it last said reads as said.
                let isStillGoing = thread.status.isActive && !KittenBoard.needsYou(thread) && index == exchanges.count - 1
                messages += self.messages(of: exchange, in: thread.id, title: title, asker: asker, replier: replier, isStillGoing: isStillGoing)
            }
            guard !messages.isEmpty else { continue }
            // Started from #general, it lives there, wherever it's passed after that. Otherwise it's its kitten's.
            let home: ChannelID = inGeneral[thread.id] != nil || owner == nil ? .general : .of(owner!)
            gather(thread.id, Gathered(title: title, home: home, owner: owner?.id, messages: messages, isCut: exchanges.count >= keptExchanges))
        }

        // What you just sent waits where you sent it until T3 has it. A reply also sent to a channel shows there too.
        var placed: [ChannelID: [Placed]] = [:]
        for (sequence, sent) in sent.enumerated() {
            var message = sent.message
            let post = { (post: ChannelPost) in placed[sent.channel, default: []].append(Placed(position: message.at, sequence: sequence, post: post)) }
            if message.threadID.isEmpty {
                guard sent.startsThread else {
                    post(.message(message))
                    continue
                }
                let owner: String? = if case .kitten(let id) = sent.channel { id } else { nil }
                gather(message.exchangeID, Gathered(title: "", home: sent.channel, owner: owner, messages: [message]))
                continue
            }
            guard var thread = gathered[message.threadID] else {
                // T3 hasn't got the thread yet, or never lists it, such as a talk that only passed something on.
                if sent.alsoSent {
                    post(.message(message))
                    continue
                }
                let listed = threadsByID[message.threadID]
                let owner = listed.flatMap(ownerOf)
                let home: ChannelID = inGeneral[message.threadID] != nil ? .general : owner.map(ChannelID.of) ?? sent.channel
                if let listed { message.threadTitle = owner.map { title(of: listed, owner: $0) } ?? listed.title }
                gather(message.threadID, Gathered(title: message.threadTitle, home: home, owner: owner?.id, messages: [message]))
                continue
            }
            if let echo = thread.messages.first(where: { isEcho(of: message, $0) }) {
                if sent.alsoSent, echo.id != thread.messages.first?.id { post(.alsoSent(echo, thread: message.threadID)) }
                continue
            }
            message.threadTitle = thread.title
            // Your words that start a thread come before anything said in it.
            if let first = thread.messages.first, message.at < first.at {
                thread.messages.insert(message, at: 0)
            } else {
                thread.messages.append(message)
                if sent.alsoSent { post(.alsoSent(message, thread: message.threadID)) }
            }
            gathered[message.threadID] = thread
        }

        var built: [String: ChannelThread] = [:]
        // Threads said at the same moment keep the order T3 listed them in, ahead of what you sent.
        for (index, id) in order.enumerated() {
            guard let thread = gathered[id], let parent = thread.messages.first else { continue }
            built[id] = ChannelThread(
                id: id,
                title: thread.title,
                home: channelIDs.contains(thread.home) ? thread.home : .general,
                owner: thread.owner,
                parent: parent,
                replies: Array(thread.messages.dropFirst()),
                isCut: thread.isCut
            )
            placed[built[id]!.home, default: []].append(Placed(position: parent.at, sequence: index - order.count, post: .thread(id)))
        }

        // Threads with an owner and nothing read are too old to read, or couldn't be read, so don't say you've never talked.
        let channels = channelIDs.map { id -> Channel in
            let leavesOut: Bool = if case .kitten(let kitten) = id { !isReading && leftOut.contains(kitten) } else { false }
            return channel(id, placed[id] ?? [], leavesOutThreads: leavesOut)
        }
        let issues = statuses.compactMap { status -> KittenIssues? in
            let mine = owned(by: status.kitten, in: threads, owner: ownerOf)
            let open = mine.filter(isOpen).sorted { (urgency($0), $1.updatedAt, $0.id) < (urgency($1), $0.updatedAt, $1.id) }
            return status.state == .notSetUp && open.isEmpty ? nil : KittenIssues(kitten: status.kitten, threads: open)
        }
        var waiting = waiting
        for entry in waiting.reports {
            waiting.owners[entry.id] = threadsByID[entry.threadID].flatMap(ownerOf)?.id
        }
        let unreadListed = threads.filter(isUnread)
        var named: [String: AgentThread] = [:]
        for thread in talkThreads where named[thread.id] == nil { named[thread.id] = thread }
        for thread in threads where named[thread.id] == nil {
            named[thread.id] = thread
            if let owner = ownerOf(thread) { named[thread.id]?.title = title(of: thread, owner: owner) }
        }
        let started = Dictionary(sent.compactMap { $0.startsThread && !$0.message.threadID.isEmpty ? ($0.message.exchangeID, $0.message.threadID) : nil }, uniquingKeysWith: { first, _ in first })
        return ChannelBook(
            statuses: statuses,
            channels: channels,
            threads: built,
            issues: issues,
            waiting: waiting,
            unread: Set(unreadListed.compactMap { ownerOf($0)?.id }),
            unreadThreads: Set(unreadListed.map(\.id)).intersection(built.keys),
            listed: named,
            started: started,
            talks: Set(talkThreads.map(\.id)),
            isReading: isReading,
            unreadable: unreadable,
            cantReachT3: cantReachT3
        )
    }

    private static func speaker(of asker: Exchange.Asker, replier: Speaker, threads: [String: AgentThread], owner: (AgentThread) -> Kitten?, inGeneral: [String: Date]) -> Speaker {
        switch asker {
        case .you:
            return .you
        // A kitten's schedule is its own routine, so its run is its own work, and what it reports goes in its channel.
        case .schedule:
            return replier
        case .agent(let threadID):
            guard let threadID, let asking = threads[threadID] else { return .someoneElse }
            if let kitten = owner(asking) { return .kitten(kitten.id) }
            // Work the cat started for you in #general, passing it on.
            return inGeneral[threadID] != nil ? .cat : .someoneElse
        }
    }

    private static func messages(of exchange: Exchange, in threadID: String, title: String, asker: Speaker, replier: Speaker, isStillGoing: Bool) -> [ChannelMessage] {
        let talkingToItself = asker == replier
        var messages: [ChannelMessage] = []
        if let ask = exchange.ask, !talkingToItself {
            messages.append(ChannelMessage(exchangeID: exchange.id, kind: .ask, speaker: asker, text: ask, at: exchange.askedAt, threadID: threadID, threadTitle: title))
        }
        if exchange.reply != nil || exchange.failure != nil || (isStillGoing && !talkingToItself) {
            messages.append(ChannelMessage(
                exchangeID: exchange.id,
                kind: .reply,
                speaker: replier,
                text: exchange.reply,
                at: exchange.repliedAt ?? exchange.askedAt,
                threadID: threadID,
                threadTitle: title,
                earlierNotes: exchange.earlierNotes,
                isStillGoing: isStillGoing,
                failure: exchange.failure
            ))
        }
        return messages
    }

    private static func channel(_ id: ChannelID, _ placed: [Placed], leavesOutThreads: Bool = false) -> Channel {
        let ordered = placed.sorted { a, b in
            if a.position != b.position { return a.position < b.position }
            return a.sequence < b.sequence
        }
        return Channel(id: id, posts: ordered.suffix(keptExchanges).map(\.post), isCut: leavesOutThreads || ordered.count > keptExchanges)
    }

    /// A conversation with the cat: what you asked, and what it said or did about it, since the router answers in
    /// lines the app acts on. Only your words come out of what was asked, never the screen that went with them.
    private static func talk(in thread: AgentThread, _ exchanges: [Exchange], said: (String) -> String?) -> [ChannelMessage] {
        exchanges.enumerated().flatMap { index, exchange -> [ChannelMessage] in
            let isStillGoing = thread.status.isActive && index == exchanges.count - 1
            var messages: [ChannelMessage] = []
            if exchange.asker == .you, let ask = exchange.ask {
                messages.append(ChannelMessage(exchangeID: exchange.id, kind: .ask, speaker: .you, text: ask, at: exchange.askedAt, threadID: thread.id, threadTitle: thread.title))
            }
            // A reply still being written is read the way the bubble reads it, so a half-written marker never shows.
            let reply = exchange.reply.flatMap { isStillGoing ? saidSoFar($0) : said($0) }
            if reply != nil || exchange.failure != nil || isStillGoing {
                messages.append(ChannelMessage(
                    exchangeID: exchange.id,
                    kind: .reply,
                    speaker: .cat,
                    text: reply,
                    at: exchange.repliedAt ?? exchange.askedAt,
                    threadID: thread.id,
                    threadTitle: thread.title,
                    isStillGoing: isStillGoing && reply == nil,
                    failure: exchange.failure
                ))
            }
            return messages
        }
    }

    static func saidSoFar(_ reply: String) -> String? {
        var holdback = ReplyHoldback()
        return holdback.add(withoutPromptBlocks(reply)).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// A reply that quotes what the router was given can't bring along its lists of sessions and kittens, or the screen.
    private static func withoutPromptBlocks(_ reply: String) -> String {
        Prompts.withoutBlocks(named: "screen|sessions|kittens", in: reply)
    }

    /// What the router's reply came to, in words. `nil` for nothing worth reading.
    static func said(_ reply: String) -> String? {
        let reply = withoutPromptBlocks(reply)
        let corrected = !Prompts.corrections(in: reply).owners.isEmpty
        switch ReplyHoldback().finish(fullText: reply) {
        case .answer(let text, _): return text.isEmpty ? (corrected ? CatWords.passedOnCorrection : nil) : text
        case .rewrite(let text): return text
        case .handoff(let task): return CatWords.handedOff(task)
        case .route: return CatWords.passedOnToSession
        case .kitten: return CatWords.passedOnToKitten
        }
    }

    /// T3 has it once the same one says the same thing there, since a minute before it was shown. That's you, or the
    /// cat answering you in its DM, where its thread is read too.
    private static func isEcho(of message: ChannelMessage, _ said: ChannelMessage) -> Bool {
        guard message.speaker == .you || message.speaker == .cat else { return false }
        return said.speaker == message.speaker && said.text == message.text && said.at >= message.at.addingTimeInterval(-60)
    }

    private static func owned(by kitten: Kitten, in threads: [AgentThread], owner: (AgentThread) -> Kitten?) -> [AgentThread] {
        threads
            .filter { owner($0) == kitten }
            .map { thread in
                var thread = thread
                thread.title = title(of: thread, owner: kitten)
                return thread
            }
    }

    /// Today an issue is an open thread: still going, or stopped short of done and not settled yet. One that
    /// finished is in its channel, the way a settled one is in T3, so it doesn't sit there for you to keep looking at.
    private static func isOpen(_ thread: AgentThread) -> Bool {
        thread.status.isActive || KittenBoard.needsYou(thread) || (!thread.isSettled && thread.status != .completed)
    }

    private static func urgency(_ thread: AgentThread) -> Int {
        KittenBoard.needsYou(thread) ? 0 : thread.status.isActive ? 1 : 2
    }

    private static func title(of thread: AgentThread, owner: Kitten) -> String {
        title(of: thread.title, owner: owner)
    }

    /// Without the owner's "Name:" prefix.
    static func title(of title: String, owner: Kitten) -> String {
        let prefix = "\(owner.name):"
        guard title.hasPrefix(prefix) else { return title }
        return title.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
    }

    /// A kitten's name the way Slack names a channel: lowercase, with hyphens for spaces.
    static func slug(_ name: String) -> String {
        name.lowercased()
            .split { !($0.isLetter || $0.isNumber || $0 == "_") }
            .joined(separator: "-")
    }
}

extension ChannelBook {
    var issueCount: Int { issues.reduce(0) { $0 + $1.threads.count } }

    func channel(_ id: ChannelID) -> Channel? {
        channels.first { $0.id == id }
    }

    func kitten(_ id: String) -> Kitten? {
        statuses.first { $0.id == id }?.kitten
    }

    /// The thread an approval or question is shown in: the listed one it holds up.
    func thread(holding request: String, else threadID: String) -> String {
        waiting.listed[request] ?? threadID
    }

    func kitten(of requestID: String) -> Kitten? {
        waiting.owners[requestID].flatMap { kitten($0) }
    }

    /// The kitten whose channel this is, if it's one you can write in.
    func writableKitten(in id: ChannelID) -> Kitten? {
        guard case .kitten(let kitten) = id else { return nil }
        return statuses.first { $0.id == kitten && $0.state != .notSetUp }?.kitten
    }

    /// A thread's title as shown, from T3's list or, for one too new to be listed, from what's been said in it.
    func title(ofThread id: String) -> String {
        if let title = listed[id]?.title { return title }
        guard let thread = threads[id] else { return "" }
        return thread.title.isEmpty ? ChannelRows.firstWords(of: thread.parent.text ?? "") : thread.title
    }

    /// Whether anything is known of this thread, so there's somewhere for words to go.
    func knows(thread id: String) -> Bool {
        listed[id] != nil || threads[id].map { !$0.isStarting } == true
    }

    /// Where a thread lives: #general if it was started there, or its kitten's channel.
    func home(ofThread id: String) -> ChannelID? {
        if let thread = threads[id] { return thread.home }
        if talks.contains(id) { return .shades }
        guard let listed = listed[id] else { return nil }
        let owner = KittenBoard.owner(of: listed, among: statuses.map(\.kitten))
        return owner.map(ChannelID.of) ?? .general
    }

    /// Where an approval, question or report is answered: its kitten's channel, or #general for the cat's own work.
    func home(of kitten: Kitten?) -> ChannelID {
        kitten.map(ChannelID.of) ?? .general
    }

    func status(of speaker: Speaker) -> KittenStatus? {
        statuses.first { .kitten($0.id) == speaker }
    }

    func name(of speaker: Speaker) -> String {
        switch speaker {
        case .you: return CatWords.you
        case .kitten: return status(of: speaker)?.kitten.name ?? CatWords.someoneElse
        case .cat: return CatWords.shades
        case .someoneElse: return CatWords.someoneElse
        }
    }

    /// A channel's name in the sidebar: `general`, a kitten's as Slack would write it, or the cat's.
    func name(of id: ChannelID) -> String {
        switch id {
        case .general: return CatWords.general
        case .kitten(let kitten): return self.kitten(kitten).map { ChannelBook.slug($0.name) } ?? kitten
        case .shades: return CatWords.shades
        }
    }

    /// With the `#` a channel has, and the DM without.
    func title(of id: ChannelID) -> String {
        id == .shades ? name(of: id) : "#\(name(of: id))"
    }

    /// What a channel's badge counts, as Slack does mentions: that kitten's approvals, questions and decisions.
    func badge(of id: ChannelID) -> Int {
        guard case .kitten(let kitten) = id else { return 0 }
        let mine = { (request: String) in waiting.owners[request] == kitten }
        return waiting.approvals.filter { mine($0.id) }.count + waiting.questions.filter { mine($0.id) }.count
            + waiting.reports.filter { $0.needsYou && mine($0.id) }.count
    }

    /// A channel's bold: a kitten's with a finished run you haven't seen, or #general with an unread thread of its own.
    func isUnread(_ id: ChannelID) -> Bool {
        switch id {
        case .kitten(let kitten): return unread.contains(kitten)
        case .general: return unreadThreads.contains { threads[$0]?.home == .general }
        case .shades: return false
        }
    }

    /// Every thread you've written in, unread ones first, then the newest. Talks with the cat stay in its DM.
    var yours: [ChannelThread] {
        threads.values
            .filter { $0.hasYou && $0.home != .shades }
            .sorted { a, b in
                let unreadA = unreadThreads.contains(a.id), unreadB = unreadThreads.contains(b.id)
                if unreadA != unreadB { return unreadA }
                if a.latest.at != b.latest.at { return a.latest.at > b.latest.at }
                return a.id < b.id
            }
    }

    /// The threads a channel shows, in the order it shows them.
    func threads(in id: ChannelID) -> [String] {
        channel(id)?.posts.compactMap { if case .thread(let thread) = $0 { thread } else { nil } } ?? []
    }
}
