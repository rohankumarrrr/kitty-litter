import AppKit
import ScreenCaptureKit

/// One display as a capped, optionally marked JPEG.
public enum ScreenCapture {
    public struct Request: Sendable {
        /// The area to mark, in AppKit global points. Decides which display gets captured.
        public var focusRegion: CGRect?
        /// Otherwise the display holding this app's front window gets captured.
        public var frontmostPID: pid_t?
        /// Kept out of the picture even when they're only behind the front window.
        public var hiddenBundleIDs: [String]
        /// Captures these windows alone, so a probe can test against a window of its own without
        /// taking anything else from your screen. The picture only covers the display if one of
        /// them does, as ScreenCaptureKit frames it to the windows.
        public var onlyWindows: [CGWindowID]?

        public init(
            focusRegion: CGRect? = nil,
            frontmostPID: pid_t? = nil,
            hiddenBundleIDs: [String] = [],
            onlyWindows: [CGWindowID]? = nil
        ) {
            self.focusRegion = focusRegion
            self.frontmostPID = frontmostPID
            self.hiddenBundleIDs = hiddenBundleIDs
            self.onlyWindows = onlyWindows
        }
    }

    public struct Result: Sendable {
        public var jpeg: Data
        public var pixelSize: CGSize
        /// In screenshot pixels, with the origin at the top left.
        public var focusRegion: CGRect?
        /// The part of the screen it shows, in AppKit global points.
        public var area: CGRect
        public var listSeconds: Double
        public var grabSeconds: Double
        public var encodeSeconds: Double
    }

    public enum Failure: Error {
        case noDisplay, encodingFailed
    }

    /// Never call this without Screen Recording, as ScreenCaptureKit would prompt for it.
    public static func capture(_ request: Request) async throws -> Result {
        let clock = ContinuousClock()
        let started = clock.now

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let displays = content.displays
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height

        // Everything from here on is in Quartz coordinates, like ScreenCaptureKit itself.
        let focus = request.focusRegion.map { ScreenGeometry.flipped($0, primaryHeight: primaryHeight) }
        let mouse = ScreenGeometry.flipped(
            CGRect(origin: NSEvent.mouseLocation, size: .zero),
            primaryHeight: primaryHeight
        ).origin
        guard let index = ScreenGeometry.displayToCapture(
            focusRegion: focus,
            frontWindow: request.frontmostPID.flatMap(FrontWindow.bounds(of:)),
            mouse: mouse,
            among: displays.map(\.frame)
        ) else { throw Failure.noDisplay }
        let display = displays[index]

        let filter = contentFilter(for: display, in: content, request: request)
        let configuration = SCStreamConfiguration()
        let size = ScreenGeometry.cappedPixelSize(
            points: display.frame.size,
            scale: CGFloat(filter.pointPixelScale),
            longSide: ScreenshotImage.longSide
        )
        configuration.width = Int(size.width)
        configuration.height = Int(size.height)
        configuration.showsCursor = false
        let listed = clock.now

        var image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        let grabbed = clock.now

        var region: CGRect?
        if let focus {
            let imageSize = CGSize(width: image.width, height: image.height)
            region = ScreenGeometry.pixelRect(of: focus, onDisplay: display.frame, imageSize: imageSize)
            if let region, let marked = ScreenshotImage.marked(image, region: region) { image = marked }
        }
        guard let jpeg = ScreenshotImage.jpeg(image) else { throw Failure.encodingFailed }
        let encoded = clock.now

        return Result(
            jpeg: jpeg,
            pixelSize: CGSize(width: image.width, height: image.height),
            focusRegion: region,
            area: ScreenGeometry.flipped(display.frame, primaryHeight: primaryHeight),
            listSeconds: seconds(listed - started),
            grabSeconds: seconds(grabbed - listed),
            encodeSeconds: seconds(encoded - grabbed)
        )
    }

    private static func contentFilter(for display: SCDisplay, in content: SCShareableContent, request: Request) -> SCContentFilter {
        if let only = request.onlyWindows {
            let windows = content.windows.filter { only.contains($0.windowID) }
            return SCContentFilter(display: display, including: windows)
        }
        let me = ProcessInfo.processInfo.processIdentifier
        let hidden = content.applications.filter {
            shouldHide(pid: $0.processID, bundleID: $0.bundleIdentifier, me: me, hidden: request.hiddenBundleIDs)
        }
        return SCContentFilter(display: display, excludingApplications: hidden, exceptingWindows: [])
    }

    /// Shades never appears in its own screenshots, and neither do apps on the privacy list.
    static func shouldHide(pid: pid_t, bundleID: String, me: pid_t, hidden: [String]) -> Bool {
        pid == me || hidden.contains(bundleID)
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
