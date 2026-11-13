import AppKit

/// The one-word things the cat says, as the small dark pill from the site.
@MainActor
final class SayPill {
    let panel = QuietPanel(shadow: false)
    private let pill = PillView()
    private var hideTimer: Timer?

    init() {
        panel.ignoresMouseEvents = true
        panel.contentView = pill
    }

    var isVisible: Bool { panel.isVisible }

    /// In the theme you just picked.
    func restyle() {
        panel.wearTheme()
    }

    func say(_ word: String, over anchor: NSRect, in visible: NSRect, seconds: TimeInterval?) {
        hideTimer?.invalidate()
        pill.text = word
        let size = pill.fittingSize
        let x = min(max(anchor.midX - size.width / 2, visible.minX + 4), visible.maxX - 4 - size.width)
        panel.setFrame(NSRect(origin: NSPoint(x: x, y: anchor.maxY + 3), size: size), display: true)
        panel.orderFrontRegardless()
        guard let seconds else { return }
        hideTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    func follow(_ anchor: NSRect, in visible: NSRect) {
        guard panel.isVisible else { return }
        let size = panel.frame.size
        let x = min(max(anchor.midX - size.width / 2, visible.minX + 4), visible.maxX - 4 - size.width)
        panel.setFrameOrigin(NSPoint(x: x, y: anchor.maxY + 3))
    }

    func hide() {
        hideTimer?.invalidate()
        panel.orderOut(nil)
    }
}

private final class PillView: NSView {
    var text = "" { didSet { needsDisplay = true } }

    private var label: NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: MessagesInk.pillText])
    }

    override var fittingSize: NSSize {
        let size = label.size()
        return NSSize(width: ceil(size.width) + 16, height: ceil(size.height) + 7)
    }

    override func draw(_ dirtyRect: NSRect) {
        MessagesInk.pill.setFill()
        let radius = min(10, bounds.height / 2)
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        let text = label
        let size = text.size()
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
}
