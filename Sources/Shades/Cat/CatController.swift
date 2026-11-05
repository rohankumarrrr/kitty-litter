import AppKit

/// Puts the brain on screen: one small window, moved at 10 ticks a second. The timer
/// sleeps through ticks where nothing would change, so an idle cat costs next to nothing.
@MainActor
final class CatController {
    private static let homeKey = "catHome"
    private static let dragSlop: CGFloat = 3
    private static let tick: TimeInterval = 0.1
    private static let margin: CGFloat = 16

    let panel = QuietPanel(shadow: false)
    let view = CatView(frame: NSRect(x: 0, y: 0, width: CatArt.points, height: CatArt.points))
    private let renderer = CatRenderer()
    private(set) var brain: CatBrain
    private(set) var home: CGPoint
    private var timer: Timer?
    private var arrival: (() -> Void)?
    private var shown: CatPose?
    private var shownTheme: CatTheme?
    private var mouseMonitors: [Any] = []
    /// Demo mode can hold one drawing still, to look at it closely.
    var heldPose: CatPose?

    private var dragStart: (mouse: NSPoint, origin: CGPoint)?
    private var dragging = false

    private var strokeX: CGFloat?
    private var strokeDirection: CGFloat = 0
    private var strokeTurns = 0
    private var strokeAt = Date.distantPast

    var onClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    var onStroke: (() -> Void)?
    /// The cat's window moved, so whatever hangs off it should follow.
    var onMove: (() -> Void)?

    init() {
        let saved = UserDefaults.standard.array(forKey: Self.homeKey) as? [Double]
        let start = saved.flatMap { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil } ?? Self.defaultHome()
        home = ScreenBounds.clamp(start, size: Self.size, to: Self.screens())
        brain = CatBrain(position: home)

        panel.contentView = view
        panel.setFrame(NSRect(origin: home, size: Self.size), display: false)
        panel.ignoresMouseEvents = true

        view.onAppearanceChange = { [weak self] in self?.apply() }
        view.onMouseDown = { [weak self] _ in self?.mouseDown() }
        view.onMouseDragged = { [weak self] _ in self?.mouseDragged() }
        view.onMouseUp = { [weak self] _ in self?.mouseUp() }
        view.onRightMouseDown = { [weak self] event in self?.onRightClick?(event) }

        // These events don't need any permission, and only wake us while the mouse moves.
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseMoved() }
        }) { mouseMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.mouseMoved() }
            return event
        }) { mouseMonitors.append(local) }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
    }

    func start() {
        panel.orderFrontRegardless()
        apply()
        schedule()
    }

    /// Where the cat is, or where it's headed. Anything anchored to it can settle there straight away.
    var frame: NSRect { NSRect(origin: brain.position, size: Self.size) }
    var destinationFrame: NSRect { NSRect(origin: brain.target, size: Self.size) }

    /// The usable part of the screen the cat is on.
    var visibleFrame: NSRect {
        let center = NSPoint(x: destinationFrame.midX, y: destinationFrame.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
        return screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    // MARK: - Things it does

    func run(to origin: CGPoint, arrived: (() -> Void)? = nil) {
        let target = ScreenBounds.clamp(origin, size: Self.size, to: Self.screens())
        arrival = arrived
        if target == brain.position {
            brain.move(to: target)
            finishArrival()
        } else {
            brain.go(to: target)
        }
        poke()
    }

    func goHome(arrived: (() -> Void)? = nil) {
        run(to: home, arrived: arrived)
    }

    func pet() -> String {
        let word = brain.pet(roll: Int.random(in: 0..<CatBrain.pettingWords.count))
        poke()
        return word
    }

    func wake() {
        brain.wake()
        poke()
    }

    func setStatus(_ status: CatStatus) {
        guard brain.status != status else { return }
        brain.setStatus(status)
        poke()
    }

    func setAgentsBusy(_ busy: Bool) {
        guard brain.agentsBusy != busy else { return }
        brain.setAgentsBusy(busy)
        poke()
    }

    func setLevel(_ level: Float) {
        brain.level = level
    }

    func celebrate() {
        brain.celebrate()
        poke()
    }

    func hold(_ pose: CatPose?) {
        heldPose = pose
        poke()
    }

    // MARK: - Ticking

    /// Something changed from outside, so draw now and work out the next wake-up again.
    private func poke() {
        apply()
        schedule()
    }

    private func schedule() {
        timer?.invalidate()
        let ticks = brain.ticksUntilChange()
        let interval = Self.tick * Double(ticks)
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire(ticks) }
        }
        timer.tolerance = interval * 0.1
        // Common modes, so the cat keeps going while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func fire(_ ticks: Int) {
        var arrived = false
        for _ in 0..<ticks where brain.tick() { arrived = true }
        apply()
        if arrived { finishArrival() }
        schedule()
    }

    private func finishArrival() {
        let done = arrival
        arrival = nil
        done?()
    }

    private func apply() {
        let theme: CatTheme = view.effectiveAppearance.isDark ? .dark : .light
        let pose = heldPose ?? brain.pose
        if pose != shown || theme != shownTheme {
            shown = pose
            shownTheme = theme
            view.pose = pose
            view.show(renderer.image(for: pose, theme: theme))
            updateClickThrough()
        }
        let origin = CGPoint(x: brain.position.x.rounded(), y: brain.position.y.rounded())
        if !dragging && panel.frame.origin != origin {
            panel.setFrameOrigin(origin)
            updateClickThrough()
            onMove?()
        }
    }

    // MARK: - The mouse

    /// The window only takes clicks while the pointer is on one of the cat's pixels, so
    /// the empty corners of its square really are empty.
    private func updateClickThrough() {
        guard !dragging else { return }
        let mouse = NSEvent.mouseLocation
        let inView = NSPoint(x: mouse.x - panel.frame.minX, y: mouse.y - panel.frame.minY)
        let over = view.isVisiblePixel(at: inView)
        if panel.ignoresMouseEvents == over { panel.ignoresMouseEvents = !over }
    }

    private func mouseMoved() {
        guard !dragging else { return }
        let near = panel.frame.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation)
        if near || !panel.ignoresMouseEvents { updateClickThrough() }
        if near { stroke() } else { strokeX = nil }
    }

    /// Moving the pointer back and forth over the cat counts as petting it.
    private func stroke() {
        let x = NSEvent.mouseLocation.x
        defer { strokeX = x }
        guard let last = strokeX, x != last else { return }
        let direction: CGFloat = x > last ? 1 : -1
        if direction != strokeDirection {
            strokeDirection = direction
            strokeTurns = Date().timeIntervalSince(strokeAt) < 0.6 ? strokeTurns + 1 : 1
            strokeAt = Date()
            if strokeTurns >= 4 {
                strokeTurns = 0
                onStroke?()
            }
        }
    }

    private func mouseDown() {
        dragStart = (NSEvent.mouseLocation, CGPoint(x: panel.frame.minX, y: panel.frame.minY))
        dragging = false
    }

    private func mouseDragged() {
        guard let start = dragStart else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - start.mouse.x
        let dy = mouse.y - start.mouse.y
        if !dragging, hypot(dx, dy) < Self.dragSlop { return }
        if !dragging {
            dragging = true
            brain.pickUp()
            apply()
            schedule()
        }
        let origin = CGPoint(x: start.origin.x + dx, y: start.origin.y + dy)
        panel.setFrameOrigin(origin)
        brain.move(to: origin)
        onMove?()
    }

    private func mouseUp() {
        defer {
            dragStart = nil
            dragging = false
            updateClickThrough()
        }
        guard dragging else {
            onClick?()
            return
        }
        let origin = ScreenBounds.clamp(panel.frame.origin, size: Self.size, to: Self.screens())
        let settled = CGPoint(x: origin.x.rounded(), y: origin.y.rounded())
        dragging = false
        brain.putDown(at: settled)
        home = settled
        UserDefaults.standard.set([Double(settled.x), Double(settled.y)], forKey: Self.homeKey)
        poke()
        onMove?()
        // Picked up on the way somewhere, so wherever it landed will have to do.
        finishArrival()
    }

    private func screensChanged() {
        home = ScreenBounds.clamp(home, size: Self.size, to: Self.screens())
        if brain.state != .run {
            brain.move(to: ScreenBounds.clamp(brain.position, size: Self.size, to: Self.screens()))
            poke()
        }
    }

    // MARK: - Screens

    private static let size = CGSize(width: CatArt.points, height: CatArt.points)

    private static func screens() -> [CGRect] {
        NSScreen.screens.map(\.visibleFrame)
    }

    private static func defaultHome() -> CGPoint {
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return CGPoint(x: visible.maxX - size.width - margin, y: visible.minY + margin)
    }
}
