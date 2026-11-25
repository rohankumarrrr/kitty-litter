import Foundation

enum SettingsFacts {
    struct Fact: Hashable {
        var path: [String]
        var json: String
        var inList: Bool

        var isText: Bool { json.hasPrefix("\"") }
    }

    static let mostShown = 8

    static func assess(local: Bool, before: Data?, after: Data, other: Data?) -> (opens: [String], widens: [String]) {
        let old = readable(before), new = readable(after), beside = readable(other)
        let was = local ? merged(beside, old) : merged(old, beside)
        let will = local ? merged(beside, new) : merged(new, beside)
        let gapsBefore = ScreenBlock.gaps(in: try? JSONSerialization.data(withJSONObject: was))
        let opens = ScreenBlock.gaps(in: try? JSONSerialization.data(withJSONObject: will)).filter { !gapsBefore.contains($0) }
        return (opens, widening(from: was, to: will))
    }

    private static func readable(_ data: Data?) -> [String: Any] {
        data.flatMap { try? StrictJSON.parse($0) as? [String: Any] } ?? [:]
    }

    // Outside the repo: Claude Code layers settings files this way: lists add up, and anything else in the later file wins.
    static func merged(_ base: [String: Any], _ over: [String: Any]) -> [String: Any] {
        base.merging(over) { old, new in
            if let old = old as? [String: Any], let new = new as? [String: Any] { return merged(old, new) }
            if let old = old as? [Any], let new = new as? [Any] { return old + new }
            return new
        }
    }

    static func widening(from was: [String: Any], to will: [String: Any]) -> [String] {
        let before = facts(was), after = facts(will)
        let added = after.subtracting(before).filter { !($0.inList && $0.isText && [["permissions", "deny"], ["permissions", "ask"]].contains($0.path)) }
        let removed = before.subtracting(after).filter { !($0.inList && $0.isText && $0.path == ["permissions", "allow"]) }
        let changed = added.union(removed)
        var lines: [String] = []
        for path in Set(changed.map(\.path)).sorted(by: { $0.lexicographicallyPrecedes($1) }) {
            let adds = added.filter { $0.path == path }.map(\.json).sorted()
            let takes = removed.filter { $0.path == path }.map(\.json).sorted()
            let inList = changed.first { $0.path == path }?.inList ?? false
            let at = shown(path)
            if !inList, adds.count == 1, takes.count == 1 {
                lines.append("Changes \(at) from \(shown(takes[0])) to \(shown(adds[0])).")
                continue
            }
            lines += adds.map { inList ? "Adds \(shown($0)) to \(at)." : "Sets \(at) to \(shown($0))." }
            lines += takes.map { inList ? "Takes \(shown($0)) out of \(at)." : "Takes out \(at), which was \(shown($0))." }
        }
        guard lines.count > mostShown else { return lines }
        return Array(lines.prefix(mostShown - 1)) + ["And \(lines.count - mostShown + 1) more changes."]
    }

    static func facts(_ object: [String: Any]) -> Set<Fact> {
        var found: Set<Fact> = []
        func walk(_ value: Any, at path: [String], inList: Bool) {
            if let object = value as? [String: Any], !inList {
                for (key, inner) in object { walk(inner, at: path + [key], inList: false) }
            } else if let list = value as? [Any], !inList {
                for item in list { walk(item, at: path, inList: true) }
            } else {
                found.insert(Fact(path: path, json: json(value), inList: inList))
            }
        }
        walk(object, at: [], inList: false)
        return found
    }

    private static func json(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes]) else { return "\(value)" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func shown(_ path: [String]) -> String {
        let plain = path.map { key in
            key.isEmpty || !key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }) ? json(key) : key
        }
        return code(plain.joined(separator: "."))
    }

    private static func shown(_ json: String) -> String {
        guard json.hasPrefix("\""), let text = (try? JSONSerialization.jsonObject(with: Data(json.utf8), options: .fragmentsAllowed)) as? String,
              (try? StrictJSON.parse(Data(text.utf8))) == nil
        else { return code(json) }
        return code(text)
    }

    private static func code(_ text: String) -> String {
        ChangeRequests.code(text.count > 100 ? String(text.prefix(99)) + "…" : text)
    }
}
