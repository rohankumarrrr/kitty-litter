import Foundation

public struct ChangeRequest: Codable, Equatable, Sendable {
    public var file: String
    public var replace: String?
    public var with: String
    public var why: String?
    public var before: String?
    public var opensScreenBlock: [String] = []
    public var widens: [String] = []
    public var review: String?
    public var problem: String?
    public var alsoAskedIn: [String] = []

    public init(file: String, replace: String?, with: String, why: String?) {
        self.file = file
        self.replace = replace
        self.with = with
        self.why = why
    }

    public var isLoosening: Bool { !opensScreenBlock.isEmpty || !widens.isEmpty }
}

public enum ChangeRequests {
    public static let fence = "shades-request"
    static let longest = 64_000
    static let whyLimit = 300
    static let askLimit = 500

    public enum Request: Equatable, Sendable {
        case change(ChangeRequest)
        case ask(AskRequest)
        case withdraw(String)

        public var change: ChangeRequest? { if case .change(let change) = self { change } else { nil } }
        public var ask: AskRequest? { if case .ask(let ask) = self { ask } else { nil } }
        public var withdrawn: String? { if case .withdraw(let asked) = self { asked } else { nil } }
    }

    public static func all(in reply: String) -> [Result<Request, Problem>] {
        blocks(in: reply).map(read)
    }

    public static func cards(in reply: String) -> [Result<Request, Problem>] {
        all(in: reply).filter { (try? $0.get().withdrawn) == nil }
    }

    public static func withdrawals(in reply: String) -> [String] {
        all(in: reply).compactMap { try? $0.get().withdrawn }
    }

    public static func withoutBlocks(_ reply: String, saying placeholder: String, withdrawn: String) -> String {
        let lines = reply.split(separator: "\n", omittingEmptySubsequences: false)
        var kept: [Substring] = []
        var next = 0
        for block in scan(lines) {
            kept += lines[next..<block.lines.lowerBound]
            kept.append(Substring((try? read(block.body).get().withdrawn) == nil ? placeholder : withdrawn))
            next = block.lines.upperBound
        }
        kept += lines[next...]
        return kept.joined(separator: "\n")
    }

    public static func code(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        let longest = line.split(omittingEmptySubsequences: true) { $0 != "`" }.map(\.count).max() ?? 0
        guard longest > 0 else { return "`\(line)`" }
        let ticks = String(repeating: "`", count: longest + 1)
        return "\(ticks) \(line) \(ticks)"
    }

    public struct Problem: Error, Equatable, Sendable {
        public var reason: String
        public init(_ reason: String) { self.reason = reason }
    }

    private struct Written: Decodable {
        var file: String?
        var replace: String?
        var with: String?
        var create: String?
        var ask: String?
        var why: String?
        var withdraw: String?

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case file, replace, with, create, ask, why, withdraw
        }

        init(from decoder: Decoder) throws {
            let keys = try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue)
            if let unknown = keys.first(where: { CodingKeys(rawValue: $0) == nil }) {
                throw Problem("It has a key The Kitty Litter doesn't know, `\(unknown)`.")
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            file = try container.decodeIfPresent(String.self, forKey: .file)
            replace = try container.decodeIfPresent(String.self, forKey: .replace)
            with = try container.decodeIfPresent(String.self, forKey: .with)
            create = try container.decodeIfPresent(String.self, forKey: .create)
            ask = try container.decodeIfPresent(String.self, forKey: .ask)
            why = try container.decodeIfPresent(String.self, forKey: .why)
            withdraw = try container.decodeIfPresent(String.self, forKey: .withdraw)
        }
    }

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    private static func read(_ block: String) -> Result<Request, Problem> {
        let written: Written
        do {
            written = try JSONDecoder().decode(Written.self, from: Data(block.utf8))
        } catch let problem as Problem {
            return .failure(problem)
        } catch {
            return .failure(Problem("It isn't JSON in The Kitty Litter's request form, with a `file`, an `ask` or a `withdraw`."))
        }
        let why = written.why.map(oneLine)
        let shortWhy = why.map { $0.count > whyLimit ? String($0.prefix(whyLimit - 1)) + "…" : $0 }.flatMap { $0.isEmpty ? nil : $0 }
        guard !(why ?? "").unicodeScalars.contains(where: hides) else { return .failure(hidden) }
        if let withdraw = written.withdraw.map(oneLine) {
            guard written.file == nil, written.replace == nil, written.with == nil, written.create == nil, written.ask == nil, written.why == nil else {
                return .failure(Problem("A `withdraw` goes alone, naming the `file` or the `ask` it takes back."))
            }
            guard !withdraw.isEmpty else { return .failure(Problem("Its `withdraw` is empty, so there's nothing to take back.")) }
            guard withdraw.count <= askLimit else { return .failure(Problem("Its `withdraw` is longer than the `file` or `ask` it takes back.")) }
            guard !withdraw.unicodeScalars.contains(where: hides) else { return .failure(hidden) }
            return .success(.withdraw(withdraw))
        }
        if let ask = written.ask.map(oneLine) {
            guard written.file == nil, written.replace == nil, written.with == nil, written.create == nil else {
                return .failure(Problem("An `ask` goes alone, with only a `why`. A settings change is a block of its own."))
            }
            guard !ask.isEmpty else { return .failure(Problem("Its `ask` is empty, so there's nothing to say yes to.")) }
            guard ask.count <= askLimit else { return .failure(Problem("Its `ask` is longer than one plain sentence needs to be.")) }
            guard !ask.unicodeScalars.contains(where: hides) else { return .failure(hidden) }
            return .success(.ask(AskRequest(ask: ask, why: shortWhy, readFromWords: false)))
        }
        guard let file = written.file else { return .failure(Problem("It needs a `file` to change, or an `ask`.")) }
        let request: ChangeRequest
        switch (written.replace, written.with, written.create) {
        case (let replace?, let with?, nil):
            guard !replace.isEmpty else { return .failure(Problem("Its `replace` is empty, so there's nothing to find.")) }
            request = ChangeRequest(file: file, replace: replace, with: with, why: shortWhy)
        case (nil, nil, let create?):
            request = ChangeRequest(file: file, replace: nil, with: create, why: shortWhy)
        default:
            return .failure(Problem("It needs `replace` and `with`, or `create` alone."))
        }
        for text in [request.replace, request.with].compactMap({ $0 }) {
            guard text.count <= longest else { return .failure(Problem("It's longer than a settings change needs to be.")) }
            guard !text.unicodeScalars.contains(where: hides) else { return .failure(hidden) }
        }
        return .success(.change(request))
    }

    private static let hidden = Problem("It has characters that don't show, so you couldn't see exactly what it asks.")

    static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    static func hides(text: String) -> Bool {
        text.unicodeScalars.contains(where: hides)
    }

    private static func hides(_ scalar: Unicode.Scalar) -> Bool {
        if scalar == "\n" || scalar == "\t" || scalar == "\r" { return false }
        if scalar.properties.isDefaultIgnorableCodePoint || scalar.properties.isNoncharacterCodePoint { return true }
        switch scalar.properties.generalCategory {
        case .control, .format, .lineSeparator, .paragraphSeparator, .privateUse, .unassigned, .surrogate: return true
        default: return false
        }
    }

    static func blocks(in reply: String) -> [String] {
        scan(reply.split(separator: "\n", omittingEmptySubsequences: false)).map(\.body)
    }

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
