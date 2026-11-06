import Foundation

/// Whether your words only make sense to someone who can see your screen: they point at
/// something without including it. It reads only your words, so a page can't set it off or
/// keep it quiet. A wrong guess costs a notice to dismiss, or the kitten asking for the link
/// itself, so a short list is enough.
enum ScreenWords {
    /// Past this, or over more than one line, it's probably the text itself, pasted in.
    private static let pastedLength = 280

    /// "This week" points at the calendar.
    private static let this = #"\b(this|these)\b(?! ((past|coming|next|last) )?(week|weekend|month|year|quarter|semester|sprint|morning|afternoon|evening|time|days|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b)"#

    /// Things that live on a page, and that people don't usually build themselves.
    private static let things = "thread|tweet|post|article|blog|video|screenshot|picture|photo|paper"

    /// The thing used to describe something in code, like "this thread pool" or "this video player", isn't the thing.
    private static let notThe = #"(?!-)\b(?! (pool|safe|safety|local|id|ids|count|request|requests|response|handler|player|upload|uploads|uploader|picker|viewer|editor|component|model|controller|service|endpoint|route|router|queue|table|card|button|form|field|type|schema|url|urls|cache|manager|view|layout|template|parser|class|struct|function|method|module|metadata|thumbnail|preview|feed|list)s?\b)"#

    /// These name something outside the conversation, so they hold for a session that has context too.
    private static let naming = [
        #"\#(this) (\S+ )?(\#(things))s?\#(notThe)"#,
        #"\b(on|at) my screen\b"#,
        #"\b(what|the \w+) i.?m (looking at|reading|watching)\b"#,
    ]

    /// These only point. A new thread has nothing else they could mean, but in a follow-up "this"
    /// is usually the session's own work.
    private static let pointing = [
        #"\#(this) (\S+ )?(page|site|website|link|email|image)s?\#(notThe)"#,
        #"\b(read|look at|watch|check out|summari[sz]e|translate) \#(this)"#,
        #"\b(see|what.?s|what is|what are) (this|these) ?([?.!]|$)"#,
        #"\bwhat does \#(this) (\S+ )?(say|mean)\b"#,
        #"\b(what do you think (of|about)|thoughts on) \#(this)"#,
    ]

    static func pointAtScreen(_ words: String, isFollowUp: Bool = false) -> Bool {
        let words = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard words.count <= pastedLength, !words.contains(where: \.isNewline), !hasLink(words) else { return false }
        return (isFollowUp ? naming : naming + pointing).contains { pattern in
            guard let match = words.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return false }
            return !camePasted(before: words[..<match.lowerBound], after: words[match.upperBound...])
        }
    }

    /// What they're pointing at is already here: a sentence before the pointing words, or a
    /// colon or quote mark with text after them. Asking for it would be silly.
    private static func camePasted(before: Substring, after: Substring) -> Bool {
        before.range(of: #"(\S+ ){3,}\S*[.!?:"”] "#, options: .regularExpression) != nil
            || after.range(of: #"(:\s+\S|["“]\s*\w)"#, options: .regularExpression) != nil
    }

    /// A web address they typed, or one to a page. A site's name on its own, like "on x.com", isn't the thing.
    private static func hasLink(_ words: String) -> Bool {
        guard let links = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return false }
        return links.matches(in: words, range: NSRange(words.startIndex..., in: words)).contains { match in
            guard let url = match.url, ["http", "https"].contains(url.scheme?.lowercased()),
                  let range = Range(match.range, in: words)
            else { return false }
            let typed = words[range].lowercased()
            return typed.hasPrefix("http") || typed.hasPrefix("www.") || url.path.count > 1 || url.query != nil
        }
    }
}
