import Foundation

/// Tidies a transcript with fixed rules. It only deletes and reformats what was said, so it can't invent
/// anything, and it leaves alone whatever it isn't sure about.
public final class RuleCleaner: TextCleaning {
    public init() {}

    public func clean(_ raw: String) async -> String? { tidy(raw) }

    public func tidy(_ raw: String) -> String {
        var words = WordList.parse(raw)
        words = Self.removeFillers(words)
        words = Self.collapseStutters(words)
        words = Self.applyScratchThat(words)
        words = Self.applyCorrections(words)
        return Self.finish(words)
    }

    /// What's left to do after any other cleaner: spoken formatting, which rules can do reliably, and tidy edges.
    public func format(_ text: String) -> String {
        var result = SpokenFormatting.apply(to: text)
        result = Self.fixPronounI(result)
        result = SpokenFormatting.tidyListLines(result)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func finish(_ words: [SpokenWord]) -> String {
        var words = words
        guard !words.isEmpty else { return "" }
        words[0].capitalize()
        return SpokenFormatting.apply(to: fixPronounI(addEndPunctuation(WordList.render(words))))
    }

    // MARK: - Fillers

    private static let fillers: Set<String> = [
        "um", "umm", "ummm", "uh", "uhh", "uhhh", "uhm", "uhmm", "er", "erm", "hm", "hmm", "hmmm", "mm", "mmm", "mhm",
    ]

    /// Words that can only come before "you know" when it's a real question or clause.
    private static let beforeRealYouKnow: Set<String> = [
        "do", "did", "does", "if", "as", "what", "when", "that", "how", "don't", "didn't", "would", "could", "should",
        "will", "can", "let", "then", "because", "why", "where", "who", "and", "but",
    ]

    static func isOnlyFillers(_ text: String) -> Bool {
        let words = WordList.parse(text)
        return !words.isEmpty && removeFillers(words).isEmpty
    }

    static func removeFillers(_ input: [SpokenWord]) -> [SpokenWord] {
        var output: [SpokenWord] = []
        var i = 0
        var capitalizeNext = false

        func drop(_ dropped: SpokenWord) {
            // ", um," takes one comma with it, "think, um." moves its stop to the word before,
            // and "well, um I" keeps its comma.
            if !output.isEmpty {
                let ownEnd = dropped.trailing.filter { ".?!".contains($0) }
                if !ownEnd.isEmpty {
                    output[output.count - 1].trailing = ownEnd
                } else if dropped.trailing.contains(","), output[output.count - 1].trailing == "," {
                    output[output.count - 1].trailing = ""
                }
            }
            if dropped.isCapitalized || output.isEmpty { capitalizeNext = true }
        }

        while i < input.count {
            let word = input[i]
            var skip = 0
            if fillers.contains(word.key) {
                skip = 1
            } else if isFillerYouKnow(input, at: i) {
                skip = 2
            } else if isFillerLike(input, at: i) {
                skip = 1
            }
            if skip > 0 {
                var dropped = word
                dropped.trailing = input[i + skip - 1].trailing
                drop(dropped)
                i += skip
                continue
            }
            var kept = word
            if capitalizeNext {
                kept.capitalize()
                capitalizeNext = false
            }
            output.append(kept)
            i += 1
        }
        return output
    }

    private static func isFillerYouKnow(_ words: [SpokenWord], at i: Int) -> Bool {
        guard i + 1 < words.count, words[i].key == "you", words[i + 1].key == "know" else { return false }
        if i > 0, beforeRealYouKnow.contains(words[i - 1].key), !words[i - 1].hasPause { return false }
        // Followed by a clause with no pause, it's a real sentence: "you know the answer".
        return words[i + 1].hasPause || i + 2 == words.count
    }

    private static func isFillerLike(_ words: [SpokenWord], at i: Int) -> Bool {
        guard words[i].key == "like", i > 0, i + 1 < words.count else { return false }
        return words[i - 1].trailing == "," && words[i].trailing == ","
    }

    // MARK: - Stutters

    private static let realRepeats: Set<String> = [
        "that", "had", "no", "very", "really", "so", "bye", "hello", "hi", "hey", "yes", "yeah", "ha", "knock", "there",
        "pretty", "many", "much", "more", "now", "please", "wait", "go", "oh", "okay", "ok", "never", "far", "long",
        "night", "sorry", "thanks", "again", "what", "why", "cool", "nice", "right",
    ]

    /// "the the" and "we should we should" keep one copy.
    static func collapseStutters(_ input: [SpokenWord]) -> [SpokenWord] {
        var words = input
        var i = 0
        while i < words.count {
            var collapsed = false
            for length in stride(from: 3, through: 1, by: -1) where i + 2 * length <= words.count {
                let first = words[i..<(i + length)].map(\.key)
                let second = words[(i + length)..<(i + 2 * length)].map(\.key)
                guard first == second, !first.contains(where: WordList.isNumber) else { continue }
                if length == 1, realRepeats.contains(first[0]) { continue }
                let capitalized = words[i].isCapitalized
                words.removeSubrange(i..<(i + length))
                if capitalized { words[i].capitalize() }
                collapsed = true
                break
            }
            if !collapsed { i += 1 }
        }
        return words
    }

    // MARK: - Corrections

    private static let scratchMarkers: [[String]] = [
        ["scratch", "that"], ["strike", "that"], ["delete", "that"], ["forget", "that"],
    ]

    /// Throws away the sentence or clause before "scratch that".
    static func applyScratchThat(_ input: [SpokenWord]) -> [SpokenWord] {
        var words = input
        var i = 0
        while i + 1 < words.count {
            guard scratchMarkers.contains([words[i].key, words[i + 1].key]) else {
                i += 1
                continue
            }
            let start = clauseStart(in: words, before: i)
            guard start < i else {
                i += 2
                continue
            }
            words.removeSubrange(start..<(i + 2))
            if start < words.count, start == 0 || words[start - 1].endsSentence { words[start].capitalize() }
            i = start
        }
        return words
    }

    /// Where the clause before `index` begins. When `index` opens a sentence, that's the sentence before.
    private static func clauseStart(in words: [SpokenWord], before index: Int) -> Int {
        var i = index - 1
        guard i >= 0 else { return 0 }
        // Skip back over the clause's own closing punctuation.
        while i > 0 {
            if words[i - 1].endsSentence || words[i - 1].trailing.contains(",") { return i }
            i -= 1
        }
        return 0
    }

    /// Markers that are almost always a correction, in the order they're tried.
    private static let strongMarkers: [[String]] = [
        ["no", "wait", "actually"], ["no", "sorry", "i", "mean"], ["actually", "make", "that"], ["sorry", "i", "mean"],
        ["no", "i", "mean"], ["no", "wait"], ["wait", "no"], ["no", "actually"], ["no", "sorry"], ["or", "rather"],
        ["make", "that"],
    ]

    /// Markers that need a pause before them to count, since they're common words too.
    private static let weakMarkers: [[String]] = [["i", "mean"], ["actually"], ["sorry"], ["no"], ["rather"]]

    static func applyCorrections(_ input: [SpokenWord]) -> [SpokenWord] {
        var words = input
        var i = 1
        while i < words.count {
            guard let marker = markerLength(words, at: i), i + marker < words.count else {
                i += 1
                continue
            }
            let replacement = Array(words[(i + marker)...])
            guard let from = repairStart(left: Array(words[..<i]), right: replacement) else {
                i += 1
                continue
            }
            // Whatever closed the left side moved to where the correction ends.
            var fixed = Array(words[..<from])
            if from > 0, fixed[from - 1].trailing == "," { fixed[from - 1].trailing = "" }
            fixed.append(contentsOf: replacement)
            if from == 0 { fixed[0].capitalize() }
            words = fixed
            i = from + 1
        }
        return words
    }

    private static func markerLength(_ words: [SpokenWord], at i: Int) -> Int? {
        func matches(_ marker: [String]) -> Bool {
            guard i + marker.count <= words.count else { return false }
            return marker.indices.allSatisfy { words[i + $0].key == marker[$0] }
        }
        // Keeps "no wait" from eating a lone "wait" that belongs to the next word.
        if let strong = strongMarkers.first(where: matches) {
            return strong.count
        }
        guard words[i - 1].hasPause, let weak = weakMarkers.first(where: matches) else { return nil }
        return weak.count
    }

    /// Where in `left` the words replaced by `right` begin, or `nil` if the two don't line up.
    private static func repairStart(left: [SpokenWord], right: [SpokenWord]) -> Int? {
        guard let first = right.first, !left.isEmpty else { return nil }
        let window = max(0, left.count - 10)
        // "the settings page, I mean the profile page" restarts at the word they share.
        if let shared = (window..<left.count).last(where: { left[$0].key == first.key }) { return shared }
        // "five thousand dollars, no wait, six thousand dollars" lines up from the end.
        let clauseEnd = right.firstIndex(where: \.hasPause).map { $0 + 1 } ?? right.count
        let phrase = right[..<clauseEnd]
        if phrase.count >= 2, phrase.count <= left.count, phrase.last?.key == left.last?.key {
            return left.count - phrase.count
        }
        // Three for four, Tuesday for Wednesday, John for Mike.
        if WordList.isNumber(first.key) { return lastRun(in: left, from: window) { WordList.isNumber($0.key) } }
        if WordList.isDay(first.key) { return lastRun(in: left, from: window) { WordList.isDay($0.key) } }
        if first.isCapitalized, let last = left.last, last.isCapitalized, left.count > 1 {
            return lastRun(in: left, from: window) { $0.isCapitalized }
        }
        return nil
    }

    /// Start of the last run of words passing `test`, as long as that run is near the end.
    private static func lastRun(in words: [SpokenWord], from window: Int, _ test: (SpokenWord) -> Bool) -> Int? {
        guard let end = (window..<words.count).last(where: { test(words[$0]) }), words.count - end <= 3 else { return nil }
        var start = end
        while start > window, test(words[start - 1]) { start -= 1 }
        return start
    }

    // MARK: - Edges

    private static let questionOpeners: Set<String> = [
        "what", "why", "how", "when", "where", "who", "which", "whose", "is", "are", "am", "was", "were", "do", "does",
        "did", "can", "could", "would", "should", "will", "shall", "have", "has", "what's", "where's", "who's", "how's",
    ]

    private static func addEndPunctuation(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last, last.isLetter || last.isNumber else { return trimmed }
        let opener = trimmed.split(separator: " ").first.map { $0.lowercased() } ?? ""
        return trimmed + (questionOpeners.contains(opener) ? "?" : ".")
    }

    private static func fixPronounI(_ text: String) -> String {
        text.replacingOccurrences(of: #"\bi('(?:m|d|ll|ve|re|s))?\b"#, with: "I$1", options: .regularExpression)
    }
}
