import Foundation

/// Whether your words only make sense to someone who can see your screen: they point at
/// something without including it. It reads only your words, so a page can't set it off or
/// keep it quiet. A wrong guess costs one extra sentence from the cat, or the kitten asking
/// for the link itself, so a short list is enough.
enum ScreenWords {
    /// Past this, it's probably the text itself, pasted in.
    private static let pastedLength = 280

    private static let things = "thread|tweet|post|article|blog|page|site|website|link|video|image|picture|photo|screenshot|email|doc|document|pdf|paper|tab|window|screen|chart|comment|error"

    private static let pointing = [
        #"\b(read|look at|see|watch|check out|summari[sz]e|translate|explain) (this|these)\b"#,
        #"\bwhat( is|.?s| does| are) (this|these)\b"#,
        #"\b(what do you think (of|about)|thoughts on) this\b"#,
        #"\b(this|these) (\S+ )?(\#(things))s?\b"#,
        #"\b(on|at) my screen\b"#,
        #"\b(what|the \w+) i.?m (looking at|reading|watching)\b"#,
    ]

    static func pointAtScreen(_ words: String) -> Bool {
        guard words.count <= pastedLength, !hasLink(words) else { return false }
        let oneLine = words.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return pointing.contains { oneLine.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
    }

    private static func hasLink(_ words: String) -> Bool {
        let links = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        return links?.firstMatch(in: words, range: NSRange(words.startIndex..., in: words)) != nil
    }
}
