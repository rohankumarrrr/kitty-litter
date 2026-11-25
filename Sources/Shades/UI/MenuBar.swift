import AppKit
import ShadesCore

@MainActor
final class MenuBar: NSObject, NSMenuDelegate {
    struct Extra {
        var title: String
        var action: () -> Void
    }

    let item = Offstage.isOn ? nil : NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private var status = "Napping"
    var refreshesOnOpen: [NSMenu: () -> Void] = [:]

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
        item?.menu = menu
        item?.button?.image = Self.icon()
        item?.button?.toolTip = CatWords.appName
    }

    var corner: NSPoint {
        guard let frame = item?.button?.window?.frame else {
            let visible = NSScreen.main?.visibleFrame ?? .zero
            return NSPoint(x: visible.maxX - 8, y: visible.maxY - 4)
        }
        let visible = NSScreen.screens.first { $0.frame.intersects(frame) }?.visibleFrame ?? frame
        return NSPoint(x: min(frame.maxX, visible.maxX - 8), y: frame.minY - 4)
    }

    func show(status: String, needsYou: Bool) {
        self.status = status
        item?.button?.contentTintColor = needsYou ? Ink.hex(CatGlint.attention(bright: true).color!) : nil
        item?.button?.setAccessibilityLabel("\(CatWords.appName): \(status)")
    }

    func popUpMenu(at point: NSPoint, in view: NSView) {
        rebuild()
        menu.popUp(positioning: nil, at: point, in: view)
    }

    func closeMenu() {
        menu.cancelTracking()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === self.menu { rebuild() }
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshesOnOpen[menu]?()
    }

    var shownItems: [NSMenuItem] {
        rebuild()
        return menu.items
    }

    private func rebuild() {
        menu.removeAllItems()

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
        let lockdown = NSMenuItem(title: CatWords.lockdown, action: nil, keyEquivalent: "")
        lockdown.submenu = NSMenu()
        if showLockdown(on: lockdown) { menu.addItem(lockdown) }
        menu.addItem(.separator())
        addAction("Settings…") { [weak self] in self?.onSettings?() }
        addAction("Quit \(CatWords.appName)") { NSApp.terminate(nil) }
    }

    func showLockdown(on row: NSMenuItem) -> Bool {
        let kittens = lockdownKittens?() ?? []
        let on = lockedDownKitten?()
        row.title = kittens.first { $0.id == on }.map { CatWords.lockdownOn($0.name) } ?? CatWords.lockdown
        row.state = on == nil ? .off : .on
        if let choices = row.submenu { fill(choices, lockdownOf: kittens, on: on) }
        return !kittens.isEmpty || on != nil
    }

    private func fill(_ choices: NSMenu, lockdownOf kittens: [Kitten], on: String?) {
        choices.removeAllItems()
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
        if on != nil, !kittens.contains(where: { $0.id == on }) {
            let off = NSMenuItem(title: CatWords.lockdownOff, action: nil, keyEquivalent: "")
            bind(off) { [weak self] in self?.onLockdownOff?() }
            choices.addItem(off)
        }
    }

    @discardableResult
    func addAction(_ title: String, shortcut: Shortcut? = nil, to target: NSMenu? = nil, run: @escaping () -> Void) -> NSMenuItem {
        let row = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if let shortcut, held.contains(shortcut) {
            row.keyEquivalent = shortcut.key
            row.keyEquivalentModifierMask = shortcut.keyModifiers
        }
        bind(row, run: run)
        (target ?? menu).addItem(row)
        return row
    }

    private func bind(_ row: NSMenuItem, run: @escaping () -> Void) {
        row.target = self
        row.action = #selector(runItem(_:))
        row.representedObject = MenuAction(run: run)
        row.isEnabled = true
    }

    @objc private func runItem(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? MenuAction else { return }
        // Outside the repo: NSMenu runs an item's action before the menu has finished closing.
        DispatchQueue.main.async { action.run() }
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

private final class MenuAction: NSObject {
    let run: () -> Void

    init(run: @escaping () -> Void) {
        self.run = run
    }
}
