import Foundation

public enum TextSize: String, Codable, Sendable, CaseIterable {
    case small, standard, large, larger
}

/// What words you send into a thread do while its agent is still working, as T3 Code's own composer offers: join the
/// run that's going, or wait for it to finish and get a run of their own.
public enum FollowUpBehavior: String, Codable, Sendable, CaseIterable {
    case steer, queue

    /// What ⌘Return sends, as in T3 Code.
    public var other: FollowUpBehavior { self == .steer ? .queue : .steer }
}

/// Every ask goes straight to one kitten, by its `Kitten.id`, and nothing else pops up until it's off, for a session
/// shared on screen. `thread` is the kitten's thread those asks carry on in, once there is one.
public struct Lockdown: Codable, Sendable, Equatable {
    public var kitten: String
    public var thread: String?

    public init(kitten: String, thread: String? = nil) {
        self.kitten = kitten
        self.thread = thread
    }
}

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
    /// What each channel in Messages tells you, by its key. Only ones you've changed are here.
    public var channelNotifications: [String: ChannelNotifications]
    /// How big the words are in Messages, in what's said and in the box you type in.
    public var textSize: TextSize
    /// Open shows a thread in Messages wherever Messages has it, and T3 only for one it doesn't. Off, Open is always T3.
    public var openInMessages: Bool
    /// The font Messages draws its words in, by family name, or `nil` for the system's. "New York", "SF Pro Rounded"
    /// and "SF Mono" are the system's own serif, rounded and monospaced faces.
    public var messagesFont: String?
    /// What a message you send to a thread from Messages or your phone does while it's working.
    public var followUpBehavior: FollowUpBehavior
    /// Off until you pick a kitten for it from the cat's menu.
    public var lockdown: Lockdown?

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
        case quickModel, frontierModel, summaryModel, quickMode, frontierMode, privateApps, vocabulary, talkKey, dictateKey, phone, notifyFinished, doNotDisturb, channelNotifications, textSize, openInMessages, messagesFont, followUpBehavior, lockdown
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
        channelNotifications = try saved.decodeIfPresent([String: ChannelNotifications].self, forKey: .channelNotifications) ?? defaults.channelNotifications
        textSize = try saved.decodeIfPresent(TextSize.self, forKey: .textSize) ?? defaults.textSize
        openInMessages = try saved.decodeIfPresent(Bool.self, forKey: .openInMessages) ?? defaults.openInMessages
        messagesFont = try saved.decodeIfPresent(String.self, forKey: .messagesFont)
        followUpBehavior = try saved.decodeIfPresent(FollowUpBehavior.self, forKey: .followUpBehavior) ?? defaults.followUpBehavior
        lockdown = try saved.decodeIfPresent(Lockdown.self, forKey: .lockdown)
    }

    /// A channel you've never changed tells you everything.
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
