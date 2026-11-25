import CryptoKit
import Foundation

public struct SettingsFiles: Sendable {
    public var home: String
    public var kittenFolders: [String]

    public init(home: String, kittenFolders: [String]) {
        self.home = Self.standardized(home)
        self.kittenFolders = kittenFolders.map(Self.standardized)
    }

    public typealias Problem = ChangeRequests.Problem

    struct Place: Equatable {
        var anchor: String
        var folders: [String]
        var name: String

        var path: String { ([anchor] + folders + [name]).joined(separator: "/") }
        var other: String { name == "settings.json" ? "settings.local.json" : "settings.json" }
    }

    public func check(_ request: ChangeRequest) -> ChangeRequest {
        var checked = request
        do {
            let place = try allowed(request.file)
            checked.file = shown(place.path)
            let (current, other) = try inFolder(place, creating: false) { claude in
                (try read(place.name, in: claude), try? read(place.other, in: claude))
            }
            let after = try result(of: request, on: current)
            checked.before = current.map(Self.hash)
            (checked.opensScreenBlock, checked.widens) = SettingsFacts.assess(local: place.name == "settings.local.json", before: current, after: after, other: other ?? nil)
        } catch let problem as Problem {
            checked.problem = problem.reason
        } catch {
            checked.problem = error.localizedDescription
        }
        return checked
    }

    public func apply(_ request: ChangeRequest) throws {
        let place = try allowed(request.file)
        try inFolder(place, creating: request.replace == nil) { claude in
            guard let claude else { throw Problem("There's no file there to change yet.") }
            let current = try read(place.name, in: claude)
            guard current.map(Self.hash) == request.before else {
                throw Problem("The file changed after you were asked, so nothing was changed.")
            }
            let after = try result(of: request, on: current)
            var found = stat()
            let mode = fstatat(claude, place.name, &found, AT_SYMLINK_NOFOLLOW) == 0 ? found.st_mode & 0o777 : 0o644
            let temp = ".\(place.name).\(UUID().uuidString)"
            let descriptor = openat(claude, temp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode)
            guard descriptor >= 0 else { throw Problem("The Kitty Litter couldn't write next to the file.") }
            defer { unlinkat(claude, temp, 0) }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            try handle.write(contentsOf: after)
            try handle.close()
            guard renameat(claude, temp, claude, place.name) == 0 else { throw Problem("The Kitty Litter couldn't put the new file in place.") }
            guard try read(place.name, in: claude) == after else { throw Problem("The file didn't read back as it was written.") }
        }
    }

    public enum Staleness: Equatable, Sendable {
        case alreadyMade
        case cantBeMade(String)
    }

    public func staleness(of change: ChangeRequest) -> Staleness? {
        let current: Data?
        do {
            let place = try allowed(change.file)
            current = try inFolder(place, creating: false) { try read(place.name, in: $0) }
        } catch {
            return nil
        }
        guard current.map(Self.hash) != change.before else { return nil }
        if let text = current.flatMap({ String(data: $0, encoding: .utf8) }), isMade(change, in: text) { return .alreadyMade }
        let changed = "The file changed after it asked."
        do {
            _ = try result(of: change, on: current)
            return .cantBeMade(changed)
        } catch let problem as Problem {
            return .cantBeMade("\(changed) \(problem.reason)")
        } catch {
            return .cantBeMade(changed)
        }
    }

    private func isMade(_ change: ChangeRequest, in text: String) -> Bool {
        guard let replace = change.replace else { return text == change.with }
        guard !change.with.isEmpty, text.components(separatedBy: change.with).count == 2 else { return false }
        return Self.hash(Data(text.replacingOccurrences(of: change.with, with: replace).utf8)) == change.before
    }

    public func shown(listed written: String) -> String? {
        (try? allowed(written)).map { shown($0.path) }
    }

    public func current(_ request: ChangeRequest) -> String? {
        guard let place = try? allowed(request.file), let data = try? inFolder(place, creating: false, { try read(place.name, in: $0) }) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func shown(_ path: String) -> String {
        path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    func allowed(_ written: String) throws -> Place {
        let expanded = written == "~" || written.hasPrefix("~/") ? home + written.dropFirst() : written
        guard expanded.hasPrefix("/") else { throw Problem("`\(written)` isn't a full path.") }
        let file = URL(fileURLWithPath: Self.standardized(expanded))
        let claude = file.deletingLastPathComponent()
        let folder = claude.deletingLastPathComponent()
        let project = folder.deletingLastPathComponent()
        let name = file.lastPathComponent
        guard claude.lastPathComponent == ".claude" else { throw notListed(written) }
        switch name {
        case "settings.json" where kittenFolders.contains(folder.path):
            return Place(anchor: project.path, folders: [folder.lastPathComponent, ".claude"], name: name)
        case "settings.json" where folder.path == home + "/shades":
            return Place(anchor: home, folders: ["shades", ".claude"], name: name)
        case "settings.local.json" where project.deletingLastPathComponent().path == home + "/.t3/worktrees":
            return Place(anchor: home + "/.t3/worktrees", folders: [project.lastPathComponent, folder.lastPathComponent, ".claude"], name: name)
        default:
            throw notListed(written)
        }
    }

    private func notListed(_ written: String) -> Problem {
        Problem("`\(written)` isn't one of the settings files The Kitty Litter changes.")
    }

    private func inFolder<Result>(_ place: Place, creating: Bool, _ body: (Int32?) throws -> Result) throws -> Result {
        var folder = open(place.anchor, O_RDONLY | O_DIRECTORY)
        guard folder >= 0 else { throw Problem("`\(shown(place.anchor))` isn't a folder.") }
        defer { close(folder) }
        for (index, name) in place.folders.enumerated() {
            let isLast = index == place.folders.count - 1
            var next = openat(folder, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            if next < 0, errno == ENOENT, isLast {
                guard creating else { return try body(nil) }
                guard mkdirat(folder, name, 0o755) == 0 || errno == EEXIST else { throw Problem("The Kitty Litter couldn't make the `.claude` folder.") }
                next = openat(folder, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            }
            guard next >= 0 else {
                let path = ([place.anchor] + place.folders.prefix(index + 1)).joined(separator: "/")
                throw Problem("`\(shown(path))` isn't a folder of its own.")
            }
            close(folder)
            folder = next
        }
        return try body(folder)
    }

    private func read(_ name: String, in folder: Int32?) throws -> Data? {
        guard let folder else { return nil }
        let descriptor = openat(folder, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else {
            if errno == ENOENT { return nil }
            throw Problem("`\(name)` there isn't a plain file.")
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var found = stat()
        guard fstat(descriptor, &found) == 0, found.st_mode & S_IFMT == S_IFREG else { throw Problem("`\(name)` there isn't a plain file.") }
        return try handle.readToEnd() ?? Data()
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
            guard try StrictJSON.parse(data, allowingRepeats: false) is [String: Any] else { throw Problem("The file wouldn't be a JSON object afterwards.") }
        } catch StrictJSON.Failure.repeatedKey {
            throw Problem("The file would have the same key twice in one place.")
        } catch StrictJSON.Failure.invalid {
            throw Problem("The file wouldn't be valid JSON afterwards.")
        }
        return data
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func standardized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
