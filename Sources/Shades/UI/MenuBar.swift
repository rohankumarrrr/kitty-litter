import AppKit
import ShadesCore

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
    var messagesSummary: (() -> String?)?
    var onSettings: (() -> Void)?
    var canPairPhone: (() -> Bool)?
    var onPairPhone: (() -> Void)?
    var isDoNotDisturb: (() -> Bool)?
    var onDoNotDisturb: (() -> Void)?
    var lockdownKittens: (() -> [Kitten])?
    var lockedDownKitten: (() -> String?)?
    var onLockdown: ((Kitten) -> Void)?
    var onLockdownNewThread: (() -> Void)?
    var onLockdownOff: (() -> Void)?
    var extras: [Extra] = []
    var held: [Shortcut] = []

    override init() {
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        item.button?.image = Self.icon()
        item.button?.toolTip = CatWords.appName
    }

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
        addAction(CatWords.kittensTitle) { [weak self] in self?.onKittens?() }.toolTip = "Or Shift-click the cat"
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
        addLockdown()
        menu.addItem(.separator())
        addAction("Settings…") { [weak self] in self?.onSettings?() }
        addAction("Quit \(CatWords.appName)") { NSApp.terminate(nil) }
    }

    private func addLockdown() {
        let kittens = lockdownKittens?() ?? []
        let on = lockedDownKitten?()
        guard !kittens.isEmpty || on != nil else { return }
        let pinned = kittens.first { $0.id == on }
        let row = NSMenuItem(title: pinned.map { CatWords.lockdownOn($0.name) } ?? CatWords.lockdown, action: nil, keyEquivalent: "")
        row.state = on == nil ? .off : .on
        let choices = NSMenu()
        for kitten in kittens {
            let choice = NSMenuItem(title: kitten.name, action: nil, keyEquivalent: "")
            choice.state = kitten.id == on ? .on : .off
            bind(choice) { [weak self] in self?.onLockdown?(kitten) }
            choices.addItem(choice)
        }
        if on != nil {
            if !kittens.isEmpty { choices.addItem(.separator()) }
            let fresh = NSMenuItem(title: CatWords.lockdownNewThread, action: nil, keyEquivalent: "")
            bind(fresh) { [weak self] in self?.onLockdownNewThread?() }
            choices.addItem(fresh)
        }
        if on != nil, pinned == nil {
            let off = NSMenuItem(title: CatWords.lockdownOff, action: nil, keyEquivalent: "")
            bind(off) { [weak self] in self?.onLockdownOff?() }
            choices.addItem(off)
        }
        row.submenu = choices
        menu.addItem(row)
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
        // Outside the repo: NSMenu runs an item's action before the menu has finished closing.
        let run = actions[sender.tag]
        DispatchQueue.main.async { run() }
    }

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
