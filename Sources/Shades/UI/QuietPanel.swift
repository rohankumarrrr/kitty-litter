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

    /// On its way out, so a click meant for what was there can't land on it.
    private var leaving = false
    private var fades = 0

    /// Shows it without taking the keyboard, fading in over Opal's appear time, or at once with Reduce Motion on.
    func fadeIn() {
        fades += 1
        leaving = false
        if !isVisible { alphaValue = 0 }
        orderFrontRegardless()
        guard !Motion.isReduced else {
            alphaValue = 1
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.appear
            context.timingFunction = Motion.ease
            animator().alphaValue = 1
        }
    }

    /// Puts it away with a quick fade, or at once with Reduce Motion on.
    func fadeOut() {
        guard isVisible, !leaving else { return }
        fades += 1
        guard !Motion.isReduced else { return orderOut(nil) }
        let fade = fades
        leaving = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Motion.quick
            context.timingFunction = Motion.ease
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.fades == fade else { return }
                self.leaving = false
                self.orderOut(nil)
                self.alphaValue = 1
            }
        })
    }

    override func sendEvent(_ event: NSEvent) {
        if leaving, [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp].contains(event.type) { return }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        Self.performEdit(event, from: self) || super.performKeyEquivalent(with: event)
    }

    /// There's no menu bar of ours while another app is active, so the editing keys come through here.
    static func performEdit(_ event: NSEvent, from sender: NSWindow) -> Bool {
        guard let action = editAction(for: event) else { return false }
        return NSApp.sendAction(action, to: nil, from: sender)
    }

    /// What an Edit menu would do with these keys, Redo's ⇧⌘Z included.
    static func editAction(for event: NSEvent) -> Selector? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return nil }
        if modifiers == [.command, .shift] { return key == "z" ? Selector(("redo:")) : nil }
        return modifiers == .command ? editActions[key] : nil
    }

    private static let editActions: [String: Selector] = [
        "x": #selector(NSText.cut(_:)),
        "c": #selector(NSText.copy(_:)),
        "v": #selector(NSText.paste(_:)),
        "a": #selector(NSText.selectAll(_:)),
        "z": Selector(("undo:")),
    ]
}
