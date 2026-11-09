import Foundation

/// How much one channel tells you on one device: by a bubble or notification on the Mac, or a push to your phone.
public enum NotifyLevel: String, Codable, Sendable, CaseIterable {
    case everything
    /// Approvals, questions, decisions and runs that failed, and not a session that finished or work that moved.
    case needsYou
    case nothing
}

public enum NotifyDevice: Sendable, CaseIterable {
    case mac, phone
}

/// What a channel in Messages tells you, on the Mac and on your phone. Muting it tells you nothing anywhere, and keeps
/// what each was set to for when it's unmuted.
public struct ChannelNotifications: Codable, Sendable, Equatable {
    public var mac: NotifyLevel
    public var phone: NotifyLevel
    public var muted: Bool

    public init(mac: NotifyLevel = .everything, phone: NotifyLevel = .everything, muted: Bool = false) {
        self.mac = mac
        self.phone = phone
        self.muted = muted
    }

    public subscript(device: NotifyDevice) -> NotifyLevel {
        get { device == .mac ? mac : phone }
        set { if device == .mac { mac = newValue } else { phone = newValue } }
    }

    /// "Everything" is everything that would pop up anyway, so a finished session only notifies with Also when a
    /// session finishes on.
    public func allows(needsYou: Bool, on device: NotifyDevice) -> Bool {
        if muted { return false }
        switch self[device] {
        case .everything: return true
        case .needsYou: return needsYou
        case .nothing: return false
        }
    }

    private enum CodingKeys: String, CodingKey {
        case mac, phone, muted
    }

    /// Anything left out of a hand-edited file takes its default.
    public init(from decoder: Decoder) throws {
        let saved = try decoder.container(keyedBy: CodingKeys.self)
        mac = try saved.decodeIfPresent(NotifyLevel.self, forKey: .mac) ?? .everything
        phone = try saved.decodeIfPresent(NotifyLevel.self, forKey: .phone) ?? .everything
        muted = try saved.decodeIfPresent(Bool.self, forKey: .muted) ?? false
    }
}
