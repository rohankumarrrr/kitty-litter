import Foundation
import ShadesContext
import ShadesCore

struct PhoneAsk: Decodable {
    var act: String
    var key: String?
    var text: String?
    var id: String?
    var value: String?
    var answers: [[String]]?
    var kind: String?
    var also: Bool?
    var files: [String]?

    func action(in book: ChannelBook, newTopic: () -> String, file uploaded: (String) -> Drop? = { _ in nil }) -> (action: MessagesAction, opens: String?)? {
        switch act {
        case "send":
            let words = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let ids = files ?? []
            let attached = ids.compactMap(uploaded)
            guard let key, !words.isEmpty || !attached.isEmpty, attached.count == ids.count, Set(ids).count == ids.count, ids.count <= Drop.mostAtOnce else { return nil }
            let place = PhonePlace(key, in: book)
            guard let target = place.target, attached.isEmpty || target.takesFiles else { return nil }
            switch target {
            case .router:
                return (.send(words, to: target, shownIn: place.selection?.channelID, files: attached), nil)
            case .thread(let id, _, _):
                let home = book.home(ofThread: id) ?? .shades
                return (.send(words, to: target, shownIn: home, alsoSent: also == true && place.alsoSendTo(in: book) != nil, files: attached), nil)
            case .newThread(let kitten):
                let topic = newTopic()
                return (.startTopic(words, with: kitten, id: topic, files: attached), PhonePlace.key(.thread(topic, in: .channel(.of(kitten)))))
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
            guard let entry = book.waiting.reports.first(where: { $0.id == id }), entry.kind == .decision, entry.change == nil, entry.ask == nil else { return nil }
            return (.inbox(.done(id: entry.id)), nil)
        case "ask":
            guard let entry = book.waiting.reports.first(where: { $0.id == id }), entry.change == nil, entry.ask != nil,
                  let decision = value.flatMap(ApprovalDecision.init(rawValue:)), [.accept, .decline].contains(decision)
            else { return nil }
            return (.inbox(decision == .accept ? .allow(id: entry.id) : .deny(id: entry.id)), nil)
        case "clear":
            guard let kind = self.kind.flatMap(InboxEntry.Kind.init(rawValue:)), kind != .decision else { return nil }
            return (.inbox(.clear(kind)), nil)
        case "seen":
            guard var selection = key.flatMap({ PhonePlace($0, in: book).selection }) else { return nil }
            if selection.channelID == .shades {
                guard let thread = selection.thread else { return nil }
                selection = .thread(thread, in: .threads)
            }
            return (.seen(selection), nil)
        case "read":
            guard let selection = key.flatMap({ PhonePlace($0, in: book).selection }), selection.thread == nil else { return nil }
            let threads = PhoneView.unreadThreads(in: selection.place, of: book)
            guard !threads.isEmpty else { return nil }
            return (.markRead(threads), nil)
        case "unread":
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
        case "picture":
            guard let message = id.flatMap(book.message), book.home(ofThread: message.threadID) != .shades,
                  let url = message.files.lazy.compactMap(\.source?.webAddress).first(where: { $0.absoluteString == value })
            else { return nil }
            return (.showPicture(url), nil)
        default:
            return nil
        }
    }
}
