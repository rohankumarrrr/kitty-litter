import Foundation

struct SourceComment: Equatable {
    let line: Int
    let text: String
}

struct SwiftLexer {
    enum Piece: Equatable {
        case code(String)
        case literal(String)
        case comment(SourceComment)
    }

    private let bytes: [UInt8]
    private var at = 0
    private var line = 1
    private(set) var pieces: [Piece] = []
    private(set) var commentsInsideMultilineStrings: [SourceComment] = []
    private var pending: [UInt8] = []

    init(_ source: String) {
        bytes = Array(source.utf8)
        if bytes.starts(with: Array("#!".utf8)) {
            while at < bytes.count, bytes[at] != newline { take() }
        }
        lexCode(insideInterpolation: false)
        flushCode()
    }

    var comments: [SourceComment] {
        pieces.compactMap { if case .comment(let comment) = $0 { comment } else { nil } }
    }

    var codeWithoutComments: [String] {
        pieces.flatMap { piece -> [String] in
            switch piece {
            case .code(let text): text.split(whereSeparator: \.isWhitespace).map(String.init)
            case .literal(let text): [text]
            case .comment: []
            }
        }
    }

    private let newline = UInt8(ascii: "\n")
    private let slash = UInt8(ascii: "/")
    private let star = UInt8(ascii: "*")
    private let quote = UInt8(ascii: "\"")
    private let hash = UInt8(ascii: "#")
    private let backslash = UInt8(ascii: "\\")
    private let open = UInt8(ascii: "(")
    private let close = UInt8(ascii: ")")

    private func peek(_ offset: Int = 0) -> UInt8? {
        at + offset < bytes.count ? bytes[at + offset] : nil
    }

    private mutating func take() {
        if bytes[at] == newline { line += 1 }
        pending.append(bytes[at])
        at += 1
    }

    private mutating func flushCode() {
        guard !pending.isEmpty else { return }
        pieces.append(.code(String(decoding: pending, as: UTF8.self)))
        pending = []
    }

    private mutating func flushLiteral() {
        pieces.append(.literal(String(decoding: pending, as: UTF8.self)))
        pending = []
    }

    private func hashes(from offset: Int) -> Int {
        var count = 0
        while peek(offset + count) == hash { count += 1 }
        return count
    }

    private mutating func lexCode(insideInterpolation: Bool) {
        var depth = 0
        while let byte = peek() {
            if byte == slash, peek(1) == slash {
                lexLineComment()
            } else if byte == slash, peek(1) == star {
                lexBlockComment()
            } else if byte == quote {
                lexString(hashes: 0)
            } else if byte == hash {
                let count = hashes(from: 0)
                if peek(count) == quote {
                    lexString(hashes: count)
                } else if peek(count) == slash {
                    lexRegex(hashes: count)
                } else {
                    for _ in 0..<count { take() }
                }
            } else if insideInterpolation, byte == open {
                depth += 1
                take()
            } else if insideInterpolation, byte == close {
                if depth == 0 { return }
                depth -= 1
                take()
            } else {
                take()
            }
        }
    }

    private mutating func lexLineComment() {
        flushCode()
        let start = line
        while let byte = peek(), byte != newline { take() }
        pieces.append(.comment(SourceComment(line: start, text: String(decoding: pending, as: UTF8.self))))
        pending = []
    }

    private mutating func lexBlockComment() {
        flushCode()
        let start = line
        var depth = 0
        while peek() != nil {
            if peek() == slash, peek(1) == star {
                depth += 1
                take(); take()
            } else if peek() == star, peek(1) == slash {
                depth -= 1
                take(); take()
                if depth == 0 { break }
            } else {
                take()
            }
        }
        pieces.append(.comment(SourceComment(line: start, text: String(decoding: pending, as: UTF8.self))))
        pending = []
    }

    private func closes(hashes count: Int, after offset: Int) -> Bool {
        (0..<count).allSatisfy { peek(offset + $0) == hash }
    }

    private mutating func lexString(hashes count: Int) {
        flushCode()
        for _ in 0..<count { take() }
        let multiline = peek() == quote && peek(1) == quote && peek(2) == quote
        let delimiter = multiline ? 3 : 1
        for _ in 0..<delimiter { take() }
        while let byte = peek() {
            if byte == backslash, closes(hashes: count, after: 1) {
                if peek(1 + count) == open {
                    for _ in 0..<(count + 2) { take() }
                    flushLiteral()
                    lexCode(insideInterpolation: true)
                    flushCode()
                    if peek() == close { take() }
                } else {
                    for _ in 0..<(count + 1) { take() }
                    if peek() != nil { take() }
                }
            } else if byte == newline, multiline {
                take()
                noteEmbeddedComment()
            } else if byte == quote,
                      (0..<delimiter).allSatisfy({ peek($0) == quote }),
                      closes(hashes: count, after: delimiter) {
                for _ in 0..<(delimiter + count) { take() }
                break
            } else {
                take()
            }
        }
        flushLiteral()
    }

    private mutating func noteEmbeddedComment() {
        var offset = 0
        while peek(offset) == UInt8(ascii: " ") || peek(offset) == UInt8(ascii: "\t") { offset += 1 }
        let rest = bytes[(at + offset)...].prefix { $0 != newline }
        let text = String(decoding: rest, as: UTF8.self)
        if ["//", "/*", "<!--"].contains(where: text.hasPrefix) {
            commentsInsideMultilineStrings.append(SourceComment(line: line, text: text))
        }
    }

    private mutating func lexRegex(hashes count: Int) {
        flushCode()
        for _ in 0..<(count + 1) { take() }
        while let byte = peek() {
            if byte == backslash {
                take()
                if peek() != nil { take() }
            } else if byte == slash, closes(hashes: count, after: 1) {
                for _ in 0..<(count + 1) { take() }
                break
            } else {
                take()
            }
        }
        flushLiteral()
    }
}
