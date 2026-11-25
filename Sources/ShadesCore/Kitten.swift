import Foundation

public struct Kitten: Sendable, Equatable, Identifiable {
    public var name: String
    public var role: String
    public var covers: String
    public var folder: String
    public var project: String
    public var planned: Bool
    public var color: UInt32?
    public var seesScreen: Bool
    public var usesInbox: Bool

    public var id: String { folder }

    public var workspace: String { seesScreen ? project : folder }

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
        var project: String?
        var planned: Bool?
        var color: String?
        var seesScreen: Bool?
        var inbox: Bool?
    }

    public static var defaultFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("kittens", isDirectory: true)
    }

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
                    // Outside the repo: Foundation resolves a relative path from the base's parent unless the base ends in a slash, which a linked folder's URL lacks.
                    URL(
                        fileURLWithPath: NSString(string: $0).expandingTildeInPath,
                        relativeTo: URL(fileURLWithPath: home.path, isDirectory: true)
                    ).standardizedFileURL.path
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
