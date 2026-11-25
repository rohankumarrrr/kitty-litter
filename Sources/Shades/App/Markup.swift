import Foundation

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

    struct Pull: Equatable, Encodable {
        var state: String?
    }

    struct Block: Equatable, Encodable {
        enum Kind: String, Encodable {
            case paragraph, heading, item, quote, code, table, rule
        }

        var kind: Kind
        var spans: [Span]?
        var marker: String?
        var depth: Int?
        var code: String?
        var rows: [[[Span]]]?
    }

    var blocks: [Block]

    init(_ text: String, pulls: [String: String] = [:]) {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
        guard let parsed = try? AttributedString(markdown: text, options: options) else {
            blocks = [Block(kind: .paragraph, spans: [Span(text: text)])]
            return
        }
        var blocks: [Block] = []
        var inner: Int?
        var item: Int?
        var table: Int?
        var row: Int?
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
                guard case .table(let columns) = tableIntent.kind else { continue }
                let rowIntent = intents.first { if case .tableRow = $0.kind { true } else { $0.kind == .tableHeaderRow } }
                var column = 0
                for intent in intents { if case .tableCell(let index) = intent.kind { column = index } }
                if rows.isEmpty || row != rowIntent?.identity { rows.append(Array(repeating: [], count: columns.count)) }
                row = rowIntent?.identity
                while rows[rows.count - 1].count <= column { rows[rows.count - 1].append([]) }
                rows[rows.count - 1][column].append(span)
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
            // Outside the repo: Foundation's markdown parser keeps the newline that ends a code block.
            if block.kind == .code, block.code?.hasSuffix("\n") == true { block.code?.removeLast() }
            return block
        }
    }

    struct Picture: Equatable {
        var name: String
        var url: URL
    }

    static func pictures(in text: String) -> [Picture] {
        guard text.contains("!["), let parsed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)) else { return [] }
        let pictures = parsed.runs.compactMap { run in
            run.imageURL.map { url in
                let said = String(parsed[run.range].characters).replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                return Picture(name: said.isEmpty ? (url.lastPathComponent.isEmpty ? url.host ?? "" : url.lastPathComponent) : said, url: url)
            }
        }
        return Array(pictures.prefix(10))
    }

    private static func span(_ run: AttributedString.Runs.Run, _ text: String, pulls: [String: String]) -> Span {
        let intent = run.inlinePresentationIntent ?? []
        // Outside the repo: Foundation's markdown parser gives a picture with no description the text U+FFFC.
        let text = run.imageURL != nil ? text.replacingOccurrences(of: "\u{FFFC}", with: "") : text
        var span = Span(text: intent.contains(.softBreak) || intent.contains(.lineBreak) ? "\n" : text)
        if intent.contains(.stronglyEmphasized) { span.bold = true }
        if intent.contains(.emphasized) { span.italic = true }
        if intent.contains(.code) { span.code = true }
        if intent.contains(.strikethrough) { span.strike = true }
        guard let link = run.link, opens(link) else { return span }
        span.link = link
        if text == link.absoluteString, let pull = pull(link) {
            span.pull = Pull(state: pulls[pull.key])
            span.text = pull.label
        }
        return span
    }

    static func opens(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased()) && url.host?.isEmpty == false && url.user == nil && url.password == nil
    }

    static func pull(_ url: URL) -> (key: String, label: String)? {
        guard url.host?.lowercased() == "github.com" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 4, parts[2] == "pull", let number = Int(parts[3]),
              parts[0...1].allSatisfy({ $0.range(of: "^[A-Za-z0-9_.-]+$", options: .regularExpression) != nil && $0 != "." && $0 != ".." })
        else { return nil }
        return ("\(parts[0])/\(parts[1])#\(number)".lowercased(), "\(parts[0])/\(parts[1]) #\(number)")
    }
}
