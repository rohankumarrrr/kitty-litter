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

/// Each message's words without their markdown, read once, since reading markdown is slow and a message's words don't
/// change. It reads ahead off the main thread while Messages is open, so a search seldom waits on it. It's in memory
/// only, and keeps just the messages of the last book it saw.
final class PlainWords: @unchecked Sendable {
    struct Words {
        var text: String
        var plain: String
        /// Without case or accents, which is what a search compares.
        var folded: String

        init(_ text: String) {
            self.text = text
            plain = MessageSearch.plain(text)
            folded = MessageSearch.fold(plain)
        }
    }

    private let lock = NSLock()
    private var kept: [String: Words] = [:]
    private var _reads = 0
    private var ahead: Task<Void, Never>?

    /// How many messages' markdown it has read.
    var reads: Int { lock.withLock { _reads } }

    deinit {
        ahead?.cancel()
    }

    /// Reads what it hasn't of this book in the background, and lets go of what isn't in it.
    func readAhead(_ book: ChannelBook) {
        let said = MessageSearch.said(in: book)
        keep(only: Set(said.map(\.0.id)))
        let unread = said.compactMap { message, _ in message.text.flatMap { known(message.id, $0) == nil ? (message.id, $0) : nil } }
        ahead?.cancel()
        guard !unread.isEmpty else { return }
        ahead = Task.detached(priority: .utility) { [weak self] in
            for (id, text) in unread where !Task.isCancelled {
                self?.store(id, Words(text))
            }
        }
    }

    fileprivate func known(_ id: String, _ text: String) -> Words? {
        lock.withLock { kept[id].flatMap { $0.text == text ? $0 : nil } }
    }

    fileprivate func read(_ id: String, _ text: String) -> Words {
        let words = Words(text)
        store(id, words)
        return words
    }

    private func store(_ id: String, _ words: Words) {
        lock.withLock {
            _reads += 1
            kept[id] = words
        }
    }

    fileprivate func keep(only ids: Set<String>) {
        lock.withLock { kept = kept.filter { ids.contains($0.key) } }
    }
}

/// ⌘F and the phone's Search: every message Messages has read, Load older's included, that has every word you typed.
/// It reads the words a message shows, not the markdown they were written in, and keeps nothing but those words.
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
    /// a selection opens for whoever's searching, or `nil` if they can't see it there, as on a phone.
    static func find(
        _ query: String,
        in book: ChannelBook,
        limit: Int,
        reading plainWords: PlainWords = PlainWords(),
        opening: (ChannelMessage, ChannelSelection) -> ChannelSelection? = { $1 }
    ) -> (found: [FoundMessage], more: Bool) {
        let typed = words(in: query)
        guard !typed.isEmpty, limit > 0 else { return ([], false) }
        let folded = typed.map(fold)
        let cores = typed.map { $0.split { !($0.isLetter || $0.isNumber) }.map(String.init) }
        let said = said(in: book)
        plainWords.keep(only: Set(said.map(\.0.id)))
        var found: [FoundMessage] = []
        var foundIDs: Set<String> = []
        for (message, selection) in said {
            guard let text = message.text, !foundIDs.contains(message.id) else { continue }
            let shown: PlainWords.Words
            if let known = plainWords.known(message.id, text) {
                shown = known
            } else {
                // Cheap first: the words, without the punctuation around them, have to be in what was written.
                // shortcut: a word split by markup, such as ma**rk**up, isn't found, so read every message if that matters.
                guard cores.allSatisfy({ $0.allSatisfy { has(text, $0) } }) else { continue }
                shown = plainWords.read(message.id, text)
            }
            guard folded.allSatisfy({ shown.folded.range(of: $0, options: .literal) != nil }), let opens = opening(message, selection) else { continue }
            guard found.count < limit else { return (found, true) }
            let snippet = snippet(of: shown.plain, around: typed)
            foundIDs.insert(message.id)
            found.append(FoundMessage(message: message, selection: opens, snippet: snippet, marks: marks(of: typed, in: snippet)))
        }
        return (found, false)
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Every message with words, newest first, with where the window opens it. A message in a channel comes before
    /// the same one in a thread, so a reply also sent to a channel opens there.
    fileprivate static func said(in book: ChannelBook) -> [(ChannelMessage, ChannelSelection)] {
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
        // Words that overlap, such as "silk" and "silkscreen", are one mark, so neither hides the other.
        return marks.sorted { $0.location < $1.location }.reduce(into: []) { merged, mark in
            if let last = merged.last, mark.location <= NSMaxRange(last) {
                merged[merged.count - 1] = NSUnionRange(last, mark)
            } else {
                merged.append(mark)
            }
        }
    }
}
