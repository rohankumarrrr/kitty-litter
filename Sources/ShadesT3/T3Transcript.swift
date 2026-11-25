import Foundation
import ShadesCore

enum T3Transcript {
    private static let limit = 8_000
    private static let cutEnding = "\n\nThe rest is in T3."

    static func exchanges(in items: [T3Wire.TurnItem], runs: [T3Wire.Run], sender: (String) -> String?) -> [Exchange] {
        let askedInRun = Dictionary(runs.map { ($0.id, $0.userMessageId) }, uniquingKeysWith: { $1 })
        var exchanges: [Exchange] = []
        var byMessage: [String: Int] = [:]
        var steered: [String: Int] = [:]

        func exchange(answeredBy item: T3Wire.TurnItem) -> Int {
            if let run = item.runId, let steer = steered[run] { return steer }
            if let message = item.runId.flatMap({ askedInRun[$0] }), let index = byMessage[message] { return index }
            if let latest = exchanges.indices.last { return latest }
            exchanges.append(Exchange(id: item.id, asker: .you, askedAt: item.when))
            return 0
        }

        for item in T3Wire.ownItems(items) {
            if item.isUserMessage {
                guard !item.isWrittenByT3 else { continue }
                if let message = item.messageId { byMessage[message] = exchanges.count }
                if let run = item.runId, let asked = askedInRun[run], asked != item.messageId { steered[run] = exchanges.count }
                let asker: Exchange.Asker = item.scheduledTaskId != nil ? .schedule
                    : item.isFromPerson ? .you : .agent(threadID: item.agentSenderThreadID.flatMap(sender))
                let ask = item.isFromPerson ? ownWords(item.text) : shown(item.text)
                let files = item.isFromPerson ? T3Wire.files(of: item) : []
                let passedOn = item.isFromPerson ? item.text.flatMap(Prompts.threadWhoseReportIsPassedOn(in:)) : nil
                let opened = item.runId.flatMap { askedInRun[$0] == item.messageId ? $0 : nil }
                exchanges.append(Exchange(id: item.id, asker: asker, askedAt: item.when, ask: ask, files: files, passesOnReportOf: passedOn, opensRun: opened))
            } else if item.isSpoken, let words = shown(item.text) {
                let index = exchange(answeredBy: item)
                if exchanges[index].reply != nil { exchanges[index].earlierNotes += 1 }
                exchanges[index].reply = words
                exchanges[index].repliedAt = item.updatedAt ?? item.when
                exchanges[index].failure = nil
            } else if item.isError {
                exchanges[exchange(answeredBy: item)].failure = shown(item.failure?.message) ?? "Something went wrong."
            }
        }
        return exchanges
    }

    private static func ownWords(_ text: String?) -> String? {
        guard let words = text.flatMap({ Prompts.question(in: $0) ?? Prompts.dispatched(in: $0) ?? Prompts.ownWords(in: $0) }).map(T3Wire.withoutToolBlocks), !words.isEmpty, words != T3Wire.attachmentsOnly else { return nil }
        guard words.hasPrefix(T3Wire.ultrathinkPrefix) else { return capped(words) }
        let rest = words.dropFirst(T3Wire.ultrathinkPrefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? nil : capped(rest)
    }

    private static func shown(_ text: String?) -> String? {
        guard let words = text.map(Prompts.withoutScreenBlocks), !words.isEmpty else { return nil }
        return capped(words)
    }

    private static func capped(_ text: String) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit - cutEnding.count)) + cutEnding
    }
}
