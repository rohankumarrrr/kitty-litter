import AppKit
import ShadesContext

@MainActor
enum ClickAway {
    static var isPaused = false
}

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
        collectionBehavior = .floatsOverEverything
        canHide = false
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

    private var leaving = false
    private var fades = 0

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

    // Outside the repo: an app that isn't active has no menu bar, so its Edit keys reach no menu.
    static func performEdit(_ event: NSEvent, from sender: NSWindow) -> Bool {
        guard let action = editAction(for: event) else { return false }
        return NSApp.sendAction(action, to: nil, from: sender)
    }

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
