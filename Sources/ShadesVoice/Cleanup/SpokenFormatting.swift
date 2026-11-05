import Foundation

/// Turns spoken layout into real layout: "new line", "bullet point", "first, second, third".
enum SpokenFormatting {
    static func apply(to text: String) -> String {
        var result = applyEndMarks(text)
        result = applyLineBreaks(result)
        if let list = bulletList(result) { return list }
        if let list = numberedList(result) { return list }
        if let list = ordinalList(result) { return list }
        return result
    }

    /// List lines read better without a full stop, and a model tends to add one.
    static func tidyListLines(_ text: String) -> String {
        guard text.contains("\n") else { return text }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let isItem = line.hasPrefix("- ") || line.range(of: #"^\d+\. "#, options: .regularExpression) != nil
            return isItem && line.hasSuffix(".") ? String(line.dropLast()) : String(line)
        }.joined(separator: "\n")
    }

    // MARK: - Marks

    /// Only at the very end, because "question mark" mid-sentence is usually about the mark itself.
    private static func applyEndMarks(_ text: String) -> String {
        var words = WordList.parse(text)
        guard words.count >= 3 else { return text }
        let tail = words.suffix(2).map(\.key)
        let mark: String
        switch tail {
        case ["question", "mark"]: mark = "?"
        case ["exclamation", "point"], ["exclamation", "mark"]: mark = "!"
        case ["full", "stop"]: mark = "."
        default: return text
        }
        words.removeLast(2)
        words[words.count - 1].trailing = mark
        return WordList.render(words)
    }

    /// Words that make "new line" or "new paragraph" part of a sentence rather than a command.
    private static let beforeRealPhrase: Set<String> = [
        "a", "an", "the", "this", "that", "each", "every", "one", "another", "any", "per", "my", "your", "our", "their",
        "add", "insert", "start", "for", "with", "and", "or", "of", "to",
    ]

    private static func applyLineBreaks(_ text: String) -> String {
        let words = WordList.parse(text)
        guard words.count >= 3 else { return text }
        var result = ""
        var i = 0
        var capitalize = false
        while i < words.count {
            var word = words[i]
            if capitalize {
                word.capitalize()
                capitalize = false
            }
            if i + 1 < words.count, word.key == "new", let gap = lineBreak(for: words[i + 1].key),
               i > 0, i + 2 < words.count, !beforeRealPhrase.contains(words[i - 1].key),
               words[i - 1].hasPause || words[i + 1].hasPause {
                while result.hasSuffix(" ") { result.removeLast() }
                result += gap
                capitalize = true
                i += 2
                continue
            }
            result += word.rendered
            if i + 1 < words.count { result += " " }
            i += 1
        }
        return result
    }

    private static func lineBreak(for key: String) -> String? {
        switch key {
        case "line": return "\n"
        case "paragraph": return "\n\n"
        default: return nil
        }
    }

    // MARK: - Lists

    /// A list needs at least this many items, so an ordinary "bullet point" or "first" stays in the sentence.
    private static let minimumItems = 2

    private static func bulletList(_ text: String) -> String? {
        let pieces = split(text, onPhrase: ["bullet", "point"])
        guard let pieces, pieces.items.count >= minimumItems else { return nil }
        return join(lead: pieces.lead, items: pieces.items.map { "- \(item($0))" })
    }

    private static func numberedList(_ text: String) -> String? {
        let words = WordList.parse(text)
        let names = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        var marks: [Int] = []
        var expected = 0
        var i = 0
        while i + 1 < words.count, expected < names.count {
            let isMark = words[i].key == "number"
                && (words[i + 1].key == names[expected] || words[i + 1].key == String(expected + 1))
            if isMark {
                marks.append(i)
                expected += 1
                i += 2
            } else {
                i += 1
            }
        }
        guard marks.count >= minimumItems else { return nil }
        return list(words: words, marks: marks, markLength: 2) { "\($0 + 1). \($1)" }
    }

    private static func ordinalList(_ text: String) -> String? {
        let words = WordList.parse(text)
        let order = [["first", "firstly"], ["second", "secondly"], ["third", "thirdly"], ["fourth", "fourthly"], ["fifth", "fifthly"]]
        let lastWords = ["finally", "lastly", "last"]
        var marks: [Int] = []
        for i in words.indices {
            // Evidence that it opens a clause, unlike "the first thing".
            let opens = i == 0 || words[i - 1].hasPause
            guard opens, words[i].trailing == "," || i == 0 || words[i - 1].endsSentence else { continue }
            if marks.count < order.count, order[marks.count].contains(words[i].key) {
                marks.append(i)
            } else if marks.count >= 2, lastWords.contains(words[i].key) {
                marks.append(i)
                break
            }
        }
        guard marks.count >= 3 else { return nil }
        return list(words: words, marks: marks, markLength: 1) { "\($0 + 1). \($1)" }
    }

    private static func list(
        words: [SpokenWord],
        marks: [Int],
        markLength: Int,
        line: (Int, String) -> String
    ) -> String? {
        var items: [String] = []
        for (index, mark) in marks.enumerated() {
            let start = mark + markLength
            let end = index + 1 < marks.count ? marks[index + 1] : words.count
            guard start < end else { return nil }
            items.append(line(index, item(WordList.render(Array(words[start..<end])))))
        }
        return join(lead: WordList.render(Array(words[..<marks[0]])), items: items)
    }

    private static func split(_ text: String, onPhrase phrase: [String]) -> (lead: String, items: [String])? {
        let words = WordList.parse(text)
        var marks: [Int] = []
        var i = 0
        while i + phrase.count <= words.count {
            if phrase.indices.allSatisfy({ words[i + $0].key == phrase[$0] }) {
                marks.append(i)
                i += phrase.count
            } else {
                i += 1
            }
        }
        guard let first = marks.first else { return nil }
        var items: [String] = []
        for (index, mark) in marks.enumerated() {
            let start = mark + phrase.count
            let end = index + 1 < marks.count ? marks[index + 1] : words.count
            guard start < end else { return nil }
            items.append(WordList.render(Array(words[start..<end])))
        }
        return (WordList.render(Array(words[..<first])), items)
    }

    private static func item(_ text: String) -> String {
        var words = WordList.parse(text)
        guard !words.isEmpty else { return text }
        words[0].capitalize()
        words[words.count - 1].trailing = words[words.count - 1].trailing.filter { "?!".contains($0) }
        return WordList.render(words)
    }

    private static func join(lead: String, items: [String]) -> String {
        guard !lead.isEmpty else { return items.joined(separator: "\n") }
        var words = WordList.parse(lead)
        // "Here are the next steps." and "To set it up," both become a line ending in a colon.
        if let last = words.indices.last { words[last].trailing = ":" }
        words[0].capitalize()
        return WordList.render(words) + "\n" + items.joined(separator: "\n")
    }
}
