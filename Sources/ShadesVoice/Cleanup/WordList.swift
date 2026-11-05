import Foundation

/// A word with whatever punctuation was stuck to it, so edits can keep or move the punctuation.
struct SpokenWord: Equatable {
    var leading: String
    var text: String
    var trailing: String

    /// Lowercase with curly quotes straightened, for comparing.
    var key: String {
        text.lowercased().replacingOccurrences(of: "’", with: "'")
    }

    var endsSentence: Bool { trailing.contains(where: { ".?!".contains($0) }) }
    var hasPause: Bool { trailing.contains(where: { ",;:.?!—-".contains($0) }) }
    var isCapitalized: Bool { text.first?.isUppercase == true }

    var rendered: String { leading + text + trailing }

    mutating func capitalize() {
        guard let first = text.first, first.isLowercase else { return }
        text = first.uppercased() + text.dropFirst()
    }

    mutating func lowercaseFirst() {
        guard let first = text.first, first.isUppercase, text.dropFirst().allSatisfy({ !$0.isUppercase }) else { return }
        text = first.lowercased() + text.dropFirst()
    }
}

enum WordList {
    private static let edgePunctuation = CharacterSet.punctuationCharacters
        .subtracting(CharacterSet(charactersIn: "$%@#&'’_"))

    static func parse(_ text: String) -> [SpokenWord] {
        text.split(whereSeparator: \.isWhitespace).map { piece in
            var scalars = Substring(piece).unicodeScalars
            var leading = String.UnicodeScalarView()
            while let first = scalars.first, edgePunctuation.contains(first) {
                leading.append(first)
                scalars.removeFirst()
            }
            var trailing: [Unicode.Scalar] = []
            while let last = scalars.last, edgePunctuation.contains(last) {
                trailing.insert(last, at: 0)
                scalars.removeLast()
            }
            return SpokenWord(
                leading: String(leading),
                text: String(scalars),
                trailing: String(String.UnicodeScalarView(trailing))
            )
        }
    }

    static func render(_ words: [SpokenWord]) -> String {
        words.map(\.rendered).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static let numberWords: Set<String> = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve",
        "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty", "thirty", "forty",
        "fifty", "sixty", "seventy", "eighty", "ninety", "hundred", "thousand", "million", "billion", "half", "quarter",
    ]

    static func isNumber(_ key: String) -> Bool {
        numberWords.contains(key) || key.contains(where: \.isNumber)
    }

    private static let dayWords: Set<String> = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "today", "tomorrow", "yesterday",
        "tonight", "january", "february", "march", "april", "may", "june", "july", "august", "september", "october",
        "november", "december",
    ]

    static func isDay(_ key: String) -> Bool { dayWords.contains(key) }
}
