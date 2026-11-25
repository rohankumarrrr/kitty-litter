import Foundation
import ShadesCore

enum PhoneCat {
    enum Pose: String, CaseIterable {
        case sit
        case alert
        case work
        case sleep

        init(_ state: KittenStatus.State) {
            switch state {
            case .working: self = .work
            case .needsYou: self = .alert
            case .idle: self = .sleep
            case .notSetUp: self = .sit
            }
        }

        var art: CatPose {
            switch self {
            case .sit: return CatPose(frame: .sit)
            case .alert: return CatPose(frame: .sit, glint: .attention(bright: true))
            case .work: return CatPose(frame: .run1, glint: .thinking(bright: true))
            case .sleep: return CatPose(frame: .sleep1, z: 0)
            }
        }
    }

    static let scale = 6
    private static let own = "shades"

    static func key(_ pose: Pose, jacket: UInt32?) -> String {
        "\(pose.rawValue)/\(jacket.map { String(Opal.hex($0).dropFirst()) } ?? own)"
    }

    @MainActor
    static func png(at path: String) -> Data? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 5, parts[0].isEmpty, parts[1] == "cat", ["light", "dark"].contains(parts[2]),
              let pose = Pose(rawValue: String(parts[3])), parts[4].hasSuffix(".png")
        else { return nil }
        let name = parts[4].dropLast(4)
        let jacket: UInt32?
        if name == own {
            jacket = nil
        } else {
            guard name.count == 6, name.allSatisfy("0123456789abcdef".contains), let value = UInt32(name, radix: 16) else { return nil }
            jacket = value
        }
        return CatStamp.png(pose.art, jacket: jacket, dark: parts[2] == "dark", scale: scale)
    }
}
