import Foundation
import ShadesCore

enum Speaker: Hashable {
    case you
    /// A `Kitten.id`.
    case kitten(String)
    /// Shades itself, answering in Everyone.
    case cat
    case someoneElse
}

/// The set of who's in it, so A→B and B→A are the same channel with nothing to sort.
struct ChannelID: Hashable {
    let members: Set<Speaker>

    /// `nil` for the same speaker twice: talking to yourself isn't a channel.
    init?(_ a: Speaker, _ b: Speaker) {
        guard a != b else { return nil }
        members = [a, b]
    }

    private init(members: Set<Speaker>) {
        self.members = members
    }

    static func direct(_ kitten: Kitten) -> ChannelID {
        ChannelID(members: [.you, .kitten(kitten.id)])
    }

    /// The group chat: every DM at once, and what you say there goes through the router.
    static let everyone = ChannelID(members: [.you])
    /// What you've said to the cat itself, from the Ask box, out loud, in Everyone or here. What you say here goes
    /// through the router, as it does in Everyone, and the cat answers here.
    static let shades = ChannelID(members: [.you, .cat])
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

struct Channel: Equatable, Identifiable {
    var id: ChannelID
    var messages: [ChannelMessage]
    /// Some older messages were left out.
    var isCut: Bool
}

/// Something said in Messages that T3 doesn't have yet, or never will, like the cat's own answer.
/// It's kept in memory only while the window's open.
struct SentMessage: Equatable {
    var channel: ChannelID
    var message: ChannelMessage
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
    /// Every other thread of theirs, newest first, for when you go looking.
    var done: [AgentThread] = []
}

/// Everything the Channels window shows, worked out from scratch each time, so nothing gets synced or merged.
struct ChannelBook: Equatable {
    static let keptExchanges = 200

    var directs: [Channel]
    var statuses: [KittenStatus]
    var between: [Channel]
    var issues: [KittenIssues]
    var everyone: Channel
    var shades: Channel
    var waiting: Waiting
    /// Kittens with a finished run you haven't looked at.
    var unread: Set<String>
    /// Every thread T3 listed, by ID, with its title as shown.
    var threads: [String: AgentThread]
    /// The thread each new topic you started became, by the ID of what you sent.
    var started: [String: String]
    /// Threads only ever heard between kittens, which aren't yours to carry on.
    var elsewhere: Set<String>
    /// The router's own threads. Nothing goes straight into one, since the app acts on what the router says.
    var talks: Set<String>
    var isReading: Bool
    var unreadable: Int
    var cantReachT3: Bool

    /// The messages of one exchange, which always stay together.
    private struct Placed {
        var position: Date
        var sequence: Int
        var messages: [ChannelMessage]
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
        inEveryone: [String: Date] = [:],
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
        var placed: [ChannelID: [Placed]] = [:]
        var leftOut: Set<String> = []
        var heardIn: [String: Set<ChannelID>] = [:]
        for thread in talkThreads where !thread.isLiveTest {
            if let exchanges = transcripts[thread.id] { placed[.shades, default: []] += talk(in: thread, exchanges, said: said) }
        }
        for thread in threads {
            guard let owner = ownerOf(thread) else {
                if let since = inEveryone[thread.id], let exchanges = transcripts[thread.id] {
                    placed[.everyone, default: []] += answers(in: thread, exchanges, since: since)
                }
                continue
            }
            guard let exchanges = transcripts[thread.id] else {
                leftOut.insert(owner.id)
                continue
            }
            // Within a thread, a later ask never sits above an earlier one.
            var latest = Date.distantPast
            for (index, exchange) in exchanges.enumerated() {
                let speaker = speaker(of: exchange.asker, threads: threadsByID, owner: ownerOf)
                // Waiting on you isn't working, so what it last said reads as said, and sits at the bottom where you'll see it.
                let isStillGoing = thread.status.isActive && !KittenBoard.needsYou(thread) && index == exchanges.count - 1
                let messages = messages(of: exchange, in: thread, owner: owner, speaker: speaker, isStillGoing: isStillGoing)
                guard !messages.isEmpty else { continue }
                // A kitten talking to itself has no channel of its own, so its reports go in its DM.
                let channel = ChannelID(speaker, .kitten(owner.id)) ?? .direct(owner)
                // It sits where it last finished, and doesn't move while it's going.
                latest = max(latest, isStillGoing ? exchange.askedAt : exchange.repliedAt ?? exchange.askedAt)
                placed[channel, default: []].append(Placed(position: latest, sequence: index, messages: messages))
                heardIn[thread.id, default: []].insert(channel)
                // Work from Everyone that was passed on to a kitten answers there as that kitten, not only between kittens.
                if channel != .direct(owner), let since = inEveryone[thread.id], exchange.askedAt >= since.addingTimeInterval(-60) {
                    let replies = messages.filter { $0.kind == .reply }
                    if !replies.isEmpty { placed[.everyone, default: []].append(Placed(position: latest, sequence: index, messages: replies)) }
                }
            }
        }

        // What you just sent waits where you sent it until T3 has it.
        let heard = placed
        for (order, sent) in sent.enumerated() {
            // Everyone is every DM, and not what you said to the cat, which is in the router's own threads.
            let there = sent.channel == .everyone ? Array(heard.filter { $0.key != .shades }.values.joined()) : heard[sent.channel] ?? []
            guard !isEchoed(sent.message, in: there) else { continue }
            placed[sent.channel, default: []].append(Placed(position: sent.message.at, sequence: order, messages: [sent.message]))
        }

        let statuses = KittenBoard.statuses(kittens: kittens, threads: threads)
        // Threads with an owner and nothing read are too old to read, or couldn't be read, so don't say you've never talked.
        let directs = statuses.map { status in
            channel(.direct(status.kitten), placed[.direct(status.kitten)] ?? [], leavesOutThreads: !isReading && leftOut.contains(status.kitten.id))
        }
        let directIDs = Set(directs.map(\.id))
        let between = placed
            .filter { !directIDs.contains($0.key) && $0.key != .everyone && $0.key != .shades }
            .map { channel($0.key, $0.value) }
            .sorted { (latest($0), latestID($0)) > (latest($1), latestID($1)) }
        let issues = statuses.compactMap { status -> KittenIssues? in
            let mine = owned(by: status.kitten, in: threads, owner: ownerOf)
            let open = mine.filter(isOpen).sorted { (urgency($0), $1.updatedAt, $0.id) < (urgency($1), $0.updatedAt, $1.id) }
            let done = mine.filter { !isOpen($0) }.sorted { ($1.updatedAt, $0.id) < ($0.updatedAt, $1.id) }
            return status.state == .notSetUp && open.isEmpty ? nil : KittenIssues(kitten: status.kitten, threads: open, done: done)
        }
        var waiting = waiting
        for entry in waiting.reports {
            waiting.owners[entry.id] = threadsByID[entry.threadID].flatMap(ownerOf)?.id
        }
        let everyone = channel(.everyone, directIDs.flatMap { placed[$0] ?? [] } + (placed[.everyone] ?? []))
        let unread = Set(threads.filter(isUnread).compactMap { ownerOf($0)?.id })
        var named: [String: AgentThread] = [:]
        var elsewhere: Set<String> = []
        for thread in talkThreads where named[thread.id] == nil { named[thread.id] = thread }
        for thread in threads where named[thread.id] == nil {
            named[thread.id] = thread
            guard let owner = ownerOf(thread) else { continue }
            named[thread.id]?.title = title(of: thread, owner: owner)
            if let heard = heardIn[thread.id], !heard.contains(.direct(owner)) { elsewhere.insert(thread.id) }
        }
        let started = Dictionary(sent.compactMap { $0.message.threadID.isEmpty ? nil : ($0.message.exchangeID, $0.message.threadID) }, uniquingKeysWith: { first, _ in first })
        return ChannelBook(
            directs: directs,
            statuses: statuses,
            between: between,
            issues: issues,
            everyone: everyone,
            shades: channel(.shades, placed[.shades] ?? []),
            waiting: waiting,
            unread: unread,
            threads: named,
            started: started,
            elsewhere: elsewhere,
            talks: Set(talkThreads.map(\.id)),
            isReading: isReading,
            unreadable: unreadable,
            cantReachT3: cantReachT3
        )
    }

    private static func speaker(of asker: Exchange.Asker, threads: [String: AgentThread], owner: (AgentThread) -> Kitten?) -> Speaker {
        switch asker {
        case .you:
            return .you
        case .agent(let threadID):
            return threadID.flatMap { threads[$0] }.flatMap(owner).map { .kitten($0.id) } ?? .someoneElse
        }
    }

    private static func messages(of exchange: Exchange, in thread: AgentThread, owner: Kitten, speaker: Speaker, isStillGoing: Bool) -> [ChannelMessage] {
        let talkingToItself = speaker == .kitten(owner.id)
        let title = title(of: thread, owner: owner)
        var messages: [ChannelMessage] = []
        if let ask = exchange.ask, !talkingToItself {
            messages.append(ChannelMessage(exchangeID: exchange.id, kind: .ask, speaker: speaker, text: ask, at: exchange.askedAt, threadID: thread.id, threadTitle: title))
        }
        if exchange.reply != nil || exchange.failure != nil || (isStillGoing && !talkingToItself) {
            messages.append(ChannelMessage(
                exchangeID: exchange.id,
                kind: .reply,
                speaker: .kitten(owner.id),
                text: exchange.reply,
                at: exchange.repliedAt ?? exchange.askedAt,
                threadID: thread.id,
                threadTitle: title,
                earlierNotes: exchange.earlierNotes,
                isStillGoing: isStillGoing,
                failure: exchange.failure
            ))
        }
        return messages
    }

    private static func channel(_ id: ChannelID, _ placed: [Placed], leavesOutThreads: Bool = false) -> Channel {
        // A message's ID is made each time it's asked for, so it's only asked for when nothing else tells them apart.
        let ordered = placed.sorted { a, b in
            if a.position != b.position { return a.position < b.position }
            if a.sequence != b.sequence { return a.sequence < b.sequence }
            return a.messages[0].id < b.messages[0].id
        }
        return Channel(id: id, messages: ordered.suffix(keptExchanges).flatMap(\.messages), isCut: leavesOutThreads || ordered.count > keptExchanges)
    }

    /// Work the router took on from Everyone outside any kitten. Only its answers, as Shades, since what you said is already there.
    private static func answers(in thread: AgentThread, _ exchanges: [Exchange], since: Date) -> [Placed] {
        exchanges.enumerated().compactMap { index, exchange in
            guard exchange.askedAt >= since.addingTimeInterval(-60) else { return nil }
            let isStillGoing = thread.status.isActive && !KittenBoard.needsYou(thread) && index == exchanges.count - 1
            guard exchange.reply != nil || exchange.failure != nil || isStillGoing else { return nil }
            let at = exchange.repliedAt ?? exchange.askedAt
            let message = ChannelMessage(
                exchangeID: exchange.id,
                kind: .reply,
                speaker: .cat,
                text: exchange.reply,
                at: at,
                threadID: thread.id,
                threadTitle: thread.title,
                earlierNotes: exchange.earlierNotes,
                isStillGoing: isStillGoing,
                failure: exchange.failure
            )
            return Placed(position: isStillGoing ? exchange.askedAt : at, sequence: index, messages: [message])
        }
    }

    /// A conversation with the cat: what you asked, and what it said or did about it, since the router answers in
    /// lines the app acts on. Only your words come out of what was asked, never the screen that went with them.
    private static func talk(in thread: AgentThread, _ exchanges: [Exchange], said: (String) -> String?) -> [Placed] {
        // As in a kitten's thread, a later ask never sits above an earlier one.
        var latest = Date.distantPast
        return exchanges.enumerated().compactMap { index, exchange in
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
            guard !messages.isEmpty else { return nil }
            latest = max(latest, isStillGoing ? exchange.askedAt : exchange.repliedAt ?? exchange.askedAt)
            return Placed(position: latest, sequence: index, messages: messages)
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

    /// T3 has it once the same one says the same thing there, since a minute before it was shown. That's you asking,
    /// or the cat answering you in Shades, where its thread is read too.
    private static func isEchoed(_ message: ChannelMessage, in placed: [Placed]) -> Bool {
        guard message.speaker == .you || message.speaker == .cat else { return false }
        return placed.lazy.flatMap(\.messages).contains { said in
            said.speaker == message.speaker && said.text == message.text && said.at >= message.at.addingTimeInterval(-60)
        }
    }

    private static func latest(_ channel: Channel) -> Date { channel.messages.last?.at ?? .distantPast }
    private static func latestID(_ channel: Channel) -> String { channel.messages.last?.id ?? "" }

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
    /// finished goes to Done, the way a settled one does in T3, so it doesn't sit there for you to keep looking at.
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
}

extension ChannelBook {
    var issueCount: Int { issues.reduce(0) { $0 + $1.threads.count } }

    func channel(_ id: ChannelID) -> Channel? {
        if id == .everyone { return everyone }
        if id == .shades { return shades }
        return directs.first { $0.id == id } ?? between.first { $0.id == id }
    }

    /// The thread an approval or question is shown in: the listed one it holds up.
    func thread(holding request: String, else threadID: String) -> String {
        waiting.listed[request] ?? threadID
    }

    func kitten(of requestID: String) -> Kitten? {
        waiting.owners[requestID].flatMap { owner in statuses.first { $0.id == owner }?.kitten }
    }

    /// The kitten a DM is with, if it's one you can write in.
    func writableKitten(in id: ChannelID) -> Kitten? {
        statuses.first { id == .direct($0.kitten) && $0.state != .notSetUp }?.kitten
    }

    /// A thread's title as shown, from T3's list or, for one too new to be listed, from what's been said in it.
    func title(ofThread id: String, in channel: ChannelID) -> String {
        threads[id]?.title ?? self.channel(channel)?.messages.first { $0.threadID == id && !$0.threadTitle.isEmpty }?.threadTitle ?? ""
    }

    /// Whether anything is known of this thread, so there's somewhere for words to go.
    func knows(thread id: String, in channel: ChannelID) -> Bool {
        threads[id] != nil || self.channel(channel)?.messages.contains { $0.threadID == id } == true
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

    func others(in id: ChannelID) -> [Speaker] {
        let kittens = statuses.map { Speaker.kitten($0.id) }.filter(id.members.contains)
        return kittens + id.members.subtracting(kittens).subtracting([.you])
    }

    func title(of id: ChannelID) -> String {
        if id == .everyone { return CatWords.everyone }
        return others(in: id)
            .map { $0 == .someoneElse ? CatWords.someoneElse.lowercased() : name(of: $0) }
            .joined(separator: ", ")
    }
}
