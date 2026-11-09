import Foundation

/// What Search on a phone found: only messages a phone can open, each with the key of where it opens. It's worked out
/// from what Messages on the Mac has read, and T3 isn't asked, so a phone never leads Messages to read anything.
struct PhoneFound: Encodable, Equatable {
    struct Message: Encodable, Equatable {
        /// `ChannelMessage.id`, which the page scrolls to once it's there.
        var id: String
        var open: String
        var name: String
        var detail: String
        var text: String
        /// Where each word you typed is in `text`, as a start and a length in UTF-16, which is how a page counts.
        var marks: [[Int]]
    }

    static let limit = 20

    var found: [Message]
    var more: Bool

    init(_ words: String, in book: ChannelBook, now: Date, reading plainWords: PlainWords = PlainWords()) {
        let (found, more) = MessageSearch.find(words, in: book, limit: Self.limit, reading: plainWords) { PhonePlace.opening($0, in: book) }
        self.found = found.map { found in
            let item = JumpItem(found, in: book, now: now)
            return Message(id: found.message.id, open: PhonePlace.key(found.selection), name: item.title, detail: item.detail ?? "", text: found.snippet, marks: found.marks.map { [$0.location, $0.length] })
        }
        self.more = more
    }
}
