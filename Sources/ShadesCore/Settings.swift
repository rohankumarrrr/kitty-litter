import Foundation

/// Stored as JSON in Application Support, so it's easy to edit by hand.
public struct Settings: Codable, Sendable, Equatable {
    public var quickModel: ModelChoice
    public var frontierModel: ModelChoice
    /// Writes the few sentences the cat says when a session ends.
    public var summaryModel: ModelChoice
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
    /// Messages on your phone, over your tailnet. Off until you turn it on.
    public var phone: Bool
    /// A notification when a session finishes, as well as when something needs you. Off until you turn it on.
    public var notifyFinished: Bool
    /// Nothing pops up while it's on, and what came in waits for you to catch up on.
    public var doNotDisturb: Bool

    public init(
        quickModel: ModelChoice = .quick,
        frontierModel: ModelChoice = .frontier,
        summaryModel: ModelChoice = .summary,
        quickMode: RuntimeMode = .auto,
        frontierMode: RuntimeMode = .auto,
        privateApps: [String] = Settings.defaultPrivateApps,
        vocabulary: [String] = [],
        talkKey: HoldKey = .rightOption,
        dictateKey: HoldKey = .fn,
        phone: Bool = false,
        notifyFinished: Bool = false,
        doNotDisturb: Bool = false
    ) {
        self.quickModel = quickModel
        self.frontierModel = frontierModel
        self.summaryModel = summaryModel
        self.quickMode = quickMode
        self.frontierMode = frontierMode
        self.privateApps = privateApps
        self.vocabulary = vocabulary
        self.talkKey = talkKey
        self.dictateKey = dictateKey
        self.phone = phone
        self.notifyFinished = notifyFinished
        self.doNotDisturb = doNotDisturb
    }

    private enum CodingKeys: String, CodingKey {
        case quickModel, frontierModel, summaryModel, quickMode, frontierMode, privateApps, vocabulary, talkKey, dictateKey, phone, notifyFinished, doNotDisturb
    }

    /// Anything missing takes its default, so a settings file from an older version keeps working.
    public init(from decoder: Decoder) throws {
        let saved = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Settings()
        quickModel = try saved.decodeIfPresent(ModelChoice.self, forKey: .quickModel) ?? defaults.quickModel
        frontierModel = try saved.decodeIfPresent(ModelChoice.self, forKey: .frontierModel) ?? defaults.frontierModel
        summaryModel = try saved.decodeIfPresent(ModelChoice.self, forKey: .summaryModel) ?? defaults.summaryModel
        quickMode = try saved.decodeIfPresent(RuntimeMode.self, forKey: .quickMode) ?? defaults.quickMode
        frontierMode = try saved.decodeIfPresent(RuntimeMode.self, forKey: .frontierMode) ?? defaults.frontierMode
        privateApps = try saved.decodeIfPresent([String].self, forKey: .privateApps) ?? defaults.privateApps
        vocabulary = try saved.decodeIfPresent([String].self, forKey: .vocabulary) ?? defaults.vocabulary
        talkKey = try saved.decodeIfPresent(HoldKey.self, forKey: .talkKey) ?? defaults.talkKey
        dictateKey = try saved.decodeIfPresent(HoldKey.self, forKey: .dictateKey) ?? defaults.dictateKey
        phone = try saved.decodeIfPresent(Bool.self, forKey: .phone) ?? defaults.phone
        notifyFinished = try saved.decodeIfPresent(Bool.self, forKey: .notifyFinished) ?? defaults.notifyFinished
        doNotDisturb = try saved.decodeIfPresent(Bool.self, forKey: .doNotDisturb) ?? defaults.doNotDisturb
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
