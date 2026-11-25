import Foundation
import ShadesCore

struct PhonePlace: Equatable {
    var selection: ChannelSelection?
    var target: MessageTarget?
    var key: String
    var backlog: String?

    static let home = "home"

    init(_ key: String, in book: ChannelBook) {
        if key.hasPrefix("b:") {
            guard let kitten = Self.unescape(key.dropFirst(2)), book.kitten(kitten)?.planned == false else {
                self.init(selection: nil, in: book)
                return
            }
            self.init(selection: nil, target: nil, key: Self.backlog(of: kitten))
            backlog = kitten
            return
        }
        if key.hasPrefix("r:") {
            guard let id = Self.unescape(key.dropFirst(2)), let entry = book.waiting.reports.first(where: { $0.id == id && $0.change == nil }), !book.talks.contains(entry.threadID) else {
                self.init(selection: .activity, in: book)
                return
            }
            let title = book.title(ofThread: entry.threadID)
            let target = MessageTarget.thread(id: entry.threadID, title: title.isEmpty ? entry.threadTitle : title, report: entry.id)
            self.init(selection: .thread(entry.threadID, in: .activity), target: target, key: key)
            return
        }
        guard var selection = Self.selection(key), !Self.staysOnMac(selection, in: book), Self.exists(selection.place, in: book) else {
            self.init(selection: nil, in: book)
            return
        }
        if let thread = selection.thread, let started = book.started[thread] { selection.thread = started }
        if let thread = selection.thread, !Self.leadsTo(thread, from: selection.place, in: book) {
            self.init(selection: selection.closed, target: nil, key: Self.key(selection.closed))
            return
        }
        self.init(selection: selection, in: book)
    }

    private static func staysOnMac(_ selection: ChannelSelection, in book: ChannelBook) -> Bool {
        if let thread = selection.thread, book.talks.contains(thread) || book.home(ofThread: thread) == .shades {
            return !book.onPhone.contains(thread)
        }
        return selection.channelID == .shades && book.onPhone.isEmpty
    }

    private static func exists(_ place: ChannelPlace, in book: ChannelBook) -> Bool {
        if case .channel(.kitten(let kitten)) = place { return book.kitten(kitten) != nil }
        return true
    }

    static func leadsTo(_ id: String, from place: ChannelPlace, in book: ChannelBook) -> Bool {
        switch place {
        case .channel(.shades):
            return book.onPhone.contains(id)
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
        if case .question = target { target = nil }
        if selection == .channel(.shades) { target = nil }
        self.init(selection: selection, target: target, key: selection.map(Self.key) ?? Self.home)
    }

    private init(selection: ChannelSelection?, target: MessageTarget?, key: String) {
        self.selection = selection
        self.target = target
        self.key = key
    }

    static func opening(_ selection: ChannelSelection, in book: ChannelBook) -> ChannelSelection? {
        let tries = [selection] + (selection.thread.map { [ChannelSelection.thread($0, in: .threads)] } ?? [])
        return tries.first { PhonePlace(key($0), in: book).selection == $0 }
    }

    func alsoSendTo(in book: ChannelBook) -> ChannelID? {
        guard case .thread(let id, _, _)? = target, let home = book.home(ofThread: id), home != .shades else { return nil }
        return home
    }

    static func key(_ selection: ChannelSelection) -> String {
        let place = key(selection.place)
        guard let thread = selection.thread else { return place }
        return "t:\(escape(thread))@\(place)"
    }

    static func thread(in key: String) -> String? {
        selection(key)?.thread
    }

    static func reply(to entry: InboxEntry) -> String {
        "r:\(escape(entry.id))"
    }

    static func backlog(of kitten: String) -> String {
        "b:\(escape(kitten))"
    }

    private static func key(_ place: ChannelPlace) -> String {
        switch place {
        case .activity: return "activity"
        case .threads: return "threads"
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
        case "activity", "needs": return .activity
        case "threads": return .threads
        case "shades", "general", "everyone": return .channel(.shades)
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

struct PhoneView: Encodable, Equatable {
    struct Place: Encodable, Equatable {
        var key: String
        var title: String
        var group: String?
        var count: Int?
        var unread: Bool
        var cat: String?
        var state: String?
        var dot: String?
        var icon: String?
    }

    struct Link: Encodable, Equatable {
        var label: String
        var open: String
    }

    struct Face: Encodable, Equatable {
        var cat: String?
        var color: String?
    }

    struct File: Encodable, Equatable {
        var name: String
        var picture: String?
        var web: String?
        var failed: Bool?
    }

    struct Box: Encodable, Equatable {
        var label: String
        var placeholder: String
        var ready = true
        var also: String?
        var files = true
    }

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
        var several = false
    }

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
        var faded: Bool?
        var cat: String?
        var dot: String?
        var mine: Bool?
        var going: Bool?
        var failure: String?
        var sending: Bool?
        var retry: Bool?
        var at: Double?
        var open: String?
        var clear: String?
        var done: Bool?
        var choices: [Choice]?
        var parts: [Part]?
        var context: String?
        var replies: Int?
        var lastReply: String?
        var faces: [Face]?
        var waiting: Bool?
        var reply: Reply?
        var more: Int?
        var unread: Bool?
        var files: [File]?
        var markup: [Markup.Block]?
        var reactions: [Choice]?
        var t3: String?
    }

    var key: String
    var title: String
    var subtitle: String?
    var cat: String?
    var link: Link?
    var back: String?
    var backTitle: String?
    var places: [Place]
    var rows: [Row]
    var box: Box?
    var unread: String?
    var cantReachT3: Bool
    var you: String?
    var marks = Reaction.allCases.map { Choice(label: $0.emoji, value: $0.rawValue) }
    var t3: String?
    var backlog: Link?

    init(_ place: PhonePlace, in book: ChannelBook, now: Date, newFrom: [String: String] = [:], t3 environment: String? = nil, priorities: Priorities = Priorities(), takesFiles: (MessageTarget) -> Bool = { $0.takesFiles }) {
        key = place.key
        places = Self.places(in: book)
        cantReachT3 = book.cantReachT3
        let also = place.alsoSendTo(in: book).map { CatWords.alsoSendTo(book.name(of: $0)) }
        box = place.target.map { target in
            var label = CatWords.target(target)
            if case .thread(let id, _, let report) = target, book.home(ofThread: id) == .shades {
                label = CatWords.target(.thread(id: id, title: "", report: report))
            }
            return Box(label: label, placeholder: CatWords.placeholder(target), ready: target.isReady, also: also, files: takesFiles(target))
        }
        if let kitten = place.backlog {
            let name = book.name(of: ChannelID.kitten(kitten))
            title = CatWords.backlogTitle
            subtitle = CatWords.backlogKeeper(name)
            cat = Self.cat(of: .kitten(kitten), in: book)
            back = PhonePlace.key(.channel(.kitten(kitten)))
            backTitle = name
            rows = Self.rows(of: priorities.backlogs[kitten] ?? Backlog())
            return
        }
        guard let selection = place.selection else {
            title = CatWords.appName
            subtitle = priorities.focus
            rows = []
            return
        }
        you = MessagesInk.picture.map { "data:image/jpeg;base64,\($0.base64EncodedString())" }
        if let thread = selection.thread {
            (title, subtitle) = ChannelHeader.words(forThread: thread, in: book)
            if book.home(ofThread: thread) == .shades { subtitle = book.name(of: .shades) }
            cat = book.home(ofThread: thread).flatMap { Self.cat(of: $0, in: book) }
            back = PhonePlace.key(selection.closed)
            backTitle = ChannelHeader.words(for: selection.place, in: book).title
            t3 = environment.flatMap { Self.t3($0, thread: thread, in: book) }
            rows = Self.rows(selection, in: book, now: now, newFrom: newFrom, t3: environment)
            if book.canMarkUnread(thread), let messages = book.threads[thread]?.messages.filter({ !$0.isSending }) {
                unread = newFrom[thread].flatMap { first in messages.first { $0.id == first }?.id } ?? (messages.last { $0.speaker != .you } ?? messages.last)?.id
            }
        } else {
            (title, subtitle) = ChannelHeader.words(for: selection.place, in: book)
            cat = selection.channelID.flatMap { Self.cat(of: $0, in: book) }
            if case .channel(.kitten(let kitten)) = selection.place, let count = book.issues.first(where: { $0.kitten.id == kitten })?.threads.count, count > 0 {
                link = Link(label: CatWords.issues(count), open: PhonePlace.key(.activity))
            }
            if case .channel(.kitten(let kitten)) = selection.place, let count = priorities.backlogs[kitten]?.items.count, count > 0 {
                backlog = Link(label: CatWords.backlog(count), open: PhonePlace.backlog(of: kitten))
            }
            back = PhonePlace.home
            backTitle = CatWords.appName
            if selection.place == .channel(.shades) { subtitle = CatWords.shadesOnPhone }
            rows = Self.rows(selection, in: book, now: now, newFrom: newFrom, t3: environment)
        }
    }

    private static func rows(of backlog: Backlog) -> [Row] {
        Backlog.Level.allCases.flatMap { level -> [Row] in
            let items = backlog.items.filter { $0.level == level }
            guard !items.isEmpty else { return [Row(kind: "section", title: level.rawValue), Row(kind: "note", text: CatWords.backlogEmpty)] }
            return [Row(kind: "section", title: level.rawValue)] + items.map { item in
                let about = [item.date, item.words.map { "\u{201C}\($0)\u{201D}" }].compactMap { $0 }.joined(separator: " · ")
                return Row(kind: "backlog", title: item.what, detail: about.isEmpty ? nil : about)
            }
        }
    }

    private static func rows(_ selection: ChannelSelection, in book: ChannelBook, now: Date, newFrom: [String: String], t3 environment: String?) -> [Row] {
        shown(selection, in: book, newFrom: newFrom).map { shown in
            var row = Self.row(shown, at: selection.place, in: book, now: now)
            let thread: String?
            switch shown {
            case .approval(let request): thread = book.thread(holding: request.id, else: request.threadID)
            case .question(let question): thread = book.thread(holding: question.id, else: question.threadID)
            case .report(let entry): thread = entry.threadID
            case .issue(let issue): thread = row.open == nil ? issue.id : nil
            default: thread = nil
            }
            row.t3 = environment.flatMap { environment in thread.flatMap { t3(environment, thread: $0, in: book) } }
            return row
        }
    }

    private static func t3(_ environment: String, thread: String, in book: ChannelBook) -> String? {
        guard case .kitten? = book.home(ofThread: thread) else { return nil }
        // Outside the repo: T3 Code's page builds its addresses with JavaScript's encodeURIComponent, which leaves these unescaped.
        let plain = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.!~*'()"))
        guard let place = environment.addingPercentEncoding(withAllowedCharacters: plain), let id = thread.addingPercentEncoding(withAllowedCharacters: plain) else { return nil }
        return "/\(place)/\(id)"
    }

    static func shown(_ selection: ChannelSelection, in book: ChannelBook, newFrom: [String: String] = [:]) -> [ChannelRow] {
        if let thread = selection.thread { return ChannelRows.thread(thread, in: book, newFrom: newFrom) }
        if selection.place == .channel(.shades) { return shownOnPhone(in: book) }
        return ChannelRows.rows(selection.place, in: book, newFrom: newFrom)
    }

    private static func shownOnPhone(in book: ChannelBook) -> [ChannelRow] {
        var rows: [ChannelRow] = []
        var day: ChannelRow?
        for row in ChannelRows.rows(.channel(.shades), in: book) {
            switch row {
            case .day:
                day = row
            case .parent(let post) where book.onPhone.contains(post.threadID):
                if let shown = day { rows.append(shown) }
                day = nil
                rows.append(row)
            default:
                break
            }
        }
        return rows
    }

    private static func places(in book: ChannelBook) -> [Place] {
        ChannelSidebarItem.groups(in: book).flatMap { group in
            group.items.filter { $0.place.channelID != .shades || !book.onPhone.isEmpty }.map { item in
                var cat: String?
                var state: String?
                var dot: UInt32?
                var icon: String?
                switch item.icon {
                case .kitten(let status):
                    cat = PhoneCat.key(PhoneCat.Pose(status.state), jacket: ChannelSpeakerLook.color(of: status.kitten))
                    state = CatWords.kittenState(status.state)
                    dot = item.badge > 0 ? nil : status.state.dot
                case .shades: cat = PhoneCat.key(.sit, jacket: nil)
                case .activity: icon = "activity"
                case .threads: icon = "threads"
                }
                return Place(
                    key: PhonePlace.key(ChannelSelection(item.place)),
                    title: item.title,
                    group: group.heading,
                    count: item.badge > 0 ? item.badge : nil,
                    unread: item.place == .channel(.shades) ? !book.unreadThreads.isDisjoint(with: book.onPhone) : item.isUnread,
                    cat: cat,
                    state: state,
                    dot: dot.map(hex),
                    icon: icon
                )
            }
        }
    }

    private static func cat(of channel: ChannelID, in book: ChannelBook) -> String? {
        guard case .kitten(let kitten) = channel, book.kitten(kitten) != nil else { return nil }
        return cat(of: ChannelSpeakerLook(.kitten(kitten), in: book))
    }

    private static func cat(of look: ChannelSpeakerLook, _ pose: PhoneCat.Pose = .sit) -> String? {
        look.hasCat ? PhoneCat.key(pose, jacket: look.jacket) : nil
    }

    private static func message(_ message: ChannelMessage, in book: ChannelBook) -> Row {
        let look = ChannelSpeakerLook(message.speaker, in: book)
        let text = message.text ?? (message.isStillGoing ? CatWords.stillGoing : nil)
        let files = book.home(ofThread: message.threadID) == .shades ? [] : message.files
        return Row(
            kind: "message",
            id: message.id,
            name: look.name,
            detail: message.earlierNotes > 0 ? CatWords.earlierNotes(message.earlierNotes) : nil,
            text: text,
            color: look.bubble.map(hex),
            faded: message.isStillGoing || message.isSending ? true : nil,
            cat: cat(of: look),
            mine: look.isYou,
            going: message.isStillGoing,
            failure: message.failure,
            sending: message.isSending ? true : nil,
            retry: message.canTryAgain ? true : nil,
            at: millis(message.at),
            files: files.isEmpty ? nil : files.map { file in
                File(
                    name: file.name,
                    picture: file.thumbnail.map { "data:image/jpeg;base64,\($0.base64EncodedString())" },
                    web: file.thumbnail == nil ? file.source?.webAddress?.absoluteString : nil,
                    failed: file.couldntShow ? true : nil
                )
            },
            markup: text.map { Markup($0, pulls: book.pulls).blocks },
            reactions: message.reactions?.map { Choice(label: $0.emoji, value: $0.rawValue) }
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
            let hidden = digest.channel == .shades && !book.onPhone.contains(digest.threadID)
            return Row(
                kind: "digest",
                id: digest.threadID,
                title: book.name(of: digest.channel),
                name: look.name,
                text: hidden ? Self.title(ofThread: digest.threadID, "", in: book) : digest.parent.text,
                color: look.bubble.map(hex),
                cat: cat(of: look),
                at: millis(digest.parent.at),
                open: hidden ? nil : PhonePlace.key(.thread(digest.threadID, in: .threads)),
                reply: hidden ? nil : reply,
                more: hidden || digest.more == 0 ? nil : digest.more,
                unread: digest.isUnread
            )
        case .replies(let count):
            return Row(kind: "replies", text: CatWords.replies(count))
        case .new(let count):
            return Row(kind: "new", detail: CatWords.jumpToNew(count), text: CatWords.new)
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
            return Row(
                kind: "issue",
                title: Self.title(ofThread: thread.id, thread.title, in: book),
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
            let title = Self.title(ofThread: book.thread(holding: request.id, else: request.threadID), request.threadTitle, in: book)
            return card("approval", id: request.id, kitten: kitten, title: title, text: request.summary, at: request.createdAt, in: book) {
                $0.choices = choices
            }
        case .question(let question):
            let kitten = book.kitten(of: question.id)
            let parts = (question.form?.parts ?? []).map { part in
                Part(text: part.text, choices: zip(part.options, part.values).map { Choice(label: $0, value: $1) }, words: part.takesOwnWords, several: part.picksSeveral)
            }
            let text = question.text.isEmpty ? CatWords.unreadableQuestion : question.text
            let title = Self.title(ofThread: book.thread(holding: question.id, else: question.threadID), question.threadTitle, in: book)
            return card("question", id: question.id, kitten: kitten, title: title, text: text, at: nil, in: book) {
                $0.parts = parts
                $0.footer = question.form == nil ? CatWords.answerInT3 : nil
            }
        case .report(let entry) where entry.change == nil && entry.ask != nil:
            let kitten = book.kitten(of: entry.id)
            let ask = entry.ask!
            let text = CatWords.askRow(ask, decision: ask.readFromWords ? entry.text : nil, by: kitten?.name ?? "it")
            return card("ask", id: entry.id, kitten: kitten, title: entry.threadTitle, text: text, at: entry.at, in: book) {
                $0.answer = ask.review
                $0.footer = entry.repliedAt == nil ? nil : CatWords.inboxSent
                $0.open = ask.readFromWords ? PhonePlace.reply(to: entry) : nil
                $0.choices = [Choice(label: "Deny", value: ApprovalDecision.decline.rawValue), Choice(label: "Allow", value: ApprovalDecision.accept.rawValue)]
                    + (ask.readFromWords ? [Choice(label: "Reply", value: "reply")] : [])
            }
        case .report(let entry) where entry.change != nil:
            return card("report", id: entry.id, kitten: book.kitten(of: entry.id), title: entry.threadTitle, text: entry.text, at: entry.at, in: book) {
                $0.answer = entry.change?.review
                $0.footer = CatWords.allowChangeOnMac
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
        case .older(let isLoading):
            return Row(kind: "older", text: isLoading ? CatWords.loadingOlder : CatWords.loadOlder, done: isLoading)
        }
    }

    static func title(ofThread id: String, _ title: String, in book: ChannelBook) -> String {
        if book.home(ofThread: id).map({ $0 != .shades }) ?? (book.listed[id] != nil) { return title }
        guard let parent = book.threads[id]?.parent, parent.speaker == .you, let words = parent.text else { return CatWords.shades }
        return ChannelRows.firstWords(of: words)
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
        Opal.hex(color)
    }
}

extension PhoneView {
    func since(_ shown: PhoneView?) -> PhoneView {
        guard let shown else { return self }
        var before: [String: Row] = [:]
        var twice: Set<String> = []
        for row in shown.rows {
            guard let id = row.id else { continue }
            if before.updateValue(row, forKey: id) != nil { twice.insert(id) }
        }
        var sent = self
        sent.rows = rows.map { row in
            guard let id = row.id, !twice.contains(id), before[id] == row else { return row }
            return Row(kind: "same", id: id)
        }
        return sent
    }

    func parts() -> [Data] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var bare = self
        bare.rows = []
        guard let whole = try? encoder.encode(bare), let at = whole.range(of: Data(#""rows":[]"#.utf8)) else { return [] }
        var parts = [Data(whole[..<(at.upperBound - 1)])]
        for (index, row) in rows.enumerated() {
            guard var pieces = Self.pieces(of: row, encoder) else { return [] }
            if index > 0 { pieces[0] = Data(",".utf8) + pieces[0] }
            parts += pieces
        }
        return parts + [Data(whole[(at.upperBound - 1)...])]
    }

    private static func pieces(of row: Row, _ encoder: JSONEncoder) -> [Data]? {
        var rest = row
        (rest.title, rest.answer, rest.reply, rest.context) = (nil, nil, nil, nil)
        guard var body = try? encoder.encode(rest) else { return nil }
        var apart: [Data] = []
        for (key, value) in [("title", row.title), ("answer", row.answer), ("context", row.context)] {
            guard let value else { continue }
            guard let json = try? encoder.encode(value) else { return nil }
            apart.append(Data(",\"\(key)\":".utf8) + json)
        }
        if let reply = row.reply {
            guard let json = try? encoder.encode(reply) else { return nil }
            apart.append(Data(",\"reply\":".utf8) + json)
        }
        guard !apart.isEmpty else { return [body] }
        body.removeLast()
        apart[apart.count - 1] += Data("}".utf8)
        return [body] + apart
    }
}
