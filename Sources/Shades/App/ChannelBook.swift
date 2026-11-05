import Foundation
import ShadesCore

enum Speaker: Hashable {
    case you
    /// A `Kitten.id`.
    case kitten(String)
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

struct KittenIssues: Equatable {
    var kitten: Kitten
    /// Their titles are without the owner's "Name:" prefix.
    var threads: [AgentThread]
}

/// Everything the Channels window shows, worked out from scratch each time, so nothing gets synced or merged.
struct ChannelBook: Equatable {
    private static let keptExchanges = 200

    var directs: [Channel]
    var statuses: [KittenStatus]
    var between: [Channel]
    var issues: [KittenIssues]
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
        cantReachT3: Bool
    ) -> ChannelBook {
        // A subagent's question holds up the thread above it, even if that one's turn has ended.
        let threads = threads.map { thread -> AgentThread in
            guard thread.pendingQuestion != nil else { return thread }
            var waiting = thread
            waiting.status = .waitingForAnswer
            return waiting
        }
        let threadsByID = Dictionary(threads.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var placed: [ChannelID: [Placed]] = [:]
        var leftOut: Set<String> = []
        for thread in threads {
            guard let owner = KittenBoard.owner(of: thread, among: kittens) else { continue }
            guard let exchanges = transcripts[thread.id] else {
                leftOut.insert(owner.id)
                continue
            }
            // Within a thread, a later ask never sits above an earlier one.
            var latest = Date.distantPast
            for (index, exchange) in exchanges.enumerated() {
                let speaker = speaker(of: exchange.asker, among: kittens, threads: threadsByID)
                // Waiting on you isn't working, so what it last said reads as said, and sits at the bottom where you'll see it.
                let isStillGoing = thread.status.isActive && !KittenBoard.needsYou(thread) && index == exchanges.count - 1
                let messages = messages(of: exchange, in: thread, owner: owner, speaker: speaker, isStillGoing: isStillGoing)
                guard !messages.isEmpty else { continue }
                // A kitten talking to itself has no channel of its own, so its reports go in its DM.
                let channel = ChannelID(speaker, .kitten(owner.id)) ?? .direct(owner)
                // It sits where it last finished, and doesn't move while it's going.
                latest = max(latest, isStillGoing ? exchange.askedAt : exchange.repliedAt ?? exchange.askedAt)
                placed[channel, default: []].append(Placed(position: latest, sequence: index, messages: messages))
            }
        }

        let statuses = KittenBoard.statuses(kittens: kittens, threads: threads)
        // Threads with an owner and nothing read are too old to read, or couldn't be read, so don't say you've never talked.
        let directs = statuses.map { status in
            channel(.direct(status.kitten), placed[.direct(status.kitten)] ?? [], leavesOutThreads: !isReading && leftOut.contains(status.kitten.id))
        }
        let directIDs = Set(directs.map(\.id))
        let between = placed
            .filter { !directIDs.contains($0.key) }
            .map { channel($0.key, $0.value) }
            .sorted { (latest($0), latestID($0)) > (latest($1), latestID($1)) }
        let issues = statuses.compactMap { status -> KittenIssues? in
            let open = openThreads(of: status.kitten, among: kittens, in: threads)
            return status.state == .notSetUp && open.isEmpty ? nil : KittenIssues(kitten: status.kitten, threads: open)
        }
        return ChannelBook(
            directs: directs,
            statuses: statuses,
            between: between,
            issues: issues,
            isReading: isReading,
            unreadable: unreadable,
            cantReachT3: cantReachT3
        )
    }

    private static func speaker(of asker: Exchange.Asker, among kittens: [Kitten], threads: [String: AgentThread]) -> Speaker {
        switch asker {
        case .you:
            return .you
        case .agent(let threadID):
            return threadID.flatMap { threads[$0] }.flatMap { KittenBoard.owner(of: $0, among: kittens) }.map { .kitten($0.id) } ?? .someoneElse
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
        let ordered = placed.sorted { ($0.position, $0.sequence, $0.messages[0].id) < ($1.position, $1.sequence, $1.messages[0].id) }
        return Channel(id: id, messages: ordered.suffix(keptExchanges).flatMap(\.messages), isCut: leavesOutThreads || ordered.count > keptExchanges)
    }

    private static func latest(_ channel: Channel) -> Date { channel.messages.last?.at ?? .distantPast }
    private static func latestID(_ channel: Channel) -> String { channel.messages.last?.id ?? "" }

    /// Today an issue is an open thread. A finished one that isn't settled stays, because
    /// that's a pull request waiting on "ship it". What needs you comes first, then what's working.
    private static func openThreads(of kitten: Kitten, among kittens: [Kitten], in threads: [AgentThread]) -> [AgentThread] {
        threads
            .filter { KittenBoard.owner(of: $0, among: kittens) == kitten && (!$0.isSettled || $0.status.isActive) }
            .map { thread in
                var thread = thread
                thread.title = title(of: thread, owner: kitten)
                return thread
            }
            .sorted { (urgency($0), $1.updatedAt, $0.id) < (urgency($1), $0.updatedAt, $1.id) }
    }

    private static func urgency(_ thread: AgentThread) -> Int {
        KittenBoard.needsYou(thread) ? 0 : thread.status.isActive ? 1 : 2
    }

    private static func title(of thread: AgentThread, owner: Kitten) -> String {
        let prefix = "\(owner.name):"
        guard thread.title.hasPrefix(prefix) else { return thread.title }
        return thread.title.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
    }
}

extension ChannelBook {
    var issueCount: Int { issues.reduce(0) { $0 + $1.threads.count } }

    func channel(_ id: ChannelID) -> Channel? {
        directs.first { $0.id == id } ?? between.first { $0.id == id }
    }

    func status(of speaker: Speaker) -> KittenStatus? {
        statuses.first { .kitten($0.id) == speaker }
    }

    func name(of speaker: Speaker) -> String {
        switch speaker {
        case .you: return CatWords.you
        case .kitten: return status(of: speaker)?.kitten.name ?? CatWords.someoneElse
        case .someoneElse: return CatWords.someoneElse
        }
    }

    func others(in id: ChannelID) -> [Speaker] {
        let kittens = statuses.map { Speaker.kitten($0.id) }.filter(id.members.contains)
        return kittens + id.members.subtracting(kittens).subtracting([.you])
    }

    func title(of id: ChannelID) -> String {
        others(in: id)
            .map { $0 == .someoneElse ? CatWords.someoneElse.lowercased() : name(of: $0) }
            .joined(separator: ", ")
    }
}
