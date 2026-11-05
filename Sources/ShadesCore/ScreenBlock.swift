import Foundation

/// What keeps an agent off your screen when being told to isn't enough: the settings in a folder's
/// `.claude/settings.json`. Agents run as you, so everything here has to be enforced by what runs them.
public enum ScreenBlock {
    /// Where the text and pictures from your screen come to rest, whichever agent they were sent to.
    static let restingPlaces = [
        "~/.t3/userdata/**",
        "~/.t3/scratch/**",
        "~/.claude/projects/**/*.jsonl",
        "~/.codex/**",
        "~/Library/Application Support/shades/captures/**",
    ]

    /// T3's tools that can show another thread's words, other than reading it, which has its own filter.
    static let tools = [
        "mcp__t3-code__t3_thread_search",
        "mcp__t3-code__t3_thread_transfer",
        "mcp__t3-code__t3_queue",
    ]

    /// What's missing from these settings. Empty means they're all there.
    public static func gaps(in settings: Data?) -> [String] {
        guard let settings, let parsed = try? JSONDecoder().decode(Parsed.self, from: settings) else { return ["settings"] }
        var gaps: [String] = []
        let sandbox = parsed.sandbox
        if sandbox?.enabled != true { gaps.append("sandbox.enabled") }
        // Without this, a sandbox that can't start just warns and carries on without it.
        if sandbox?.failIfUnavailable != true { gaps.append("sandbox.failIfUnavailable") }
        // Each of these defaults to the wrong answer: a way out, and no more asking before commands run.
        if sandbox?.allowUnsandboxedCommands != false { gaps.append("sandbox.allowUnsandboxedCommands") }
        if sandbox?.autoAllowBashIfSandboxed != false { gaps.append("sandbox.autoAllowBashIfSandboxed") }

        let denied = Set(parsed.permissions?.deny ?? [])
        // T3 makes its attachments folder writable for every thread, and a file can be moved out of
        // a folder that can't be read. So reading isn't the only thing to deny.
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
