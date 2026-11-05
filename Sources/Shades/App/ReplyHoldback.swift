import Foundation
import ShadesCore

/// A handoff should never flash up as an answer, but real answers shouldn't wait. So
/// text is held only while it could still turn out to be the marker, which for most
/// replies is no longer than the first letter.
struct ReplyHoldback {
    enum Outcome: Equatable {
        case answer(String)
        case handoff(task: String)
    }

    private(set) var text = ""
    private(set) var released = false

    /// Takes the next bit of text, returning everything to show so far, or `nil` to keep waiting.
    mutating func add(_ delta: String) -> String? {
        text += delta
        if released { return Self.visible(text) }
        let start = Self.visible(text)
        if start.isEmpty || start.hasPrefix(Prompts.handoffMarker) || Prompts.handoffMarker.hasPrefix(start) {
            return nil
        }
        released = true
        return start
    }

    /// The reply is done, so it's clear what it was. Prefers the backend's full text, if any.
    func finish(fullText: String?) -> Outcome {
        let full = fullText ?? text
        if let task = Prompts.handoffTask(in: full) { return .handoff(task: task) }
        let visible = Self.visible(full)
        // The marker with nothing after it is nothing worth reading.
        return .answer(visible.trimmingCharacters(in: .whitespacesAndNewlines) == Prompts.handoffMarker ? "" : visible)
    }

    private static func visible(_ text: String) -> String {
        String(text.drop(while: \.isWhitespace))
    }
}
