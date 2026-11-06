import Foundation
import ShadesCore

/// What a phone asks Messages to do, as it arrives. None of it is trusted: the phone names a place by its key and
/// things by their IDs, and where words go, what's being answered and what choices there are all come from the book.
struct PhoneAsk: Decodable {
    var act: String
    var key: String?
    var text: String?
    var id: String?
    var value: String?
    var answers: [String]?
    var kind: String?

    /// The same action the window would take, and the key of where the phone goes next, or `nil` if the window
    /// couldn't do it either.
    func action(in book: ChannelBook, newTopic: () -> String) -> (action: MessagesAction, opens: String?)? {
        switch act {
        case "send":
            guard let key, let words = text?.trimmingCharacters(in: .whitespacesAndNewlines), !words.isEmpty else { return nil }
            let place = PhonePlace(key, in: book)
            guard let target = place.target else { return nil }
            switch target {
            case .router, .thread:
                return (.send(words, to: target, shownIn: place.selection?.channelID), nil)
            case .newThread(let kitten):
                let topic = newTopic()
                return (.startTopic(words, with: kitten, id: topic), PhonePlace.key(.thread(topic, in: .direct(kitten))))
            case .starting, .question:
                return nil
            }
        case "approval":
            guard let request = book.waiting.approvals.first(where: { $0.id == id }),
                  let decision = value.flatMap(ApprovalDecision.init(rawValue:)),
                  decision != .acceptForSession || ApprovalPolicy.offersSessionAllow(request.kind)
            else { return nil }
            return (.approval(request, decision), nil)
        case "answer":
            guard let question = book.waiting.questions.first(where: { $0.id == id }),
                  let parts = question.form?.parts, let answers, answers.count == parts.count,
                  zip(parts, answers).allSatisfy(Self.fits)
            else { return nil }
            return (.answer(question, answers), nil)
        case "done":
            guard let entry = book.waiting.reports.first(where: { $0.id == id }), entry.kind == .decision else { return nil }
            return (.inbox(.done(id: entry.id)), nil)
        case "clear":
            guard let kind = self.kind.flatMap(InboxEntry.Kind.init(rawValue:)), kind != .decision else { return nil }
            return (.inbox(.clear(kind)), nil)
        case "seen":
            guard let selection = key.flatMap({ PhonePlace($0, in: book).selection }) else { return nil }
            return (.seen(selection), nil)
        default:
            return nil
        }
    }

    /// One of its choices, or your own words where it takes them.
    private static func fits(_ part: AnswerForm.Part, _ answer: String) -> Bool {
        part.values.contains(answer) || (part.takesOwnWords && !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
