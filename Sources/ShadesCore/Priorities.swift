import Foundation

/// What comes first right now, and what each kitten has waiting, from the plain files the kittens keep: the focus in
/// `FOCUS.md` and each kitten's `backlog.md`. Only The Kitty Litter's window reads them, since they're for you to see,
/// so nothing here ever reaches a prompt, the phone or the cat. See docs/kittens.md.
public struct Priorities: Equatable, Sendable {
    /// The first line under "## Right now", bold taken off, or `nil` with no focus.
    public var focus: String?
    /// Each kitten's backlog, by the kitten's ID.
    public var backlogs: [String: Backlog]

    public init(focus: String? = nil, backlogs: [String: Backlog] = [:]) {
        self.focus = focus
        self.backlogs = backlogs
    }

    /// A file that's missing or can't be read is left out, so it can't take the rest with it.
    public static func read(for kittens: [Kitten], in folder: URL = Kittens.defaultFolder) -> Priorities {
        let text = { (url: URL) in try? String(contentsOf: url, encoding: .utf8) }
        var backlogs: [String: Backlog] = [:]
        for kitten in kittens where !kitten.folder.isEmpty {
            backlogs[kitten.id] = text(URL(fileURLWithPath: kitten.folder).appendingPathComponent("backlog.md")).map(Backlog.init(reading:))
        }
        return Priorities(focus: text(folder.appendingPathComponent("FOCUS.md")).flatMap(focus(in:)), backlogs: backlogs)
    }

    /// The line as written, or `nil` when the section is missing, empty or says there's no focus.
    public static func focus(in text: String) -> String? {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let heading = lines.firstIndex(where: { $0.lowercased() == "## right now" }),
              let line = lines[(heading + 1)...].first(where: { !$0.isEmpty }), !line.hasPrefix("#")
        else { return nil }
        let shown = line.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
        return shown.isEmpty || shown.lowercased().hasPrefix("no focus") ? nil : shown
    }
}

/// A kitten's `backlog.md`: one line an item under Doing, Next and Later, each `date · what · "your words" · thread
/// <id>`. A line in another form still shows, as it's written.
public struct Backlog: Equatable, Sendable {
    public enum Level: String, CaseIterable, Sendable {
        case doing = "Doing"
        case next = "Next"
        case later = "Later"
    }

    public struct Item: Equatable, Sendable {
        public var level: Level
        public var date: String?
        public var what: String
        /// Your own words, which approved it, without their quotes.
        public var words: String?
        public var thread: String?

        public init(level: Level, date: String? = nil, what: String, words: String? = nil, thread: String? = nil) {
            self.level = level
            self.date = date
            self.what = what
            self.words = words
            self.thread = thread
        }

        /// From the ends in, so a ` · ` in your words stays in them.
        init?(level: Level, line: String) {
            var parts = line.components(separatedBy: " · ").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count > 1, let last = parts.last, last.hasPrefix("thread ") {
                thread = String(last.dropFirst("thread ".count)).trimmingCharacters(in: .whitespaces)
                parts.removeLast()
            }
            if parts.count > 1, parts[0].count == 10, parts[0].allSatisfy({ $0.isNumber || $0 == "-" }) {
                date = parts.removeFirst()
            }
            guard let first = parts.first, !first.isEmpty else { return nil }
            self.level = level
            what = first
            let rest = parts.dropFirst().joined(separator: " · ")
            words = rest.isEmpty ? nil : Self.unquoted(rest)
        }

        private static func unquoted(_ text: String) -> String {
            let quotes: Set<Character> = ["\"", "\u{201C}", "\u{201D}"]
            guard text.count > 1, let first = text.first, let last = text.last, quotes.contains(first), quotes.contains(last) else { return text }
            return String(text.dropFirst().dropLast())
        }
    }

    /// Doing first, then Next and Later, each oldest first, as the file has them.
    public var items: [Item]

    public init(items: [Item] = []) {
        self.items = items
    }

    /// Only items under a heading it knows count, so notes above them don't.
    public init(reading text: String) {
        var level: Level?
        var items: [Item] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") {
                let heading = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces).lowercased()
                level = Level.allCases.first { heading.hasPrefix($0.rawValue.lowercased()) }
            } else if let level, line.hasPrefix("- "), let item = Item(level: level, line: String(line.dropFirst(2))) {
                items.append(item)
            }
        }
        self.items = Level.allCases.flatMap { level in items.filter { $0.level == level } }
    }
}
