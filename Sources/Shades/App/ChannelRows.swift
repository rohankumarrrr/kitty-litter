import Foundation
import ShadesCore

enum ChannelSelection: Hashable {
    case issues
    case channel(ChannelID)
}

enum ChannelRow: Equatable {
    case day(Date)
    case subject(String, threadID: String)
    case message(ChannelMessage)
    case heading(KittenStatus)
    case issue(AgentThread)
    case note(String)
}

/// Turns a selection into rows, so the view doesn't branch.
enum ChannelRows {
    static func rows(_ selection: ChannelSelection, in book: ChannelBook) -> [ChannelRow] {
        switch selection {
        case .issues: return issues(in: book)
        case .channel(let id): return messages(in: id, of: book)
        }
    }

    private static func issues(in book: ChannelBook) -> [ChannelRow] {
        // Threads are known before any words are, so reading only matters if there's nothing to show yet.
        if book.issueCount == 0 {
            if book.cantReachT3 { return [.note(CatWords.cantReachT3Yet)] }
            if book.isReading { return [.note(CatWords.readingMessages)] }
        }
        return statusNotes(of: book) + book.issues.flatMap { issues -> [ChannelRow] in
            guard let status = book.status(of: .kitten(issues.kitten.id)) else { return [] }
            let open: [ChannelRow] = issues.threads.isEmpty ? [.note(CatWords.nothingOpen)] : issues.threads.map(ChannelRow.issue)
            return [.heading(status)] + open
        }
    }

    private static func messages(in id: ChannelID, of book: ChannelBook) -> [ChannelRow] {
        guard let channel = book.channel(id), !channel.messages.isEmpty else { return [emptyNote(id, in: book)] }
        var rows: [ChannelRow] = channel.isCut ? [.note(CatWords.olderMessages)] : []
        var lastDay = Date.distantPast
        var lastThread: String?
        for message in channel.messages {
            // An exchange sits where it finished, so its ask can be older than the row above. Days only go forward.
            let day = Calendar.current.startOfDay(for: message.at)
            if day > lastDay {
                rows.append(.day(day))
                lastDay = day
            }
            if message.threadID != lastThread {
                rows.append(.subject(message.threadTitle, threadID: message.threadID))
                lastThread = message.threadID
            }
            rows.append(.message(message))
        }
        return rows + statusNotes(of: book)
    }

    private static func emptyNote(_ id: ChannelID, in book: ChannelBook) -> ChannelRow {
        let others = book.others(in: id)
        if let planned = others.lazy.compactMap({ book.status(of: $0) }).first(where: { $0.state == .notSetUp }) {
            return .note(CatWords.notSetUpYet(planned.kitten))
        }
        if book.cantReachT3 { return .note(CatWords.cantReachT3Yet) }
        if book.isReading { return .note(CatWords.readingMessages) }
        if book.unreadable > 0 { return .note(CatWords.couldntRead(book.unreadable)) }
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
