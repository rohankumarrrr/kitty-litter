import Foundation
import NaturalLanguage

public struct AskRequest: Codable, Equatable, Sendable {
    public var ask: String
    public var why: String?
    public var review: String?
    public var readFromWords: Bool

    public init(ask: String, why: String? = nil, review: String? = nil, readFromWords: Bool) {
        self.ask = ask
        self.why = why
        self.review = review
        self.readFromWords = readFromWords
    }

    public init?(readingDecision reply: String) {
        let lines = reply.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        let asks = lines.filter { $0.hasPrefix(Prompts.askMarker) }
        guard asks.count == 1 else { return nil }
        let ask = asks[0].dropFirst(Prompts.askMarker.count).trimmingCharacters(in: .whitespaces)
        let none = ask.trimmingCharacters(in: CharacterSet(charactersIn: " .")).lowercased() == "none"
        guard !ask.isEmpty, !none, ask.count <= ChangeRequests.askLimit, !ChangeRequests.hides(text: ask), Self.sentences(in: ask) == 1 else { return nil }
        let recommends = lines.drop { !$0.hasPrefix(Prompts.recommendMarker) }
        let review = recommends.joined(separator: " ").dropFirst(Prompts.recommendMarker.count).trimmingCharacters(in: .whitespaces)
        self.init(ask: ask, review: review.isEmpty ? nil : review, readFromWords: true)
    }

    static func sentences(in text: String) -> Int {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex).count
    }
}
