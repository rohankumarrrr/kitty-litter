import Foundation

public enum ScreenBlock {
    static let restingPlaces = [
        "~/.t3/userdata/**",
        "~/.t3/scratch/**",
        "~/.claude/projects/**/*.jsonl",
        "~/.codex/**",
        "~/Library/Application Support/shades/captures/**",
    ]

    static let tools = [
        "mcp__t3-code__t3_thread_search",
        "mcp__t3-code__t3_thread_transfer",
        "mcp__t3-code__t3_queue",
    ]

    public static func gaps(in settings: Data?) -> [String] {
        guard let settings, let parsed = try? JSONDecoder().decode(Parsed.self, from: settings) else { return ["settings"] }
        var gaps: [String] = []
        let sandbox = parsed.sandbox
        if sandbox?.enabled != true { gaps.append("sandbox.enabled") }
        if sandbox?.failIfUnavailable != true { gaps.append("sandbox.failIfUnavailable") }
        if sandbox?.allowUnsandboxedCommands != false { gaps.append("sandbox.allowUnsandboxedCommands") }
        if sandbox?.autoAllowBashIfSandboxed != false { gaps.append("sandbox.autoAllowBashIfSandboxed") }

        let denied = Set(parsed.permissions?.deny ?? [])
        // Outside the repo: T3 lets every thread write to its attachments folder, and a file can be moved out of a folder that can't be read.
        let needed = restingPlaces.map { "Read(\($0))" } + tools + ["Edit(~/.t3/userdata/**)", "Edit(.claude/**)"]
        gaps += needed.filter { !denied.contains($0) }

        let filtersReads = parsed.hooks?.PostToolUse?.contains { rule in
            rule.matcher == "mcp__t3-code__t3_thread_read" && rule.hooks?.contains { $0.command?.contains("thread-read-filter") == true } == true
        }
        if filtersReads != true { gaps.append("thread read filter") }
        return gaps
    }

    private struct Parsed: Decodable {
        struct Permissions: Decodable {
            var deny: [String]?
        }

        struct Sandbox: Decodable {
            var enabled: Bool?
            var failIfUnavailable: Bool?
            var allowUnsandboxedCommands: Bool?
            var autoAllowBashIfSandboxed: Bool?
        }

        struct Hooks: Decodable {
            struct Rule: Decodable {
                struct Command: Decodable {
                    var command: String?
                }
                var matcher: String?
                var hooks: [Command]?
            }
            var PostToolUse: [Rule]?
        }

        var permissions: Permissions?
        var sandbox: Sandbox?
        var hooks: Hooks?
    }
}
