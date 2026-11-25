import Foundation

public enum BrowserStatus: Sendable, Equatable {
    case notABrowser
    case ok
    case javaScriptOff
    case automationNotAsked
    case automationDenied
    case timedOut
}

public struct CaptureReport: Sendable, Equatable {
    public var screenRecording = false
    public var accessibility = false
    public var browser = BrowserStatus.notABrowser
    public var wasPrivate = false
    public var timings = Timings()

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
