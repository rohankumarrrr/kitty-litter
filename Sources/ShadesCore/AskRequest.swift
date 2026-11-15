import Foundation
import NaturalLanguage

/// Something a kitten needs your yes for and then does itself, such as merging or sending something. It writes one in
/// a `shades-request` block, or Shades reads one from what it said in plain words. Either way the card shows exactly
/// what it would do, and that's all Allow says yes to.
public struct AskRequest: Codable, Equatable, Sendable {
    /// Exactly what the kitten would do on your yes, in one plain sentence.
    public var ask: String
    /// The kitten's reason, in its own words, from a block it wrote.
    public var why: String?
    /// What Shades made of it, or `nil` if it couldn't look.
    public var review: String?
    /// Shades read it from what the kitten said in plain words, rather than the kitten writing it in the form.
    public var readFromWords: Bool

    public init(ask: String, why: String? = nil, review: String? = nil, readFromWords: Bool) {
        self.ask = ask
        self.why = why
        self.review = review
        self.readFromWords = readFromWords
    }

    /// What Shades read from a kitten's decision: exactly what it would do on a yes, and what Shades would do.
    /// `nil` when there's nothing for the kitten to do on a yes, or the reply doesn't say it in exactly one sentence.
    public init?(readingDecision reply: String) {
        let lines = reply.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        let asks = lines.filter { $0.hasPrefix(Prompts.askMarker) }
        guard asks.count == 1 else { return nil }
        let ask = asks[0].dropFirst(Prompts.askMarker.count).trimmingCharacters(in: .whitespaces)
        // As the sorter reads "none", whatever its case or the full stop after it.
        let none = ask.trimmingCharacters(in: CharacterSet(charactersIn: " .")).lowercased() == "none"
        guard !ask.isEmpty, !none, ask.count <= ChangeRequests.askLimit, !ChangeRequests.hides(text: ask), Self.sentences(in: ask) == 1 else { return nil }
        let recommends = lines.drop { !$0.hasPrefix(Prompts.recommendMarker) }
        let review = recommends.joined(separator: " ").dropFirst(Prompts.recommendMarker.count).trimmingCharacters(in: .whitespaces)
        self.init(ask: ask, review: review.isEmpty ? nil : review, readFromWords: true)
    }

    /// Two sentences can be two things to say yes to, so a reading has to be one.
    static func sentences(in text: String) -> Int {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex).count
    }
}
