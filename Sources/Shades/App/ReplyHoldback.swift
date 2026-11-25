import Foundation
import ShadesCore

struct ReplyHoldback {
    enum Outcome: Equatable {
        case answer(String, point: PointTarget? = nil)
        case rewrite(String)
        case handoff(task: String)
        case route(session: Int)
        case kitten(number: Int)
    }

    struct Reading: Equatable {
        var corrections: [Int]
        var outcome: Outcome
        var wentNowhere = false
    }

    private static let markers = [Prompts.handoffMarker, Prompts.routeMarker, Prompts.kittenMarker, Prompts.rewriteMarker, Prompts.correctionMarker]

    private(set) var text = ""
    private(set) var released = false

    mutating func add(_ delta: String) -> String? {
        text += delta
        let start = Self.visible(text)
        if !released {
            if start.isEmpty || Self.markers.contains(where: { start.hasPrefix($0) || $0.hasPrefix(start) }) {
                return nil
            }
            released = true
        }
        return Self.withoutPointing(start)
    }

    func read(fullText: String?) -> Reading {
        let outcome = finish(fullText: fullText)
        let rest = Self.visible(fullText ?? text).trimmingCharacters(in: .whitespacesAndNewlines)
        let marked = [Prompts.routeMarker, Prompts.kittenMarker, Prompts.handoffMarker, Prompts.rewriteMarker].contains { rest.hasPrefix($0) }
        return Reading(
            corrections: Prompts.corrections(in: fullText ?? text).owners,
            outcome: outcome,
            wentNowhere: outcome == .answer("") && marked
        )
    }

    func finish(fullText: String?) -> Outcome {
        let full = Prompts.corrections(in: fullText ?? text).rest
        if let session = Prompts.routeTarget(in: full) { return .route(session: session) }
        if let kitten = Prompts.kittenTarget(in: full) { return .kitten(number: kitten) }
        if let task = Prompts.handoffTask(in: full) { return .handoff(task: task) }
        if let text = Prompts.rewrite(in: full) { return .rewrite(text) }
        let visible = Self.visible(full)
        if [Prompts.routeMarker, Prompts.kittenMarker, Prompts.rewriteMarker].contains(where: visible.hasPrefix) { return .answer("") }
        if visible.trimmingCharacters(in: .whitespacesAndNewlines) == Prompts.handoffMarker { return .answer("") }
        let (words, point) = Prompts.pointing(in: visible)
        return .answer(words, point: point)
    }

    private static func withoutPointing(_ text: String) -> String {
        var written = Substring(text)
        while written.last?.isWhitespace == true { written.removeLast() }
        let lineStart = written.lastIndex(where: \.isNewline).map(written.index(after:)) ?? written.startIndex
        let line = written[lineStart...].drop(while: \.isWhitespace)
        guard !line.isEmpty, line.hasPrefix(Prompts.pointMarker) || Prompts.pointMarker.hasPrefix(line) else { return text }
        var kept = written[..<lineStart]
        while kept.last?.isWhitespace == true { kept.removeLast() }
        return String(kept)
    }

    private static func visible(_ text: String) -> String {
        String(Prompts.corrections(in: text).rest.drop(while: \.isWhitespace))
    }
}
