import Foundation
import ShadesCore

/// Where a phone is in Messages, and where words typed there go. The phone only ever names a place by its key, so
/// what it can reach is worked out here from the book, the same way the window works it out.
struct PhonePlace: Equatable {
    /// `nil` is the list of places.
    var selection: ChannelSelection?
    var target: MessageTarget?
    var key: String

    static let home = "home"

    /// An unknown key is the list of places, and a key for an inbox row that's gone is Needs you.
    init(_ key: String, in book: ChannelBook) {
        if key.hasPrefix("r:") {
            guard let id = Self.unescape(key.dropFirst(2)), let entry = book.waiting.reports.first(where: { $0.id == id }) else {
                self.init(selection: .needsYou, in: book)
                return
            }
            let channel = book.kitten(of: entry.id).map(ChannelID.direct) ?? .everyone
            let title = book.title(ofThread: entry.threadID, in: channel)
            // As with Reply on a report in the window: it goes to the report's thread wherever that is, and stops it asking.
            let target = MessageTarget.thread(id: entry.threadID, title: title.isEmpty ? entry.threadTitle : title, report: entry.id)
            self.init(selection: .thread(entry.threadID, in: channel), target: target, key: key)
            return
        }
        guard var selection = Self.selection(key) else {
            self.init(selection: nil, in: book)
            return
        }
        // A new topic carries on in its own thread once T3 has one.
        if case .thread(let id, let channel) = selection, let started = book.started[id] { selection = .thread(started, in: channel) }
        self.init(selection: selection, in: book)
    }

    init(selection: ChannelSelection?, in book: ChannelBook) {
        // A question is answered from its card, where every part goes at once, so the box doesn't take it.
        var target = selection.flatMap { MessageTarget.standard(for: $0, in: book) }
        if case .question = target { target = nil }
        self.init(selection: selection, target: target, key: selection.map(Self.key) ?? Self.home)
    }

    private init(selection: ChannelSelection?, target: MessageTarget?, key: String) {
        self.selection = selection
        self.target = target
        self.key = key
    }

    static func key(_ selection: ChannelSelection) -> String {
        switch selection {
        case .needsYou: return "needs"
        case .done: return "done"
        case .channel(let id): return key(id)
        case .thread(let id, let channel): return "t:\(escape(id))@\(key(channel))"
        }
    }

    static func reply(to entry: InboxEntry) -> String {
        "r:\(escape(entry.id))"
    }

    private static func key(_ channel: ChannelID) -> String {
        if channel == .everyone { return "everyone" }
        let members = channel.members.map { member -> String in
            switch member {
            case .you: return "you"
            case .cat: return "cat"
            case .someoneElse: return "other"
            case .kitten(let id): return "k.\(escape(id))"
            }
        }
        return "c:" + members.sorted().joined(separator: "+")
    }

    private static func selection(_ key: String) -> ChannelSelection? {
        switch key {
        case "needs": return .needsYou
        case "done": return .done
        case "everyone": return .channel(.everyone)
        default: break
        }
        if key.hasPrefix("t:"), let at = key.lastIndex(of: "@"), at > key.index(key.startIndex, offsetBy: 2),
           let id = unescape(key[key.index(key.startIndex, offsetBy: 2)..<at]),
           case .channel(let channel)? = selection(String(key[key.index(after: at)...])) {
            return .thread(id, in: channel)
        }
        guard key.hasPrefix("c:") else { return nil }
        let members = key.dropFirst(2).split(separator: "+", omittingEmptySubsequences: false).map { member -> Speaker? in
            switch member {
            case "you": return .you
            case "cat": return .cat
            case "other": return .someoneElse
            default: return member.hasPrefix("k.") ? unescape(member.dropFirst(2)).map(Speaker.kitten) : nil
            }
        }
        guard members.count == 2, let first = members[0], let second = members[1], let channel = ChannelID(first, second) else { return nil }
        return .channel(channel)
    }

    private static let plain = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")

    private static func escape(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: plain) ?? ""
    }

    private static func unescape(_ text: Substring) -> String? {
        let text = text.removingPercentEncoding
        return text?.isEmpty == false ? text : nil
    }
}

/// What a phone is shown: one place in Messages, worked out on the Mac from the same rows the window shows, so the page
/// only draws. A phone gets these and never whole threads.
struct PhoneView: Encodable, Equatable {
    struct Place: Encodable, Equatable {
        var key: String
        var title: String
        var group: String?
        var count: Int?
        var unread: Bool
        var color: String?
        var asleep: Bool
    }

    struct Box: Encodable, Equatable {
        var label: String
        var placeholder: String
        /// A new topic that's still starting can't take more yet.
        var ready = true
    }

    struct Choice: Encodable, Equatable {
        var label: String
        var value: String
    }

    struct Part: Encodable, Equatable {
        var text: String
        var choices: [Choice]
        var words: Bool
    }

    /// One row, by `kind`, with only the fields that kind uses.
    struct Row: Encodable, Equatable {
        var kind: String
        var id: String?
        var title: String?
        var name: String?
        var detail: String?
        var text: String?
        var answer: String?
        var footer: String?
        var color: String?
        var ink: String?
        var mine: Bool?
        var going: Bool?
        var failure: String?
        /// Milliseconds since 1970.
        var at: Double?
        /// The key of the place it opens.
        var open: String?
        var clear: String?
        var done: Bool?
        var choices: [Choice]?
        var parts: [Part]?
    }

    var key: String
    var title: String
    var subtitle: String?
    var back: String?
    var backTitle: String?
    var places: [Place]
    var rows: [Row]
    var box: Box?
    var cantReachT3: Bool

    init(_ place: PhonePlace, in book: ChannelBook, now: Date) {
        key = place.key
        places = Self.places(in: book)
        cantReachT3 = book.cantReachT3
        box = place.target.map { Box(label: CatWords.target($0), placeholder: CatWords.placeholder($0), ready: $0.isReady) }
        guard let selection = place.selection else {
            title = CatWords.messagesTitle
            rows = []
            return
        }
        (title, subtitle) = ChannelHeader.words(for: selection, in: book)
        if case .thread(_, let channel) = selection {
            back = PhonePlace.key(.channel(channel))
            backTitle = book.title(of: channel)
        } else {
            back = PhonePlace.home
            backTitle = CatWords.messagesTitle
        }
        rows = ChannelRows.rows(selection, in: book).map { Self.row($0, at: selection, in: book, now: now) }
    }

    private static func places(in book: ChannelBook) -> [Place] {
        ChannelSidebarItem.groups(in: book).flatMap { group in
            group.items.map { item in
                var color: UInt32?
                var asleep = false
                if case .kitten(let status)? = item.cats.first {
                    color = ChannelSpeakerLook.color(of: status.kitten)
                    asleep = status.state == .notSetUp
                }
                return Place(
                    key: PhonePlace.key(item.selection),
                    title: item.title,
                    group: group.heading,
                    count: item.count.flatMap { $0 > 0 ? $0 : nil },
                    unread: item.isUnread,
                    color: color.map(hex),
                    asleep: asleep
                )
            }
        }
    }

    private static func row(_ row: ChannelRow, at selection: ChannelSelection, in book: ChannelBook, now: Date) -> Row {
        switch row {
        case .day(let date):
            return Row(kind: "day", text: CatWords.day(date, now: now))
        case .subject(let title, let project, let threadID):
            let open = selection.channelID.map { PhonePlace.key(.thread(threadID, in: $0)) }
            return Row(kind: "subject", title: title, detail: project, open: open)
        case .message(let message):
            let look = ChannelSpeakerLook(message.speaker, in: book)
            return Row(
                kind: "message",
                id: message.id,
                name: look.name,
                detail: message.earlierNotes > 0 ? CatWords.earlierNotes(message.earlierNotes) : nil,
                text: message.text ?? (message.isStillGoing ? CatWords.stillGoing : nil),
                color: look.bubble.map(hex),
                ink: look.bubble.map(ink),
                mine: look.isYou,
                going: message.isStillGoing,
                failure: message.failure,
                at: millis(message.at)
            )
        case .section(let title, let kind):
            return Row(kind: "section", title: title, clear: kind?.rawValue)
        case .heading(let status):
            return Row(
                kind: "heading",
                name: status.kitten.name,
                detail: "\(status.kitten.role) · \(CatWords.kittenState(status.state))",
                color: ChannelSpeakerLook.color(of: status.kitten).map(hex)
            )
        case .issue(let thread):
            let owner = book.issues.first { $0.threads.contains { $0.id == thread.id } || $0.done.contains { $0.id == thread.id } }?.kitten
            let details = [CatWords.age(of: thread.updatedAt, now: now), CatWords.status(thread), thread.pullRequest.map(CatWords.pullRequest)]
            return Row(
                kind: "issue",
                title: thread.title,
                detail: details.compactMap { $0 }.joined(separator: " · "),
                open: PhonePlace.key(.thread(thread.id, in: owner.map(ChannelID.direct) ?? .everyone))
            )
        case .approval(let request):
            let kitten = book.kitten(of: request.id)
            var choices = [Choice(label: "Deny", value: ApprovalDecision.decline.rawValue), Choice(label: "Allow", value: ApprovalDecision.accept.rawValue)]
            if ApprovalPolicy.offersSessionAllow(request.kind) {
                choices.append(Choice(label: "Allow for this session", value: ApprovalDecision.acceptForSession.rawValue))
            }
            return card("approval", id: request.id, kitten: kitten, title: request.threadTitle, text: request.summary, at: request.createdAt, in: book) {
                $0.choices = choices
            }
        case .question(let question):
            let kitten = book.kitten(of: question.id)
            let parts = (question.form?.parts ?? []).map { part in
                Part(text: part.text, choices: zip(part.options, part.values).map { Choice(label: $0, value: $1) }, words: part.takesOwnWords)
            }
            let text = question.text.isEmpty ? CatWords.unreadableQuestion : question.text
            return card("question", id: question.id, kitten: kitten, title: question.threadTitle, text: text, at: nil, in: book) {
                $0.parts = parts
                $0.footer = question.form == nil ? CatWords.answerInT3 : nil
            }
        case .report(let entry):
            let kitten = book.kitten(of: entry.id)
            return card("report", id: entry.id, kitten: kitten, title: entry.threadTitle, text: entry.text, at: entry.at, in: book) {
                $0.answer = entry.answer
                $0.footer = entry.repliedAt == nil ? nil : CatWords.inboxSent
                $0.done = entry.kind == .decision
                $0.open = PhonePlace.reply(to: entry)
                $0.choices = [Choice(label: entry.kind == .decision ? "Reply" : "Ask", value: "reply")]
            }
        case .note(let text):
            return Row(kind: "note", text: text)
        }
    }

    private static func card(_ kind: String, id: String, kitten: Kitten?, title: String, text: String, at: Date?, in book: ChannelBook, _ fill: (inout Row) -> Void) -> Row {
        let look = ChannelSpeakerLook(kitten.map { .kitten($0.id) } ?? .someoneElse, in: book)
        var row = Row(
            kind: kind,
            id: id,
            title: kitten.map { "\($0.name) · \(ChannelBook.title(of: title, owner: $0))" } ?? title,
            name: look.name,
            text: text,
            color: look.jacket.map(hex),
            at: at.map(millis)
        )
        fill(&row)
        return row
    }

    private static func millis(_ date: Date) -> Double {
        (date.timeIntervalSince1970 * 1000).rounded()
    }

    private static func hex(_ color: UInt32) -> String {
        String(format: "#%06x", color)
    }

    /// Black or white, whichever reads better on it, as the window picks.
    private static func ink(_ color: UInt32) -> String {
        ChannelSpeakerLook.contrast(color, 0x000000) >= ChannelSpeakerLook.contrast(color, 0xffffff) ? "#000000" : "#ffffff"
    }
}
