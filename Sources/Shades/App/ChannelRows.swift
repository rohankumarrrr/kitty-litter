import Foundation
import ShadesCore

enum ChannelSelection: Hashable {
    case needsYou
    /// What's finished, out of the way of what's still going.
    case done
    case channel(ChannelID)
    /// One thread of a channel on its own, like a thread in Slack. What you type there goes only into it. Until a new
    /// topic has its thread, its ID is the ID of what you sent.
    case thread(String, in: ChannelID)

    var channelID: ChannelID? {
        switch self {
        case .needsYou, .done: return nil
        case .channel(let id), .thread(_, let id): return id
        }
    }

    /// What the sidebar shows as selected: a thread's channel, or the selection itself.
    var place: ChannelSelection {
        if case .thread(_, let id) = self { return .channel(id) }
        return self
    }
}

enum ChannelRow: Equatable {
    case day(Date)
    case subject(String, project: String?, threadID: String)
    case message(ChannelMessage)
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
    /// Everyone: through the router, as the Ask box sends it.
    case router
    /// A new thread in the kitten's folder.
    case newThread(Kitten)
    /// `report` is the inbox row you're replying to, if you pressed Reply or Ask on one, so the answer goes under it.
    case thread(id: String, title: String, report: String? = nil)
    /// The new topic you just started, until T3 has its thread. Nothing can be sent before then.
    case starting(Kitten)
    /// Your own words as the answer.
    case question(AgentQuestion)

    /// Where typing goes. `nil` means there's no box: you only read there. A DM's own box always starts something
    /// new, the way a message in a Slack channel does, so carrying on in a thread is always a choice you can see.
    /// `answered` is how many parts of each question have their answer so far, since your words answer the next one.
    static func standard(for selection: ChannelSelection, in book: ChannelBook, answered: [String: Int] = [:]) -> MessageTarget? {
        switch selection {
        case .needsYou, .done:
            return nil
        case .channel(.everyone):
            return .router
        case .channel(let id):
            return book.writableKitten(in: id).map(MessageTarget.newThread)
        case .thread(let id, let channel):
            guard channel == .everyone || book.writableKitten(in: channel) != nil else { return nil }
            if let topic = book.channel(channel)?.messages.first(where: { $0.exchangeID == id && $0.threadID.isEmpty }),
               let kitten = book.writableKitten(in: channel) {
                return topic.failure == nil ? .starting(kitten) : .newThread(kitten)
            }
            let takesWords = { (question: AgentQuestion) -> Bool in
                guard let parts = question.form?.parts, parts.indices.contains(answered[question.id] ?? 0) else { return false }
                return parts[answered[question.id] ?? 0].takesOwnWords
            }
            // A question is yours to answer even in a thread another kitten started. Carrying on there isn't.
            if let question = book.waiting.questions.first(where: { book.thread(holding: $0.id, else: $0.threadID) == id && takesWords($0) }) {
                return .question(question)
            }
            guard !book.elsewhere.contains(id), book.knows(thread: id, in: channel) else { return nil }
            return .thread(id: id, title: book.title(ofThread: id, in: channel))
        }
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
        case .thread(let id, _, _): return !book.elsewhere.contains(id)
        case .router, .newThread: return true
        }
    }
}

/// Turns a selection into rows, so the view doesn't branch.
enum ChannelRows {
    static func rows(_ selection: ChannelSelection, in book: ChannelBook) -> [ChannelRow] {
        switch selection {
        case .needsYou: return needsYou(in: book)
        case .done: return done(in: book)
        case .channel(let id): return messages(in: id, of: book) + cards(in: id, of: book)
        case .thread(let id, let channel): return thread(id, in: channel, of: book)
        }
    }

    /// What's waiting on you first, then reports, then what each kitten is on.
    private static func needsYou(in book: ChannelBook) -> [ChannelRow] {
        let waiting = book.waiting
        var rows: [ChannelRow] = waiting.approvals.map(ChannelRow.approval) + waiting.questions.map(ChannelRow.question)
        let reports = Inbox.panelOrder(waiting.reports)
        rows += reports.filter { $0.kind == .decision }.map(ChannelRow.report)
        rows = rows.isEmpty ? [.note(CatWords.nothingNeedsYou)] : [.section(CatWords.needsYouTitle, clearing: nil)] + rows
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

    private static func done(in book: ChannelBook) -> [ChannelRow] {
        let rows = book.issues.flatMap { issues -> [ChannelRow] in
            guard !issues.done.isEmpty, let status = book.status(of: .kitten(issues.kitten.id)) else { return [] }
            return [.heading(status)] + issues.done.map(ChannelRow.issue)
        }
        if book.cantReachT3 { return [.note(CatWords.cantReachT3Yet)] + rows }
        return rows.isEmpty ? [.note(book.isReading ? CatWords.readingMessages : CatWords.nothingDone)] : rows
    }

    /// A DM ends with whatever that kitten is waiting on you for, so it can be answered right there.
    private static func cards(in id: ChannelID, of book: ChannelBook) -> [ChannelRow] {
        guard let kitten = book.statuses.first(where: { id == .direct($0.kitten) })?.kitten else { return [] }
        let approvals = book.waiting.approvals.filter { book.kitten(of: $0.id) == kitten }.map(ChannelRow.approval)
        return approvals + book.waiting.questions.filter { book.kitten(of: $0.id) == kitten }.map(ChannelRow.question)
    }

    private static func messages(in id: ChannelID, of book: ChannelBook) -> [ChannelRow] {
        guard let channel = book.channel(id), !channel.messages.isEmpty else { return [emptyNote(id, in: book)] }
        // A thread that couldn't be read looks like one too old to read, and it could be the newest.
        var rows: [ChannelRow] = channel.isCut && !book.cantReachT3 && book.unreadable == 0 ? [.note(CatWords.olderMessages)] : []
        var lastDay = Date.distantPast
        var lastThread: String?
        for message in channel.messages {
            // An exchange sits where it finished, so its ask can be older than the row above. Days only go forward.
            let day = Calendar.current.startOfDay(for: message.at)
            if day > lastDay {
                rows.append(.day(day))
                lastDay = day
            }
            // What you've just sent, and the cat's own answers, aren't in any thread yet.
            if !message.threadID.isEmpty, message.threadID != lastThread {
                rows.append(.subject(message.threadTitle, project: book.threads[message.threadID]?.projectTitle, threadID: message.threadID))
                lastThread = message.threadID
            }
            rows.append(.message(message))
        }
        return rows + statusNotes(of: book)
    }

    /// One thread on its own: what's been said in it here, then whatever it's waiting on you for. The header says
    /// which thread it is, so there are no subjects.
    private static func thread(_ id: String, in channel: ChannelID, of book: ChannelBook) -> [ChannelRow] {
        let said = book.channel(channel)?.messages.filter { $0.threadID == id || ($0.threadID.isEmpty && $0.exchangeID == id) } ?? []
        var rows: [ChannelRow] = []
        var lastDay = Date.distantPast
        for message in said {
            let day = Calendar.current.startOfDay(for: message.at)
            if day > lastDay {
                rows.append(.day(day))
                lastDay = day
            }
            rows.append(.message(message))
        }
        if rows.isEmpty {
            rows = [.note(book.cantReachT3 ? CatWords.cantReachT3Yet : book.isReading ? CatWords.readingMessages : CatWords.quietThread)]
        } else {
            rows += statusNotes(of: book)
        }
        let approvals = book.waiting.approvals.filter { book.thread(holding: $0.id, else: $0.threadID) == id }.map(ChannelRow.approval)
        return rows + approvals + book.waiting.questions.filter { book.thread(holding: $0.id, else: $0.threadID) == id }.map(ChannelRow.question)
    }

    private static func emptyNote(_ id: ChannelID, in book: ChannelBook) -> ChannelRow {
        let others = book.others(in: id)
        let isCut = book.channel(id)?.isCut == true
        if !isCut, let planned = others.lazy.compactMap({ book.status(of: $0) }).first(where: { $0.state == .notSetUp }) {
            return .note(CatWords.notSetUpYet(planned.kitten))
        }
        if book.cantReachT3 { return .note(CatWords.cantReachT3Yet) }
        if book.isReading { return .note(CatWords.readingMessages) }
        if book.unreadable > 0 { return .note(CatWords.couldntRead(book.unreadable)) }
        if isCut { return .note(CatWords.olderMessages) }
        if id == .everyone { return .note(CatWords.everyoneEmpty) }
        let names = id.members.contains(.you) ? [CatWords.you] + others.map(book.name) : others.map(book.name)
        return .note(CatWords.haventTalked(names))
    }

    private static func statusNotes(of book: ChannelBook) -> [ChannelRow] {
        var notes: [ChannelRow] = []
        if book.cantReachT3 { notes.append(.note(CatWords.cantReachT3Yet)) }
        if book.unreadable > 0 { notes.append(.note(CatWords.couldntRead(book.unreadable))) }
        return notes
    }
}
