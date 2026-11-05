import Foundation
import ShadesCore

/// Everything a snapshot reads from the system, kept apart so the privacy rules can be tested
/// by checking what never got called.
protocol ContextSources: Sendable {
    var hasScreenRecording: Bool { get }
    var hasAccessibility: Bool { get }
    func frontApp() -> FrontApp?
    func privateApps() -> [String]
    func focus(pid: pid_t) async -> FocusedContext
    func location(of browser: Browser, pid: pid_t) async -> BrowserLocation
    func page(of browser: Browser, pid: pid_t, location: BrowserLocation, wantsText: Bool) async -> PageRead
    func screenshot(_ request: ScreenCapture.Request) async -> ScreenCapture.Result?
}

struct LiveSources: ContextSources {
    /// How long each part may take when an app or system service has stalled.
    private static let focusLimit: TimeInterval = 0.4
    private static let locationLimit: TimeInterval = 0.4
    private static let accessibilityPageLimit: TimeInterval = 0.3
    private static let screenshotLimit: TimeInterval = 2

    var hasScreenRecording: Bool { Permissions.hasScreenRecording }
    var hasAccessibility: Bool { Permissions.hasAccessibility }

    func frontApp() -> FrontApp? { FrontApp.current() }

    func privateApps() -> [String] { Settings.load().privateApps }

    func focus(pid: pid_t) async -> FocusedContext {
        var focus = FocusedContext()
        if hasAccessibility {
            focus = await blocking(within: Self.focusLimit) { AccessibilityReader.focusedContext(pid: pid) } ?? focus
        }
        if focus.windowTitle == nil, hasScreenRecording {
            focus.windowTitle = FrontWindow.title(of: pid)
        }
        return focus
    }

    func location(of browser: Browser, pid: pid_t) async -> BrowserLocation {
        await blocking(within: Self.locationLimit) { BrowserReader.location(of: browser, pid: pid) }
            ?? BrowserLocation(isPrivateWindow: true, failure: .timedOut)
    }

    /// JavaScript first, as it leaves the browser untouched. Accessibility covers for it
    /// when it's turned off, and for scripting you haven't allowed.
    func page(of browser: Browser, pid: pid_t, location: BrowserLocation, wantsText: Bool) async -> PageRead {
        var failure = location.failure
        if failure == nil {
            let limit = BrowserReader.pageTimeout + 0.1
            let read = await blocking(within: limit) { BrowserReader.page(of: browser, pid: pid, wantsText: wantsText) }
            guard let read else { return PageRead(failure: .timedOut) }
            guard read.failure == .javaScriptOff else { return read }
            failure = read.failure
        }
        guard failure == .javaScriptOff || failure == .notAllowed || failure == .notAsked, hasAccessibility else {
            return PageRead(failure: failure)
        }
        var read = await blocking(within: Self.accessibilityPageLimit) {
            AccessibilityReader.page(pid: pid, wantsText: wantsText)
        } ?? PageRead()
        read.failure = failure
        return read
    }

    func screenshot(_ request: ScreenCapture.Request) async -> ScreenCapture.Result? {
        await waiting(within: Self.screenshotLimit) { try? await ScreenCapture.capture(request) }
    }
}
