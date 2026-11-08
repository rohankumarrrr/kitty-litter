import Foundation

/// A message's markdown, read once by Foundation's parser into blocks that Messages and the phone both draw. It's only
/// ever words: a link is to an http or https address or it's plain words, and a picture is its description, so nothing
/// in a message loads or runs by itself.
struct Markup: Equatable {
    struct Span: Equatable, Encodable {
        var text: String
        var bold: Bool?
        var italic: Bool?
        var code: Bool?
        var strike: Bool?
        var link: URL?
        var pull: Pull?
    }

    /// A link to a pull request, with its state as T3 has it, `open`, `merged` or `closed`. `nil` when no thread T3
    /// lists opened it, since a message is never followed anywhere to find out.
    struct Pull: Equatable, Encodable {
        var state: String?
    }

    struct Block: Equatable, Encodable {
        enum Kind: String, Encodable {
            case paragraph, heading, item, quote, code, table, rule
        }

        var kind: Kind
        var spans: [Span]?
        /// A list item's bullet or number, empty for its second paragraph on, and how many lists deep it is, from 1.
        var marker: String?
        var depth: Int?
        var code: String?
        /// A table's cells, row by row, its header first.
        var rows: [[[Span]]]?
    }

    var blocks: [Block]

    /// `pulls` is the state of each pull request T3 knows, by `pullKey`.
    init(_ text: String, pulls: [String: String] = [:]) {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
        guard let parsed = try? AttributedString(markdown: text, options: options) else {
            blocks = [Block(kind: .paragraph, spans: [Span(text: text)])]
            return
        }
        var blocks: [Block] = []
        // Which of the parser's blocks the last run was in, so the next run knows whether it starts a new one.
        var inner: Int?
        var item: Int?
        var table: Int?
        var row: Int?
        var cell: Int?
        var rows: [[[Span]]] = []
        func endTable() {
            guard !rows.isEmpty else { return }
            blocks.append(Block(kind: .table, rows: rows))
            rows = []
        }
        for run in parsed.runs {
            let span = Self.span(run, String(parsed[run.range].characters), pulls: pulls)
            let intents = run.presentationIntent?.components ?? []
            if let tableIntent = intents.first(where: { if case .table = $0.kind { true } else { false } }) {
                if table != tableIntent.identity { endTable() }
                table = tableIntent.identity
                let rowIntent = intents.first { if case .tableRow = $0.kind { true } else { $0.kind == .tableHeaderRow } }
                let cellIntent = intents.first { if case .tableCell = $0.kind { true } else { false } }
                if rows.isEmpty || row != rowIntent?.identity {
                    rows.append([])
                    cell = nil
                }
                if rows[rows.count - 1].isEmpty || cell != cellIntent?.identity { rows[rows.count - 1].append([]) }
                row = rowIntent?.identity
                cell = cellIntent?.identity
                rows[rows.count - 1][rows[rows.count - 1].count - 1].append(span)
                inner = nil
                continue
            }
            endTable()
            table = nil
            if let current = intents.first?.identity, current == inner, !blocks.isEmpty {
                if blocks[blocks.count - 1].kind == .code {
                    blocks[blocks.count - 1].code? += span.text
                } else {
                    blocks[blocks.count - 1].spans?.append(span)
                }
                continue
            }
            inner = intents.first?.identity
            switch intents.first?.kind {
            case .codeBlock:
                blocks.append(Block(kind: .code, code: span.text))
            case .thematicBreak:
                blocks.append(Block(kind: .rule))
            case .header:
                blocks.append(Block(kind: .heading, spans: [span]))
            default:
                if let itemIndex = intents.firstIndex(where: { if case .listItem = $0.kind { true } else { false } }) {
                    let depth = intents.filter { $0.kind == .orderedList || $0.kind == .unorderedList }.count
                    var marker = "•"
                    if case .listItem(let ordinal) = intents[itemIndex].kind, intents.dropFirst(itemIndex + 1).first?.kind == .orderedList {
                        marker = "\(ordinal)."
                    }
                    if item == intents[itemIndex].identity { marker = "" }
                    item = intents[itemIndex].identity
                    blocks.append(Block(kind: .item, spans: [span], marker: marker, depth: depth))
                } else {
                    let quoted = intents.contains { $0.kind == .blockQuote }
                    blocks.append(Block(kind: quoted ? .quote : .paragraph, spans: [span]))
                }
            }
        }
        endTable()
        self.blocks = blocks.map { block in
            var block = block
            // The parser keeps the newline that ends a code block, which would draw as a blank line.
            if block.kind == .code, block.code?.hasSuffix("\n") == true { block.code?.removeLast() }
            return block
        }
    }

    private static func span(_ run: AttributedString.Runs.Run, _ text: String, pulls: [String: String]) -> Span {
        let intent = run.inlinePresentationIntent ?? []
        // A line break in what was written stays one, as it was before markdown had blocks.
        var span = Span(text: intent.contains(.softBreak) || intent.contains(.lineBreak) ? "\n" : text)
        if intent.contains(.stronglyEmphasized) { span.bold = true }
        if intent.contains(.emphasized) { span.italic = true }
        if intent.contains(.code) { span.code = true }
        if intent.contains(.strikethrough) { span.strike = true }
        guard let link = run.link, opens(link) else { return span }
        span.link = link
        if let pull = pull(link) {
            span.pull = Pull(state: pulls[pull.key])
            // A bare address reads better as the pull request it is. Words someone chose for a link stay theirs.
            if text == link.absoluteString { span.text = pull.label }
        }
        return span
    }

    /// Only web addresses open, so a message can't point at a file, a script or another app.
    static func opens(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased()) && url.host?.isEmpty == false
    }

    /// A link to a pull request on GitHub: `owner/repo#number` in lower case, which finds its state, and `repo #number`.
    static func pull(_ url: URL) -> (key: String, label: String)? {
        guard url.host?.lowercased() == "github.com" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 4, parts[2] == "pull", let number = Int(parts[3]) else { return nil }
        return ("\(parts[0])/\(parts[1])#\(number)".lowercased(), "\(parts[1]) #\(number)")
    }
}
