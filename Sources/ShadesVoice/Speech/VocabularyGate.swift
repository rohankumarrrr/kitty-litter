import CoreServices
import Foundation

/// Words the system dictionary knows, in any case.
enum EverydayWords {
    static func contains(_ word: String) -> Bool {
        let lowered = word.lowercased() as CFString
        return DCSCopyTextDefinition(nil, lowered, CFRange(location: 0, length: CFStringGetLength(lowered))) != nil
    }
}

/// A last check on vocabulary replacements. The recognizer can be talked into odd swaps, such as "2 plus"
/// into "Opus" just because the sounds overlap, and a wrong word is worse than a misspelled name.
enum VocabularyGate {
    /// Whether what was heard could really be the listed word.
    static func allows(heard: String, term: String, isEveryday: (String) -> Bool = EverydayWords.contains) -> Bool {
        let heardLetters = compact(heard)
        let termLetters = compact(term)
        guard !heardLetters.isEmpty, !termLetters.isEmpty else { return false }

        // "fluid audio", "work tree", "copulet money": nearly the same spelling.
        let longest = max(heardLetters.count, termLetters.count)
        let similarity = 1 - Double(CleanupGuard.editDistance(heardLetters, termLetters)) / Double(longest)
        if similarity >= 0.75 { return true }

        // Otherwise the words have to look misheard, not like ordinary words that were said on purpose.
        let words = heard.split(whereSeparator: { $0.isWhitespace })
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        return !words.contains { word in
            word.allSatisfy(\.isNumber) || (word.allSatisfy(\.isLetter) && isEveryday(word))
        }
    }

    /// `base` with only the believable replacements applied.
    static func apply(
        replacements: [(heard: String, term: String)],
        to base: String,
        allowed: (String, String) -> Bool = { allows(heard: $0, term: $1) }
    ) -> String {
        var result = base
        for replacement in replacements where allowed(replacement.heard, replacement.term) {
            if let range = result.range(of: replacement.heard, options: .caseInsensitive) {
                result.replaceSubrange(range, with: replacement.term)
            }
        }
        return result
    }

    private static func compact(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
