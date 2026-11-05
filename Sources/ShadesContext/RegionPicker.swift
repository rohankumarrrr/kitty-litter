import AppKit

/// The drag-a-box overlay. It runs in non-activating panels, so the app you're pointing at stays
/// frontmost throughout, and Shades can still tell what you're looking at afterwards.
@MainActor
final class RegionPicker {
    static let shared = RegionPicker()

    private var waiting: CheckedContinuation<CGRect?, Never>?
    private var panels: [RegionPanel] = []
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    func pick() async -> CGRect? {
        // Two overlays at once would fight over the mouse, so a second request just cancels.
        guard waiting == nil else { return nil }
        return await withCheckedContinuation { continuation in
            waiting = continuation
            show()
        }
    }

    private func show() {
        _ = NSApplication.shared
        panels = NSScreen.screens.map { screen in
            let panel = RegionPanel(screen: screen)
            let view = panel.overlay
            view.onDragStart = { [weak self] in
                self?.panels.forEach { $0.overlay.hideHint() }
            }
            view.onFinish = { [weak self, weak panel] rect in
                guard let self, let panel else { return }
                self.finish(rect.map(panel.globalRect(from:)))
            }
            return panel
        }
        guard !panels.isEmpty else {
            finish(nil)
            return
        }
        panels.forEach { $0.reveal() }

        // Esc only reaches a key window. The panel under the mouse takes that, without activating us.
        let mouse = NSEvent.mouseLocation
        let target = panels.first { $0.frame.contains(mouse) } ?? panels.first
        target?.makeKey()
        target?.makeFirstResponder(target?.overlay)
        NSCursor.crosshair.set()
        // The system ignores this until the panel has reached the screen, so ask again once it has.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            if self?.waiting != nil { NSCursor.crosshair.set() }
        }

        // A stuck overlay would block the whole Mac, so anything that pulls you away cancels it.
        watch(NSWorkspace.shared.notificationCenter, NSWorkspace.didActivateApplicationNotification)
        watch(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification)
    }

    private func watch(_ center: NotificationCenter, _ name: Notification.Name) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(nil) }
        }
        observers.append((center, token))
    }

    private func finish(_ rect: CGRect?) {
        guard let waiting else { return }
        self.waiting = nil
        observers.forEach { $0.center.removeObserver($0.token) }
        observers = []
        panels.forEach { $0.orderOut(nil) }
        panels = []
        NSCursor.arrow.set()
        waiting.resume(returning: rect)
    }
}

/// Covers one display, above the menu bar and Dock, and over full-screen apps too.
final class RegionPanel: NSPanel {
    let overlay: RegionOverlayView

    init(screen: NSScreen) {
        let size = screen.frame.size
        let visible = screen.visibleFrame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        overlay = RegionOverlayView(frame: CGRect(origin: .zero, size: size), hintArea: visible)
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        contentView = overlay
        setFrame(screen.frame, display: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// AppKit would otherwise push a borderless window out from under the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    func reveal() {
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            animator().alphaValue = 1
        }
    }

    /// Overlay coordinates to AppKit global points.
    func globalRect(from rect: CGRect) -> CGRect {
        rect.offsetBy(dx: frame.minX, dy: frame.minY)
    }
}
