import Foundation
import ShadesCore

enum ChannelSelection: Hashable {
    case needsYou
    case channel(ChannelID)
}

enum ChannelRow: Equatable {
    case day(Date)
    case subject(String, threadID: String)
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
    case thread(id: String, title: String)
    /// The new topic you just started, until T3 has its thread. Nothing can be sent before then.
    case starting(Kitten)
    /// Your own words as the answer.
    case question(AgentQuestion)

    /// Where typing goes until you pick somewhere else. `nil` means there's no box: you only read there.
    static func standard(for selection: ChannelSelection, in book: ChannelBook) -> MessageTarget? {
        guard case .channel(let id) = selection else { return nil }
        if id == .everyone { return .router }
        guard let status = book.statuses.first(where: { id == .direct($0.kitten) }), status.state != .notSetUp else { return nil }
        // Your words with no thread yet are a new topic still starting, even if something else has been said since.
        if book.channel(id)?.messages.contains(where: { $0.speaker == .you && $0.threadID.isEmpty && $0.failure == nil }) == true {
            return .starting(status.kitten)
        }
        if let question = book.waiting.questions.first(where: { book.kitten(of: $0.id) == status.kitten && $0.form?.parts.first?.takesOwnWords == true }) {
            return .question(question)
        }
        // Carrying on where you left off is what a message in a DM usually means: the last thing said, or a newer
        // thread whose words haven't been read yet.
        let lastSaid = book.channel(id)?.messages.last { !$0.threadID.isEmpty }
        if let newest = book.newestThreads[status.kitten.id], newest.updatedAt > lastSaid?.at ?? .distantPast {
            return .thread(id: newest.id, title: newest.title)
        }
        if let lastSaid { return .thread(id: lastSaid.threadID, title: lastSaid.threadTitle) }
        return .newThread(status.kitten)
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
        case .thread(let id, _): return !book.elsewhere.contains(id)
        case .router, .newThread: return true
        }
    }
}

/// Turns a selection into rows, so the view doesn't branch.
enum ChannelRows {
    static func rows(_ selection: ChannelSelection, in book: ChannelBook) -> [ChannelRow] {
        switch selection {
        case .needsYou: return needsYou(in: book)
        case .channel(let id): return messages(in: id, of: book) + cards(in: id, of: book)
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
                rows.append(.subject(message.threadTitle, threadID: message.threadID))
                lastThread = message.threadID
            }
            rows.append(.message(message))
        }
        return rows + statusNotes(of: book)
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
