import AppKit

/// Dims one display, except for the box you're dragging on it.
final class RegionOverlayView: NSView {
    var onDragStart: (() -> Void)?
    /// A rect in view coordinates, or `nil` if you cancelled.
    var onFinish: ((CGRect?) -> Void)?

    private var selection: RegionSelection?
    private let dim = CAShapeLayer()
    private let halo = CAShapeLayer()
    private let edge = CAShapeLayer()
    private let hint = OverlayPill(text: "Drag around what you mean  ·  Esc to cancel", font: .systemFont(ofSize: 13, weight: .medium))
    private let sizeLabel = OverlayPill(text: "", font: .monospacedDigitSystemFont(ofSize: 11, weight: .medium))

    /// `hintArea` is the part of the display not under the menu bar or Dock.
    init(frame: CGRect, hintArea: CGRect) {
        super.init(frame: frame)
        wantsLayer = true

        dim.fillColor = NSColor.black.withAlphaComponent(0.42).cgColor
        dim.fillRule = .evenOdd
        halo.fillColor = nil
        halo.strokeColor = NSColor.white.withAlphaComponent(0.85).cgColor
        halo.lineWidth = 3.5
        edge.fillColor = nil
        edge.strokeColor = NSColor(srgbRed: 1, green: 0.12, blue: 0.12, alpha: 1).cgColor
        edge.lineWidth = 2
        [dim, halo, edge].forEach { layer?.addSublayer($0) }

        addSubview(hint)
        hint.setFrameOrigin(CGPoint(
            x: (hintArea.midX - hint.frame.width / 2).rounded(),
            y: (hintArea.maxY - hint.frame.height - 28).rounded()
        ))
        sizeLabel.isHidden = true
        addSubview(sizeLabel)
        redraw()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    /// The first click on a display that isn't key has to count as the start of a drag.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let scale = window?.backingScaleFactor else { return }
        [dim, halo, edge].forEach { $0.contentsScale = scale }
    }

    func hideHint() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            hint.animator().alphaValue = 0
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // Always active, because the app in front stays in front the whole time.
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate],
            owner: self
        ))
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }
    override func mouseEntered(with event: NSEvent) { NSCursor.crosshair.set() }
    override func mouseMoved(with event: NSEvent) { NSCursor.crosshair.set() }

    override func mouseDown(with event: NSEvent) {
        selection = RegionSelection(start: location(of: event), bounds: bounds)
        onDragStart?()
    }

    override func mouseDragged(with event: NSEvent) {
        selection?.current = location(of: event)
        redraw()
    }

    override func mouseUp(with event: NSEvent) {
        selection?.current = location(of: event)
        let finished = selection
        onFinish?(finished?.isDrag == true ? finished?.rect : nil)
    }

    override func rightMouseDown(with event: NSEvent) { onFinish?(nil) }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish?(nil) } else { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) { onFinish?(nil) }

    private func location(of event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    private func redraw() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let hole = selection.flatMap { $0.rect.isEmpty ? nil : $0.rect }
        let path = CGMutablePath()
        path.addRect(bounds)
        if let hole { path.addRect(hole) }
        dim.path = path

        // Just outside the box, the same way the mark lands on the screenshot.
        let outline = hole.map { CGPath(rect: $0.insetBy(dx: -1, dy: -1), transform: nil) }
        halo.path = outline
        edge.path = outline
        placeSizeLabel(for: hole)
    }

    private func placeSizeLabel(for hole: CGRect?) {
        guard let hole else {
            sizeLabel.isHidden = true
            return
        }
        sizeLabel.setText("\(Int(hole.width.rounded())) × \(Int(hole.height.rounded()))")
        let label = sizeLabel.frame.size
        let gap: CGFloat = 8
        // Under the box's bottom right corner, or tucked inside it near the edge of the display.
        let x = min(max(hole.maxX - label.width, bounds.minX + gap), bounds.maxX - label.width - gap)
        let below = hole.minY - label.height - gap
        let y = below >= bounds.minY + gap ? below : hole.minY + gap
        sizeLabel.setFrameOrigin(CGPoint(x: x.rounded(), y: y.rounded()))
        sizeLabel.isHidden = hole.width < 24 && hole.height < 24
    }
}

/// A small dark label that reads on any screen.
final class OverlayPill: NSView {
    private let label = NSTextField(labelWithString: "")
    private static let padding = CGSize(width: 12, height: 6)

    init(text: String, font: NSFont) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        layer?.borderWidth = 0.5
        layer?.cornerCurve = .continuous
        label.font = font
        label.textColor = .white
        label.alignment = .center
        addSubview(label)
        setText(text)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setText(_ text: String) {
        label.stringValue = text
        label.sizeToFit()
        let size = label.frame.size
        setFrameSize(CGSize(
            width: (size.width + Self.padding.width * 2).rounded(.up),
            height: (size.height + Self.padding.height * 2).rounded(.up)
        ))
        label.setFrameOrigin(CGPoint(x: Self.padding.width, y: Self.padding.height))
        layer?.cornerRadius = frame.height / 2
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
