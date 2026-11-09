import AppKit

/// Reduce Motion, from Accessibility settings. With it on, nothing moves on its own: the cat is just there,
/// and the cats in Messages and the kittens view hold still.
@MainActor
enum Motion {
    /// Overrides the setting. `--reduce-motion` turns it on in the demo, and tests pick either way.
    static var forced: Bool? = DevFlags.reducesMotion ? true : nil

    static var isReduced: Bool { forced ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}
