import Foundation

struct FoundMessage: Equatable {
    var message: ChannelMessage
    var selection: ChannelSelection
    var snippet: String
    var marks: [NSRange]
}

final class PlainWords: @unchecked Sendable {
    struct Words {
        var text: String
        var plain: String
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

    var reads: Int { lock.withLock { _reads } }

    deinit {
        ahead?.cancel()
    }

    func readAhead(_ book: ChannelBook) {
        ahead?.cancel()
        ahead = Task.detached(priority: .utility) { [weak self] in
            let said = MessageSearch.said(in: book)
            self?.keep(only: Set(said.map(\.0.id)))
            for (message, _) in said where !Task.isCancelled {
                guard let self, let text = message.text, self.known(message.id, text) == nil else { continue }
                self.store(message.id, Words(text))
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

enum MessageSearch {
    static let shortest = 2
    private static let before = 40
    private static let length = 140

    static func words(in query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= shortest else { return [] }
        return trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
    }

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

    static func plain(_ text: String) -> String {
        let blocks = Markup(text).blocks.map { block -> String in
            let spans = block.spans.map { $0.map(\.text).joined() } ?? ""
            let cells = block.rows.map { $0.flatMap { $0.map { $0.map(\.text).joined() } }.joined(separator: " ") } ?? ""
            return [spans, block.code ?? "", cells].joined(separator: " ")
        }
        return blocks.joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

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
        return marks.sorted { $0.location < $1.location }.reduce(into: []) { merged, mark in
            if let last = merged.last, mark.location <= NSMaxRange(last) {
                merged[merged.count - 1] = NSUnionRange(last, mark)
            } else {
                merged.append(mark)
            }
        }
    }
}
