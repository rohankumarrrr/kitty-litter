import Foundation

public enum NotifyLevel: String, Codable, Sendable, CaseIterable {
    case everything
    case needsYou
    case nothing
}

public enum NotifyDevice: Sendable, CaseIterable {
    case mac, phone
}

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

    public init(from decoder: Decoder) throws {
        let saved = try decoder.container(keyedBy: CodingKeys.self)
        mac = try saved.decodeIfPresent(NotifyLevel.self, forKey: .mac) ?? .everything
        phone = try saved.decodeIfPresent(NotifyLevel.self, forKey: .phone) ?? .everything
        muted = try saved.decodeIfPresent(Bool.self, forKey: .muted) ?? false
    }
}
