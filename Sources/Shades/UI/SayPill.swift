import AppKit

/// The one-word things the cat says, on a capsule of Opal's glass.
@MainActor
final class SayPill {
    let panel = QuietPanel()
    private let pill = PillView()
    private var hideTimer: Timer?

    init() {
        panel.ignoresMouseEvents = true
        panel.contentView = pill
    }

    private(set) var isVisible = false

    func say(_ word: String, over anchor: NSRect, in visible: NSRect, seconds: TimeInterval?) {
        hideTimer?.invalidate()
        pill.text = word
        let size = pill.fittingSize
        let x = min(max(anchor.midX - size.width / 2, visible.minX + 4), visible.maxX - 4 - size.width)
        panel.setFrame(NSRect(origin: NSPoint(x: x, y: anchor.maxY + 3), size: size), display: true)
        panel.invalidateShadow()
        isVisible = true
        panel.fadeIn()
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
        isVisible = false
        panel.fadeOut()
    }
}

private final class PillView: NSView {
    var text = "" { didSet { needsDisplay = true } }

    private static let height: CGFloat = 22

    private var label: NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: MessagesInk.font(ofSize: 12), .foregroundColor: MessagesInk.pillText])
    }

    override var fittingSize: NSSize {
        NSSize(width: ceil(label.size().width) + 20, height: Self.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        Opal.glass(NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius - 0.5, yRadius: radius - 0.5))
        let text = label
        let size = text.size()
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
}
