import AppKit
import ShadesCore

/// The menu bar item: how things are going, and the main actions. What your agents are saying is in Messages.
@MainActor
final class MenuBar: NSObject, NSMenuDelegate {
    struct Extra {
        var title: String
        var action: () -> Void
    }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private var status = "Napping"
    private var actions: [() -> Void] = []

    var onAsk: (() -> Void)?
    var onFix: (() -> Void)?
    var onKittens: (() -> Void)?
    var onMessages: (() -> Void)?
    /// What goes next to Messages, read each time the menu opens.
    var messagesSummary: (() -> String?)?
    var onSettings: (() -> Void)?
    /// Whether Messages on your phone is on, so there's a phone to pair.
    var canPairPhone: (() -> Bool)?
    var onPairPhone: (() -> Void)?
    var isDoNotDisturb: (() -> Bool)?
    var onDoNotDisturb: (() -> Void)?
    /// Extra items, such as setting up permissions or demo mode's controls.
    var extras: [Extra] = []
    /// The shortcuts the app holds, which are the only ones the menu shows.
    var held: [Shortcut] = []

    override init() {
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        item.button?.image = Self.icon()
        item.button?.toolTip = CatWords.appName
    }

    /// The top-right corner of the menu bar icon, for hanging things from.
    var corner: NSPoint {
        guard let frame = item.button?.window?.frame else {
            let visible = NSScreen.main?.visibleFrame ?? .zero
            return NSPoint(x: visible.maxX - 8, y: visible.maxY - 4)
        }
        let visible = NSScreen.screens.first { $0.frame.intersects(frame) }?.visibleFrame ?? frame
        return NSPoint(x: min(frame.maxX, visible.maxX - 8), y: frame.minY - 4)
    }

    func show(status: String, needsYou: Bool) {
        self.status = status
        item.button?.contentTintColor = needsYou ? Ink.hex(CatGlint.attention(bright: true).color!) : nil
        item.button?.setAccessibilityLabel("\(CatWords.appName): \(status)")
    }

    func popUpMenu(at point: NSPoint, in view: NSView) {
        rebuild()
        menu.popUp(positioning: nil, at: point, in: view)
    }

    func closeMenu() {
        menu.cancelTracking()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild()
    }

    /// Each item as the menu would show it now, for the demo to print and press.
    var shownItems: [NSMenuItem] {
        rebuild()
        return menu.items
    }

    private func rebuild() {
        menu.removeAllItems()
        actions = []

        let header = NSMenuItem(title: status, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        menu.addItem(.separator())
        let messages = addAction(CatWords.appName, shortcut: .messages) { [weak self] in self?.onMessages?() }
        messages.badge = messagesSummary?().map { NSMenuItemBadge(string: $0) }
        addAction("Ask…", shortcut: .ask) { [weak self] in self?.onAsk?() }
        addAction("Fix What I'm Looking At", shortcut: .fix) { [weak self] in self?.onFix?() }
        addAction("Kittens") { [weak self] in self?.onKittens?() }.toolTip = "Or Shift-click the cat"
        if canPairPhone?() == true { addAction(CatWords.pairItem) { [weak self] in self?.onPairPhone?() } }

        if !extras.isEmpty {
            menu.addItem(.separator())
            for extra in extras { addAction(extra.title, run: extra.action) }
        }

        menu.addItem(.separator())
        let quiet = NSMenuItem(title: CatWords.doNotDisturb, action: nil, keyEquivalent: "")
        quiet.state = isDoNotDisturb?() == true ? .on : .off
        bind(quiet) { [weak self] in self?.onDoNotDisturb?() }
        menu.addItem(quiet)
        addAction("Settings…") { [weak self] in self?.onSettings?() }
        addAction("Quit \(CatWords.appName)") { NSApp.terminate(nil) }
    }

    @discardableResult
    private func addAction(_ title: String, shortcut: Shortcut? = nil, run: @escaping () -> Void) -> NSMenuItem {
        let row = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if let shortcut, held.contains(shortcut) {
            row.keyEquivalent = shortcut.key
            row.keyEquivalentModifierMask = shortcut.keyModifiers
        }
        bind(row, run: run)
        menu.addItem(row)
        return row
    }

    private func bind(_ row: NSMenuItem, run: @escaping () -> Void) {
        row.target = self
        row.action = #selector(runItem(_:))
        row.tag = actions.count
        row.isEnabled = true
        actions.append(run)
    }

    @objc private func runItem(_ sender: NSMenuItem) {
        guard actions.indices.contains(sender.tag) else { return }
        // Let the menu finish closing before anything looks at the screen.
        let run = actions[sender.tag]
        DispatchQueue.main.async { run() }
    }

    /// The cat's face from the sitting frame, as a template the menu bar can tint.
    private static func icon() -> NSImage {
        let scale = 2
        let rows = Array(CatFrame.sit.rows[1...9])
        let height = rows.count * scale
        let width = 12 * scale
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4, bitsPerPixel: 32
        )!
        let pixels = rep.bitmapData!
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() where (2..<14).contains(x) {
                // Outline and lenses are solid. Fur is the empty middle.
                guard ch == "k" || ch == "s" else { continue }
                for dx in 0..<scale {
                    for dy in 0..<scale {
                        pixels[(y * scale + dy) * width * 4 + ((x - 2) * scale + dx) * 4 + 3] = 255
                    }
                }
            }
        }
        let image = NSImage(size: NSSize(width: width / scale, height: height / scale))
        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }
}
