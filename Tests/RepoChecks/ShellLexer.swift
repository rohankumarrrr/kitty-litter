import Foundation

struct ShellLexer {
    private(set) var comments: [SourceComment] = []

    init(_ source: String) {
        var heredocEnds: [(word: String, indented: Bool)] = []
        var insideHeredoc: (word: String, indented: Bool)?
        for (index, line) in source.components(separatedBy: "\n").enumerated() {
            let number = index + 1
            if let heredoc = insideHeredoc {
                let end = heredoc.indented ? line.trimmingCharacters(in: .whitespaces) : line
                if end == heredoc.word { insideHeredoc = heredocEnds.isEmpty ? nil : heredocEnds.removeFirst() }
                continue
            }
            if number == 1, line.hasPrefix("#!") { continue }
            let scanned = Self.scan(line)
            if let comment = scanned.comment { comments.append(SourceComment(line: number, text: comment)) }
            heredocEnds += scanned.heredocs
            if insideHeredoc == nil, !heredocEnds.isEmpty { insideHeredoc = heredocEnds.removeFirst() }
        }
    }

    private static func scan(_ line: String) -> (comment: String?, heredocs: [(word: String, indented: Bool)]) {
        let characters = Array(line)
        var heredocs: [(word: String, indented: Bool)] = []
        var single = false
        var double = false
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if single {
                if character == "'" { single = false }
            } else if character == "\\" {
                index += 1
            } else if character == "'", !double {
                single = true
            } else if character == "\"" {
                double.toggle()
            } else if !double, character == "#", index == 0 || " \t;|&(".contains(characters[index - 1]) {
                return (String(characters[index...]), heredocs)
            } else if !double, line.dropFirst(index).hasPrefix("<<<") {
                index += 3
                continue
            } else if !double, line.dropFirst(index).hasPrefix("<<") {
                index += 2
                let indented = index < characters.count && characters[index] == "-"
                if indented { index += 1 }
                while index < characters.count, characters[index] == " " { index += 1 }
                let word = characters[index...].prefix { !" \t;|&)<>".contains($0) }
                heredocs.append((String(word).trimmingCharacters(in: CharacterSet(charactersIn: "'\"")), indented))
                index += word.count
                continue
            }
            index += 1
        }
        return (nil, heredocs)
    }
}
