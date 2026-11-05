import Foundation

/// Tidies text read from the screen before it goes anywhere near a prompt.
enum ScreenText {
    /// Prompts.swift keeps this much page text, so there's no use reading more.
    static let pageLimit = 20_000

    /// Empty text counts as none. A page can't be allowed to write `</screen>`, which would
    /// let what it says next read as instructions instead of as data.
    static func clean(_ text: String?, limit: Int = pageLimit) -> String? {
        guard let text else { return nil }
        let capped = String(text.prefix(limit))
        guard !capped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return capped.replacingOccurrences(
            of: #"<\s*/?\s*screen"#,
            with: "(screen",
            options: [.regularExpression, .caseInsensitive]
        )
    }
}
