import AppKit
import ShadesCore

final class SidebarCat: QuietView {
    static let poseKey = "pose"
    private static let frameSeconds: CFTimeInterval = 0.2
    private static let framesInACycle = 4

    private let status: KittenStatus
    private let jacket: UInt32?

    init(status: KittenStatus, jacket: UInt32?) {
        self.status = status
        self.jacket = jacket
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var moves: Bool { !Motion.isReduced && status.state.dotColor != nil }

    // Outside the repo: AppKit's drawn copy of a layer smooths its pixel art, so a picture has the cat draw itself.
    static var drawsForAPicture = false

    override var wantsUpdateLayer: Bool { !Self.drawsForAPicture }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateLayer() {
        guard let layer else { return }
        let frames = (0..<(moves ? Self.framesInACycle : 1)).map { CatStamp.image(status.pose(tick: $0), jacket: jacket, on: self) }
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .nearest
        layer.contents = frames[0]
        layer.removeAnimation(forKey: Self.poseKey)
        guard frames.count > 1 else { return }
        let running = CAKeyframeAnimation(keyPath: "contents")
        running.values = frames
        running.keyTimes = (0...frames.count).map { NSNumber(value: Double($0) / Double(frames.count)) }
        running.calculationMode = .discrete
        running.duration = Double(frames.count) * Self.frameSeconds
        running.repeatCount = .infinity
        running.isRemovedOnCompletion = false
        let now = CACurrentMediaTime()
        running.beginTime = now - now.truncatingRemainder(dividingBy: running.duration)
        layer.add(running, forKey: Self.poseKey)
    }

    override func draw(_ dirtyRect: NSRect) {
        let tick = moves ? Int(CACurrentMediaTime() / Self.frameSeconds) : 0
        CatStamp.draw(status.pose(tick: tick), jacket: jacket, in: bounds, on: self)
    }
}

final class SidebarDot: QuietView {
    private let color: NSColor
    var ground: NSColor {
        didSet { if ground != oldValue { needsDisplay = true } }
    }

    init(color: NSColor, ground: NSColor) {
        self.color = color
        self.ground = ground
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        ground.setFill()
        NSBezierPath(ovalIn: bounds).fill()
        color.setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2)).fill()
    }
}
