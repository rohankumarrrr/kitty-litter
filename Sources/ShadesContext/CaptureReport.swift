import Foundation

/// How reading the front browser went.
public enum BrowserStatus: Sendable, Equatable {
    /// The front app isn't a browser we can script, or nothing was read from it.
    case notABrowser
    case ok
    /// The URL came through, but JavaScript from Apple Events is turned off in the browser.
    /// Page text only comes through if the browser exposes it to Accessibility, which Chromium
    /// browsers don't unless VoiceOver is on. `takeJavaScriptTip()` has the fix.
    case javaScriptOff
    /// You haven't been asked yet. `Permissions.requestBrowserAutomation(bundleID:)` will ask.
    case automationNotAsked
    /// You said no. `Permissions.openSettings(.automation)` is where to change that.
    case automationDenied
    case timedOut
}

/// How the latest snapshot went. Holds nothing from the screen, so it's safe to log.
public struct CaptureReport: Sendable, Equatable {
    public var screenRecording = false
    public var accessibility = false
    public var browser = BrowserStatus.notABrowser
    /// Whether anything was left out because the front app or window is private.
    public var wasPrivate = false
    public var timings = Timings()

    /// In milliseconds. `nil` for anything that didn't run.
    public struct Timings: Sendable, Equatable {
        public var total: Double = 0
        public var focus: Double?
        public var browserLocation: Double?
        public var page: Double?
        public var screenshot: Double?
        public var screenshotList: Double?
        public var screenshotGrab: Double?
        public var screenshotEncode: Double?
        public var elements: Double?
    }

    public init() {}
}
