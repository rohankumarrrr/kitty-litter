import AppKit

/// The app you're using right now.
struct FrontApp: Equatable, Sendable {
    var pid: pid_t
    var bundleID: String?
    var name: String?

    init(pid: pid_t, bundleID: String?, name: String?) {
        self.pid = pid
        self.bundleID = bundleID
        self.name = name
    }

    private init(_ app: NSRunningApplication) {
        self.init(pid: app.processIdentifier, bundleID: app.bundleIdentifier, name: app.localizedName)
    }

    /// If Shades itself is in front, what you're looking at is whatever sits behind it.
    static func current() -> FrontApp? {
        let me = ProcessInfo.processInfo.processIdentifier
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != me {
            return FrontApp(app)
        }
        guard let pid = FrontWindow.topOwner(excluding: me),
              let app = NSRunningApplication(processIdentifier: pid)
        else { return nil }
        return FrontApp(app)
    }
}

/// The window list needs no permissions for this, and it's the only place with the stacking order.
enum FrontWindow {
    private static func windows() -> [[String: Any]] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        return CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
    }

    private static func isNormal(_ window: [String: Any]) -> Bool {
        window[kCGWindowLayer as String] as? Int == 0
    }

    private static func owner(_ window: [String: Any]) -> pid_t? {
        (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
    }

    /// In Quartz coordinates.
    static func bounds(of pid: pid_t) -> CGRect? {
        let window = windows().first { isNormal($0) && owner($0) == pid }
        guard let box = window?[kCGWindowBounds as String] else { return nil }
        return CGRect(dictionaryRepresentation: box as! CFDictionary)
    }

    /// Only available with Screen Recording. Useful when Accessibility is off.
    static func title(of pid: pid_t) -> String? {
        let window = windows().first { isNormal($0) && owner($0) == pid }
        return window?[kCGWindowName as String] as? String
    }

    static func topOwner(excluding pid: pid_t) -> pid_t? {
        windows().first { isNormal($0) && owner($0) != pid }.flatMap(owner)
    }
}
