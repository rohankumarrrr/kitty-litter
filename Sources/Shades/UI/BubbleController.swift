import AppKit
import ShadesCore

/// The speech bubble's window. It floats over the cat and follows it around. It doesn't
/// take the keyboard unless you click into its text.
@MainActor
final class BubbleController {
    /// Long enough to stop a click that was already on its way from landing on a new button.
    static let armDelay: TimeInterval = 0.7
    private static let clickAwayGrace: TimeInterval = 1
    /// A notice turns up unasked, so a click that was already on its way shouldn't lose it unread.
    private static let noticeClickAwayGrace: TimeInterval = 6

    let panel = QuietPanel(allowsKey: true)
    let view = BubbleView(frame: .zero)
    private(set) var content: BubbleContent?

    var anchor: () -> (frame: NSRect, visible: NSRect) = { (.zero, .zero) }
    /// Esc or a click somewhere else. The flag says which.
    var onDismiss: ((_ byClick: Bool) -> Void)?
    /// Esc is only taken from other apps while the bubble's up.
    var onVisibilityChange: (() -> Void)?

    private var clickMonitor: Any?
    private var thinkingTimer: Timer?
    private var armTimer: Timer?
    private var shownAt = Date.distantPast

    init() {
        panel.contentView = view
    }

    var isVisible: Bool { panel.isVisible }

    func show(_ content: BubbleContent?) {
        guard let content else {
            hide()
            return
        }
        let sameKind = self.content.map { kindMatches($0, content) } ?? false
        var nextApproval = false
        if case .approval(let shown, _, _)? = self.content, case .approval(let next, _, _) = content {
            nextApproval = shown.id != next.id
        }
        let isNew = !(sameKind && panel.isVisible)
        if case .notice(_, let shown, _)? = self.content, case .notice(_, let next, _) = content, shown != next {
            shownAt = Date()
        }
        self.content = content

        relayout(keepingWidth: !isNew)
        if isNew {
            shownAt = Date()
            panel.orderFrontRegardless()
            installClickMonitor()
            onVisibilityChange?()
        }
        if isNew || nextApproval { armIfNeeded(content) }
        updateThinkingTimer()
    }

    /// Runs after the cat moves or a window's size changes.
    func reposition() {
        guard panel.isVisible, content != nil else { return }
        let (frame, visible) = anchor()
        let placement = BubbleLayout.place(size: panel.frame.size, over: frame, in: visible)
        apply(placement)
    }

    func hide() {
        content = nil
        thinkingTimer?.invalidate()
        armTimer?.invalidate()
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        panel.orderOut(nil)
        onVisibilityChange?()
    }

    private func relayout(keepingWidth: Bool) {
        guard let content else { return }
        let (frame, visible) = anchor()
        let limit = max(120, (visible.maxY - frame.maxY) - BubbleLayout.margin)
        let size = view.update(content, keepingWidth: keepingWidth, limitHeight: max(limit, visible.height * 0.4))
        apply(BubbleLayout.place(size: size, over: frame, in: visible))
        panel.invalidateShadow()
    }

    private func apply(_ placement: BubbleLayout.Placement) {
        view.tailX = placement.tailX
        view.tailOnTop = placement.below
        if panel.frame != placement.frame {
            panel.setFrame(placement.frame, display: true)
            panel.invalidateShadow()
        }
    }

    private func kindMatches(_ a: BubbleContent, _ b: BubbleContent) -> Bool {
        switch (a, b) {
        case (.thinking, .thinking), (.listening, .listening), (.reply, .reply), (.line, .line),
             (.notice, .notice), (.approval, .approval):
            return true
        default:
            return false
        }
    }

    /// Buttons that start or allow things wait a moment, so a click meant for something
    /// else can't land on them as they appear under the pointer.
    private func armIfNeeded(_ content: BubbleContent) {
        switch content {
        case .approval: break
        default: return
        }
        view.setButtonsArmed(false)
        armTimer?.invalidate()
        armTimer = Timer.scheduledTimer(withTimeInterval: Self.armDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.view.setButtonsArmed(true) }
        }
    }

    private func updateThinkingTimer() {
        guard case .thinking = content else {
            thinkingTimer?.invalidate()
            thinkingTimer = nil
            return
        }
        guard thinkingTimer == nil else { return }
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.view.advanceThinking()
                self.relayout(keepingWidth: true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        thinkingTimer = timer
    }

    private func installClickMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                var grace = Self.clickAwayGrace
                if case .notice = self.content { grace = Self.noticeClickAwayGrace }
                guard Date().timeIntervalSince(self.shownAt) > grace else { return }
                self.onDismiss?(true)
            }
        }
    }
}
