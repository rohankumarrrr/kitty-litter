import CoreGraphics
import Foundation

public struct ScreenSnapshot: Sendable {
    public var capturedAt: Date
    public var appName: String?
    public var bundleID: String?
    public var windowTitle: String?
    public var url: URL?
    public var selectedText: String?
    public var pageText: String?
    public var screenshotJPEG: Data?
    public var focusRegion: CGRect?
    public var screenshotArea: CGRect?
    public var elements: [ScreenElement]
    public var isPrivate: Bool
    public var droppedNames: [String]
    public var pictures: [AgentAttachment]

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
        droppedNames: [String] = [],
        pictures: [AgentAttachment] = []
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
        self.droppedNames = droppedNames
        self.pictures = pictures
    }

    public var isDropped: Bool { !droppedNames.isEmpty }
}

public struct ScreenElement: Sendable, Equatable {
    public var role: String
    public var label: String
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
    public var includeElements: Bool
    public var focusRegion: CGRect?

    public init(includeScreenshot: Bool = true, includePageText: Bool = true, includeElements: Bool = true, focusRegion: CGRect? = nil) {
        self.includeScreenshot = includeScreenshot
        self.includePageText = includePageText
        self.includeElements = includeElements
        self.focusRegion = focusRegion
    }
}

public protocol ScreenContextProviding: AnyObject, Sendable {
    func snapshot(_ options: CaptureOptions) async throws -> ScreenSnapshot
    func pickRegion() async -> CGRect?
    func saveScreenshot(of snapshot: ScreenSnapshot) throws -> String?
}
