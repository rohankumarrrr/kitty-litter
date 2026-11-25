import Foundation

struct PhoneFound: Encodable, Equatable {
    struct Message: Encodable, Equatable {
        var id: String
        var open: String
        var name: String
        var detail: String
        var text: String
        var marks: [[Int]]
    }

    static let limit = 20

    var found: [Message]
    var more: Bool

    init(_ words: String, in book: ChannelBook, now: Date, reading plainWords: PlainWords = PlainWords()) {
        var shown: [String: Set<String>] = [:]
        let (found, more) = MessageSearch.find(words, in: book, limit: Self.limit, reading: plainWords) { message, selection in
            guard let opens = PhonePlace.opening(selection, in: book) else { return nil }
            let key = PhonePlace.key(opens)
            let messages = shown[key] ?? Set(PhoneView.shown(opens, in: book).compactMap(\.messageID))
            shown[key] = messages
            return messages.contains(message.id) ? opens : nil
        }
        self.found = found.map { found in
            let item = JumpItem(found, in: book, now: now) { PhoneView.title(ofThread: $0, book.title(ofThread: $0), in: book) }
            return Message(id: found.message.id, open: PhonePlace.key(found.selection), name: item.title, detail: item.detail ?? "", text: found.snippet, marks: found.marks.map { [$0.location, $0.length] })
        }
        self.more = more
    }
}
