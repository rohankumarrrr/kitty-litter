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
    /// The part of the screen the screenshot shows, in AppKit global points.
    public var screenshotArea: CGRect?
    /// What the cat could point at in the front window and the menu bar.
    public var elements: [ScreenElement]
    /// The app is on the privacy list, so nothing else was captured.
    public var isPrivate: Bool
    /// The name of a file or link dropped onto the cat, when that's what this holds instead of the screen.
    /// It goes wherever the screen may and nowhere else, since a file can be a copy of the screen.
    public var droppedName: String?

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
        screenshotArea: CGRect? = nil,
        elements: [ScreenElement] = [],
        isPrivate: Bool = false,
        droppedName: String? = nil
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
        self.screenshotArea = screenshotArea
        self.elements = elements
        self.isPrivate = isPrivate
        self.droppedName = droppedName
    }
}

/// A button, link, field or label on screen, read through Accessibility.
public struct ScreenElement: Sendable, Equatable {
    /// In plain words, such as "button".
    public var role: String
    public var label: String
    /// In AppKit global points.
    public var frame: CGRect

    public init(role: String, label: String, frame: CGRect) {
        self.role = role
        self.label = label
        self.frame = frame
    }
}

public struct CaptureOptions: Sendable {
    public var includeScreenshot: Bool
    public var includePageText: Bool
    /// What the cat could point at, for answers that say where something is.
    public var includeElements: Bool
    /// Screen area to mark on the screenshot, in AppKit global points: the origin is at
    /// the bottom left of the primary display.
    public var focusRegion: CGRect?

    public init(includeScreenshot: Bool = true, includePageText: Bool = true, includeElements: Bool = true, focusRegion: CGRect? = nil) {
        self.includeScreenshot = includeScreenshot
        self.includePageText = includePageText
        self.includeElements = includeElements
        self.focusRegion = focusRegion
    }
}

public protocol ScreenContextProviding: AnyObject, Sendable {
    /// Must be called before any cat window takes focus, and never captures the cat.
    func snapshot(_ options: CaptureOptions) async throws -> ScreenSnapshot
    /// Lets you drag out the part of the screen you mean, in AppKit global points. `nil` if you cancel.
    func pickRegion() async -> CGRect?
    /// Saves the screenshot for an agent to open, returning its path. Old ones get cleaned up.
    func saveScreenshot(of snapshot: ScreenSnapshot) throws -> String?
}
