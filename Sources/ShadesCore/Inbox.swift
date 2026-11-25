import Foundation

public struct InboxEntry: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case decision, shipped, note
    }

    public var id: String
    public var kind: Kind
    public var text: String
    public var threadID: String
    public var threadTitle: String
    public var at: Date
    public var repliedAt: Date?
    public var answer: String?
    public var questionID: String?
    public var change: ChangeRequest?
    public var ask: AskRequest?
    public var raisedAt: Date?
    public var turnSeenAt: Date?
    public var pullRequest: Int?

    public init(
        id: String,
        kind: Kind,
        text: String,
        threadID: String,
        threadTitle: String,
        at: Date,
        repliedAt: Date? = nil,
        answer: String? = nil,
        questionID: String? = nil,
        change: ChangeRequest? = nil,
        ask: AskRequest? = nil,
        raisedAt: Date? = nil,
        turnSeenAt: Date? = nil,
        pullRequest: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.threadID = threadID
        self.threadTitle = threadTitle
        self.at = at
        self.repliedAt = repliedAt
        self.answer = answer
        self.questionID = questionID
        self.change = change
        self.ask = ask
        self.raisedAt = raisedAt
        self.turnSeenAt = turnSeenAt
        self.pullRequest = pullRequest
    }

    public var needsYou: Bool { kind == .decision && repliedAt == nil }

    public var isStanding: Bool { change != nil || ask?.readFromWords == false }

    func isAsked(by thread: String) -> Bool {
        threadID == thread || change?.alsoAskedIn.contains(thread) == true
    }

    func asksForSame(as other: InboxEntry) -> Bool {
        if let change, let asked = other.change {
            return !change.file.isEmpty && (change.file, change.replace) == (asked.file, asked.replace)
        }
        guard let ask, let asked = other.ask else { return false }
        return !ask.readFromWords && !asked.readFromWords && ask.ask == asked.ask
    }

    var followsItsThread: Bool { kind == .decision && !isStanding }
}

public struct Inbox: Codable, Equatable, Sendable {
    public private(set) var entries: [InboxEntry] = []
    private var since: Date
    private var handled: [String: String] = [:]
    private var read: [String: String]?
    private var readTo: [String: String]?
    private var markedUnread: Set<String>?
    private var corrections: Set<String>?
    private var general: [String: Date]?
    private var withShades: [String: Date]?
    private var answeredInGeneral: [String: Date]?
    private var alsoShownInGeneral: [String: ShownInGeneral]?
    private var missed: [Missed]?
    private var alsoShown: [String: Date]?
    private var shownOnPhone: [String: Date]?
    private var reacted: [String: Reacted]?
    private var forYou: [String: Date]?
    public var record = WaitingRecord()

    private enum CodingKeys: String, CodingKey {
        case entries, since, handled, read, readTo, markedUnread, corrections, general, withShades, answeredInGeneral
        case alsoShownInGeneral, missed, alsoShown, shownOnPhone, reacted, forYou
    }

    public static let placesKept = 300

    public init(since: Date) {
        self.since = since
    }

    public var messagesThreads: [String: Date] {
        get { general ?? [:] }
        set { general = Self.newest(newValue) }
    }

    public var catsWork: [String: Date] {
        get { withShades ?? [:] }
        set { withShades = Self.newest(newValue) }
    }

    public var onPhone: [String: Date] {
        get { shownOnPhone ?? [:] }
        set { shownOnPhone = Self.newest(newValue) }
    }

    public var away: [Missed] {
        get { missed ?? [] }
        set { missed = newValue.filter { if case .line = $0 { false } else { true } } }
    }

    public var alsoSent: [String: Date] {
        get { alsoShown ?? [:] }
        set { alsoShown = Self.newest(newValue) }
    }

    public var reactions: [String: [Reaction]] {
        (reacted ?? [:]).compactMapValues { kept in
            let reactions = kept.reactions.compactMap(Reaction.init(rawValue:))
            return reactions.isEmpty ? nil : reactions
        }
    }

    public mutating func react(_ reaction: Reaction, to message: String, at date: Date) {
        var reacted = self.reacted ?? [:]
        var kept = reacted[message] ?? Reacted(reactions: [], at: date)
        if kept.reactions.contains(reaction.rawValue) {
            kept.reactions.removeAll { $0 == reaction.rawValue }
        } else {
            kept.reactions.append(reaction.rawValue)
            kept.at = date
        }
        reacted[message] = kept.reactions.isEmpty ? nil : kept
        self.reacted = Self.newest(reacted) { $0.at }
    }

    private struct Reacted: Codable, Equatable, Sendable {
        var reactions: [String]
        var at: Date
    }

    private struct ShownInGeneral: Codable, Equatable, Sendable {
        var thread: String
        var at: Date
    }

    private static func newest(_ ids: [String: Date]) -> [String: Date] {
        newest(ids) { $0 }
    }

    private static func newest<Kept>(_ ids: [String: Kept], at: (Kept) -> Date) -> [String: Kept] {
        guard ids.count > placesKept else { return ids }
        let kept = ids.sorted { (at($0.value), $0.key) > (at($1.value), $1.key) }.prefix(placesKept)
        return Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
    }

    public func owes(_ thread: AgentThread) -> Bool {
        guard thread.status == .completed || thread.status == .failed || thread.turnEnded,
              let run = thread.lastRunID,
              handled[thread.id] != run
        else { return false }
        return (thread.lastRunEndedAt ?? thread.updatedAt) >= since
    }

    private var waiting: [InboxEntry] { entries.filter(\.needsYou) }

    private mutating func log(
        since before: [InboxEntry],
        at date: Date,
        leaving exit: WaitingVisit.Exit,
        exits: [String: WaitingVisit.Exit] = [:],
        entering: (startedBy: WaitingVisit.Starter, held: Bool, source: WaitingVisit.Source)? = nil
    ) {
        let now = waiting
        let still = Set(now.map(\.id))
        let was = Set(before.map(\.id))
        for entry in before where !still.contains(entry.id) { record.left(entry.id, exits[entry.id] ?? exit, at: date) }
        guard let entering else { return }
        for entry in now where !was.contains(entry.id) {
            record.entered(entry, startedBy: entering.startedBy, held: entering.held, source: entering.source, at: date)
        }
    }

    private static func raised(_ thread: AgentThread, filedAt date: Date) -> Date {
        min(date, thread.lastRunEndedAt ?? date)
    }

    private static func openPullRequest(of thread: AgentThread) -> Int? {
        thread.pullRequest.flatMap { $0.isOpen ? $0.number : nil }
    }

    @discardableResult
    public mutating func file(_ sorted: SortedReport, from thread: AgentThread, startedBy: WaitingVisit.Starter, at: Date, id: () -> String) -> Bool {
        guard let run = thread.lastRunID, handled[thread.id] != run else { return false }
        handled[thread.id] = run
        let before = waiting

        func add(_ kind: InboxEntry.Kind, _ text: String) {
            entries.append(InboxEntry(
                id: id(), kind: kind, text: text, threadID: thread.id, threadTitle: thread.title, at: at,
                raisedAt: Self.raised(thread, filedAt: at), pullRequest: Self.openPullRequest(of: thread)
            ))
        }
        guard sorted.decision != nil || sorted.shipped != nil else {
            guard let note = sorted.note else { return false }
            if let row = rowYouAskedOn(from: thread.id) {
                entries[row].answer = note
                entries[row].repliedAt = nil
                entries[row].raisedAt = Self.raised(thread, filedAt: at)
                log(since: before, at: at, leaving: .reportDidntAsk, entering: (startedBy, thread.turnEnded, .answerToYou))
                return true
            }
            if !sorted.isOpening { entries.removeAll { $0.threadID == thread.id && $0.followsItsThread } }
            if let row = entries.lastIndex(where: { $0.threadID == thread.id && $0.kind != .decision && !$0.isStanding && $0.ask == nil }) {
                entries[row].answer = [entries[row].answer, note].compactMap { $0 }.joined(separator: "\n\n")
            } else {
                add(.note, note)
            }
            log(since: before, at: at, leaving: .reportDidntAsk)
            return false
        }

        entries.removeAll { $0.threadID == thread.id && $0.followsItsThread }
        for index in entries.indices where entries[index].threadID == thread.id {
            entries[index].repliedAt = nil
        }
        if let decision = sorted.decision { add(.decision, [decision, sorted.note].compactMap { $0 }.joined(separator: " ")) }
        if let shipped = sorted.shipped { add(.shipped, [shipped, sorted.decision == nil ? sorted.note : nil].compactMap { $0 }.joined(separator: " ")) }
        let source: WaitingVisit.Source = thread.status == .failed ? .failedRun : .sorter
        log(since: before, at: at, leaving: .superseded, entering: (startedBy, thread.turnEnded, source))
        return true
    }

    public mutating func flag(_ decision: String, from thread: AgentThread, startedBy: WaitingVisit.Starter, at: Date, id: String) {
        let before = waiting
        entries.removeAll { $0.threadID == thread.id && $0.followsItsThread }
        entries.append(InboxEntry(
            id: id, kind: .decision, text: decision, threadID: thread.id, threadTitle: thread.title, at: at,
            raisedAt: Self.raised(thread, filedAt: at), pullRequest: Self.openPullRequest(of: thread)
        ))
        log(since: before, at: at, leaving: .superseded, entering: (startedBy, thread.turnEnded, .sorter))
    }

    public mutating func ask(_ entry: InboxEntry, startedBy: WaitingVisit.Starter, held: Bool, title: (String) -> String? = { _ in nil }) {
        var before = waiting
        let again = entries.first { $0.needsYou && $0.threadID == entry.threadID && $0.asksForSame(as: entry) }?.id
        add(asked: entry, title: title)
        if let again, !entries.contains(where: { $0.id == again }), entries.contains(where: { $0.id == entry.id && $0.needsYou }) {
            record.renamed(again, to: entry.id)
            before = before.map { $0.id == again ? entry : $0 }
        }
        log(since: before, at: entry.at, leaving: .superseded, entering: (startedBy, held, .requestCard))
    }

    private mutating func add(asked entry: InboxEntry, title: (String) -> String?) {
        guard entry.isStanding, !entries.contains(where: { $0.id == entry.id }) else { return }
        for index in entries.indices.reversed() where entries[index].isAsked(by: entry.threadID) && entries[index].asksForSame(as: entry) {
            leave(index, by: entry.threadID, title: title)
        }
        guard let change = entry.change else { return entries.append(entry) }
        let same = entries.firstIndex { other in
            guard let asked = other.change, asked.problem == nil, change.problem == nil else { return false }
            return (asked.file, asked.replace, asked.with) == (change.file, change.replace, change.with)
        }
        guard let same else { return entries.append(entry) }
        if entries[same].threadID != entry.threadID, entries[same].change?.alsoAskedIn.contains(entry.threadID) == false {
            entries[same].change?.alsoAskedIn.append(entry.threadID)
        }
    }

    public mutating func withdraw(_ asked: String, file: String?, by thread: String, at date: Date, title: (String) -> String? = { _ in nil }) {
        let before = waiting
        for index in entries.indices.reversed() where entries[index].isAsked(by: thread) {
            let entry = entries[index]
            let named = entry.change.map { !$0.file.isEmpty && ($0.file == asked || $0.file == file) } ?? (entry.isStanding && entry.ask?.ask == asked)
            if named { leave(index, by: thread, title: title) }
        }
        log(since: before, at: date, leaving: .withdrawn)
    }

    public mutating func cantBeMade(_ id: String, because reason: String, row: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }), entries[index].change?.problem == nil else { return }
        entries[index].change?.problem = reason
        entries[index].change?.review = nil
        entries[index].text = row
    }

    private mutating func leave(_ index: Int, by thread: String, title: (String) -> String?) {
        guard var change = entries[index].change, !change.alsoAskedIn.isEmpty else {
            entries.remove(at: index)
            return
        }
        if let share = change.alsoAskedIn.firstIndex(of: thread) {
            change.alsoAskedIn.remove(at: share)
        } else {
            let next = change.alsoAskedIn.removeFirst()
            entries[index].threadID = next
            entries[index].threadTitle = title(next) ?? entries[index].threadTitle
        }
        entries[index].change = change
    }

    @discardableResult
    public mutating func attach(_ ask: AskRequest, to id: String) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == id }), entries[index].kind == .decision, !entries[index].isStanding,
              entries[index].ask == nil, entries[index].repliedAt == nil, entries[index].answer == nil else { return false }
        entries[index].ask = ask
        return true
    }

    private func rowYouAskedOn(from threadID: String) -> Int? {
        entries.indices
            .filter { entries[$0].threadID == threadID && !entries[$0].isStanding && entries[$0].ask == nil && entries[$0].repliedAt != nil }
            .max { entries[$0].repliedAt! < entries[$1].repliedAt! }
    }

    @discardableResult
    public mutating func follow(_ threads: [AgentThread], at date: Date) -> Bool {
        guard !threads.isEmpty else { return false }
        let listed = Dictionary(threads.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let before = waiting
        var exits: [String: WaitingVisit.Exit] = [:]
        var changed = false
        for index in entries.indices.reversed() where !entries[index].isStanding {
            let entry = entries[index]
            let exit = listed[entry.threadID].map { Self.movedOn(entry, $0) } ?? .archived
            guard let exit else { continue }
            if exit == .replied {
                entries[index].turnSeenAt = listed[entry.threadID]?.lastRunStartedAt
                if entry.followsItsThread, entry.repliedAt == nil {
                    entries[index].repliedAt = date
                    exits[entry.id] = .replied
                }
            } else if entry.followsItsThread {
                entries.remove(at: index)
                exits[entry.id] = exit
            } else {
                guard entry.repliedAt != nil else { continue }
                entries[index].repliedAt = nil
            }
            changed = true
        }
        log(since: before, at: date, leaving: .turnWithoutYou, exits: exits)
        return changed
    }

    static func movedOn(_ entry: InboxEntry, _ thread: AgentThread) -> WaitingVisit.Exit? {
        let raised = entry.raisedAt ?? entry.at
        let since = max(raised, entry.turnSeenAt ?? raised)
        if let number = entry.pullRequest, let pull = thread.pullRequest, pull.number == number {
            if pull.state == "merged" { return .pullRequestMerged }
            if pull.state == "closed" { return .pullRequestClosed }
        }
        if let settled = thread.settledAt, settled > raised { return .settled }
        guard let started = thread.lastRunStartedAt, started > since else { return nil }
        if let words = thread.lastWordsFromYouAt, words > since { return .replied }
        return .turnWithoutYou
    }

    public mutating func anotherThreadWrote(to threadID: String, at date: Date) {
        let before = waiting
        entries.removeAll { $0.threadID == threadID && $0.followsItsThread }
        for index in entries.indices where entries[index].threadID == threadID && !entries[index].isStanding {
            entries[index].repliedAt = nil
        }
        log(since: before, at: date, leaving: .turnWithoutYou)
    }

    public mutating func startedForYou(_ threadID: String, at date: Date) {
        var marks = forYou ?? [:]
        marks[threadID] = date
        forYou = Self.newest(marks)
    }

    public func wasStartedForYou(_ threadID: String) -> Bool {
        forYou?[threadID] != nil
    }

    public func isUnread(_ thread: AgentThread) -> Bool {
        guard !thread.status.isActive || thread.turnEnded else { return false }
        if markedUnread?.contains(thread.id) == true { return true }
        guard let run = thread.lastRunID, read?[thread.id] != run, !thread.wasSeenInT3 else { return false }
        return (thread.lastRunEndedAt ?? thread.updatedAt) >= since
    }

    public mutating func markRead(_ threads: [AgentThread], upTo last: (String) -> String? = { _ in nil }) -> Bool {
        var changed = false
        for thread in threads {
            if isUnread(thread) {
                var marks = read ?? [:]
                marks[thread.id] = thread.lastRunID
                read = marks
                markedUnread?.remove(thread.id)
                changed = true
            }
            if let message = last(thread.id), readTo?[thread.id] != message {
                var marks = readTo ?? [:]
                marks[thread.id] = message
                readTo = marks
                changed = true
            }
        }
        return changed
    }

    public mutating func markUnread(_ threadID: String, from message: String, of messages: [String]) {
        guard let index = messages.firstIndex(of: message) else { return }
        if index == 0 {
            readTo?[threadID] = nil
            read?[threadID] = nil
        } else {
            var marks = readTo ?? [:]
            marks[threadID] = messages[index - 1]
            readTo = marks
        }
        markedUnread = (markedUnread ?? []).union([threadID])
    }

    public func firstNew(in thread: AgentThread, among messages: [(id: String, isYours: Bool)]) -> String? {
        guard isUnread(thread), let latest = messages.last else { return nil }
        let new: ArraySlice<(id: String, isYours: Bool)>
        if let seen = readTo?[thread.id] {
            new = messages.firstIndex { $0.id == seen }.map { messages[($0 + 1)...] } ?? [latest]
        } else if read?[thread.id] == nil {
            new = messages[...]
        } else {
            new = [latest]
        }
        let marked = markedUnread?.contains(thread.id) == true
        return new.first { marked || !$0.isYours }?.id
    }

    public mutating func noteCorrection(in threadID: String) {
        corrections = (corrections ?? []).union([threadID])
    }

    public mutating func forgetCorrection(in threadID: String) {
        corrections?.remove(threadID)
    }

    public func wasCorrected(_ threadID: String) -> Bool {
        corrections?.contains(threadID) == true
    }

    public mutating func skip(_ thread: AgentThread) {
        if let run = thread.lastRunID { handled[thread.id] = run }
    }

    public mutating func markReplied(_ id: String, at date: Date?) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let before = waiting
        entries[index].repliedAt = date
        if date != nil, entries[index].ask?.readFromWords == true { entries[index].ask = nil }
        if let date {
            log(since: before, at: date, leaving: .replied)
        } else if entries[index].needsYou {
            record.cameBack(id)
        }
    }

    public mutating func remove(_ id: String, because exit: WaitingVisit.Exit, at date: Date) {
        let before = waiting
        entries.removeAll { $0.id == id }
        log(since: before, at: date, leaving: exit)
    }

    public mutating func clear(_ kind: InboxEntry.Kind, at date: Date) {
        let before = waiting
        entries.removeAll { $0.kind == kind }
        log(since: before, at: date, leaving: .done)
    }

    public static func panelOrder(_ entries: [InboxEntry]) -> [InboxEntry] {
        func rank(_ entry: InboxEntry) -> Int {
            switch entry.kind {
            case .decision: return entry.needsYou ? 0 : 1
            case .shipped: return 2
            case .note: return 3
            }
        }
        return entries.enumerated()
            .sorted { (rank($0.element), $1.element.at, $1.offset) < (rank($1.element), $0.element.at, $0.offset) }
            .map(\.element)
    }

    public static func load(from file: URL, now: Date) -> Inbox {
        var inbox = read(from: file, now: now)
        inbox.record = WaitingRecord.load(beside: file)
        return inbox
    }

    private static func read(from file: URL, now: Date) -> Inbox {
        let manager = FileManager.default
        guard manager.fileExists(atPath: file.path) else { return Inbox(since: now) }
        if let data = try? Data(contentsOf: file), let inbox = try? JSONDecoder().decode(Inbox.self, from: data) { return inbox }

        let written = (try? manager.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
        let broken = file.deletingLastPathComponent().appendingPathComponent("inbox.broken.json")
        try? manager.removeItem(at: broken)
        try? manager.moveItem(at: file, to: broken)
        return Inbox(since: written ?? now)
    }

    public func save(to file: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try PrivateFile.write(try encoder.encode(self), to: file)
        try record.save(beside: file)
    }
}

public struct SortedReport: Equatable, Sendable {
    private static let lineLimit = 400

    public var shipped: String?
    public var decision: String?
    public var note: String?
    public var passedOn: Bool
    public var isOpening: Bool

    public init(shipped: String? = nil, decision: String? = nil, note: String? = nil, passedOn: Bool = false, isOpening: Bool = false) {
        self.shipped = shipped
        self.decision = decision
        self.note = note
        self.passedOn = passedOn
        self.isOpening = isOpening
    }

    public var hasLines: Bool { shipped != nil || decision != nil || note != nil }

    public init?(reply: String) {
        var found: [String: [String]] = [:]
        var current: String?
        for line in reply.components(separatedBy: .newlines) {
            var words = line.trimmingCharacters(in: .whitespaces)
            let markers = [Prompts.shippedMarker, Prompts.decisionMarker, Prompts.noteMarker, Prompts.passedMarker]
            if let marker = markers.first(where: { words.range(of: $0, options: [.anchored, .caseInsensitive]) != nil }) {
                current = marker
                words = String(words.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
            }
            if let current, !words.isEmpty { found[current, default: []].append(words) }
        }
        func value(_ marker: String) -> String? {
            guard let text = found[marker]?.joined(separator: " ") else { return nil }
            if text.trimmingCharacters(in: CharacterSet(charactersIn: " .")).lowercased() == "none" { return nil }
            return text.count > Self.lineLimit ? String(text.prefix(Self.lineLimit - 1)) + "…" : text
        }
        self.init(
            shipped: value(Prompts.shippedMarker),
            decision: value(Prompts.decisionMarker),
            note: value(Prompts.noteMarker),
            passedOn: value(Prompts.passedMarker)?.lowercased().hasPrefix("yes") == true
        )
        if !hasLines, !passedOn { return nil }
    }
}

public enum Missed: Codable, Hashable, Sendable {
    case thread(String)
    case approval(String)
    case question(String)
    case line(String)
}

public enum Reaction: String, CaseIterable, Sendable {
    case thumbsUp, check, eyes, heart, laugh, tada

    public var emoji: String {
        switch self {
        case .thumbsUp: "👍"
        case .check: "✅"
        case .eyes: "👀"
        case .heart: "❤️"
        case .laugh: "😂"
        case .tada: "🎉"
        }
    }
}
