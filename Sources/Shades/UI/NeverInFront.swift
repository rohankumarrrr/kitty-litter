import AppKit

@MainActor
enum NeverInFront {
    private(set) static var isKept = false
    private(set) static var timesMadeActive = 0
    private(set) static var secondsActive: Double = 0
    private static var lastOther: NSRunningApplication?
    private static var madeActiveAt: DispatchTime?

    static func keep(_ app: NSApplication) {
        isKept = true
        app.setActivationPolicy(.prohibited)
        NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: app, queue: .main) { _ in
            MainActor.assumeIsolated { _ = app.setActivationPolicy(.accessory) }
        }
        lastOther = other(NSWorkspace.shared.frontmostApplication)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { notification in
            let activated = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                if let other = other(activated) { lastOther = other }
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: app, queue: .main) { _ in
            MainActor.assumeIsolated {
                timesMadeActive += 1
                madeActiveAt = .now()
                handBack()
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: app, queue: .main) { _ in
            MainActor.assumeIsolated {
                guard let madeActiveAt else { return }
                secondsActive += Double(DispatchTime.now().uptimeNanoseconds - madeActiveAt.uptimeNanoseconds) / 1_000_000_000
                self.madeActiveAt = nil
            }
        }
    }

    private static func other(_ app: NSRunningApplication?) -> NSRunningApplication? {
        guard let app, app.processIdentifier != NSRunningApplication.current.processIdentifier, !app.isTerminated else { return nil }
        return app
    }

    private static func handBack() {
        guard let lastOther = other(lastOther) else { return NSApp.deactivate() }
        NSApp.yieldActivation(to: lastOther)
        _ = lastOther.activate(from: .current, options: [])
    }
}
