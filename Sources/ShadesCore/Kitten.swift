import Foundation

/// A specialist agent. It's a folder registered as a T3 project: instructions and notes in there
/// load by themselves in every thread it starts, which is how it already knows what you'd
/// otherwise have to explain. See docs/kittens.md.
public struct Kitten: Sendable, Equatable, Identifiable {
    public var name: String
    public var role: String
    /// What it looks after, in the words Shades reads to decide what goes to it.
    public var covers: String
    public var folder: String
    /// The folder of the T3 project it works in. That's its own folder, unless it looks after an
    /// app that already has a project.
    public var project: String
    /// Not taking work yet. It shows up with the others, but nothing gets sent to it.
    public var planned: Bool
    /// The colour of its jacket, as 0xRRGGBB, or `nil` for the black one Shades wears.
    public var color: UInt32?
    /// Whether text from your screen can reach it. Off for a kitten that can change the rules
    /// everyone else works by, because a page shouldn't get a say in those.
    public var seesScreen: Bool
    /// Whether its reports wait in the inbox, rather than each taking a turn in the bubble.
    public var usesInbox: Bool

    public var id: String { folder }

    public init(
        name: String,
        role: String,
        covers: String,
        folder: String,
        project: String? = nil,
        planned: Bool = false,
        color: UInt32? = nil,
        seesScreen: Bool = true,
        usesInbox: Bool = false
    ) {
        self.name = name
        self.role = role
        self.covers = covers
        self.folder = folder
        self.project = project ?? folder
        self.planned = planned
        self.color = color
        self.seesScreen = seesScreen
        self.usesInbox = usesInbox
    }
}

public enum Kittens {
    private struct Profile: Decodable {
        let name: String
        let role: String
        let covers: String
        /// Like "~/code/app". A relative path starts from the kitten's folder.
        var project: String?
        var planned: Bool?
        /// Like "#b3261e".
        var color: String?
        var seesScreen: Bool?
        var inbox: Bool?
    }

    /// Where kittens live. Their contents are personal, so they stay out of this repo.
    public static var defaultFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("kittens", isDirectory: true)
    }

    /// Every folder with a `kitten.json`. One that can't be read is skipped, so it can't take the rest with it.
    public static func load(from folder: URL = defaultFolder) -> [Kitten] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { home -> Kitten? in
            let file = home.appendingPathComponent("kitten.json")
            guard let data = try? Data(contentsOf: file),
                  let profile = try? JSONDecoder().decode(Profile.self, from: data)
            else { return nil }
            return Kitten(
                name: profile.name,
                role: profile.role,
                covers: profile.covers,
                folder: home.standardizedFileURL.path,
                project: profile.project.map {
                    URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath, relativeTo: home).standardizedFileURL.path
                },
                planned: profile.planned ?? false,
                color: profile.color.flatMap { UInt32($0.replacingOccurrences(of: "#", with: ""), radix: 16) },
                seesScreen: profile.seesScreen ?? true,
                usesInbox: profile.inbox ?? false
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
