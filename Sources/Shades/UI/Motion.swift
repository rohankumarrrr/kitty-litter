import AppKit

/// How things move: short and easing out, as Opal does. Reduce Motion, from Accessibility settings, stills it all:
/// the cat is just there, and the cats in Messages and the kittens view hold still.
@MainActor
enum Motion {
    /// Overrides the setting. `--reduce-motion` turns it on in the demo, and tests pick either way.
    static var forced: Bool? = DevFlags.reducesMotion ? true : nil

    static var isReduced: Bool { forced ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Opal's curve, `cubic-bezier(.2, .8, .2, 1)`.
    static let ease = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
    /// Hovering and pressing.
    static let quick: TimeInterval = 0.12
    /// Something appearing.
    static let appear: TimeInterval = 0.2
    /// Something moving.
    static let move: TimeInterval = 0.28
}
