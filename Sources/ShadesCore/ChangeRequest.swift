import Foundation

/// A kitten asking for a change to a settings file, which its own sandbox won't let it make. It writes one in its
/// reply as a fenced `shades-request` block of JSON, and the app shows you exactly that change, and makes only that
/// change, once you press Allow.
public struct ChangeRequest: Codable, Equatable, Sendable {
    /// The file as checked: absolute, with `~` and links worked out.
    public var file: String
    /// The text that comes out, which was in the file exactly once. `nil` makes a new file.
    public var replace: String?
    /// What goes in its place, or the whole of a new file.
    public var with: String
    /// The kitten's reason, in its own words, cut to one short line.
    public var why: String?
    /// A SHA-256 of the file when it was checked, or `nil` if there wasn't one. Allow only goes ahead while it still is.
    public var before: String?
    /// What it takes away from the screen block in that folder, which keeps agents there off your screen.
    public var opensScreenBlock: [String] = []
    /// Each thing it lets agents do that they couldn't before, in plain words.
    public var widens: [String] = []
    /// What Shades made of it, or `nil` if it couldn't look.
    public var review: String?
    /// Why it can't be done as asked, which leaves only Deny.
    public var problem: String?

    public init(file: String, replace: String?, with: String, why: String?) {
        self.file = file
        self.replace = replace
        self.with = with
        self.why = why
    }

    public var isLoosening: Bool { !opensScreenBlock.isEmpty || !widens.isEmpty }
}

public enum ChangeRequests {
    /// The info string a request's fence carries.
    public static let fence = "shades-request"
    static let longest = 64_000
    static let whyLimit = 300

    /// Each request in a reply, as the kitten wrote it, or why it can't be read. Only fenced blocks count, so a
    /// reply that quotes the format inside another code block, or talks about it, asks for nothing.
    public static func all(in reply: String) -> [Result<ChangeRequest, Problem>] {
        blocks(in: reply).map(read)
    }

    /// The reply with each request block swapped for one line, for the sorter, which only needs to know it's there.
    public static func withoutBlocks(_ reply: String, saying placeholder: String) -> String {
        let lines = reply.split(separator: "\n", omittingEmptySubsequences: false)
        var kept: [Substring] = []
        var next = 0
        for block in scan(lines) {
            kept += lines[next..<block.lines.lowerBound]
            kept.append(Substring(placeholder))
            next = block.lines.upperBound
        }
        kept += lines[next...]
        return kept.joined(separator: "\n")
    }

    public struct Problem: Error, Equatable, Sendable {
        public var reason: String
        public init(_ reason: String) { self.reason = reason }
    }

    private struct Written: Decodable {
        var file: String
        var replace: String?
        var with: String?
        var create: String?
        var why: String?

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case file, replace, with, create, why
        }

        /// A key it doesn't know means the kitten thinks it asked for something that would be left out.
        init(from decoder: Decoder) throws {
            let keys = try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue)
            if let unknown = keys.first(where: { CodingKeys(rawValue: $0) == nil }) {
                throw Problem("It has a key The Kitty Litter doesn't know, `\(unknown)`.")
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            file = try container.decode(String.self, forKey: .file)
            replace = try container.decodeIfPresent(String.self, forKey: .replace)
            with = try container.decodeIfPresent(String.self, forKey: .with)
            create = try container.decodeIfPresent(String.self, forKey: .create)
            why = try container.decodeIfPresent(String.self, forKey: .why)
        }
    }

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    private static func read(_ block: String) -> Result<ChangeRequest, Problem> {
        let written: Written
        do {
            written = try JSONDecoder().decode(Written.self, from: Data(block.utf8))
        } catch let problem as Problem {
            return .failure(problem)
        } catch {
            return .failure(Problem("It isn't JSON with a `file`, The Kitty Litter's request form."))
        }
        let why = written.why.map { $0.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces) }
        let shortWhy = why.map { $0.count > whyLimit ? String($0.prefix(whyLimit - 1)) + "…" : $0 }.flatMap { $0.isEmpty ? nil : $0 }
        let request: ChangeRequest
        switch (written.replace, written.with, written.create) {
        case (let replace?, let with?, nil):
            guard !replace.isEmpty else { return .failure(Problem("Its `replace` is empty, so there's nothing to find.")) }
            request = ChangeRequest(file: written.file, replace: replace, with: with, why: shortWhy)
        case (nil, nil, let create?):
            request = ChangeRequest(file: written.file, replace: nil, with: create, why: shortWhy)
        default:
            return .failure(Problem("It needs `replace` and `with`, or `create` alone."))
        }
        for text in [request.replace, request.with].compactMap({ $0 }) + [why ?? ""] {
            guard text.count <= longest else { return .failure(Problem("It's longer than a settings change needs to be.")) }
            // Text that draws as nothing, or reverses what's around it, could make the change look like another.
            guard !text.unicodeScalars.contains(where: hides) else {
                return .failure(Problem("It has characters that don't show, so you couldn't see exactly what it does."))
            }
        }
        return .success(request)
    }

    private static func hides(_ scalar: Unicode.Scalar) -> Bool {
        if scalar == "\n" || scalar == "\t" || scalar == "\r" { return false }
        switch scalar.properties.generalCategory {
        case .control, .format, .lineSeparator, .paragraphSeparator, .privateUse, .unassigned, .surrogate: return true
        default: return false
        }
    }

    static func blocks(in reply: String) -> [String] {
        scan(reply.split(separator: "\n", omittingEmptySubsequences: false)).map(\.body)
    }

    /// Each closed request block, by the lines it takes up, fences included. A request fence inside another code
    /// block is only that block's text.
    private static func scan(_ lines: [Substring]) -> [(lines: Range<Int>, body: String)] {
        var found: [(lines: Range<Int>, body: String)] = []
        var open: (fence: Fence, at: Int)?
        for (index, line) in lines.enumerated() {
            if let (fence, start) = open {
                guard fence.closes(line) else { continue }
                if fence.info == Self.fence { found.append((start..<index + 1, lines[(start + 1)..<index].joined(separator: "\n"))) }
                open = nil
            } else if let fence = Fence(opening: line) {
                open = (fence, index)
            }
        }
        return found
    }

    /// A Markdown code fence, as CommonMark has them: three or more of one mark, and what follows says what's in it.
    private struct Fence {
        var mark: Character
        var count: Int
        var info: String

        init?(opening line: Substring) {
            let indent = line.prefix { $0 == " " }
            guard indent.count < 4, let mark = line.dropFirst(indent.count).first, mark == "`" || mark == "~" else { return nil }
            let rest = line.dropFirst(indent.count)
            let marks = rest.prefix { $0 == mark }
            guard marks.count >= 3 else { return nil }
            let info = rest.dropFirst(marks.count).trimmingCharacters(in: .whitespaces)
            guard mark == "~" || !info.contains("`") else { return nil }
            self.mark = mark
            count = marks.count
            self.info = String(info.prefix { !$0.isWhitespace })
        }

        func closes(_ line: Substring) -> Bool {
            let indent = line.prefix { $0 == " " }
            let rest = line.dropFirst(indent.count)
            let marks = rest.prefix { $0 == mark }
            return indent.count < 4 && marks.count >= count && rest.dropFirst(marks.count).allSatisfy { $0 == " " || $0 == "\t" }
        }
    }
}
