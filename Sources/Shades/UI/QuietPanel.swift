import AppKit

/// Clicking or typing somewhere else closes the cat's small windows. The demo pauses that while it records, since the
/// real desktop around it goes on being used.
@MainActor
enum ClickAway {
    static var isPaused = false
}

/// A window that floats over everything, on every Space and over full-screen apps,
/// without ever making Shades the active app. Most never take the keyboard either.
class QuietPanel: NSPanel {
    private let allowsKey: Bool

    init(allowsKey: Bool = false, shadow: Bool = true) {
        self.allowsKey = allowsKey
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = shadow
        isMovable = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        Self.performEdit(event, from: self) || super.performKeyEquivalent(with: event)
    }

    /// There's no menu bar of ours while another app is active, so the editing keys come through here.
    static func performEdit(_ event: NSEvent, from sender: NSWindow) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              let key = event.charactersIgnoringModifiers?.lowercased(),
              let action = editActions[key]
        else { return false }
        return NSApp.sendAction(action, to: nil, from: sender)
    }

    private static let editActions: [String: Selector] = [
        "x": #selector(NSText.cut(_:)),
        "c": #selector(NSText.copy(_:)),
        "v": #selector(NSText.paste(_:)),
        "a": #selector(NSText.selectAll(_:)),
        "z": Selector(("undo:")),
    ]
}

extension QuietPanel {
    /// In the theme you picked in Messages: its light or dark for scrollers, selections and cats, and everything in it
    /// drawn again in its colours.
    func wearTheme() {
        appearance = MessagesInk.appearance
        contentView?.redrawAll()
    }
}

private extension NSView {
    func redrawAll() {
        needsDisplay = true
        subviews.forEach { $0.redrawAll() }
    }
}
