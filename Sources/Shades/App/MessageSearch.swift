import Foundation

/// A message Search found: its words around what you typed, and where it opens.
struct FoundMessage: Equatable {
    var message: ChannelMessage
    /// Its thread beside the thread's channel, or for a message in no thread, the channel it's in.
    var selection: ChannelSelection
    /// Its words as they're shown, on one line, from a little before the first word you typed.
    var snippet: String
    /// Where each word you typed is in `snippet`, counted in UTF-16, as both the window and the phone's page count.
    var marks: [NSRange]
}

/// ⌘F and the phone's Search: every message Messages has read, Load older's included, that has every word you typed.
/// It reads the words a message shows, not the markdown they were written in, and keeps nothing.
enum MessageSearch {
    /// T3's own search takes no fewer letters.
    static let shortest = 2
    private static let before = 40
    private static let length = 140

    /// What you typed, word by word, or nothing until it's `shortest` letters long.
    static func words(in query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= shortest else { return [] }
        return trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Newest first, at most `limit`, and whether there were more. `opening` says where a message the window opens at
    /// a selection opens for whoever's searching, or `nil` if they can't see it, as on a phone.
    static func find(
        _ query: String,
        in book: ChannelBook,
        limit: Int,
        opening: (ChannelSelection) -> ChannelSelection? = { $0 }
    ) -> (found: [FoundMessage], more: Bool) {
        let words = words(in: query)
        guard !words.isEmpty, limit > 0 else { return ([], false) }
        let cores = words.map { $0.split { !($0.isLetter || $0.isNumber) }.map(String.init) }
        var found: [FoundMessage] = []
        var foundIDs: Set<String> = []
        for (message, selection) in said(in: book) {
            guard let text = message.text, !foundIDs.contains(message.id) else { continue }
            // Cheap first: the words, without the punctuation around them, have to be in what was written.
            // shortcut: a word split by markup, such as ma**rk**up, isn't found, so read every message if that matters.
            guard cores.allSatisfy({ $0.allSatisfy { has(text, $0) } }) else { continue }
            let plain = plain(text)
            guard words.allSatisfy({ has(plain, $0) }), let opens = opening(selection) else { continue }
            guard found.count < limit else { return (found, true) }
            let snippet = snippet(of: plain, around: words)
            foundIDs.insert(message.id)
            found.append(FoundMessage(message: message, selection: opens, snippet: snippet, marks: marks(of: words, in: snippet)))
        }
        return (found, false)
    }

    /// Every message with words, newest first, with where the window opens it. A message in a channel comes before
    /// the same one in a thread, so the cat's answer in #general opens there rather than in its DM.
    private static func said(in book: ChannelBook) -> [(ChannelMessage, ChannelSelection)] {
        let loose = book.channels.flatMap { channel in
            channel.posts.compactMap { post -> (ChannelMessage, ChannelSelection)? in
                guard case .message(let message) = post else { return nil }
                return (message, .channel(channel.id))
            }
        }
        let threaded = book.threads.values.flatMap { thread in
            thread.messages.map { ($0, ChannelSelection.thread(thread.id, in: .channel(thread.home))) }
        }
        let all = (loose + threaded).enumerated().filter { $0.element.0.text != nil }
        return all.sorted { a, b in
            if a.element.0.at != b.element.0.at { return a.element.0.at > b.element.0.at }
            return a.offset < b.offset
        }.map(\.element)
    }

    private static func has(_ text: String, _ word: String) -> Bool {
        text.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// A message's words as they're shown, without the markdown they were written in, on one line.
    static func plain(_ text: String) -> String {
        let blocks = Markup(text).blocks.map { block -> String in
            let spans = block.spans.map { $0.map(\.text).joined() } ?? ""
            let cells = block.rows.map { $0.flatMap { $0.map { $0.map(\.text).joined() } }.joined(separator: " ") } ?? ""
            return [spans, block.code ?? "", cells].joined(separator: " ")
        }
        return blocks.joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// From a little before the first word you typed, starting on a word, with … where it's cut.
    private static func snippet(of plain: String, around words: [String]) -> String {
        let first = words.compactMap { plain.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive])?.lowerBound }.min() ?? plain.startIndex
        var start = plain.index(first, offsetBy: -before, limitedBy: plain.startIndex) ?? plain.startIndex
        if start > plain.startIndex, let space = plain[start..<first].firstIndex(of: " ") { start = plain.index(after: space) }
        let end = plain.index(start, offsetBy: length, limitedBy: plain.endIndex) ?? plain.endIndex
        return (start > plain.startIndex ? "…" : "") + plain[start..<end] + (end < plain.endIndex ? "…" : "")
    }

    private static func marks(of words: [String], in snippet: String) -> [NSRange] {
        var marks: [NSRange] = []
        for word in words {
            var from = snippet.startIndex
            while let range = snippet.range(of: word, options: [.caseInsensitive, .diacriticInsensitive], range: from..<snippet.endIndex) {
                marks.append(NSRange(range, in: snippet))
                from = range.upperBound
            }
        }
        return marks.sorted { $0.location < $1.location }
    }
}
