import Foundation

enum ScreenWords {
    private static let pastedLength = 280

    private static let this = #"\b(this|these)\b(?! ((past|coming|next|last) )?(week|weekend|month|year|quarter|semester|sprint|morning|afternoon|evening|time|days|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b)"#

    private static let things = "thread|tweet|post|article|blog|video|screenshot|picture|photo|paper"

    private static let notThe = #"(?!-)\b(?! (pool|safe|safety|local|id|ids|count|request|requests|response|handler|player|upload|uploads|uploader|picker|viewer|editor|component|model|controller|service|endpoint|route|router|queue|table|card|button|form|field|type|schema|url|urls|cache|manager|view|layout|template|parser|class|struct|function|method|module|metadata|thumbnail|preview|feed|list|\#(things)|page|site|website|link|email|image)s?\b)"#

    private static let naming = [
        #"\#(this) (\S+ )?(\#(things))s?\#(notThe)"#,
        #"\b(on|at) my screen\b"#,
        #"\b(what|the \w+) i.?m (looking at|reading|watching)\b"#,
    ]

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

    private static func camePasted(before: Substring, after: Substring) -> Bool {
        before.range(of: #"(\S+ ){3,}\S*[.!?:"”] "#, options: .regularExpression) != nil
            || after.range(of: #"(:\s+\S|[\s(\[{—–-]["“][^"“”]*[\p{L}\p{N}])"#, options: .regularExpression) != nil
    }

    private static func hasLink(_ words: String) -> Bool {
        guard let links = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return false }
        return links.matches(in: words, range: NSRange(words.startIndex..., in: words)).contains { match in
            guard let url = match.url, ["http", "https"].contains(url.scheme?.lowercased()),
                  let range = Range(match.range, in: words)
            else { return false }
            let typed = words[range].lowercased()
            return ["http://", "https://", "www."].contains { typed.hasPrefix($0) } || url.path.count > 1 || url.query != nil
        }
    }
}
