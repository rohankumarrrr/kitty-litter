import AppKit

@MainActor
enum Motion {
    static var forced: Bool? = DevFlags.reducesMotion ? true : nil

    static var isReduced: Bool { forced ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    static let ease = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
    static let quick: TimeInterval = 0.12
    static let appear: TimeInterval = 0.2
    static let move: TimeInterval = 0.28
}
