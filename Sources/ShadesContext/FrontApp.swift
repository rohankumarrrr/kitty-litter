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
public enum FrontWindow {
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

    /// Whether no app's normal window is over any of this one. Floating windows don't count, since nothing at the
    /// normal level can go over them.
    public static func isOnTop(_ id: Int) -> Bool {
        let options: CGWindowListOption = [.optionOnScreenAboveWindow, .optionIncludingWindow]
        let above = CGWindowListCopyWindowInfo(options, CGWindowID(id)) as? [[String: Any]] ?? []
        return isOnTop(id, among: above) { NSRunningApplication(processIdentifier: $0).map { $0.activationPolicy != .prohibited } ?? false }
    }

    /// `windows` are the ones above it, and it. A tool with no app, such as one drawing a border around the window
    /// you're in, puts windows of its own over others, and those reach past the window they're for.
    static func isOnTop(_ id: Int, among windows: [[String: Any]], isApp: (pid_t) -> Bool) -> Bool {
        func number(_ window: [String: Any]) -> Int? { window[kCGWindowNumber as String] as? Int }
        func frame(_ window: [String: Any]) -> CGRect? {
            (window[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
        }
        guard let mine = windows.first(where: { number($0) == id }).flatMap(frame) else { return false }
        return !windows.contains { window in
            number(window) != id && isNormal(window) && frame(window).map { !$0.intersection(mine).isEmpty } == true
                && owner(window).map(isApp) == true
        }
    }
}
