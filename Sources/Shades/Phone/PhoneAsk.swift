import Foundation
import ShadesContext
import ShadesCore

/// What a phone asks Messages to do, as it arrives. None of it is trusted: the phone names a place by its key and
/// things by their IDs, and where words go, what's being answered and what choices there are all come from the book.
struct PhoneAsk: Decodable {
    var act: String
    var key: String?
    var text: String?
    var id: String?
    var value: String?
    /// One for each part: the values of the choices picked, or your own words alone.
    var answers: [[String]]?
    var kind: String?
    /// A thread's "Also send to #channel".
    var also: Bool?
    /// A photo or file the page sent ahead, by the ID the Mac gave it.
    var file: String?

    /// The same action the window would take, and the key of where the phone goes next, or `nil` if the window
    /// couldn't do it either.
    /// `file` finds what the page sent ahead, which is only ever something it uploaded itself.
    func action(in book: ChannelBook, newTopic: () -> String, file uploaded: (String) -> Drop? = { _ in nil }) -> (action: MessagesAction, opens: String?)? {
        switch act {
        case "send":
            let words = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let attached = file.flatMap(uploaded)
            guard let key, !words.isEmpty || attached != nil, file == nil || attached != nil else { return nil }
            let place = PhonePlace(key, in: book)
            guard let target = place.target, attached == nil || target.takesFiles else { return nil }
            switch target {
            case .router:
                return (.send(words, to: target, shownIn: place.selection?.channelID, file: attached), nil)
            case .thread(let id, _, _):
                let home = book.home(ofThread: id)
                return (.send(words, to: target, shownIn: home, alsoSent: also == true && place.alsoSendTo(in: book) != nil, file: attached), nil)
            case .newThread(let kitten):
                let topic = newTopic()
                return (.startTopic(words, with: kitten, id: topic, file: attached), PhonePlace.key(.thread(topic, in: .channel(.of(kitten)))))
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
                  zip(parts, answers).allSatisfy({ $0.takes($1) })
            else { return nil }
            return (.answer(question, answers), nil)
        case "done":
            guard let entry = book.waiting.reports.first(where: { $0.id == id }), entry.kind == .decision else { return nil }
            return (.inbox(.done(id: entry.id)), nil)
        case "clear":
            guard let kind = self.kind.flatMap(InboxEntry.Kind.init(rawValue:)), kind != .decision else { return nil }
            return (.inbox(.clear(kind)), nil)
        case "seen":
            guard var selection = key.flatMap({ PhonePlace($0, in: book).selection }) else { return nil }
            // A phone shows only some of the cat's DM, so all it's seen there is the thread it's on.
            if selection.channelID == .shades {
                guard let thread = selection.thread else { return nil }
                selection = .thread(thread, in: .threads)
            }
            return (.seen(selection), nil)
        case "unread":
            // Only a message in the thread this page shows, and one Messages can mark.
            guard let thread = key.flatMap({ PhonePlace($0, in: book).selection?.thread }), book.canMarkUnread(thread),
                  let id, book.threads[thread]?.messages.contains(where: { $0.id == id }) == true
            else { return nil }
            return (.markUnread(thread, from: id), nil)
        case "retry":
            guard let message = id.flatMap(book.message), message.canTryAgain else { return nil }
            return (.tryAgain(message.exchangeID), nil)
        case "react":
            guard let message = id.flatMap(book.message), message.reactions != nil, let reaction = value.flatMap(Reaction.init(rawValue:)) else { return nil }
            return (.react(message.id, reaction), nil)
        case "older":
            guard let channel = key.flatMap({ PhonePlace($0, in: book).selection?.channelID }), channel != .shades else { return nil }
            return (.older(channel), nil)
        default:
            return nil
        }
    }
}
