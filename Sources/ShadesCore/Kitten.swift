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

    public var id: String { folder }

    public init(name: String, role: String, covers: String, folder: String) {
        self.name = name
        self.role = role
        self.covers = covers
        self.folder = folder
    }
}

public enum Kittens {
    private struct Profile: Decodable {
        let name: String
        let role: String
        let covers: String
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
            return Kitten(name: profile.name, role: profile.role, covers: profile.covers, folder: home.standardizedFileURL.path)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
