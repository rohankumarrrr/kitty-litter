import AppKit
import ShadesCore

/// Notifications, in a channel's header: mute it, or say what it tells you on this Mac and on your phone. A menu opens
/// without making Shades the active app, the way Theme's does.
@MainActor
final class NotificationsMenu: NSObject {
    private var onPick: ((ChannelNotifications) -> Void)?

    func show(_ current: ChannelNotifications, phone: Bool, under anchor: NSView, onPick: @escaping (ChannelNotifications) -> Void) {
        self.onPick = onPick
        let menu = NSMenu()
        menu.autoenablesItems = false
        items(current, phone: phone).forEach(menu.addItem)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.isFlipped ? anchor.bounds.height : 0), in: anchor)
    }

    /// Each item carries what picking it makes the channel's notifications. Picking a level unmutes it, since that's
    /// asking to hear from it. The phone only shows once it's turned on.
    func items(_ current: ChannelNotifications, phone: Bool) -> [NSMenuItem] {
        var muted = current
        muted.muted.toggle()
        var items = [item(CatWords.mute, isOn: current.muted, picks: muted)]
        for device in NotifyDevice.allCases where device == .mac || phone {
            items += [.separator(), .sectionHeader(title: CatWords.notifyOn(device))]
            for level in NotifyLevel.allCases {
                var picked = current
                picked[device] = level
                picked.muted = false
                items.append(item(CatWords.notifyLevel(level), isOn: current[device] == level, picks: picked))
            }
        }
        return items
    }

    private func item(_ title: String, isOn: Bool, picks: ChannelNotifications) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(picked(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = picks
        item.state = isOn ? .on : .off
        return item
    }

    @objc private func picked(_ item: NSMenuItem) {
        guard let picks = item.representedObject as? ChannelNotifications else { return }
        onPick?(picks)
    }
}
