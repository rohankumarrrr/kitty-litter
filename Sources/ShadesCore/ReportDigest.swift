import Foundation

/// Agents' reports read well in a window but not in a small bubble. These decide when one can be
/// shown as it is, and cut one down when no model is around to sum it up.
public enum ReportDigest {
    private static let shortLimit = 320
    private static let cutLimit = 420

    /// Three plain sentences or fewer: there's nothing to gain from summing this up.
    public static func isShort(_ report: String) -> Bool {
        let text = report.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= shortLimit else { return false }
        let looksFormatted = ["\n\n", "`", "**", "://", "<", "|", "\n- ", "\n* ", "#"].contains { text.contains($0) }
        return !looksFormatted && sentences(in: text).count <= 3
    }

    /// The first few sentences, with the formatting taken out. Reports tend to lead with how it went.
    public static func firstSentences(of report: String, count: Int = 3) -> String {
        let prose = report
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("#") && !$0.hasPrefix("|") && !$0.hasPrefix("```") }
            .map(withoutMarks)
            .joined(separator: "\n")
        let opening = prose
            .components(separatedBy: "\n\n")
            .first { $0.contains(where: { !$0.isWhitespace }) } ?? prose
        let kept = sentences(in: opening.replacingOccurrences(of: "\n", with: " ")).prefix(count).joined(separator: " ")
        guard kept.count > cutLimit else { return kept }
        return String(kept.prefix(cutLimit)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// The thread a report points to, when all an agent did was start another one.
    public static func linkedThreadID(in report: String) -> String? {
        guard let match = report.firstMatch(of: #/t3-thread://v2/[^/\s>]+/([^>\s)]+)/#) else { return nil }
        return String(match.1)
    }

    private static func withoutMarks(_ line: String) -> String {
        var text = line.replacingOccurrences(of: #"^([-*•]|\d+\.)\s+"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<[a-z0-9-]+://[^>]*>"#, with: "", options: .regularExpression)
        for mark in ["**", "__", "`"] { text = text.replacingOccurrences(of: mark, with: "") }
        return text
    }

    private static func sentences(in text: String) -> [String] {
        var found: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sentence, _, _, _ in
            if let sentence = sentence?.trimmingCharacters(in: .whitespacesAndNewlines), !sentence.isEmpty {
                found.append(sentence)
            }
        }
        return found
    }
}
