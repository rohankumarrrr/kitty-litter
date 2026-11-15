import Foundation

/// JSON exactly as RFC 8259 has it, which is all Claude Code's parser takes. Foundation's own reader lets a trailing
/// comma through, and a settings file Claude Code can't read loses every rule in it, screen block and all.
enum StrictJSON {
    enum Failure: Error, Equatable {
        case invalid
        /// One object names a key twice. Claude Code keeps the last, so what's read here could differ from what it uses.
        case repeatedKey
    }

    static func validate(_ data: Data) throws {
        var reader = Reader(bytes: [UInt8](data))
        try reader.value(depth: 0)
        reader.skipSpace()
        guard reader.at == reader.bytes.count else { throw Failure.invalid }
    }

    private struct Reader {
        let bytes: [UInt8]
        var at = 0

        private var next: UInt8? { at < bytes.count ? bytes[at] : nil }

        mutating func skipSpace() {
            while let byte = next, [0x20, 0x09, 0x0A, 0x0D].contains(byte) { at += 1 }
        }

        private mutating func take(_ character: Unicode.Scalar) -> Bool {
            guard next == UInt8(ascii: character) else { return false }
            at += 1
            return true
        }

        mutating func value(depth: Int) throws {
            guard depth < 100 else { throw Failure.invalid }
            skipSpace()
            switch next {
            case UInt8(ascii: "{"): try object(depth: depth)
            case UInt8(ascii: "["): try array(depth: depth)
            case UInt8(ascii: "\""): _ = try string()
            case UInt8(ascii: "t"): try word("true")
            case UInt8(ascii: "f"): try word("false")
            case UInt8(ascii: "n"): try word("null")
            default: try number()
            }
        }

        private mutating func object(depth: Int) throws {
            at += 1
            skipSpace()
            if take("}") { return }
            var keys: Set<String> = []
            while true {
                skipSpace()
                guard next == UInt8(ascii: "\"") else { throw Failure.invalid }
                guard keys.insert(try string()).inserted else { throw Failure.repeatedKey }
                skipSpace()
                guard take(":") else { throw Failure.invalid }
                try value(depth: depth + 1)
                skipSpace()
                if take(",") { continue }
                guard take("}") else { throw Failure.invalid }
                return
            }
        }

        private mutating func array(depth: Int) throws {
            at += 1
            skipSpace()
            if take("]") { return }
            while true {
                try value(depth: depth + 1)
                skipSpace()
                if take(",") { continue }
                guard take("]") else { throw Failure.invalid }
                return
            }
        }

        /// What it says, worked out the way any reader would, so two keys written differently still match.
        private mutating func string() throws -> String {
            let start = at
            at += 1
            while true {
                guard let byte = next, byte >= 0x20 else { throw Failure.invalid }
                at += 1
                if byte == UInt8(ascii: "\"") { break }
                guard byte == UInt8(ascii: "\\") else { continue }
                guard let escaped = next else { throw Failure.invalid }
                at += 1
                if escaped == UInt8(ascii: "u") {
                    guard at + 4 <= bytes.count, bytes[at..<at + 4].allSatisfy(\.isHexDigit) else { throw Failure.invalid }
                    at += 4
                } else if !Array("\"\\/bfnrt".utf8).contains(escaped) {
                    throw Failure.invalid
                }
            }
            guard let text = (try? JSONSerialization.jsonObject(with: Data(bytes[start..<at]), options: .fragmentsAllowed)) as? String else {
                throw Failure.invalid
            }
            return text
        }

        private mutating func word(_ word: String) throws {
            let expected = Array(word.utf8)
            guard bytes.count - at >= expected.count, Array(bytes[at..<at + expected.count]) == expected else { throw Failure.invalid }
            at += expected.count
        }

        private mutating func number() throws {
            _ = take("-")
            if !take("0") {
                guard digits() > 0 else { throw Failure.invalid }
            }
            if take(".") { guard digits() > 0 else { throw Failure.invalid } }
            if take("e") || take("E") {
                if !take("+") { _ = take("-") }
                guard digits() > 0 else { throw Failure.invalid }
            }
        }

        private mutating func digits() -> Int {
            let start = at
            while let byte = next, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) { at += 1 }
            return at - start
        }
    }
}

private extension UInt8 {
    var isHexDigit: Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(self) || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(self)
            || (UInt8(ascii: "A")...UInt8(ascii: "F")).contains(self)
    }
}
