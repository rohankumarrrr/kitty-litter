import Foundation

/// JSON exactly as RFC 8259 has it, read the way Claude Code's parser reads it: the last of a repeated key wins.
/// Foundation's own reader lets a trailing comma through and keeps the first of a repeated key, so what it read could
/// differ from what Claude Code uses, and a settings file Claude Code can't read loses every rule in it.
enum StrictJSON {
    enum Failure: Error, Equatable {
        case invalid
        /// One object names a key twice.
        case repeatedKey
    }

    /// Objects come back as `[String: Any]`, lists as `[Any]`, and the rest as Foundation's JSON values.
    static func parse(_ data: Data, allowingRepeats: Bool = true) throws -> Any {
        var reader = Reader(bytes: [UInt8](data), allowingRepeats: allowingRepeats)
        let value = try reader.value(depth: 0)
        reader.skipSpace()
        guard reader.at == reader.bytes.count else { throw Failure.invalid }
        return value
    }

    /// For a file about to be written, where a repeated key is refused rather than read.
    static func validate(_ data: Data) throws {
        _ = try parse(data, allowingRepeats: false)
    }

    private struct Reader {
        let bytes: [UInt8]
        let allowingRepeats: Bool
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

        mutating func value(depth: Int) throws -> Any {
            guard depth < 100 else { throw Failure.invalid }
            skipSpace()
            switch next {
            case UInt8(ascii: "{"): return try object(depth: depth)
            case UInt8(ascii: "["): return try array(depth: depth)
            case UInt8(ascii: "\""): return try string()
            case UInt8(ascii: "t"): return try word("true", is: true)
            case UInt8(ascii: "f"): return try word("false", is: false)
            case UInt8(ascii: "n"): return try word("null", is: NSNull())
            default: return try number()
            }
        }

        private mutating func object(depth: Int) throws -> [String: Any] {
            at += 1
            skipSpace()
            var object: [String: Any] = [:]
            if take("}") { return object }
            while true {
                skipSpace()
                guard next == UInt8(ascii: "\"") else { throw Failure.invalid }
                let key = try string()
                guard allowingRepeats || object[key] == nil else { throw Failure.repeatedKey }
                skipSpace()
                guard take(":") else { throw Failure.invalid }
                object[key] = try value(depth: depth + 1)
                skipSpace()
                if take(",") { continue }
                guard take("}") else { throw Failure.invalid }
                return object
            }
        }

        private mutating func array(depth: Int) throws -> [Any] {
            at += 1
            skipSpace()
            var list: [Any] = []
            if take("]") { return list }
            while true {
                list.append(try value(depth: depth + 1))
                skipSpace()
                if take(",") { continue }
                guard take("]") else { throw Failure.invalid }
                return list
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

        private mutating func word(_ word: String, is value: Any) throws -> Any {
            let expected = Array(word.utf8)
            guard bytes.count - at >= expected.count, Array(bytes[at..<at + expected.count]) == expected else { throw Failure.invalid }
            at += expected.count
            return value
        }

        private mutating func number() throws -> Any {
            let start = at
            _ = take("-")
            if !take("0") {
                guard digits() > 0 else { throw Failure.invalid }
            }
            if take(".") { guard digits() > 0 else { throw Failure.invalid } }
            if take("e") || take("E") {
                if !take("+") { _ = take("-") }
                guard digits() > 0 else { throw Failure.invalid }
            }
            let text = String(decoding: bytes[start..<at], as: UTF8.self)
            if let whole = Int(text) { return whole }
            guard let number = Double(text) else { throw Failure.invalid }
            return number
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
