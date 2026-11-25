import AppKit
import CoreServices
import UniformTypeIdentifiers

// Outside the repo: a file picker makes the app active, and a menu doesn't.
@MainActor
final class RecentFiles: NSObject {
    nonisolated static let shown = 12
    private var onPick: ((URL) -> Void)?

    func show(_ files: [URL], under anchor: NSView, onPick: @escaping (URL) -> Void) {
        self.onPick = onPick
        let menu = NSMenu()
        menu.autoenablesItems = false
        items(files).forEach(menu.addItem)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.isFlipped ? anchor.bounds.height : 0), in: anchor)
    }

    func items(_ files: [URL]) -> [NSMenuItem] {
        var items = files.prefix(Self.shown).map { file in
            let item = NSMenuItem(title: file.lastPathComponent, action: #selector(picked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = file
            item.toolTip = (file.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
            let icon = NSWorkspace.shared.icon(for: UTType(filenameExtension: file.pathExtension) ?? .data)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            return item
        }
        if items.isEmpty { items.append(note(CatWords.noRecentFiles)) }
        return items + [.separator(), note(CatWords.dropAFile)]
    }

    private func note(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func picked(_ item: NSMenuItem) {
        guard let file = item.representedObject as? URL else { return }
        onPick?(file)
    }

    nonisolated static func find(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        let text = #"(kMDItemContentTypeTree == "public.image" || kMDItemContentTypeTree == "com.adobe.pdf") && kMDItemLastUsedDate >= $time.today(-30)"#
        guard let query = MDQueryCreate(kCFAllocatorDefault, text as CFString, nil, nil) else { return [] }
        MDQuerySetSearchScope(query, [home.path] as CFArray, 0)
        MDQuerySetMaxCount(query, 500)
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return [] }
        var found: [(url: URL, used: Date)] = []
        for index in 0..<MDQueryGetResultCount(query) {
            guard let raw = MDQueryGetResultAtIndex(query, index) else { continue }
            let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
            guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String,
                  let used = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
            else { continue }
            found.append((URL(fileURLWithPath: path), used))
        }
        return kept(found, home: home)
    }

    nonisolated static func kept(_ found: [(url: URL, used: Date)], home: URL) -> [URL] {
        let left = ["Library", ".t3"].map { home.appendingPathComponent($0).path + "/" }
        return found
            .filter { file in
                !file.url.pathComponents.contains { $0.hasPrefix(".") && $0 != "." } && !left.contains { file.url.path.hasPrefix($0) }
            }
            .sorted { $0.used > $1.used }
            .prefix(shown)
            .map(\.url)
    }
}
