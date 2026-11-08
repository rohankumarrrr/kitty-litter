import Foundation
import ShadesCore

/// Where a phone is in Messages, and where words typed there go. The phone only ever names a place by its key, so
/// what it can reach is worked out here from the book, the same way the window works it out. A phone has no room for
/// a thread's pane, so a thread is a page of its own, as in Slack's app.
struct PhonePlace: Equatable {
    /// `nil` is the list of places.
    var selection: ChannelSelection?
    var target: MessageTarget?
    var key: String

    static let home = "home"

    /// An unknown key is the list of places, and a key for an inbox row that's gone is Activity.
    init(_ key: String, in book: ChannelBook) {
        if key.hasPrefix("r:") {
            guard let id = Self.unescape(key.dropFirst(2)), let entry = book.waiting.reports.first(where: { $0.id == id }), !book.talks.contains(entry.threadID) else {
                self.init(selection: .activity, in: book)
                return
            }
            let title = book.title(ofThread: entry.threadID)
            // As with Reply on a report in the window: it goes to the report's thread wherever that is, and stops it asking.
            let target = MessageTarget.thread(id: entry.threadID, title: title.isEmpty ? entry.threadTitle : title, report: entry.id)
            self.init(selection: .thread(entry.threadID, in: .activity), target: target, key: key)
            return
        }
        // What you've asked the cat can be about your screen, so it stays on the Mac.
        guard var selection = Self.selection(key), selection.channelID != .shades, !Self.isTalk(selection, in: book), Self.exists(selection.place, in: book) else {
            self.init(selection: nil, in: book)
            return
        }
        // A new topic carries on in its own thread once T3 has one.
        if let thread = selection.thread, let started = book.started[thread] { selection.thread = started }
        // T3 lists every thread, and the window's own rules would let you write in any of them. What keeps it to the
        // ones it shows is that it only leads to those, so a phone gets only those too.
        // Words meant for it go nowhere, rather than into the place's own box.
        if let thread = selection.thread, !Self.leadsTo(thread, from: selection.place, in: book) {
            self.init(selection: selection.closed, target: nil, key: Self.key(selection.closed))
            return
        }
        self.init(selection: selection, in: book)
    }

    private static func isTalk(_ selection: ChannelSelection, in book: ChannelBook) -> Bool {
        selection.thread.map { book.talks.contains($0) || book.home(ofThread: $0) == .shades } ?? false
    }

    private static func exists(_ place: ChannelPlace, in book: ChannelBook) -> Bool {
        if case .channel(.kitten(let kitten)) = place { return book.kitten(kitten) != nil }
        return true
    }

    /// Whether anything the window shows for this place opens this thread beside it: a channel's parents and the
    /// replies also sent to it, the threads you're in, or in Activity, Type an answer, Reply or Ask, and what's in
    /// progress that Messages has read.
    static func leadsTo(_ id: String, from place: ChannelPlace, in book: ChannelBook) -> Bool {
        switch place {
        case .channel(let channel):
            return book.channel(channel)?.posts.contains { post in
                switch post {
                case .thread(let thread), .alsoSent(_, let thread): return thread == id
                case .message: return false
                }
            } == true
        case .threads:
            return book.yours.contains { $0.id == id }
        case .activity:
            return ChannelRows.activityThreads(in: book).contains(id)
        }
    }

    init(selection: ChannelSelection?, in book: ChannelBook) {
        var target = selection.flatMap { selection in
            selection.thread.map { MessageTarget.reply(in: $0, of: book) } ?? MessageTarget.standard(for: selection.place, in: book)
        }
        // A question is answered from its card, where every part goes at once, so the box doesn't take it.
        if case .question = target { target = nil }
        self.init(selection: selection, target: target, key: selection.map(Self.key) ?? Self.home)
    }

    private init(selection: ChannelSelection?, target: MessageTarget?, key: String) {
        self.selection = selection
        self.target = target
        self.key = key
    }

    /// The channel a reply here can also be sent to: the thread's home, as the window's checkbox offers.
    func alsoSendTo(in book: ChannelBook) -> ChannelID? {
        guard case .thread(let id, _, _)? = target, let home = book.home(ofThread: id), home != .shades else { return nil }
        return home
    }

    static func key(_ selection: ChannelSelection) -> String {
        let place = key(selection.place)
        guard let thread = selection.thread else { return place }
        return "t:\(escape(thread))@\(place)"
    }

    static func reply(to entry: InboxEntry) -> String {
        "r:\(escape(entry.id))"
    }

    private static func key(_ place: ChannelPlace) -> String {
        switch place {
        case .activity: return "activity"
        case .threads: return "threads"
        case .channel(.general): return "general"
        case .channel(.shades): return "shades"
        case .channel(.kitten(let kitten)): return "c:\(escape(kitten))"
        }
    }

    private static func selection(_ key: String) -> ChannelSelection? {
        if key.hasPrefix("t:"), let at = key.lastIndex(of: "@"), at > key.index(key.startIndex, offsetBy: 2),
           let id = unescape(key[key.index(key.startIndex, offsetBy: 2)..<at]),
           let place = place(String(key[key.index(after: at)...])) {
            return .thread(id, in: place)
        }
        return place(key).map { ChannelSelection($0) }
    }

    private static func place(_ key: String) -> ChannelPlace? {
        switch key {
        // The names before Activity and #general, which a page still open from then can ask for.
        case "activity", "needs": return .activity
        case "threads": return .threads
        case "general", "everyone": return .channel(.general)
        case "shades": return .channel(.shades)
        default: return key.hasPrefix("c:") ? unescape(key.dropFirst(2)).map { .channel(.kitten($0)) } : nil
        }
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
        /// As the window's sidebar writes it.
        var title: String
        var group: String?
        /// What's waiting on you there.
        var count: Int?
        var unread: Bool
        /// Its kitten, posed for what it's doing, as `PhoneCat.key` writes it.
        var cat: String?
        /// The window's dot for a kitten that's working or needs you.
        var dot: String?
        var asleep: Bool
        /// `activity`, `threads` or `channel`, for the ones without a cat.
        var icon: String?
    }

    /// A way to another place, such as a kitten's "4 open", which goes to Activity as the window's does.
    struct Link: Encodable, Equatable {
        var label: String
        var open: String
    }

    /// Someone in a reply bar: their cat, or for you, a square in your colour, as the window draws them.
    struct Face: Encodable, Equatable {
        var cat: String?
        var color: String?
    }

    struct Box: Encodable, Equatable {
        var label: String
        var placeholder: String
        /// A new topic that's still starting can't take more yet.
        var ready = true
        /// A thread's "Also send to #channel".
        var also: String?
        /// Whether a photo or file can go with your words, which an answer to a question can't.
        var files = true
    }

    /// The latest reply under a thread in Threads.
    struct Reply: Encodable, Equatable {
        var name: String
        var text: String?
        var color: String?
        var cat: String?
        var at: Double
    }

    struct Choice: Encodable, Equatable {
        var label: String
        var value: String
    }

    struct Part: Encodable, Equatable {
        var text: String
        var choices: [Choice]
        var words: Bool
        /// It takes as many of its choices as you pick.
        var several = false
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
        /// Whoever it's from, or what a heading's kitten is doing, as `PhoneCat.key` writes it. Yours have none.
        var cat: String?
        /// The colour of an issue's dot. `nil` is the soft grey.
        var dot: String?
        var mine: Bool?
        var going: Bool?
        var failure: String?
        /// Yours, on its way to T3.
        var sending: Bool?
        /// Yours, which went nowhere and can go again.
        var retry: Bool?
        /// Milliseconds since 1970.
        var at: Double?
        /// The key of the place it opens.
        var open: String?
        var clear: String?
        var done: Bool?
        var choices: [Choice]?
        var parts: [Part]?
        /// Over a reply also sent to a channel: which thread it's in.
        var context: String?
        /// A thread's reply bar: how many replies, when the last one was, and who replied.
        var replies: Int?
        var lastReply: String?
        var faces: [Face]?
        var waiting: Bool?
        var reply: Reply?
        var more: Int?
        var unread: Bool?
        /// A file or picture on a message: its name, and for a picture sent while Shades has been running, a small copy.
        var file: String?
        var picture: String?
    }

    var key: String
    var title: String
    var subtitle: String?
    /// The kitten whose channel it is, or whose channel a thread is in.
    var cat: String?
    var link: Link?
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
        let channel = place.selection?.channelID
        let also = place.alsoSendTo(in: book).map { CatWords.alsoSendTo(book.title(of: $0)) }
        box = place.target.map { target in
            Box(label: CatWords.target(target, in: channel), placeholder: CatWords.placeholder(target, in: channel, name: channel.map(book.name)), ready: target.isReady, also: also, files: target.takesFiles)
        }
        guard let selection = place.selection else {
            title = CatWords.messagesTitle
            rows = []
            return
        }
        if let thread = selection.thread {
            (title, subtitle) = ChannelHeader.words(forThread: thread, in: book)
            cat = book.home(ofThread: thread).flatMap { Self.cat(of: $0, in: book) }
            back = PhonePlace.key(selection.closed)
            backTitle = ChannelHeader.words(for: selection.place, in: book).title
            rows = ChannelRows.thread(thread, in: book).map { Self.row($0, at: selection.place, in: book, now: now) }
        } else {
            (title, subtitle) = ChannelHeader.words(for: selection.place, in: book)
            cat = selection.channelID.flatMap { Self.cat(of: $0, in: book) }
            if case .channel(.kitten(let kitten)) = selection.place, let count = book.issues.first(where: { $0.kitten.id == kitten })?.threads.count, count > 0 {
                link = Link(label: CatWords.issues(count), open: PhonePlace.key(.activity))
            }
            back = PhonePlace.home
            backTitle = CatWords.messagesTitle
            rows = ChannelRows.rows(selection.place, in: book).map { Self.row($0, at: selection.place, in: book, now: now) }
        }
    }

    private static func places(in book: ChannelBook) -> [Place] {
        ChannelSidebarItem.groups(in: book).flatMap { group in
            group.items.filter { $0.place.channelID != .shades }.map { item in
                var cat: String?
                var dot: UInt32?
                var asleep = false
                var icon: String?
                switch item.icon {
                case .kitten(let status):
                    cat = PhoneCat.key(PhoneCat.Pose(status.state), jacket: ChannelSpeakerLook.color(of: status.kitten))
                    dot = status.state.dot
                    asleep = status.state == .notSetUp
                case .activity: icon = "activity"
                case .threads: icon = "threads"
                case .general, .shades: icon = "channel"
                }
                return Place(
                    key: PhonePlace.key(ChannelSelection(item.place)),
                    title: item.title,
                    group: group.heading,
                    count: item.badge > 0 ? item.badge : nil,
                    unread: item.isUnread,
                    cat: cat,
                    dot: dot.map(hex),
                    asleep: asleep,
                    icon: icon
                )
            }
        }
    }

    /// The header's cat: a kitten's channel has its kitten, sitting, as the window's header draws it.
    private static func cat(of channel: ChannelID, in book: ChannelBook) -> String? {
        guard case .kitten(let kitten) = channel, book.kitten(kitten) != nil else { return nil }
        return cat(of: ChannelSpeakerLook(.kitten(kitten), in: book))
    }

    private static func cat(of look: ChannelSpeakerLook, _ pose: PhoneCat.Pose = .sit) -> String? {
        look.hasCat ? PhoneCat.key(pose, jacket: look.jacket) : nil
    }

    private static func message(_ message: ChannelMessage, in book: ChannelBook) -> Row {
        let look = ChannelSpeakerLook(message.speaker, in: book)
        return Row(
            kind: "message",
            id: message.id,
            name: look.name,
            detail: message.earlierNotes > 0 ? CatWords.earlierNotes(message.earlierNotes) : nil,
            text: message.text ?? (message.isStillGoing ? CatWords.stillGoing : nil),
            color: look.bubble.map(hex),
            ink: look.words.map(hex),
            cat: cat(of: look),
            mine: look.isYou,
            going: message.isStillGoing,
            failure: message.failure,
            sending: message.isSending ? true : nil,
            retry: message.canTryAgain ? true : nil,
            at: millis(message.at),
            file: message.file?.name,
            // Only ever a JPEG Shades made, as base64.
            picture: message.file?.thumbnail.map { "data:image/jpeg;base64,\($0.base64EncodedString())" }
        )
    }

    private static func row(_ row: ChannelRow, at place: ChannelPlace, in book: ChannelBook, now: Date) -> Row {
        switch row {
        case .day(let date):
            return Row(kind: "day", text: CatWords.day(date, now: now))
        case .message(let message):
            return self.message(message, in: book)
        case .parent(let post):
            var row = message(post.parent, in: book)
            row.kind = "parent"
            row.open = PhonePlace.key(.thread(post.threadID, in: place))
            row.replies = post.replies
            row.lastReply = post.replies > 0 ? post.lastReply.map { CatWords.lastReply($0, now: now) } : nil
            row.faces = post.repliers.prefix(4).map { speaker in
                let look = ChannelSpeakerLook(speaker, in: book)
                return Face(cat: cat(of: look), color: look.hasCat ? nil : look.bubble.map(hex))
            }
            row.waiting = post.needsYou ? true : nil
            row.going = post.isGoing
            return row
        case .alsoSent(let message, let threadID, let parent):
            var row = self.message(message, in: book)
            row.context = CatWords.repliedToThread(parent)
            row.open = PhonePlace.key(.thread(threadID, in: place))
            return row
        case .digest(let digest):
            let look = ChannelSpeakerLook(digest.parent.speaker, in: book)
            let reply = digest.latest.map { latest in
                let look = ChannelSpeakerLook(latest.speaker, in: book)
                return Reply(name: look.name, text: latest.text ?? latest.failure, color: look.bubble.map(hex), cat: cat(of: look), at: millis(latest.at))
            }
            return Row(
                kind: "digest",
                id: digest.threadID,
                title: book.title(of: digest.channel),
                name: look.name,
                text: digest.parent.text,
                color: look.bubble.map(hex),
                cat: cat(of: look),
                at: millis(digest.parent.at),
                open: PhonePlace.key(.thread(digest.threadID, in: .threads)),
                reply: reply,
                more: digest.more > 0 ? digest.more : nil,
                unread: digest.isUnread
            )
        case .replies(let count):
            return Row(kind: "replies", text: CatWords.replies(count))
        case .section(let title, let kind):
            return Row(kind: "section", title: title, clear: kind?.rawValue)
        case .heading(let status):
            return Row(
                kind: "heading",
                name: status.kitten.name,
                detail: "\(status.kitten.role) · \(CatWords.kittenState(status.state))",
                cat: PhoneCat.key(PhoneCat.Pose(status.state), jacket: ChannelSpeakerLook.color(of: status.kitten))
            )
        case .issue(let thread):
            let details = [CatWords.age(of: thread.updatedAt, now: now), CatWords.status(thread), thread.pullRequest.map(CatWords.pullRequest)]
            // As in the window, only a thread Messages has read opens. A phone has no T3 to open the rest in.
            return Row(
                kind: "issue",
                title: thread.title,
                detail: details.compactMap { $0 }.joined(separator: " · "),
                dot: thread.dot.map(hex),
                open: book.threads[thread.id] == nil ? nil : PhonePlace.key(.thread(thread.id, in: .activity))
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
                Part(text: part.text, choices: zip(part.options, part.values).map { Choice(label: $0, value: $1) }, words: part.takesOwnWords, several: part.picksSeveral)
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
            cat: cat(of: look, .alert),
            at: at.map(millis)
        )
        fill(&row)
        return row
    }

    private static func millis(_ date: Date) -> Double {
        (date.timeIntervalSince1970 * 1000).rounded()
    }

    private static func hex(_ color: UInt32) -> String {
        ColorTheme.hex(color)
    }
}
