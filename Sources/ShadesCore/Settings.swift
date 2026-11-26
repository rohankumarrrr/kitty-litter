import Foundation

public enum TextSize: String, Codable, Sendable, CaseIterable {
    case small, standard, large, larger
}

public enum FollowUpBehavior: String, Codable, Sendable, CaseIterable {
    case steer, queue

    public var other: FollowUpBehavior { self == .steer ? .queue : .steer }
}

public struct Lockdown: Codable, Sendable, Equatable {
    public var kitten: String
    public var thread: String?

    public init(kitten: String, thread: String? = nil) {
        self.kitten = kitten
        self.thread = thread
    }
}

public struct Settings: Codable, Sendable, Equatable {
    public var quickModel: ModelChoice
    public var frontierModel: ModelChoice
    public var fallbackModel: ModelChoice
    public var summaryModel: ModelChoice
    public var quickMode: RuntimeMode
    public var frontierMode: RuntimeMode
    public var privateApps: [String]
    public var vocabulary: [String]
    public var talkKey: HoldKey
    public var dictateKey: HoldKey
    public var phone: Bool
    public var notifyFinished: Bool
    public var doNotDisturb: Bool
    public var channelNotifications: [String: ChannelNotifications]
    public var textSize: TextSize
    public var openInMessages: Bool
    public var messagesFont: String?
    public var followUpBehavior: FollowUpBehavior
    public var lockdown: Lockdown?

    public init(
        quickModel: ModelChoice = .quick,
        frontierModel: ModelChoice = .frontier,
        fallbackModel: ModelChoice = .fallback,
        summaryModel: ModelChoice = .summary,
        quickMode: RuntimeMode = .auto,
        frontierMode: RuntimeMode = .fullAccess,
        privateApps: [String] = Settings.defaultPrivateApps,
        vocabulary: [String] = [],
        talkKey: HoldKey = .rightOption,
        dictateKey: HoldKey = .fn,
        phone: Bool = false,
        notifyFinished: Bool = false,
        doNotDisturb: Bool = false,
        channelNotifications: [String: ChannelNotifications] = [:],
        textSize: TextSize = .standard,
        openInMessages: Bool = true,
        messagesFont: String? = nil,
        followUpBehavior: FollowUpBehavior = .steer,
        lockdown: Lockdown? = nil
    ) {
        self.quickModel = quickModel
        self.frontierModel = frontierModel
        self.fallbackModel = fallbackModel
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
        self.channelNotifications = channelNotifications
        self.textSize = textSize
        self.openInMessages = openInMessages
        self.messagesFont = messagesFont
        self.followUpBehavior = followUpBehavior
        self.lockdown = lockdown
    }

    private enum CodingKeys: String, CodingKey {
        case quickModel, frontierModel, fallbackModel, summaryModel, quickMode, frontierMode, privateApps, vocabulary, talkKey, dictateKey, phone, notifyFinished, doNotDisturb, channelNotifications, textSize, openInMessages, messagesFont, followUpBehavior, lockdown
    }

    public init(from decoder: Decoder) throws {
        let saved = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Settings()
        quickModel = try saved.decodeIfPresent(ModelChoice.self, forKey: .quickModel) ?? defaults.quickModel
        frontierModel = try saved.decodeIfPresent(ModelChoice.self, forKey: .frontierModel) ?? defaults.frontierModel
        fallbackModel = try saved.decodeIfPresent(ModelChoice.self, forKey: .fallbackModel) ?? defaults.fallbackModel
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
        channelNotifications = try saved.decodeIfPresent([String: ChannelNotifications].self, forKey: .channelNotifications) ?? defaults.channelNotifications
        textSize = try saved.decodeIfPresent(TextSize.self, forKey: .textSize) ?? defaults.textSize
        openInMessages = try saved.decodeIfPresent(Bool.self, forKey: .openInMessages) ?? defaults.openInMessages
        messagesFont = try saved.decodeIfPresent(String.self, forKey: .messagesFont)
        followUpBehavior = try saved.decodeIfPresent(FollowUpBehavior.self, forKey: .followUpBehavior) ?? defaults.followUpBehavior
        lockdown = try saved.decodeIfPresent(Lockdown.self, forKey: .lockdown)
    }

    public func notifications(for channel: String) -> ChannelNotifications {
        channelNotifications[channel] ?? ChannelNotifications()
    }

    public mutating func setNotifications(_ notifications: ChannelNotifications, for channel: String) {
        channelNotifications[channel] = notifications == ChannelNotifications() ? nil : notifications
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

    public static var fileURL: URL { directory.appendingPathComponent("settings.json") }

    public static func load(from file: URL = fileURL) -> Settings {
        guard let data = try? Data(contentsOf: file),
              let settings = try? JSONDecoder().decode(Settings.self, from: data)
        else { return Settings() }
        return settings
    }

    public static func moveKittensToFullAccessOnce(in folder: URL = directory) {
        let moved = folder.appendingPathComponent("kittens-moved-to-full-access")
        let file = folder.appendingPathComponent("settings.json")
        guard !FileManager.default.fileExists(atPath: moved.path) else { return }
        if let data = try? Data(contentsOf: file) {
            guard var saved = try? JSONDecoder().decode(Settings.self, from: data) else { return }
            if saved.frontierMode == .auto {
                saved.frontierMode = .fullAccess
                guard (try? saved.save(to: file)) != nil else { return }
            }
        }
        try? Data().write(to: moved)
    }

    public func save(to file: URL = fileURL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoded().write(to: file, options: .atomic)
    }

    private func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
