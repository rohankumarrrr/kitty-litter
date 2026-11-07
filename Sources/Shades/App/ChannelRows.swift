import Foundation
import ShadesCore

/// A row of the sidebar: Activity and Threads at the top, then each channel and the DM.
enum ChannelPlace: Hashable {
    /// What's waiting on you, what's shipped, and what each kitten is on.
    case activity
    /// Every thread you've written in.
    case threads
    case channel(ChannelID)

    var channelID: ChannelID? {
        if case .channel(let id) = self { return id }
        return nil
    }
}

/// What the window shows: a place, and maybe a thread open in the pane beside it, as Slack does. It holds only IDs, so
/// it survives the window closing.
struct ChannelSelection: Hashable {
    var place: ChannelPlace
    /// Until a new topic has its thread, its ID is the ID of what you sent.
    var thread: String?

    init(_ place: ChannelPlace, thread: String? = nil) {
        self.place = place
        self.thread = thread
    }

    static let activity = ChannelSelection(.activity)
    static let threads = ChannelSelection(.threads)
    static func channel(_ id: ChannelID) -> ChannelSelection { ChannelSelection(.channel(id)) }
    static func thread(_ id: String, in place: ChannelPlace) -> ChannelSelection { ChannelSelection(place, thread: id) }

    var channelID: ChannelID? { place.channelID }
    /// The same place with its thread pane closed.
    var closed: ChannelSelection { ChannelSelection(place) }
}

/// A thread's parent and its reply bar, holding only what they show, so an unchanged one isn't drawn again.
struct ThreadPost: Equatable {
    var threadID: String
    var parent: ChannelMessage
    var replies: Int
    var repliers: [Speaker]
    var lastReply: Date?
    var isGoing: Bool
    var needsYou: Bool

    init(_ thread: ChannelThread, needsYou: Bool) {
        threadID = thread.id
        parent = thread.parent
        replies = thread.replyCount
        repliers = thread.repliers
        lastReply = thread.replies.last { !($0.isStillGoing && $0.text == nil) }?.at
        isGoing = thread.isGoing
        self.needsYou = needsYou
    }
}

/// One thread you're in, as Threads lists it.
struct ThreadDigest: Equatable {
    var threadID: String
    var channel: ChannelID
    var parent: ChannelMessage
    var latest: ChannelMessage?
    /// Replies before the latest.
    var more: Int
    var isUnread: Bool
}

enum ChannelRow: Equatable {
    case day(Date)
    case parent(ThreadPost)
    case message(ChannelMessage)
    /// A reply also sent to the channel, under a line saying which thread it's in.
    case alsoSent(ChannelMessage, threadID: String, parent: String)
    case digest(ThreadDigest)
    /// In a thread's pane, the line between its parent and its replies.
    case replies(Int)
    case section(String, clearing: InboxEntry.Kind?)
    case heading(KittenStatus)
    case issue(AgentThread)
    case approval(ApprovalRequest)
    case question(AgentQuestion)
    case report(InboxEntry)
    case note(String)
}

/// Where what you type in Messages goes. None of them carry your screen, and each carries only your words.
enum MessageTarget: Equatable {
    /// #general and the cat's DM: through the router, as the Ask box sends it, on Messages' own conversation with it.
    case router
    /// A new thread in the kitten's folder.
    case newThread(Kitten)
    /// `report` is the inbox row you're replying to, if you pressed Reply or Ask on one, so the answer goes under it.
    case thread(id: String, title: String, report: String? = nil)
    /// The new topic you just started, until T3 has its thread. Nothing can be sent before then.
    case starting(Kitten)
    /// Your own words as the answer.
    case question(AgentQuestion)

    /// The box under a place. `nil` means there's no box: you only read there. A kitten's channel always starts
    /// something new, the way a message in a Slack channel does, so carrying on in a thread is always a choice you can see.
    static func standard(for place: ChannelPlace, in book: ChannelBook) -> MessageTarget? {
        switch place {
        case .activity, .threads:
            return nil
        case .channel(.general), .channel(.shades):
            return .router
        case .channel(let id):
            return book.writableKitten(in: id).map(MessageTarget.newThread)
        }
    }

    /// The box in a thread's pane, which goes only into that thread. `answered` is how many parts of each question
    /// have their answer so far, since your words answer the next one.
    static func reply(in id: String, of book: ChannelBook, answered: [String: Int] = [:]) -> MessageTarget? {
        // The router answers in lines the app acts on, so nothing goes straight into one of its threads.
        guard !book.talks.contains(id), book.home(ofThread: id) != .shades else { return nil }
        let thread = book.threads[id]
        if let thread, thread.isStarting, let kitten = thread.owner.flatMap({ book.kitten($0) }) {
            return thread.parent.failure == nil ? .starting(kitten) : .newThread(kitten)
        }
        if case .kitten(let owner)? = book.home(ofThread: id), book.statuses.first(where: { $0.id == owner })?.state == .notSetUp { return nil }
        if let question = book.waiting.questions.first(where: { book.thread(holding: $0.id, else: $0.threadID) == id && takesWords($0, answered: answered) }) {
            return .question(question)
        }
        guard book.knows(thread: id) else { return nil }
        return .thread(id: id, title: book.title(ofThread: id))
    }

    /// Whether the part of a question that's next to answer takes your own words.
    static func takesWords(_ question: AgentQuestion, answered: [String: Int]) -> Bool {
        guard let parts = question.form?.parts, parts.indices.contains(answered[question.id] ?? 0) else { return false }
        return parts[answered[question.id] ?? 0].takesOwnWords
    }
}

extension MessageTarget {
    /// Whether words already typed can still go here. An answered question can't take them, and a new topic
    /// that's started moves on to its thread.
    var isReady: Bool {
        if case .starting = self { return false }
        return true
    }

    func isStill(in book: ChannelBook) -> Bool {
        switch self {
        case .starting: return false
        case .question(let question): return book.waiting.questions.contains { $0.id == question.id }
        case .router, .newThread, .thread: return true
        }
    }
}

/// Turns a place or a thread into rows, so the view doesn't branch.
enum ChannelRows {
    static func rows(_ place: ChannelPlace, in book: ChannelBook) -> [ChannelRow] {
        switch place {
        case .activity: return activity(in: book)
        case .threads: return threads(in: book)
        case .channel(let id): return channel(id, of: book)
        }
    }

    /// One thread on its own: its parent, how many replies, each reply, then whatever it's waiting on you for.
    static func thread(_ id: String, in book: ChannelBook) -> [ChannelRow] {
        var rows: [ChannelRow] = []
        if let thread = book.threads[id] {
            rows = [.message(thread.parent)]
            if !thread.replies.isEmpty || thread.isCut { rows.append(.replies(thread.replyCount)) }
            if thread.isCut { rows.append(.note(CatWords.olderReplies)) }
            var lastDay = Calendar.current.startOfDay(for: thread.parent.at)
            for reply in thread.replies {
                let day = Calendar.current.startOfDay(for: reply.at)
                if day > lastDay {
                    rows.append(.day(day))
                    lastDay = day
                }
                rows.append(.message(reply))
            }
            rows += statusNotes(of: book)
        } else {
            rows = [.note(emptyThreadNote(id, in: book))]
        }
        let approvals = book.waiting.approvals.filter { book.thread(holding: $0.id, else: $0.threadID) == id }.map(ChannelRow.approval)
        return rows + approvals + book.waiting.questions.filter { book.thread(holding: $0.id, else: $0.threadID) == id }.map(ChannelRow.question)
    }

    /// The threads Activity opens beside a channel, top to bottom: a question's Type an answer, a report's Reply or
    /// Ask, and what's in progress that Messages has read. An approval, and anything else, only opens in T3. `answered`
    /// is how many parts of each question have their answer so far.
    static func activityThreads(in book: ChannelBook, answered: [String: Int] = [:]) -> [String] {
        var seen: Set<String> = []
        return activity(in: book).compactMap { row -> String? in
            switch row {
            case .question(let question):
                return MessageTarget.takesWords(question, answered: answered) ? book.thread(holding: question.id, else: question.threadID) : nil
            case .report(let entry): return entry.threadID
            case .issue(let thread): return book.threads[thread.id] == nil ? nil : thread.id
            default: return nil
            }
        }.filter { seen.insert($0).inserted }
    }

    /// Whether something's waiting on you in this thread, which its reply bar says.
    static func needsYou(_ id: String, in book: ChannelBook) -> Bool {
        book.waiting.approvals.contains { book.thread(holding: $0.id, else: $0.threadID) == id }
            || book.waiting.questions.contains { book.thread(holding: $0.id, else: $0.threadID) == id }
    }

    /// What's waiting on you first, then reports, then what each kitten is on.
    private static func activity(in book: ChannelBook) -> [ChannelRow] {
        let waiting = book.waiting
        var rows: [ChannelRow] = waiting.approvals.map(ChannelRow.approval) + waiting.questions.map(ChannelRow.question)
        let reports = Inbox.panelOrder(waiting.reports)
        rows += reports.filter { $0.kind == .decision }.map(ChannelRow.report)
        rows = rows.isEmpty ? [.note(CatWords.nothingNeedsYou)] : [.section(CatWords.waitingOnYou, clearing: nil)] + rows
        for kind in [InboxEntry.Kind.shipped, .note] {
            let these = reports.filter { $0.kind == kind }
            if !these.isEmpty { rows += [.section(CatWords.reportsTitle(kind), clearing: kind)] + these.map(ChannelRow.report) }
        }
        let progress = inProgress(in: book)
        return statusNotes(of: book) + rows + (progress.isEmpty ? [] : [.section(CatWords.inProgress, clearing: nil)] + progress)
    }

    private static func inProgress(in book: ChannelBook) -> [ChannelRow] {
        let shades = book.waiting.shadesWork
        // Threads are known before any words are, so reading only matters if there's nothing to show yet.
        if book.issueCount == 0, shades.isEmpty {
            if book.cantReachT3 { return [] }
            if book.isReading { return [.note(CatWords.readingMessages)] }
        }
        let own: [ChannelRow] = shades.isEmpty ? [] : [.heading(KittenBoard.shadesStatus(shades))] + shades.map(ChannelRow.issue)
        return own + book.issues.flatMap { issues -> [ChannelRow] in
            guard let status = book.status(of: .kitten(issues.kitten.id)) else { return [] }
            let open: [ChannelRow] = issues.threads.isEmpty ? [.note(CatWords.nothingOpen)] : issues.threads.map(ChannelRow.issue)
            return [.heading(status)] + open
        }
    }

    private static func threads(in book: ChannelBook) -> [ChannelRow] {
        let yours = book.yours.map { thread in
            ChannelRow.digest(ThreadDigest(
                threadID: thread.id,
                channel: thread.home,
                parent: thread.parent,
                latest: thread.replies.last { !($0.isStillGoing && $0.text == nil) },
                more: max(thread.replyCount - 1, 0),
                isUnread: book.unreadThreads.contains(thread.id)
            ))
        }
        if !yours.isEmpty { return statusNotes(of: book) + yours }
        if book.cantReachT3 { return [.note(CatWords.cantReachT3Yet)] }
        return [.note(book.isReading ? CatWords.readingMessages : CatWords.threadsEmpty)]
    }

    private static func channel(_ id: ChannelID, of book: ChannelBook) -> [ChannelRow] {
        guard let channel = book.channel(id), !channel.posts.isEmpty else { return [emptyNote(id, in: book)] }
        // A thread that couldn't be read looks like one too old to read, and it could be the newest.
        var rows: [ChannelRow] = channel.isCut && !book.cantReachT3 && book.unreadable == 0 ? [.note(CatWords.olderMessages)] : []
        var lastDay = Date.distantPast
        for post in channel.posts {
            let row: ChannelRow
            let at: Date
            switch post {
            case .thread(let threadID):
                guard let thread = book.threads[threadID] else { continue }
                row = .parent(ThreadPost(thread, needsYou: needsYou(threadID, in: book)))
                at = thread.parent.at
            case .message(let message):
                row = .message(message)
                at = message.at
            case .alsoSent(let message, let threadID):
                row = .alsoSent(message, threadID: threadID, parent: firstWords(of: book.threads[threadID]?.parent.text ?? book.title(ofThread: threadID)))
                at = message.at
            }
            let day = Calendar.current.startOfDay(for: at)
            if day > lastDay {
                rows.append(.day(day))
                lastDay = day
            }
            rows.append(row)
        }
        return rows + statusNotes(of: book)
    }

    /// The start of a thread's first message, for "replied to a thread".
    static func firstWords(of text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return line.count > 60 ? String(line.prefix(59)) + "…" : line
    }

    /// Why there's nothing to show, where that's known.
    private static func emptyThreadNote(_ id: String, in book: ChannelBook) -> String {
        if book.cantReachT3 { return CatWords.cantReachT3Yet }
        if book.isReading { return CatWords.readingMessages }
        if book.unreadable > 0 { return CatWords.couldntRead(book.unreadable) }
        // Only listed threads are read, and T3 stops listing one once it's archived.
        if book.listed[id] == nil { return CatWords.threadNotListed }
        return CatWords.quietThread
    }

    private static func emptyNote(_ id: ChannelID, in book: ChannelBook) -> ChannelRow {
        let isCut = book.channel(id)?.isCut == true
        if !isCut, case .kitten(let kitten) = id, let status = book.statuses.first(where: { $0.id == kitten }), status.state == .notSetUp {
            return .note(CatWords.notSetUpYet(status.kitten))
        }
        if book.cantReachT3 { return .note(CatWords.cantReachT3Yet) }
        if book.isReading { return .note(CatWords.readingMessages) }
        if book.unreadable > 0 { return .note(CatWords.couldntRead(book.unreadable)) }
        if isCut { return .note(CatWords.olderMessages) }
        switch id {
        case .general: return .note(CatWords.generalEmpty)
        case .shades: return .note(CatWords.shadesEmpty)
        case .kitten(let kitten): return .note(CatWords.noThreadsYet(book.kitten(kitten)?.name ?? CatWords.someoneElse))
        }
    }

    private static func statusNotes(of book: ChannelBook) -> [ChannelRow] {
        var notes: [ChannelRow] = []
        if book.cantReachT3 { notes.append(.note(CatWords.cantReachT3Yet)) }
        if book.unreadable > 0 { notes.append(.note(CatWords.couldntRead(book.unreadable))) }
        return notes
    }
}
