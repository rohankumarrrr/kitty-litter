import Foundation

public enum RouterBlock {
    static let allowed = ["WebSearch", "ToolSearch"]
    // Outside the repo: Claude Code reads an @path in a prompt without calling a tool, so the hook never sees it and only a deny stops it.
    static let denied = ["mcp__t3-code", "Bash", "Monitor", "Edit", "Write", "NotebookEdit", "Read", "Glob", "Grep"]

    static let settings = try! JSONSerialization.data(
        withJSONObject: [
            "permissions": ["deny": denied],
            "hooks": ["PreToolUse": [[
                "matcher": "^(?!(\(allowed.joined(separator: "|")))$).*",
                "hooks": [["type": "command", "command": "echo 'The router only replies, so it has no tools that act or read files.' >&2; exit 2"]],
            ]]],
        ],
        options: [.prettyPrinted, .sortedKeys]
    )

    public static func prepare(_ folder: URL) throws -> String {
        let claude = folder.appendingPathComponent(".claude")
        try keepOnly(".claude", in: folder)
        try keepOnly("settings.json", in: claude)
        let file = claude.appendingPathComponent("settings.json")
        let files = FileManager.default
        let found = try? files.attributesOfItem(atPath: file.path)
        // Outside the repo: a file reached through a link or a second name can be changed from there, and writing over a file keeps its permissions.
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
