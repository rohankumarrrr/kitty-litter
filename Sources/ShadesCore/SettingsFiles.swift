import CryptoKit
import Foundation

/// The settings files the app changes for a kitten once you press Allow. The app runs outside every sandbox, so the
/// list is fixed, only the change you saw is made, and the file has to be valid JSON afterwards.
public struct SettingsFiles: Sendable {
    public var home: String
    /// Each listed kitten's folder, whose `.claude/settings.json` is on the list.
    public var kittenFolders: [String]

    public init(home: String, kittenFolders: [String]) {
        self.home = Self.standardized(home)
        self.kittenFolders = kittenFolders.map(Self.standardized)
    }

    public typealias Problem = ChangeRequests.Problem

    /// The request with its file worked out, what it does, and the file's hash as it is now. If it can't be done as
    /// asked, `problem` says why, which leaves only Deny.
    public func check(_ request: ChangeRequest) -> ChangeRequest {
        var checked = request
        do {
            let file = try allowed(request.file)
            checked.file = shown(file.path)
            let current = try contents(of: file)
            let after = try result(of: request, on: current)
            checked.before = current.map(Self.hash)
            (checked.opensScreenBlock, checked.widens) = assess(file, before: current, after: after)
        } catch let problem as Problem {
            checked.problem = problem.reason
        } catch {
            checked.problem = error.localizedDescription
        }
        return checked
    }

    /// Makes the change, only if the file is still exactly as it was when you were shown it.
    public func apply(_ request: ChangeRequest) throws {
        let file = try allowed(request.file)
        let current = try contents(of: file)
        guard current.map(Self.hash) == request.before else {
            throw Problem("The file changed after you were asked, so nothing was changed.")
        }
        let after = try result(of: request, on: current)
        let claude = file.deletingLastPathComponent()
        if current == nil, Self.kind(of: claude.path) == nil {
            try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: false)
        }
        let mode = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.posixPermissions] as? Int ?? 0o644
        // A new file renamed into place replaces a link rather than writing through one.
        let temp = claude.appendingPathComponent(".\(file.lastPathComponent).\(UUID().uuidString)")
        let descriptor = open(temp.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(mode))
        guard descriptor >= 0 else { throw Problem("The Kitty Litter couldn't write next to the file.") }
        defer { try? FileManager.default.removeItem(at: temp) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        try handle.write(contentsOf: after)
        try handle.close()
        guard rename(temp.path, file.path) == 0 else { throw Problem("The Kitty Litter couldn't put the new file in place.") }
        guard try contents(of: file) == after else { throw Problem("The file didn't read back as it was written.") }
    }

    /// The file as it is now, for Shades to read when it looks into the request.
    public func current(_ request: ChangeRequest) -> String? {
        (try? allowed(request.file)).flatMap { try? contents(of: $0) }.flatMap { String(data: $0, encoding: .utf8) }
    }

    /// `~` for your home folder, so a card says where in a way you'd write it.
    public func shown(_ path: String) -> String {
        path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    // MARK: - Which files

    /// The path it's written as, if it's on the list. A link at the folder, its `.claude` or the file itself could
    /// send the write somewhere else, such as your own Claude settings, so none is followed.
    func allowed(_ written: String) throws -> URL {
        let expanded = written == "~" || written.hasPrefix("~/") ? home + written.dropFirst() : written
        guard expanded.hasPrefix("/") else { throw Problem("`\(written)` isn't a full path.") }
        let file = URL(fileURLWithPath: Self.standardized(expanded))
        let claude = file.deletingLastPathComponent()
        let folder = claude.deletingLastPathComponent()
        let name = file.lastPathComponent
        guard claude.lastPathComponent == ".claude" else { throw notListed(written) }

        let listed: Bool
        switch name {
        case "settings.json":
            listed = kittenFolders.contains(folder.path) || folder.path == home + "/shades"
        case "settings.local.json":
            let project = folder.deletingLastPathComponent()
            listed = project.deletingLastPathComponent().path == home + "/.t3/worktrees" && Self.kind(of: project.path) == .typeDirectory
        default:
            listed = false
        }
        guard listed else { throw notListed(written) }
        guard Self.kind(of: folder.path) == .typeDirectory else { throw Problem("`\(shown(folder.path))` isn't a folder.") }
        guard [nil, .typeDirectory].contains(Self.kind(of: claude.path)) else { throw Problem("`\(shown(claude.path))` isn't a folder.") }
        guard [nil, .typeRegular].contains(Self.kind(of: file.path)) else { throw Problem("`\(shown(file.path))` isn't a plain file.") }
        return file
    }

    private func notListed(_ written: String) -> Problem {
        Problem("`\(written)` isn't one of the settings files The Kitty Litter changes.")
    }

    // MARK: - The change

    private func contents(of file: URL) throws -> Data? {
        guard Self.kind(of: file.path) != nil else { return nil }
        guard let data = FileManager.default.contents(atPath: file.path) else { throw Problem("The Kitty Litter can't read `\(shown(file.path))`.") }
        return data
    }

    private func result(of request: ChangeRequest, on current: Data?) throws -> Data {
        let after: String
        if let replace = request.replace {
            guard let current else { throw Problem("There's no file there to change yet.") }
            guard let text = String(data: current, encoding: .utf8) else { throw Problem("The file isn't text.") }
            let found = text.components(separatedBy: replace).count - 1
            guard found == 1 else {
                throw Problem(found == 0 ? "What it asks to replace isn't in the file." : "What it asks to replace is in the file \(found) times, so there's no telling which.")
            }
            after = text.replacingOccurrences(of: replace, with: request.with)
        } else {
            guard current == nil else { throw Problem("The file is already there, so it can't be made new.") }
            after = request.with
        }
        let data = Data(after.utf8)
        do {
            try StrictJSON.validate(data)
        } catch StrictJSON.Failure.repeatedKey {
            throw Problem("The file would have the same key twice in one place.")
        } catch {
            throw Problem("The file wouldn't be valid JSON afterwards.")
        }
        guard (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else { throw Problem("The file wouldn't be a JSON object afterwards.") }
        return data
    }

    // MARK: - What it does

    /// What it opens of the screen block, and what it lets agents do that they couldn't, going by what Claude Code
    /// reads in that folder: `settings.json`, with `settings.local.json` over it.
    func assess(_ file: URL, before: Data?, after: Data) -> (opens: [String], widens: [String]) {
        let claude = file.deletingLastPathComponent()
        let isLocal = file.lastPathComponent == "settings.local.json"
        let other = Self.object(FileManager.default.contents(atPath: claude.appendingPathComponent(isLocal ? "settings.json" : "settings.local.json").path)) ?? [:]
        let old = before == nil ? [:] : Self.object(before)
        guard let old, let new = Self.object(after) else {
            return ([], ["There's no telling what it changes, since the file isn't JSON now."])
        }
        let was = isLocal ? Self.merged(other, old) : Self.merged(old, other)
        let will = isLocal ? Self.merged(other, new) : Self.merged(new, other)
        let gapsBefore = ScreenBlock.gaps(in: try? JSONSerialization.data(withJSONObject: was))
        let opens = ScreenBlock.gaps(in: try? JSONSerialization.data(withJSONObject: will)).filter { !gapsBefore.contains($0) }
        return (opens, SettingsFacts.widening(from: was, to: will))
    }

    /// JSON5 is let through, since a stray trailing comma is exactly what a request may be fixing.
    private static func object(_ data: Data?) -> [String: Any]? {
        guard let data else { return nil }
        return (try? JSONSerialization.jsonObject(with: data, options: .json5Allowed)) as? [String: Any]
    }

    /// As Claude Code layers them: lists add up, and anything else in `over` wins.
    static func merged(_ base: [String: Any], _ over: [String: Any]) -> [String: Any] {
        base.merging(over) { old, new in
            if let old = old as? [String: Any], let new = new as? [String: Any] { return merged(old, new) }
            if let old = old as? [Any], let new = new as? [Any] { return old + new }
            return new
        }
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func standardized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func kind(of path: String) -> FileAttributeType? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.type] as? FileAttributeType
    }
}

/// A settings file as a set of facts, each a value at a path, so two versions can be compared without caring how
/// they're laid out.
enum SettingsFacts {
    struct Fact: Hashable {
        var path: String
        var value: String
        var inList: Bool
    }

    static let mostShown = 8

    /// Adding a deny or an ask, or taking an allow away, only narrows what agents may do. Anything else that changes
    /// is listed, since there's no telling it's harmless.
    static func widening(from was: [String: Any], to will: [String: Any]) -> [String] {
        let before = facts(was), after = facts(will)
        let added = after.subtracting(before).filter { !["permissions.deny", "permissions.ask"].contains($0.path) }
        let removed = before.subtracting(after).filter { $0.path != "permissions.allow" }
        var lines: [String] = []
        for path in Set((added.union(removed)).map(\.path)).sorted() {
            let adds = added.filter { $0.path == path }.map(\.value).sorted()
            let takes = removed.filter { $0.path == path }.map(\.value).sorted()
            let inList = (added.union(removed)).first { $0.path == path }?.inList ?? false
            if !inList, adds.count == 1, takes.count == 1 {
                lines.append("Changes \(shown(path)) from \(shown(takes[0])) to \(shown(adds[0])).")
                continue
            }
            lines += adds.map { inList ? "Adds \(shown($0)) to \(shown(path))." : "Sets \(shown(path)) to \(shown($0))." }
            lines += takes.map { inList ? "Takes \(shown($0)) out of \(shown(path))." : "Takes out \(shown(path)), which was \(shown($0))." }
        }
        guard lines.count > mostShown else { return lines }
        return Array(lines.prefix(mostShown - 1)) + ["And \(lines.count - mostShown + 1) more changes."]
    }

    static func facts(_ object: [String: Any]) -> Set<Fact> {
        var found: Set<Fact> = []
        func walk(_ value: Any, at path: String, inList: Bool) {
            if let object = value as? [String: Any], !inList {
                for (key, inner) in object { walk(inner, at: path.isEmpty ? key : "\(path).\(key)", inList: false) }
            } else if let list = value as? [Any], !inList {
                for item in list { walk(item, at: path, inList: true) }
            } else {
                found.insert(Fact(path: path, value: written(value), inList: inList))
            }
        }
        walk(object, at: "", inList: false)
        return found
    }

    private static func written(_ value: Any) -> String {
        if let text = value as? String { return text }
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes]) else { return "\(value)" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func shown(_ value: String) -> String {
        ChangeRequests.code(value.count > 100 ? String(value.prefix(99)) + "…" : value)
    }
}
