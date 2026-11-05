import Foundation

/// Stored as JSON in Application Support, so it's easy to edit by hand.
public struct Settings: Codable, Sendable, Equatable {
    public var quickModel: ModelChoice
    public var frontierModel: ModelChoice
    public var quickMode: RuntimeMode
    /// `auto` avoids constant prompts without giving text from your screen free rein.
    public var frontierMode: RuntimeMode
    /// Nothing is captured while one of these apps is in front.
    public var privateApps: [String]
    /// Extra words for speech recognition, on top of your T3 project names.
    public var vocabulary: [String]
    /// Hold to talk to the cat.
    public var talkKey: HoldKey
    /// Hold to dictate wherever the cursor is.
    public var dictateKey: HoldKey

    public init(
        quickModel: ModelChoice = .quick,
        frontierModel: ModelChoice = .frontier,
        quickMode: RuntimeMode = .auto,
        frontierMode: RuntimeMode = .auto,
        privateApps: [String] = Settings.defaultPrivateApps,
        vocabulary: [String] = [],
        talkKey: HoldKey = .rightOption,
        dictateKey: HoldKey = .fn
    ) {
        self.quickModel = quickModel
        self.frontierModel = frontierModel
        self.quickMode = quickMode
        self.frontierMode = frontierMode
        self.privateApps = privateApps
        self.vocabulary = vocabulary
        self.talkKey = talkKey
        self.dictateKey = dictateKey
    }

    public static let defaultPrivateApps = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.apple.keychainaccess",
        "com.apple.Passwords",
    ]

    public static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("shades", isDirectory: true)
    }

    private static var fileURL: URL { directory.appendingPathComponent("settings.json") }

    public static func load() -> Settings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(Settings.self, from: data)
        else { return Settings() }
        return settings
    }

    public func save() throws {
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: Self.fileURL, options: .atomic)
    }
}
