import AppKit
import ShadesCore

/// The menu bar item: how things are going, your threads, and the main actions.
@MainActor
final class MenuBar: NSObject, NSMenuDelegate {
    struct Extra {
        var title: String
        var action: () -> Void
    }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private var status = "Napping"
    private var threads: [AgentThread] = []
    private var actions: [() -> Void] = []

    var onAsk: (() -> Void)?
    var onFix: (() -> Void)?
    var onDashboard: (() -> Void)?
    var onSettings: (() -> Void)?
    var onOpenThread: ((String) -> Void)?
    /// Extra items, such as setting up permissions or demo mode's controls.
    var extras: [Extra] = []

    override init() {
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        item.button?.image = Self.icon()
        item.button?.toolTip = "Shades"
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

    func show(status: String, threads: [AgentThread], needsYou: Bool) {
        self.status = status
        self.threads = threads
        item.button?.contentTintColor = needsYou ? Ink.hex(CatGlint.attention(bright: true).color!) : nil
        item.button?.setAccessibilityLabel("Shades: \(status)")
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

    private func rebuild() {
        menu.removeAllItems()
        actions = []

        let header = NSMenuItem(title: status, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if !threads.isEmpty {
            menu.addItem(.separator())
            for thread in threads.prefix(6) {
                let row = NSMenuItem(title: thread.title, action: nil, keyEquivalent: "")
                let detail = [thread.projectTitle, CatWords.status(thread)].compactMap { $0 }.joined(separator: " · ")
                let title = NSMutableAttributedString(string: thread.title, attributes: [.font: NSFont.menuFont(ofSize: 13)])
                title.append(NSAttributedString(string: "\n\(detail)", attributes: [
                    .font: NSFont.menuFont(ofSize: 11),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]))
                row.attributedTitle = title
                bind(row) { [weak self] in self?.onOpenThread?(thread.id) }
                menu.addItem(row)
            }
        }

        menu.addItem(.separator())
        addAction("Ask...", shortcut: Shortcut.askLabel) { [weak self] in self?.onAsk?() }
        addAction("Fix what I'm looking at", shortcut: Shortcut.fixLabel) { [weak self] in self?.onFix?() }
        addAction("Dashboard") { [weak self] in self?.onDashboard?() }

        if !extras.isEmpty {
            menu.addItem(.separator())
            for extra in extras { addAction(extra.title, run: extra.action) }
        }

        menu.addItem(.separator())
        addAction("Settings...") { [weak self] in self?.onSettings?() }
        addAction("Quit Shades") { NSApp.terminate(nil) }
    }

    private func addAction(_ title: String, shortcut: String? = nil, run: @escaping () -> Void) {
        let row = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if let shortcut {
            let text = NSMutableAttributedString(string: title, attributes: [.font: NSFont.menuFont(ofSize: 13)])
            text.append(NSAttributedString(string: "   \(shortcut)", attributes: [
                .font: NSFont.menuFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
            row.attributedTitle = text
        }
        bind(row, run: run)
        menu.addItem(row)
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
