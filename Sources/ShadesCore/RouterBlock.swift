import Foundation

/// What keeps the router to its one job, which is replying. It sees your screen first, and T3 allows all of
/// its tools in every thread, so being told not to send things was all that stood in the way. The folder it
/// runs in holds settings that Claude Code enforces, and nothing else.
public enum RouterBlock {
    /// Everything it can still use. Each only reads, and anything else, including tools Claude Code adds later,
    /// is turned away by a hook. Naming what's allowed matters, since the shell also comes as `Monitor`, and
    /// `SendMessage` reaches other Claude sessions without T3.
    static let allowed = ["Read", "Glob", "Grep", "WebSearch", "ToolSearch"]
    /// Taken out of the list altogether, which still holds if hooks are ever turned off.
    static let denied = ["mcp__t3-code", "Bash", "Edit", "Write", "NotebookEdit"]

    static let settings = try! JSONSerialization.data(
        withJSONObject: [
            "permissions": ["deny": denied],
            "hooks": ["PreToolUse": [[
                "matcher": "^(?!(\(allowed.joined(separator: "|")))$).*",
                "hooks": [["type": "command", "command": "echo 'The router only replies, so it has no tools that act.' >&2; exit 2"]],
            ]]],
        ],
        options: [.prettyPrinted, .sortedKeys]
    )

    /// Leaves the folder holding these settings and nothing else, and gives back its path. Anything else could
    /// load too, such as a hook in `settings.local.json`, which would be handed every prompt, screen and all.
    public static func prepare(_ folder: URL) throws -> String {
        let claude = folder.appendingPathComponent(".claude")
        try keepOnly(".claude", in: folder)
        try keepOnly("settings.json", in: claude)
        let file = claude.appendingPathComponent("settings.json")
        let files = FileManager.default
        let found = try? files.attributesOfItem(atPath: file.path)
        // A link, or a second name for the same file, could change it later from somewhere else, and Claude Code
        // has to be able to read it. Writing over it would keep its permissions, so it's replaced with a new file.
        let ownFile = found?[.type] as? FileAttributeType == .typeRegular
            && found?[.referenceCount] as? Int == 1
            && found?[.posixPermissions] as? Int == 0o644
        if !ownFile || files.contents(atPath: file.path) != settings {
            try? files.removeItem(at: file)
            guard files.createFile(atPath: file.path, contents: settings, attributes: [.posixPermissions: 0o644]) else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: file.path])
            }
        }
        guard files.contents(atPath: file.path) == settings else {
            throw CocoaError(.fileReadNoPermission, userInfo: [NSFilePathErrorKey: file.path])
        }
        return folder.path
    }

    /// Makes this a real folder with nothing in it but `name`. A link found here is removed, not followed.
    private static func keepOnly(_ name: String, in folder: URL) throws {
        let files = FileManager.default
        if kind(of: folder) != .typeDirectory {
            try? files.removeItem(at: folder)
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        for other in try files.contentsOfDirectory(atPath: folder.path) where other != name {
            try files.removeItem(at: folder.appendingPathComponent(other))
        }
    }

    private static func kind(of url: URL) -> FileAttributeType? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType
    }
}
