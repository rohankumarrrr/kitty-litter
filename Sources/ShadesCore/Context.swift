import CoreGraphics
import Foundation

/// What the cat can see at one moment. Taken only when you ask for something.
public struct ScreenSnapshot: Sendable {
    public var capturedAt: Date
    public var appName: String?
    public var bundleID: String?
    public var windowTitle: String?
    public var url: URL?
    public var selectedText: String?
    public var pageText: String?
    public var screenshotJPEG: Data?
    /// The area you pointed at, in screenshot pixels, with the origin at the top left.
    public var focusRegion: CGRect?
    /// The app is on the privacy list, so nothing else was captured.
    public var isPrivate: Bool

    public init(
        capturedAt: Date = Date(),
        appName: String? = nil,
        bundleID: String? = nil,
        windowTitle: String? = nil,
        url: URL? = nil,
        selectedText: String? = nil,
        pageText: String? = nil,
        screenshotJPEG: Data? = nil,
        focusRegion: CGRect? = nil,
        isPrivate: Bool = false
    ) {
        self.capturedAt = capturedAt
        self.appName = appName
        self.bundleID = bundleID
        self.windowTitle = windowTitle
        self.url = url
        self.selectedText = selectedText
        self.pageText = pageText
        self.screenshotJPEG = screenshotJPEG
        self.focusRegion = focusRegion
        self.isPrivate = isPrivate
    }
}

public struct CaptureOptions: Sendable {
    public var includeScreenshot: Bool
    public var includePageText: Bool
    /// Screen area to mark on the screenshot, in global points.
    public var focusRegion: CGRect?

    public init(includeScreenshot: Bool = true, includePageText: Bool = true, focusRegion: CGRect? = nil) {
        self.includeScreenshot = includeScreenshot
        self.includePageText = includePageText
        self.focusRegion = focusRegion
    }
}

public protocol ScreenContextProviding: AnyObject, Sendable {
    /// Must be called before any cat window takes focus, and never captures the cat.
    func snapshot(_ options: CaptureOptions) async throws -> ScreenSnapshot
    /// Lets you drag out the part of the screen you mean. `nil` if you cancel.
    func pickRegion() async -> CGRect?
    /// Saves the screenshot for an agent to open, returning its path. Old ones get cleaned up.
    func saveScreenshot(of snapshot: ScreenSnapshot) throws -> String?
}
