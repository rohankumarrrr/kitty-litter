import Foundation
import ShadesCore

enum Speaker: Hashable {
    case you
    case kitten(String)
    case cat
    case someoneElse
}

enum ChannelID: Hashable {
    case kitten(String)
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
    var text: String?
    var at: Date
    var threadID: String
    var threadTitle: String
    var earlierNotes = 0
    var isStillGoing = false
    var failure: String?
    var files: [ChannelFile] = []
    var isSending = false
    var reactions: [Reaction]?

    var id: String { "\(exchangeID):\(kind.rawValue)" }
    var canTryAgain: Bool { speaker == .you && failure != nil && files.isEmpty }
}

struct ChannelFile: Equatable {
    var name: String
    var thumbnail: Data?
    var source: PictureSource?
    var couldntShow = false
}

struct ChannelThread: Equatable, Identifiable {
    var id: String
    var title: String
    var home: ChannelID
    var owner: String?
    var parent: ChannelMessage
    var replies: [ChannelMessage]
    var isCut = false

    var latest: ChannelMessage { replies.last ?? parent }
    var messages: [ChannelMessage] { [parent] + replies }
    var replyCount: Int { replies.filter { !($0.isStillGoing && $0.text == nil) }.count }
    var isGoing: Bool { latest.isStillGoing }
    var repliers: [Speaker] {
        var seen: Set<Speaker> = []
        return replies.compactMap { seen.insert($0.speaker).inserted ? $0.speaker : nil }
    }
    var hasYou: Bool { messages.contains { $0.speaker == .you } }
    var isStarting: Bool { parent.threadID.isEmpty }
}

enum ChannelPost: Equatable {
    case thread(String)
    case message(ChannelMessage)
    case alsoSent(ChannelMessage, thread: String)
}

struct Channel: Equatable, Identifiable {
    var id: ChannelID
    var posts: [ChannelPost]
    var isCut: Bool
    var isLoadingOlder = false
}

struct SentMessage: Equatable {
    var channel: ChannelID
    var message: ChannelMessage
    var startsThread = false
    var alsoSent = false
    var isReply = false
    var target: MessageTarget?
}

struct Waiting: Equatable {
    var approvals: [ApprovalRequest] = []
    var questions: [AgentQuestion] = []
    var owners: [String: String] = [:]
    var listed: [String: String] = [:]
    var reports: [InboxEntry] = []
    var shadesWork: [AgentThread] = []
    var away: [Missed] = []
    var doNotDisturb = false
    var notifications: [String: ChannelNotifications] = [:]
    var phone = false

    var count: Int { approvals.count + questions.count + reports.filter(\.needsYou).count }
}

struct KittenIssues: Equatable {
    var kitten: Kitten
    var threads: [AgentThread]
}

struct ChannelBook: Equatable {
    static let keptExchanges = 200

    var statuses: [KittenStatus]
    var channels: [Channel]
    var threads: [String: ChannelThread]
    var issues: [KittenIssues]
    var waiting: Waiting
    var unreadThreads: Set<String>
    var newFrom: [String: String] = [:]
    var listed: [String: AgentThread]
    var listedHomes: [String: ChannelID] = [:]
    var started: [String: String]
    var talks: Set<String>
    var catsWork: Set<String> = []
    var onPhone: Set<String> = []
    var hasPhone = false
    var alsoSentHeard: [String: HeardAlsoSent] = [:]

    struct HeardAlsoSent: Equatable {
        var thread: String
        var channel: ChannelID
    }
    var isReading: Bool
    var unreadable: Int
    var cantReachT3: Bool
    var searchingT3: String?

    var pulls: [String: String] {
        Dictionary(listed.values.compactMap { thread in
            guard let pull = thread.pullRequest, let key = pull.url.flatMap(URL.init(string:)).flatMap(Markup.pull)?.key else { return nil }
            return (key, pull.state)
        }, uniquingKeysWith: { first, _ in first })
    }

    private struct Gathered {
        var title: String
        var home: ChannelID
        var owner: String?
        var messages: [ChannelMessage]
        var isCut = false
        var isPosted = true
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
        firstNew: (AgentThread, [ChannelMessage]) -> String? = { _, _ in nil },
        messagesThreads: [String: Date] = [:],
        withShades: Set<String> = [],
        catsWork: Set<String> = [],
        onPhone: Set<String> = [],
        hasPhone: Bool = false,
        alsoSent: Set<String> = [],
        olderPages: [ChannelID: Int] = [:],
        loadingOlder: Set<ChannelID> = [],
        couldntRead: Set<String> = [],
        reactions: [String: [Reaction]] = [:],
        searchingT3: String? = nil,
        said: (String) -> String? = ChannelBook.said
    ) -> ChannelBook {
        let talkThreads = threads.filter { withShades.contains($0.id) }
        let threads = threads.filter { !withShades.contains($0.id) }.map { thread -> AgentThread in
            guard thread.pendingQuestion != nil else { return thread }
            var waiting = thread
            waiting.status = .waitingForAnswer
            return waiting
        }
        let threadsByID = Dictionary(threads.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let lookup = KittenBoard.Owners(kittens)
        let owners = Dictionary(threads.map { ($0.id, lookup.of($0)) }, uniquingKeysWith: { first, _ in first })
        let ownerOf = { (thread: AgentThread) in owners[thread.id] ?? nil }
        let statuses = KittenBoard.statuses(kittens: kittens, threads: threads)
        let channelIDs = [ChannelID.shades] + statuses.map { .of($0.kitten) }

        var gathered: [String: Gathered] = [:]
        var order: [String] = []
        var leftOut: Set<ChannelID> = []
        func gather(_ id: String, _ thread: Gathered) {
            if gathered[id] == nil { order.append(id) }
            gathered[id] = thread
        }
        for thread in talkThreads where !thread.isLiveTest {
            guard let exchanges = transcripts[thread.id] else {
                if !couldntRead.contains(thread.id) { leftOut.insert(.shades) }
                continue
            }
            let messages = talk(in: thread, exchanges, said: said).map { reacted($0, reactions) }
            gather(thread.id, Gathered(title: thread.title, home: .shades, messages: messages, isCut: exchanges.count >= keptExchanges))
        }
        for thread in threads {
            let owner = ownerOf(thread)
            guard owner != nil || messagesThreads[thread.id] != nil || catsWork.contains(thread.id) else { continue }
            guard let exchanges = transcripts[thread.id] else {
                if !couldntRead.contains(thread.id) { leftOut.insert(home(of: owner)) }
                continue
            }
            let replier = owner.map { Speaker.kitten($0.id) } ?? .cat
            let title = owner.map { Self.title(of: thread, owner: $0) } ?? thread.title
            var messages: [ChannelMessage] = []
            for (index, exchange) in exchanges.enumerated() {
                let asker = speaker(of: exchange.asker, replier: replier, threads: threadsByID, owner: ownerOf, messagesThreads: messagesThreads, catsWork: catsWork)
                let isStillGoing = thread.status.isActive && !thread.turnEnded && !KittenBoard.needsYou(thread) && index == exchanges.count - 1
                messages += self.messages(of: exchange, in: thread.id, title: title, asker: asker, replier: replier, isStillGoing: isStillGoing).map { reacted($0, reactions) }
            }
            guard !messages.isEmpty else { continue }
            gather(thread.id, Gathered(title: title, home: home(of: owner), owner: owner?.id, messages: messages, isCut: exchanges.count >= keptExchanges))
        }

        var placed: [ChannelID: [Placed]] = [:]
        let ours = Set(sent.map(\.message.id))
        var alsoSentHeard: [String: HeardAlsoSent] = [:]
        var claimed: Set<String> = []
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
                if sent.alsoSent {
                    post(.message(message))
                    continue
                }
                let listed = threadsByID[message.threadID]
                let owner = listed.flatMap(ownerOf)
                let home = owner.map(ChannelID.of) ?? sent.channel
                if let listed { message.threadTitle = owner.map { title(of: listed, owner: $0) } ?? listed.title }
                gather(message.threadID, Gathered(title: message.threadTitle, home: home, owner: owner?.id, messages: [message], isPosted: !sent.isReply))
                continue
            }
            if let index = thread.messages.firstIndex(where: { !claimed.contains($0.id) && isEcho(of: message, $0) }) {
                claimed.insert(thread.messages[index].id)
                // Outside the repo: Safari on iPhone can give every photo from the camera the same name.
                var shown: [String: [Data?]] = [:]
                for file in message.files { shown[file.name, default: []].append(file.thumbnail) }
                var seen: [String: Int] = [:]
                var files = thread.messages[index].files
                for file in files.indices {
                    let place = seen[files[file].name, default: 0]
                    seen[files[file].name] = place + 1
                    guard files[file].thumbnail == nil, let same = shown[files[file].name], same.indices.contains(place) else { continue }
                    files[file].thumbnail = same[place]
                }
                if files != thread.messages[index].files {
                    thread.messages[index].files = files
                    gathered[message.threadID] = thread
                }
                let echo = thread.messages[index]
                if sent.alsoSent, echo.id != thread.messages.first?.id {
                    post(.alsoSent(echo, thread: message.threadID))
                    if !ours.contains(echo.id), message.failure == nil, echo.at >= message.at.addingTimeInterval(-2) {
                        alsoSentHeard[echo.id] = HeardAlsoSent(thread: message.threadID, channel: sent.channel)
                    }
                }
                continue
            }
            message.threadTitle = thread.title
            claimed.insert(message.id)
            if let first = thread.messages.first, message.at < first.at {
                thread.messages.insert(message, at: 0)
            } else {
                thread.messages.append(message)
                if sent.alsoSent { post(.alsoSent(message, thread: message.threadID)) }
            }
            gathered[message.threadID] = thread
        }

        var built: [String: ChannelThread] = [:]
        for (index, id) in order.enumerated() {
            guard let thread = gathered[id], let parent = thread.messages.first else { continue }
            built[id] = ChannelThread(
                id: id,
                title: thread.title,
                home: channelIDs.contains(thread.home) ? thread.home : .shades,
                owner: thread.owner,
                parent: parent,
                replies: Array(thread.messages.dropFirst()),
                isCut: thread.isCut
            )
            guard thread.isPosted else { continue }
            placed[built[id]!.home, default: []].append(Placed(position: parent.at, sequence: index - order.count, post: .thread(id)))
        }
        if !alsoSent.isEmpty {
            for (index, id) in order.enumerated() {
                guard let thread = built[id] else { continue }
                for message in thread.replies where alsoSentHeard[message.id] == nil && alsoSent.contains(message.id) {
                    placed[thread.home, default: []].append(Placed(position: message.at, sequence: sent.count + index, post: .alsoSent(message, thread: id)))
                }
            }
        }

        let channels = channelIDs.map { id in
            channel(id, placed[id] ?? [], leavesOutThreads: !isReading && leftOut.contains(id), pages: olderPages[id] ?? 0, isLoadingOlder: loadingOlder.contains(id))
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
        var named: [String: AgentThread] = [:]
        var homes: [String: ChannelID] = [:]
        for thread in talkThreads where named[thread.id] == nil { named[thread.id] = thread }
        for thread in threads where named[thread.id] == nil {
            named[thread.id] = thread
            let owner = ownerOf(thread)
            if owner != nil || messagesThreads[thread.id] != nil || catsWork.contains(thread.id) { homes[thread.id] = home(of: owner) }
            if let owner { named[thread.id]?.title = title(of: thread, owner: owner) }
        }
        let unreadShown = Set(built.keys.filter { threadsByID[$0].map(isUnread) == true })
        let newFrom = Dictionary(uniqueKeysWithValues: unreadShown.compactMap { id -> (String, String)? in
            guard let listed = threadsByID[id], let thread = built[id] else { return nil }
            return firstNew(listed, thread.messages).map { (id, $0) }
        })
        let started = Dictionary(sent.compactMap { $0.startsThread && !$0.message.threadID.isEmpty ? ($0.message.exchangeID, $0.message.threadID) : nil }, uniquingKeysWith: { first, _ in first })
        return ChannelBook(
            statuses: statuses,
            channels: channels,
            threads: built,
            issues: issues,
            waiting: waiting,
            unreadThreads: unreadShown,
            newFrom: newFrom,
            listed: named,
            listedHomes: homes,
            started: started,
            talks: Set(talkThreads.map(\.id)),
            catsWork: catsWork.intersection(threadsByID.keys),
            onPhone: onPhone.intersection(catsWork).intersection(threadsByID.keys),
            hasPhone: hasPhone,
            alsoSentHeard: alsoSentHeard,
            isReading: isReading,
            unreadable: unreadable,
            cantReachT3: cantReachT3,
            searchingT3: searchingT3
        )
    }

    private static func home(of owner: Kitten?) -> ChannelID {
        owner.map(ChannelID.of) ?? .shades
    }

    private static func speaker(of asker: Exchange.Asker, replier: Speaker, threads: [String: AgentThread], owner: (AgentThread) -> Kitten?, messagesThreads: [String: Date], catsWork: Set<String>) -> Speaker {
        switch asker {
        case .you:
            return .you
        case .schedule:
            return replier
        case .agent(let threadID):
            guard let threadID, let asking = threads[threadID] else { return .someoneElse }
            if let kitten = owner(asking) { return .kitten(kitten.id) }
            return messagesThreads[threadID] != nil || catsWork.contains(threadID) ? .cat : .someoneElse
        }
    }

    private static func messages(of exchange: Exchange, in threadID: String, title: String, asker: Speaker, replier: Speaker, isStillGoing: Bool) -> [ChannelMessage] {
        let talkingToItself = asker == replier
        var messages: [ChannelMessage] = []
        if let ask = exchange.ask, !talkingToItself {
            messages.append(ChannelMessage(exchangeID: exchange.id, kind: .ask, speaker: asker, text: ask, at: exchange.askedAt, threadID: threadID, threadTitle: title, files: files(of: exchange)))
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
                failure: exchange.failure,
                files: exchange.reply.map { pictures(in: $0, threadID: threadID) } ?? []
            ))
        }
        return messages
    }

    private static func reacted(_ message: ChannelMessage, _ reactions: [String: [Reaction]]) -> ChannelMessage {
        guard message.text != nil || !message.files.isEmpty else { return message }
        var message = message
        message.reactions = reactions[message.id] ?? []
        return message
    }

    private static func files(of exchange: Exchange) -> [ChannelFile] {
        exchange.files.map { ChannelFile(name: $0.name, source: $0.attachmentID.map(PictureSource.sent)) }
    }

    static func pictures(in reply: String, threadID: String) -> [ChannelFile] {
        Markup.pictures(in: reply).compactMap { picture in
            PictureSource(picture.url, inThread: threadID).map { ChannelFile(name: picture.name, source: $0) }
        }
    }

    private static func channel(_ id: ChannelID, _ placed: [Placed], leavesOutThreads: Bool, pages: Int, isLoadingOlder: Bool) -> Channel {
        let ordered = placed.sorted { a, b in
            if a.position != b.position { return a.position < b.position }
            return a.sequence < b.sequence
        }
        let kept = keptExchanges * (pages + 1)
        return Channel(id: id, posts: ordered.suffix(kept).map(\.post), isCut: leavesOutThreads || ordered.count > kept, isLoadingOlder: isLoadingOlder)
    }

    private static func talk(in thread: AgentThread, _ exchanges: [Exchange], said: (String) -> String?) -> [ChannelMessage] {
        exchanges.enumerated().flatMap { index, exchange -> [ChannelMessage] in
            let isStillGoing = thread.status.isActive && index == exchanges.count - 1
            var messages: [ChannelMessage] = []
            if exchange.asker == .you, let ask = exchange.ask {
                messages.append(ChannelMessage(exchangeID: exchange.id, kind: .ask, speaker: .you, text: ask, at: exchange.askedAt, threadID: thread.id, threadTitle: thread.title, files: files(of: exchange)))
            }
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

    private static func withoutPromptBlocks(_ reply: String) -> String {
        Prompts.withoutBlocks(named: "screen|sessions|kittens", in: reply)
    }

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

    private static func isOpen(_ thread: AgentThread) -> Bool {
        thread.status.isActive || KittenBoard.needsYou(thread) || (!thread.isSettled && thread.status != .completed)
    }

    private static func urgency(_ thread: AgentThread) -> Int {
        KittenBoard.needsYou(thread) ? 0 : thread.status.isActive ? 1 : 2
    }

    private static func title(of thread: AgentThread, owner: Kitten) -> String {
        title(of: thread.title, owner: owner)
    }

    static func title(of title: String, owner: Kitten) -> String {
        let prefix = "\(owner.name):"
        guard title.hasPrefix(prefix) else { return title }
        return title.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
    }

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

    func thread(holding request: String, else threadID: String) -> String {
        waiting.listed[request] ?? threadID
    }

    func kitten(of requestID: String) -> Kitten? {
        waiting.owners[requestID].flatMap { kitten($0) }
    }

    var mentionable: [Kitten] {
        statuses.filter { $0.state != .notSetUp }.map(\.kitten)
    }

    func writableKitten(in id: ChannelID) -> Kitten? {
        guard case .kitten(let kitten) = id else { return nil }
        return statuses.first { $0.id == kitten && $0.state != .notSetUp }?.kitten
    }

    func title(ofThread id: String) -> String {
        if let title = listed[id]?.title { return title }
        guard let thread = threads[id] else { return "" }
        return thread.title.isEmpty ? ChannelRows.firstWords(of: thread.parent.text ?? "") : thread.title
    }

    mutating func eachMessage(_ change: (inout ChannelMessage) -> Void) {
        for id in threads.keys {
            change(&threads[id]!.parent)
            for index in threads[id]!.replies.indices { change(&threads[id]!.replies[index]) }
        }
        for channel in channels.indices {
            for post in channels[channel].posts.indices {
                switch channels[channel].posts[post] {
                case .message(var message):
                    change(&message)
                    channels[channel].posts[post] = .message(message)
                case .alsoSent(var message, let thread):
                    change(&message)
                    channels[channel].posts[post] = .alsoSent(message, thread: thread)
                case .thread:
                    break
                }
            }
        }
    }

    func message(_ id: String) -> ChannelMessage? {
        let loose = channels.flatMap(\.posts).compactMap { post -> ChannelMessage? in
            if case .message(let message) = post { message } else { nil }
        }
        return (threads.values.flatMap(\.messages) + loose).first { $0.id == id }
    }

    func canMarkUnread(_ id: String) -> Bool {
        listed[id] != nil && threads[id] != nil && !talks.contains(id)
    }

    func knows(thread id: String) -> Bool {
        listed[id] != nil || threads[id].map { !$0.isStarting } == true
    }

    func home(ofThread id: String) -> ChannelID? {
        if talks.contains(id) { return .shades }
        if listed[id] != nil { return listedHomes[id] }
        return threads[id]?.home
    }

    func home(of kitten: Kitten?) -> ChannelID {
        kitten.map(ChannelID.of) ?? .shades
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

    func name(of id: ChannelID) -> String {
        switch id {
        case .kitten(let kitten): return self.kitten(kitten)?.name ?? kitten
        case .shades: return CatWords.shades
        }
    }

    func badge(of id: ChannelID) -> Int {
        guard case .kitten(let kitten) = id else { return 0 }
        let mine = { (request: String) in waiting.owners[request] == kitten }
        return waiting.approvals.filter { mine($0.id) }.count + waiting.questions.filter { mine($0.id) }.count
            + waiting.reports.filter { $0.needsYou && mine($0.id) }.count
    }

    func isUnread(_ id: ChannelID) -> Bool {
        !unreadThreads(in: .channel(id)).isEmpty
    }

    func unreadThreads(in place: ChannelPlace) -> [String] {
        switch place {
        case .activity: return []
        case .threads: return unreadThreads.filter { threads[$0].map(isYours) == true }.sorted()
        case .channel(let id): return unreadThreads.filter { threads[$0]?.home == id }.sorted()
        }
    }

    var yours: [ChannelThread] {
        threads.values
            .filter(isYours)
            .sorted { a, b in
                let unreadA = unreadThreads.contains(a.id), unreadB = unreadThreads.contains(b.id)
                if unreadA != unreadB { return unreadA }
                if a.latest.at != b.latest.at { return a.latest.at > b.latest.at }
                return a.id < b.id
            }
    }

    private func isYours(_ thread: ChannelThread) -> Bool {
        thread.hasYou && !talks.contains(thread.id) && !catsWork.contains(thread.id)
    }

    func threads(in id: ChannelID) -> [String] {
        channel(id)?.posts.compactMap { if case .thread(let thread) = $0 { thread } else { nil } } ?? []
    }
}
