import Foundation

/// Decides whether cleaned text is still what was said. A cleanup that adds, answers or drops too much is thrown out.
public enum CleanupGuard {
    public enum Verdict: Equatable {
        case accept
        case invented(String)
        case droppedTooMuch(String)
        case tooDifferent(String)

        public var isAccepted: Bool { self == .accept }
    }

    public static func check(raw: String, cleaned: String) -> Verdict {
        let source = comparable(raw)
        let result = comparable(cleaned)

        if result.isEmpty {
            return RuleCleaner.isOnlyFillers(raw) || source.isEmpty ? .accept : .droppedTooMuch("nothing left")
        }

        // New words. Numbers are exempt because "twenty three" can come back as "23".
        let sourceCounts = counts(source)
        var remaining = sourceCounts
        var added: [String] = []
        for word in result {
            if let left = remaining[word], left > 0 {
                remaining[word] = left - 1
            } else if !harmless.contains(word), !isNumeric(word), !isCloseToAny(word, in: sourceCounts.keys) {
                added.append(word)
            }
        }
        let allowedAdditions = max(1, result.count / 8)
        if added.count > allowedAdditions || (source.count <= 8 && !added.isEmpty) {
            return .invented(added.joined(separator: " "))
        }

        // Growth beyond what punctuation and "going to" explain usually means an answer.
        if result.count > source.count + max(2, source.count / 5) {
            return .invented("\(source.count) words became \(result.count)")
        }

        // Lost words. Corrections and fillers remove plenty on purpose, so they get more room.
        let lost = source.filter { word in
            guard !removable.contains(word), !isNumeric(word) else { return false }
            return (counts(result)[word] ?? 0) == 0
        }
        let allowed = hasCorrection(raw) ? 0.55 : 0.3
        let budget = max(source.count <= 6 ? 2 : 1, Int(Double(source.count) * allowed))
        if lost.count > budget {
            return .droppedTooMuch(lost.joined(separator: " "))
        }

        // Same words shuffled into a different sentence.
        let longestShared = longestCommonSubsequence(source, result)
        if Double(longestShared) < Double(result.count) * 0.6 {
            return .tooDifferent("only \(longestShared) of \(result.count) in order")
        }
        return .accept
    }

    static func comparable(_ text: String) -> [String] {
        WordList.parse(text.replacingOccurrences(of: "\n", with: " ")).flatMap { word -> [String] in
            // An address comes back joined up: "rohan at example dot com" as "rohan@example.com".
            word.key.split(whereSeparator: { "@./-".contains($0) }).flatMap { piece -> [String] in
                let key = String(piece)
                return spokenForms[key] ?? [key]
            }
        }
    }

    private static let spokenForms: [String: [String]] = [
        "gonna": ["going", "to"], "wanna": ["want", "to"], "gotta": ["got", "to"], "kinda": ["kind", "of"],
        "sorta": ["sort", "of"], "lemme": ["let", "me"], "gimme": ["give", "me"], "cuz": ["because"], "cause": ["because"],
        "ok": ["okay"], "yep": ["yes"], "yup": ["yes"],
    ]

    /// Words a good cleanup may add, such as for "going to" or a list's opening.
    private static let harmless: Set<String> = [
        "a", "an", "the", "and", "to", "of", "is", "are", "be", "have", "had", "it", "that", "so", "for", "in", "at",
        "on", "with", "i", "going", "dollars", "percent", "pm", "am", "p.m", "a.m",
    ]

    /// Words a good cleanup may remove without it counting against it.
    private static let removable: Set<String> = [
        "um", "umm", "uh", "uhh", "uhm", "er", "erm", "hm", "hmm", "mm", "mhm", "like", "you", "know", "so", "well",
        "basically", "actually", "literally", "just", "i", "mean", "no", "wait", "sorry", "okay", "yeah", "right",
        "the", "a", "an", "and", "but", "or", "rather", "make", "that", "scratch", "new", "line", "paragraph", "bullet",
        "point", "number", "first", "second", "third", "fourth", "fifth", "dollars", "percent", "at", "dot",
    ]

    private static let correctionWords: Set<String> = ["no", "actually", "mean", "sorry", "wait", "rather", "scratch", "make"]

    private static func hasCorrection(_ raw: String) -> Bool {
        comparable(raw).contains(where: correctionWords.contains)
    }

    private static func counts(_ words: [String]) -> [String: Int] {
        words.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    private static func isNumeric(_ word: String) -> Bool {
        word.contains(where: \.isNumber) || WordList.isNumber(word)
    }

    /// Spelling fixes, inflection and joined words, such as "git hub" as "github".
    private static func isCloseToAny<S: Sequence>(_ word: String, in words: S) -> Bool where S.Element == String {
        guard word.count >= 4 else { return false }
        return words.contains { other in
            if other.hasPrefix(word) || word.hasPrefix(other), min(other.count, word.count) >= 3 { return true }
            let limit = max(1, min(word.count, other.count) / 4)
            return abs(other.count - word.count) <= limit && editDistance(word, other, limit: limit) <= limit
        }
    }

    static func editDistance(_ a: String, _ b: String, limit: Int = .max) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var row = Array(0...b.count)
        for i in a.indices {
            var previous = row[0]
            row[0] = i + 1
            for j in b.indices {
                let saved = row[j + 1]
                row[j + 1] = min(row[j + 1] + 1, row[j] + 1, previous + (a[i] == b[j] ? 0 : 1))
                previous = saved
            }
        }
        return row[b.count]
    }

    private static func longestCommonSubsequence(_ a: [String], _ b: [String]) -> Int {
        var row = [Int](repeating: 0, count: b.count + 1)
        for x in a {
            var previous = 0
            for (j, y) in b.enumerated() {
                let saved = row[j + 1]
                row[j + 1] = x == y ? previous + 1 : max(row[j + 1], row[j])
                previous = saved
            }
        }
        return row[b.count]
    }
}
