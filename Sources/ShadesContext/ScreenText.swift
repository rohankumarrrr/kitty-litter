import Foundation

enum ScreenText {
    static let pageLimit = 20_000

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
