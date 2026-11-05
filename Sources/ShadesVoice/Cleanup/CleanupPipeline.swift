import Foundation

/// Goes from raw transcript to final text, with a safe answer no matter what any step does.
public final class CleanupPipeline {
    public enum Source: String, Sendable {
        case model, rules, raw
    }

    public struct Outcome: Sendable {
        public var text: String
        public var source: Source
        /// Why the model's text was thrown out, if it was.
        public var rejection: String?
    }

    private let model: TextCleaning?
    private let rules = RuleCleaner()
    private let lock = NSLock()
    private var spelling = VocabularySpelling(words: [])

    public init(model: TextCleaning?) {
        self.model = model
    }

    public func setVocabulary(_ words: [String]) {
        let spelling = VocabularySpelling(words: words)
        lock.lock()
        self.spelling = spelling
        lock.unlock()
    }

    public func clean(_ raw: String) async -> Outcome {
        let raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return Outcome(text: "", source: .raw, rejection: nil) }
        if RuleCleaner.isOnlyFillers(raw) { return Outcome(text: "", source: .rules, rejection: nil) }

        // The rules go first because they're certain about fillers and clear corrections, which
        // leaves the model only the punctuation, numbers and harder corrections it's good at.
        let tidied = rules.tidy(raw)

        var rejection: String?
        if let model, !tidied.isEmpty, let cleaned = await model.clean(tidied) {
            let verdict = CleanupGuard.check(raw: raw, cleaned: cleaned)
            if verdict.isAccepted {
                return finish(rules.format(cleaned), source: .model)
            }
            rejection = String(describing: verdict)
        }

        if CleanupGuard.check(raw: raw, cleaned: tidied).isAccepted {
            return finish(tidied, source: .rules, rejection: rejection)
        }
        return finish(raw, source: .raw, rejection: rejection)
    }

    private func finish(_ text: String, source: Source, rejection: String? = nil) -> Outcome {
        lock.lock()
        let spelling = self.spelling
        lock.unlock()
        return Outcome(text: spelling.apply(to: text), source: source, rejection: rejection)
    }
}
