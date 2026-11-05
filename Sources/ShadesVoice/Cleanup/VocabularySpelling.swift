import Foundation

/// Spells your listed words the way you spell them, however they were heard.
struct VocabularySpelling {
    private struct Rule {
        let pattern: NSRegularExpression
        let replacement: String
    }

    private let rules: [Rule]

    init(words: [String]) {
        rules = words.flatMap(Self.rules(for:))
    }

    func apply(to text: String) -> String {
        rules.reduce(text) { result, rule in
            let range = NSRange(result.startIndex..., in: result)
            return rule.pattern.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: rule.replacement)
            )
        }
    }

    private static func rules(for word: String) -> [Rule] {
        let word = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard word.count >= 2 else { return [] }
        // A listed word that's also everyday English keeps the case it came with, or "salt and pepper"
        // would turn into "salt and Pepper" because you have a project called Pepper.
        if isEverydayWord(word) { return [] }

        var patterns = [looseSpelling(of: word)]
        patterns += spokenDigits(of: word).map(exactPhrase)
        return patterns.compactMap { body in
            let pattern = "(?<![\\p{L}\\p{N}])" + body + "(?![\\p{L}\\p{N}])"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
            return Rule(pattern: regex, replacement: word)
        }
    }

    /// Any case, and spaces or hyphens anywhere in a longer word: "git hub", "fluid audio", "work tree".
    private static func looseSpelling(of word: String) -> String {
        let letters = word.filter { !$0.isWhitespace }.map { NSRegularExpression.escapedPattern(for: String($0)) }
        return letters.joined(separator: word.count >= 5 ? "[ -]?" : (word.count <= 3 ? "[ -]?" : ""))
    }

    private static func exactPhrase(_ phrase: String) -> String {
        phrase.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "[ -]")
    }

    /// "T3" spoken out: "T three", "tee three".
    private static func spokenDigits(of word: String) -> [String] {
        let names = ["0": "zero", "1": "one", "2": "two", "3": "three", "4": "four", "5": "five", "6": "six", "7": "seven", "8": "eight", "9": "nine"]
        guard word.count <= 4, word.contains(where: \.isNumber) else { return [] }
        var spoken: [String] = []
        for character in word {
            if let name = names[String(character)] {
                spoken.append(name)
            } else {
                spoken.append(String(character))
            }
        }
        var forms = [spoken.joined(separator: " ")]
        if spoken.first?.lowercased() == "t" {
            forms.append((["tee"] + spoken.dropFirst()).joined(separator: " "))
        }
        return forms
    }

    private static func isEverydayWord(_ word: String) -> Bool {
        guard word.allSatisfy(\.isLetter), word.dropFirst().allSatisfy(\.isLowercase) else { return false }
        return EverydayWords.contains(word)
    }
}
