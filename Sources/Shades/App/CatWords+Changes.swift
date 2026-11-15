import Foundation
import ShadesCore

/// How a settings change a kitten asked for is put to you.
extension CatWords {
    static let allowChangeOnMac = "Allow or deny it on your Mac."
    static let notReviewed = "I couldn't look into this one, so all there is to go on is the change itself."

    /// One plain paragraph, for your phone and the cat's bubble, which don't show the change itself.
    static func changeRow(_ change: ChangeRequest) -> String {
        guard !change.file.isEmpty else { return "Asked for a settings change The Kitty Litter can't read. \(change.problem ?? "")" }
        var parts = ["Asks to \(change.replace == nil ? "make" : "change") \(change.file)."]
        if !change.opensScreenBlock.isEmpty {
            parts.insert("This loosens a screen block.", at: 0)
        } else if !change.widens.isEmpty {
            parts.insert("This widens what agents can do.", at: 0)
        }
        if let problem = change.problem { parts.append("It can't be done as asked. \(problem)") }
        if let why = change.why { parts.append("Its reason: \(why)") }
        return parts.joined(separator: " ")
    }

    /// The card in Activity: what it loosens first, then exactly what would change, then the kitten's reason. Anything a
    /// kitten wrote shows as written, so none of it can pass for The Kitty Litter's own words.
    static func changeCard(_ change: ChangeRequest, by kitten: String) -> String {
        var parts: [String] = []
        if !change.opensScreenBlock.isEmpty {
            let taken = change.opensScreenBlock.map(ChangeRequests.code).joined(separator: ", ")
            parts.append("**This loosens the screen block in that folder**, which keeps agents there off your screen. It takes away \(taken).")
        }
        if !change.widens.isEmpty {
            parts.append("**This widens what agents can do.**\n\n" + change.widens.map { "- \($0)" }.joined(separator: "\n"))
        }
        if let problem = change.problem {
            parts.append("**This can't be done as asked.** \(literal(problem))")
        } else if !change.isLoosening {
            parts.append("This doesn't widen what agents can do.")
        }
        if !change.file.isEmpty {
            parts.append("\(change.replace == nil ? "Makes" : "Changes") \(ChangeRequests.code(change.file)):\n\n\(diff(change))")
        }
        if let why = change.why { parts.append("\(literal(kitten))'s reason: \(literal(why))") }
        return parts.joined(separator: "\n\n")
    }

    static func changeReview(_ change: ChangeRequest) -> String? {
        guard change.problem == nil else { return nil }
        return change.review.map { "I looked into it. \(literal($0))" } ?? notReviewed
    }

    /// An ask, for your phone and the cat's bubble: what Allow says yes to first, on lines of its own, then what the
    /// kitten wrote. Everything a kitten writes is one line, so it can't make the line breaks that set them apart.
    static func askRow(_ ask: AskRequest, decision: String? = nil, by kitten: String) -> String {
        let said = decision.map { "Its report said: “\($0)”" } ?? ask.why.map { "Its reason: “\($0)”" }
        return ["If you allow it, \(kitten) will:\n\(ask.ask)", said].compactMap { $0 }.joined(separator: "\n\n")
    }

    /// The card in Activity: what Allow says yes to first, in the app's own bold words, then what the kitten wrote, as
    /// written, so none of it can pass for The Kitty Litter's own words or come before them.
    static func askCard(_ ask: AskRequest, decision: String?, by kitten: String) -> String {
        let will = "**If you allow it, \(literal(kitten)) will:** \(literal(ask.ask))"
        let said = decision.map { "Its report said: “\(literal($0))”" } ?? ask.why.map { "\(literal(kitten))'s reason: “\(literal($0))”" }
        return [will, said].compactMap { $0 }.joined(separator: "\n\n")
    }

    static func askReview(_ ask: AskRequest) -> String? {
        ask.review.map { "I looked into it. \(literal($0))" } ?? (ask.readFromWords ? nil : notReviewed)
    }

    static func changeFailed(_ reason: String) -> String {
        "I couldn't make that change. \(reason)"
    }

    /// The lines that change, between any the old and new text share, which show as they are. A last newline is no line.
    private static func diff(_ change: ChangeRequest) -> String {
        func lines(_ text: String) -> [String] {
            let lines = text.components(separatedBy: "\n")
            return lines.last == "" ? Array(lines.dropLast()) : lines
        }
        let old = change.replace.map(lines) ?? []
        let new = lines(change.with)
        let head = zip(old, new).prefix { $0 == $1 }.count
        let tail = zip(old.dropFirst(head).reversed(), new.dropFirst(head).reversed()).prefix { $0 == $1 }.count
        let lines = old.prefix(head).map { "  \($0)" }
            + old.dropFirst(head).dropLast(tail).map { "- \($0)" }
            + new.dropFirst(head).dropLast(tail).map { "+ \($0)" }
            + old.suffix(tail).map { "  \($0)" }
        let body = lines.joined(separator: "\n")
        let longest = body.split(omittingEmptySubsequences: true) { $0 != "`" }.map(\.count).max() ?? 0
        let fence = String(repeating: "`", count: max(3, longest + 1))
        return "\(fence)\n\(body)\n\(fence)"
    }

    /// Every ASCII mark escaped, so Markdown shows it exactly as written.
    static func literal(_ text: String) -> String {
        String(text.flatMap { character -> [Character] in
            character.isASCII && (character.isPunctuation || character.isSymbol) ? ["\\", character] : [character]
        })
    }
}
