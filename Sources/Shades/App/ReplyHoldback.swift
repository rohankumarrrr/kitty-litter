import Foundation
import ShadesCore

/// Passing something on should never flash up as an answer, but real answers shouldn't wait.
/// So text is held only while it could still turn out to be a marker, which for most replies
/// is no longer than the first letter.
struct ReplyHoldback {
    enum Outcome: Equatable {
        case answer(String, point: PointTarget? = nil)
        /// New text for what's selected, which waits for you to say where it goes.
        case rewrite(String)
        case handoff(task: String)
        case route(session: Int)
        case kitten(number: Int)
    }

    private static let markers = [Prompts.handoffMarker, Prompts.routeMarker, Prompts.kittenMarker, Prompts.rewriteMarker]

    private(set) var text = ""
    private(set) var released = false

    /// Takes the next bit of text, returning everything to show so far, or `nil` to keep waiting.
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

    /// The reply is done, so it's clear what it was. Prefers the backend's full text, if any.
    func finish(fullText: String?) -> Outcome {
        let full = fullText ?? text
        if let session = Prompts.routeTarget(in: full) { return .route(session: session) }
        if let kitten = Prompts.kittenTarget(in: full) { return .kitten(number: kitten) }
        if let task = Prompts.handoffTask(in: full) { return .handoff(task: task) }
        if let text = Prompts.rewrite(in: full) { return .rewrite(text) }
        let visible = Self.visible(full)
        // A marker that goes nowhere is nothing worth reading.
        if [Prompts.routeMarker, Prompts.kittenMarker, Prompts.rewriteMarker].contains(where: visible.hasPrefix) { return .answer("") }
        // The marker with nothing after it is nothing worth reading.
        if visible.trimmingCharacters(in: .whitespacesAndNewlines) == Prompts.handoffMarker { return .answer("") }
        let (words, point) = Prompts.pointing(in: visible)
        return .answer(words, point: point)
    }

    /// The line saying where to point is for the cat, so it never shows, even half written.
    private static func withoutPointing(_ text: String) -> String {
        let lineStart = text.lastIndex(where: \.isNewline).map(text.index(after:)) ?? text.startIndex
        let line = text[lineStart...].drop(while: \.isWhitespace)
        guard !line.isEmpty, line.hasPrefix(Prompts.pointMarker) || Prompts.pointMarker.hasPrefix(line) else { return text }
        var kept = text[..<lineStart]
        while kept.last?.isWhitespace == true { kept.removeLast() }
        return String(kept)
    }

    private static func visible(_ text: String) -> String {
        String(text.drop(while: \.isWhitespace))
    }
}
