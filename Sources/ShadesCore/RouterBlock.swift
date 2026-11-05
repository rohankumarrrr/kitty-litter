import Foundation

/// What keeps the router to its one job, which is replying. It sees your screen first, so the folder it runs
/// in takes away everything that could pass that on: T3's tools, which message and start threads, the shell,
/// which can reach T3 another way, and writing files, this one included. T3 allows all of its tools in every
/// thread, so being told not to use them was all that stood in the way. Claude Code enforces these.
public enum RouterBlock {
    static let denied = ["mcp__t3-code", "Bash", "Edit", "Write", "NotebookEdit"]

    static let settings = try! JSONSerialization.data(
        withJSONObject: ["permissions": ["deny": denied]],
        options: [.prettyPrinted, .sortedKeys]
    )

    /// Puts the settings in this folder, unless they're there already, and gives back its path.
    public static func prepare(_ folder: URL) throws -> String {
        let file = folder.appendingPathComponent(".claude/settings.json")
        if FileManager.default.contents(atPath: file.path) != settings {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try settings.write(to: file, options: .atomic)
        }
        return folder.path
    }
}
