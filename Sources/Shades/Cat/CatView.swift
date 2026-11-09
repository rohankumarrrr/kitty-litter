import AppKit

/// Draws the cat through a layer with no smoothing, and only answers on its visible pixels.
final class CatView: NSView {
    var pose = CatPose(frame: .sit)
    var onAppearanceChange: (() -> Void)?
    var onMouseDown: ((NSEvent) -> Void)?
    var onMouseDragged: ((NSEvent) -> Void)?
    var onMouseUp: ((NSEvent) -> Void)?
    var onRightMouseDown: ((NSEvent) -> Void)?
    /// VoiceOver's press and show menu, which do what a click and a right-click do.
    var onPress: (() -> Void)?
    var onShowMenu: (() -> Void)?
    var onDragEnter: (() -> Void)?
    /// Something was let go over the cat. Says whether it was taken.
    var onDrop: ((NSPasteboard) -> Bool)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.magnificationFilter = .nearest
        layer?.minificationFilter = .nearest
        layer?.contentsGravity = .resize
        layer?.actions = ["contents": NSNull()]
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(CatWords.catLabel)
        setAccessibilityHelp(CatWords.catHelp)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(_ image: CGImage) {
        layer?.contents = image
    }

    func isVisiblePixel(at point: NSPoint) -> Bool {
        guard bounds.contains(point) else { return false }
        let x = Int(point.x) / CatArt.scale
        let y = CatArt.grid - 1 - Int(point.y) / CatArt.scale
        return CatRenderer.isVisible(pose, x: x, y: y)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isVisiblePixel(at: convert(point, from: superview)) ? self : nil
    }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { false }
    override func viewDidChangeEffectiveAppearance() { onAppearanceChange?() }

    override func mouseDown(with event: NSEvent) { onMouseDown?(event) }
    override func mouseDragged(with event: NSEvent) { onMouseDragged?(event) }
    override func mouseUp(with event: NSEvent) { onMouseUp?(event) }
    override func rightMouseDown(with event: NSEvent) { onRightMouseDown?(event) }

    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }

    override func accessibilityPerformShowMenu() -> Bool {
        onShowMenu?()
        return true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragEnter?()
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDrop?(sender.draggingPasteboard) ?? false
    }
}
