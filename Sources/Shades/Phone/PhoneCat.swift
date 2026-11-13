import Foundation
import ShadesCore

/// A cat on the phone's page, drawn from the window's own art. Its address names only a pose, light or dark, and a
/// jacket colour, and any colour gets a cat, so it says nothing about you or which kittens you have.
enum PhoneCat {
    enum Pose: String, CaseIterable {
        case sit
        /// Sitting with its eyes lit, as a card in Activity draws it, and a kitten that needs you.
        case alert
        case work
        case sleep

        /// Still, as the window draws a kitten at the first tick of its timer.
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

    /// Each art pixel is this many pixels square, so a 16 or 32 point cat lands on whole pixels on a 2x or 3x screen.
    static let scale = 6
    /// The cat's own jacket, which has no colour of its own.
    private static let own = "shades"

    /// What the page puts in a cat's address, such as `sit/7458e8`.
    static func key(_ pose: Pose, jacket: UInt32?) -> String {
        "\(pose.rawValue)/\(jacket.map { String(Opal.hex($0).dropFirst()) } ?? own)"
    }

    /// The picture at `/cat/<light|dark>/<pose>/<jacket>.png`, or `nil` for any other address.
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
            // Only as `key` writes it, so each picture has one address.
            guard name.count == 6, name.allSatisfy("0123456789abcdef".contains), let value = UInt32(name, radix: 16) else { return nil }
            jacket = value
        }
        return CatStamp.png(pose.art, jacket: jacket, dark: parts[2] == "dark", scale: scale)
    }
}
