import Foundation

/// One line in the inbox. It's something an agent said, so it can only be read.
public struct InboxEntry: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        /// `note` is anything else a thread had to say. It waits in the panel, and doesn't count as having shipped.
        case decision, shipped, note
    }

    public var id: String
    public var kind: Kind
    public var text: String
    public var threadID: String
    public var threadTitle: String
    public var at: Date
    /// When you last replied. It stops asking until the thread answers.
    public var repliedAt: Date?
    /// The thread's answer to your follow-up.
    public var answer: String?
    /// Set only on the live question rows, which are never saved.
    public var questionID: String?

    public init(
        id: String,
        kind: Kind,
        text: String,
        threadID: String,
        threadTitle: String,
        at: Date,
        repliedAt: Date? = nil,
        answer: String? = nil,
        questionID: String? = nil
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
    }

    public var needsYou: Bool { kind == .decision && repliedAt == nil }
}

/// What's waiting for you, and which runs have been dealt with. Saved as one file, so a report
/// is either filed or still owed, whenever the app stops.
public struct Inbox: Codable, Equatable, Sendable {
    public private(set) var entries: [InboxEntry] = []
    /// Runs that ended before this aren't news, so switching it on doesn't bring up old work.
    private var since: Date
    /// Each thread's last run that's been dealt with. Only IDs.
    private var handled: [String: String] = [:]
    /// Each thread's last run you've seen in Messages. Only IDs, and files from before Messages don't have it.
    private var read: [String: String]?

    public init(since: Date) {
        self.since = since
    }

    /// Finished, has a run ID, that run isn't handled, and it ended at or after `since`.
    public func owes(_ thread: AgentThread) -> Bool {
        guard thread.status == .completed || thread.status == .failed,
              let run = thread.lastRunID,
              handled[thread.id] != run
        else { return false }
        // A run with no end time still needs filing, or a thread that keeps to the inbox would say nothing at all.
        return (thread.lastRunEndedAt ?? thread.updatedAt) >= since
    }

    /// Records the run and files the lines in one change, so a save can't separate them. Does nothing if that
    /// run is already handled. Whatever a report turns out to be, it ends up here, where a restart can't lose it.
    /// Says whether that's worth telling you about, which a note you didn't ask for isn't.
    @discardableResult
    public mutating func file(_ sorted: SortedReport, from thread: AgentThread, at: Date, id: () -> String) -> Bool {
        guard let run = thread.lastRunID, handled[thread.id] != run else { return false }
        handled[thread.id] = run

        func add(_ kind: InboxEntry.Kind, _ text: String) {
            entries.append(InboxEntry(id: id(), kind: kind, text: text, threadID: thread.id, threadTitle: thread.title, at: at))
        }
        guard sorted.decision != nil || sorted.shipped != nil else {
            guard let note = sorted.note else { return false }
            guard let row = rowForNote(from: thread.id) else {
                add(.note, note)
                return false
            }
            // An answer to what you just asked replaces the last one, which you've seen. Anything else waits with it.
            let asked = entries[row].repliedAt != nil
            let earlier = asked ? nil : entries[row].answer
            entries[row].answer = [earlier, note].compactMap { $0 }.joined(separator: "\n\n")
            entries[row].repliedAt = nil
            return asked
        }

        entries.removeAll { $0.threadID == thread.id && $0.kind == .decision }
        for index in entries.indices where entries[index].threadID == thread.id {
            entries[index].repliedAt = nil
        }
        // Only one row takes the note, so it isn't said twice.
        if let decision = sorted.decision { add(.decision, [decision, sorted.note].compactMap { $0 }.joined(separator: " ")) }
        if let shipped = sorted.shipped { add(.shipped, [shipped, sorted.decision == nil ? sorted.note : nil].compactMap { $0 }.joined(separator: " ")) }
        return true
    }

    /// The row you asked on, or failing that the thread's open decision, or its latest row.
    private func rowForNote(from threadID: String) -> Int? {
        let own = entries.indices.filter { entries[$0].threadID == threadID }
        return own.filter { entries[$0].repliedAt != nil }.max { entries[$0].repliedAt! < entries[$1].repliedAt! }
            ?? own.last { entries[$0].kind == .decision }
            ?? own.last
    }

    /// A run that ended while you weren't looking. One still going isn't news yet.
    public func isUnread(_ thread: AgentThread) -> Bool {
        guard !thread.status.isActive, let run = thread.lastRunID, read?[thread.id] != run else { return false }
        return (thread.lastRunEndedAt ?? thread.updatedAt) >= since
    }

    /// Says whether that changed anything, so it's only saved when it did.
    /// shortcut: this grows by a short line per thread, prune it if that ever matters.
    public mutating func markRead(_ threads: [AgentThread]) -> Bool {
        let unread = threads.filter(isUnread)
        guard !unread.isEmpty else { return false }
        var marks = read ?? [:]
        for thread in unread { marks[thread.id] = thread.lastRunID }
        read = marks
        return true
    }

    /// Handled with no rows: it only passed the work on.
    public mutating func skip(_ thread: AgentThread) {
        if let run = thread.lastRunID { handled[thread.id] = run }
    }

    /// `nil` puts it back, for when the send failed.
    public mutating func markReplied(_ id: String, at date: Date?) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].repliedAt = date
    }

    public mutating func remove(_ id: String) {
        entries.removeAll { $0.id == id }
    }

    public mutating func clear(_ kind: InboxEntry.Kind) {
        entries.removeAll { $0.kind == kind }
    }

    /// Needs you, then replied decisions, then shipped, then notes, newest first within each. Later in the list counts as newer.
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

    /// With no file, it starts fresh from now. A broken file is kept for looking at, and anything
    /// that ended after it was last written still counts as news.
    public static func load(from file: URL, now: Date) -> Inbox {
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
        let manager = FileManager.default
        try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        // Reports can hold anything from a kitten's folder, so it's only ever yours to read, even mid-save.
        let temp = file.deletingLastPathComponent().appendingPathComponent(".\(file.lastPathComponent).\(UUID().uuidString)")
        let descriptor = open(temp.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { try? manager.removeItem(at: temp) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        try handle.write(contentsOf: data)
        try handle.close()
        guard rename(temp.path, file.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }
}

/// What a report comes to. A line can't do anything but be read.
public struct SortedReport: Equatable, Sendable {
    private static let lineLimit = 400

    public var shipped: String?
    public var decision: String?
    public var note: String?
    /// All it did was start another thread to do the work.
    public var passedOn: Bool

    public init(shipped: String? = nil, decision: String? = nil, note: String? = nil, passedOn: Bool = false) {
        self.shipped = shipped
        self.decision = decision
        self.note = note
        self.passedOn = passedOn
    }

    public var hasLines: Bool { shipped != nil || decision != nil || note != nil }

    /// `nil` when the reply has nothing to file. Takes lines by marker, joins continuation lines with a space,
    /// ignores anything before the first marker, drops empty or "none" values, cuts each to 400 characters.
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
        // A reply of nothing but "none" would otherwise lose the report without a word.
        if !hasLines, !passedOn { return nil }
    }
}
