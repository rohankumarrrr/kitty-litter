import Foundation

/// Whether your words only make sense to someone who can see your screen: they point at
/// something without including it. It reads only your words, so a page can't set it off or
/// keep it quiet. A wrong guess costs one extra sentence from the cat, or the kitten asking
/// for the link itself, so a short list is enough.
enum ScreenWords {
    /// Past this, it's probably the text itself, pasted in.
    private static let pastedLength = 280

    /// "This week" points at the calendar.
    private static let this = #"\b(this|these)\b(?! (week|weekend|month|year|quarter|semester|morning|afternoon|evening|time|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b)"#

    /// Things that live on a page. A session's own work, like "this error" or "this PR", isn't here.
    private static let things = "thread|tweet|post|article|blog|page|site|website|link|video|image|picture|photo|screenshot|email|pdf|paper|tab|window|screen"

    private static let pointing = [
        #"\b(read|look at|watch|check out|summari[sz]e|translate) \#(this)"#,
        #"\b(see|what.?s|what is|what are) (this|these) ?([?.!]|$)"#,
        #"\bwhat does this (\S+ )?(say|mean)\b"#,
        #"\b(what do you think (of|about)|thoughts on) this\b"#,
        #"\#(this) (\S+ )?(\#(things))s?\b"#,
        #"\b(on|at) my screen\b"#,
        #"\b(what|the \w+) i.?m (looking at|reading|watching)\b"#,
    ]

    static func pointAtScreen(_ words: String) -> Bool {
        guard words.count <= pastedLength, !hasLink(words), !hasQuotedText(words) else { return false }
        let oneLine = words.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return pointing.contains { oneLine.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
    }

    /// Text after a colon or a quote mark is what they mean, so asking for it again would be silly.
    private static func hasQuotedText(_ words: String) -> Bool {
        words.range(of: #"[:"“]\s*\S"#, options: .regularExpression) != nil
    }

    private static func hasLink(_ words: String) -> Bool {
        let links = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        return links?.firstMatch(in: words, range: NSRange(words.startIndex..., in: words)) != nil
    }
}
