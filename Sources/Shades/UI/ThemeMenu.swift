import AppKit
import ShadesCore

/// Theme, at the bottom of Messages' sidebar: Shades' own colours, and the themes T3 Code, Cursor, VS Code and iTerm2
/// already have. A menu opens without making Shades the active app, the way the cat's own menu does, where a file
/// picker wouldn't, so any other theme file is dropped onto Messages instead.
@MainActor
final class ThemeMenu: NSObject {
    private var onPick: ((AppController.ThemeChoice) -> Void)?

    func show(_ found: [ColorTheme.Found], current: ColorTheme?, under anchor: NSView, onPick: @escaping (AppController.ThemeChoice) -> Void) {
        self.onPick = onPick
        let menu = NSMenu()
        menu.autoenablesItems = false
        items(found, current: current).forEach(menu.addItem)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.isFlipped ? 0 : anchor.bounds.height), in: anchor)
    }

    /// Shades' own first, then a submenu for each app, so a Mac with dozens of themes still has a short menu.
    func items(_ found: [ColorTheme.Found], current: ColorTheme?) -> [NSMenuItem] {
        var items = [item(CatWords.plainTheme, file: nil, isOn: current == nil)]
        // One you dropped, which isn't anywhere the menu looks.
        if let current, !found.contains(where: { $0.theme == current }) {
            let item = item(current.name, file: nil, isOn: true)
            item.isEnabled = false
            items.append(item)
        }
        items.append(.separator())
        var apps: [String] = []
        for theme in found where !apps.contains(theme.app) { apps.append(theme.app) }
        for app in apps {
            let themes = found.filter { $0.app == app }.sorted { $0.theme.name.localizedStandardCompare($1.theme.name) == .orderedAscending }
            let submenu = NSMenu(title: app)
            submenu.autoenablesItems = false
            themes.forEach { submenu.addItem(item($0.theme.name, file: $0.file, isOn: $0.theme == current)) }
            let row = NSMenuItem(title: app, action: nil, keyEquivalent: "")
            row.submenu = submenu
            row.state = themes.contains { $0.theme == current } ? .on : .off
            items.append(row)
        }
        if found.isEmpty { items.append(note(CatWords.noThemesFound)) }
        items += [.separator(), note(CatWords.dropATheme)]
        return items
    }

    private func item(_ title: String, file: URL?, isOn: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(picked(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = file
        item.state = isOn ? .on : .off
        return item
    }

    private func note(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func picked(_ item: NSMenuItem) {
        onPick?((item.representedObject as? URL).map(AppController.ThemeChoice.file) ?? .plain)
    }
}
