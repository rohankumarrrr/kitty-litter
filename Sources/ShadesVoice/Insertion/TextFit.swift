import Foundation

/// Fits dictated text to what's around the cursor: a space where one's needed, no capital mid-sentence.
enum TextFit {
    static func fit(_ text: String, before: String?, after: String?) -> String {
        var result = text
        guard !result.isEmpty else { return result }

        if let before, !before.isEmpty {
            let lastSolid = before.last(where: { !$0.isWhitespace })
            if let lastSolid, !".!?:\n".contains(lastSolid), !hasNewlineTail(before), !startsWithKeptCapital(result) {
                result = result.prefix(1).lowercased() + result.dropFirst()
            }
            if let last = before.last, !last.isWhitespace, !"([{\"'“‘/-".contains(last), !isPunctuationStart(result) {
                result = " " + result
            }
        }

        if let after, let next = after.first, !next.isNewline {
            // Text in the middle of a line doesn't get its own full stop.
            if result.hasSuffix("."), !hasListShape(result) {
                result.removeLast()
            }
            if !next.isWhitespace, !".,;:!?)]}\"'”’".contains(next) {
                result += " "
            }
        }
        return result
    }

    private static func hasNewlineTail(_ text: String) -> Bool {
        text.last(where: { !($0 == " " || $0 == "\t") })?.isNewline ?? true
    }

    private static func isPunctuationStart(_ text: String) -> Bool {
        text.first.map { ".,;:!?)]}".contains($0) } ?? false
    }

    private static func hasListShape(_ text: String) -> Bool { text.contains("\n") }

    /// "I", acronyms and names keep their capitals. Everyday first words don't.
    private static func startsWithKeptCapital(_ text: String) -> Bool {
        guard let word = text.split(whereSeparator: { $0.isWhitespace }).first else { return true }
        let core = word.trimmingCharacters(in: .punctuationCharacters)
        if core == "I" || core.hasPrefix("I'") || core.hasPrefix("I’") { return true }
        if core.dropFirst().contains(where: \.isUppercase) || core.contains(where: \.isNumber) { return true }
        return !everydayStarters.contains(core.lowercased())
    }

    private static let everydayStarters: Set<String> = [
        "a", "an", "the", "and", "but", "or", "so", "if", "then", "when", "while", "because", "that", "this", "these",
        "those", "it", "it's", "we", "we're", "you", "you're", "they", "they're", "he", "she", "there", "here", "to",
        "for", "of", "in", "on", "at", "with", "by", "from", "as", "not", "also", "maybe", "just", "can", "could",
        "should", "would", "will", "what", "why", "how", "which", "who", "where", "let's", "please", "okay", "yes", "no",
        "my", "our", "your", "their", "his", "her", "its", "one", "some", "all", "any", "each", "every", "have", "has",
        "had", "do", "does", "did", "is", "are", "was", "were", "be", "been", "actually", "really", "still", "now",
    ]
}
