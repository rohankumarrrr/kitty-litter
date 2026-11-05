import AppKit
import ImageIO
@testable import ShadesContext
import XCTest

final class ScreenshotImageTests: XCTestCase {
    private func solid(width: Int, height: Int, gray: CGFloat = 0.5) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: gray, green: gray, blue: gray, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// Colour at a pixel, counted from the top left the way focus regions are.
    private func color(of image: CGImage, x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8) {
        let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        let offset = y * image.width * 4 + x * 4
        return (bytes[offset + 2], bytes[offset + 1], bytes[offset])
    }

    private func assertRed(_ image: CGImage, x: Int, y: Int, file: StaticString = #filePath, line: UInt = #line) {
        let pixel = color(of: image, x: x, y: y)
        XCTAssertGreaterThan(pixel.red, 200, "(\(x), \(y))", file: file, line: line)
        XCTAssertLessThan(pixel.green, 80, "(\(x), \(y))", file: file, line: line)
        XCTAssertLessThan(pixel.blue, 80, "(\(x), \(y))", file: file, line: line)
    }

    private func assertUntouched(_ image: CGImage, x: Int, y: Int, file: StaticString = #filePath, line: UInt = #line) {
        let pixel = color(of: image, x: x, y: y)
        XCTAssertEqual(Int(pixel.red), 127, accuracy: 2, "(\(x), \(y))", file: file, line: line)
        XCTAssertEqual(Int(pixel.green), 127, accuracy: 2, "(\(x), \(y))", file: file, line: line)
    }

    func testTheMarkGoesAroundTheRegionNotOverIt() throws {
        let image = solid(width: 400, height: 300)
        let region = CGRect(x: 100, y: 50, width: 200, height: 100)
        let marked = try XCTUnwrap(ScreenshotImage.marked(image, region: region))
        XCTAssertEqual(marked.width, 400)
        XCTAssertEqual(marked.height, 300)

        // Just outside each of the four sides, which also proves the mark isn't upside down.
        assertRed(marked, x: 200, y: 48)
        assertRed(marked, x: 200, y: 151)
        assertRed(marked, x: 98, y: 100)
        assertRed(marked, x: 301, y: 100)

        // What you pointed at stays exactly as it was, right up to the edge.
        assertUntouched(marked, x: 200, y: 100)
        assertUntouched(marked, x: 101, y: 51)
        assertUntouched(marked, x: 298, y: 148)
        // And so does everything well away from it.
        assertUntouched(marked, x: 10, y: 10)
        assertUntouched(marked, x: 200, y: 280)
    }

    func testAMarkAtTheEdgeOfTheImageStaysOnIt() throws {
        let image = solid(width: 400, height: 300)
        let marked = try XCTUnwrap(ScreenshotImage.marked(image, region: CGRect(x: 0, y: 0, width: 400, height: 300)))
        assertRed(marked, x: 200, y: 1)
        assertRed(marked, x: 1, y: 150)
        assertRed(marked, x: 398, y: 150)
        assertRed(marked, x: 200, y: 298)
        assertUntouched(marked, x: 200, y: 150)
    }

    func testTheMarkScalesWithTheImageButStaysVisible() {
        XCTAssertEqual(ScreenshotImage.strokeWidth(forLongSide: 2048), 4)
        XCTAssertEqual(ScreenshotImage.strokeWidth(forLongSide: 400), 3)
    }

    func testJPEGIsAJPEGOfTheRightSize() throws {
        let data = try XCTUnwrap(ScreenshotImage.jpeg(solid(width: 2048, height: 1330)))
        XCTAssertEqual(Array(data.prefix(2)), [0xFF, 0xD8])
        XCTAssertLessThan(data.count, 10_000_000)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(decoded.width, 2048)
        XCTAssertEqual(decoded.height, 1330)
    }

    func testAnImageThatWontFitTheLimitIsDropped() {
        XCTAssertNil(ScreenshotImage.jpeg(solid(width: 400, height: 300), byteLimit: 10))
    }
}

final class RegionSelectionTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 1512, height: 982)

    func testAClickIsNotADrag() {
        let selection = RegionSelection(start: CGPoint(x: 100, y: 100), bounds: bounds)
        XCTAssertFalse(selection.isDrag)
    }

    func testATinyWobbleIsNotADrag() {
        var selection = RegionSelection(start: CGPoint(x: 100, y: 100), bounds: bounds)
        selection.current = CGPoint(x: 102, y: 300)
        XCTAssertFalse(selection.isDrag)
        selection.current = CGPoint(x: 103, y: 103)
        XCTAssertFalse(selection.isDrag)
    }

    func testDragsWorkInEveryDirection() {
        var selection = RegionSelection(start: CGPoint(x: 100, y: 100), bounds: bounds)
        selection.current = CGPoint(x: 300, y: 250)
        XCTAssertEqual(selection.rect, CGRect(x: 100, y: 100, width: 200, height: 150))
        XCTAssertTrue(selection.isDrag)
        selection.current = CGPoint(x: 20, y: 40)
        XCTAssertEqual(selection.rect, CGRect(x: 20, y: 40, width: 80, height: 60))
        XCTAssertTrue(selection.isDrag)
    }

    func testADragStaysOnItsOwnDisplay() {
        var selection = RegionSelection(start: CGPoint(x: 1400, y: 900), bounds: bounds)
        selection.current = CGPoint(x: 3000, y: -500)
        XCTAssertEqual(selection.rect, CGRect(x: 1400, y: 0, width: 112, height: 900))
    }
}

final class RegionPanelTests: XCTestCase {
    /// Anything lower leaves the menu bar and Dock undimmed and able to take your clicks.
    /// `isFloatingPanel` is the trap here, as setting it quietly drops the level back down.
    @MainActor
    func testTheOverlaySitsAboveTheMenuBarAndDock() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let panel = RegionPanel(screen: screen)
        XCTAssertEqual(panel.level, .screenSaver)
        XCTAssertGreaterThan(panel.level.rawValue, NSWindow.Level.mainMenu.rawValue)
        XCTAssertGreaterThan(panel.level.rawValue, NSWindow.Level.dock.rawValue)
    }

    @MainActor
    func testTheOverlayNeverActivatesAndCoversTheWholeDisplay() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let panel = RegionPanel(screen: screen)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertEqual(panel.frame, screen.frame)
    }

    @MainActor
    func testOverlayRectsBecomeGlobalPoints() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let panel = RegionPanel(screen: screen)
        let local = CGRect(x: 10, y: 20, width: 30, height: 40)
        XCTAssertEqual(panel.globalRect(from: local), local.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY))
    }
}
