import AppKit

// Outside the repo: the font panel makes the app active, and a menu doesn't.
@MainActor
final class FontMenu: NSObject {
    private var onPick: ((String?) -> Void)?

    func show(current: String?, under anchor: NSView, onPick: @escaping (String?) -> Void) {
        self.onPick = onPick
        let menu = NSMenu()
        menu.autoenablesItems = false
        items(current: current, families: NSFontManager.shared.availableFontFamilies).forEach(menu.addItem)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.isFlipped ? anchor.bounds.height : 0), in: anchor)
    }

    func items(current: String?, families: [String]) -> [NSMenuItem] {
        let faces = MessagesInk.systemFaces.map(\.name)
        var items = faces.enumerated().map { index, name in
            let picks = index == 0 ? nil : name
            return item(name, picks: picks, isOn: current == picks)
        }
        if let current, !faces.contains(current), !families.contains(current) {
            let missing = item(current, picks: current, isOn: true)
            missing.isEnabled = false
            items.append(missing)
        }
        items.append(.separator())
        let submenu = NSMenu(title: CatWords.allFonts)
        submenu.autoenablesItems = false
        // Outside the repo: macOS keeps font families whose names start with a dot for itself.
        let shown = families.filter { !$0.hasPrefix(".") }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        shown.forEach { submenu.addItem(item($0, picks: $0, isOn: current == $0)) }
        let all = NSMenuItem(title: CatWords.allFonts, action: nil, keyEquivalent: "")
        all.submenu = submenu
        all.state = current.map(shown.contains) == true ? .on : .off
        items.append(all)
        return items
    }

    private func item(_ name: String, picks: String?, isOn: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: name, action: #selector(picked(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = picks
        item.state = isOn ? .on : .off
        item.attributedTitle = NSAttributedString(string: name, attributes: [.font: MessagesInk.font(ofSize: MessagesInk.body, family: picks)])
        return item
    }

    @objc private func picked(_ item: NSMenuItem) {
        onPick?(item.representedObject as? String)
    }
}
