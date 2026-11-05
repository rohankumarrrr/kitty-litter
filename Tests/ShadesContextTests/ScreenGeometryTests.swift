@testable import ShadesContext
import XCTest

final class ScreenGeometryTests: XCTestCase {
    private let primaryHeight: CGFloat = 982
    /// A 14-inch MacBook Pro at its default scale, in Quartz coordinates.
    private let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)

    private func pixels(appKit rect: CGRect, display: CGRect, image: CGSize) -> CGRect? {
        let quartz = ScreenGeometry.flipped(rect, primaryHeight: primaryHeight)
        return ScreenGeometry.pixelRect(of: quartz, onDisplay: display, imageSize: image)
    }

    func testFlipsBetweenAppKitAndQuartz() {
        let appKit = CGRect(x: 100, y: 800, width: 200, height: 100)
        let quartz = ScreenGeometry.flipped(appKit, primaryHeight: primaryHeight)
        XCTAssertEqual(quartz, CGRect(x: 100, y: 82, width: 200, height: 100))
        XCTAssertEqual(ScreenGeometry.flipped(quartz, primaryHeight: primaryHeight), appKit)
    }

    func testRetinaDoublesEverything() {
        let result = pixels(
            appKit: CGRect(x: 100, y: 800, width: 200, height: 100),
            display: laptop,
            image: CGSize(width: 3024, height: 1964)
        )
        XCTAssertEqual(result, CGRect(x: 200, y: 164, width: 400, height: 200))
    }

    func testTheTopLeftOfTheScreenIsTheTopLeftOfTheImage() {
        let result = pixels(
            appKit: CGRect(x: 0, y: 882, width: 100, height: 100),
            display: laptop,
            image: CGSize(width: 3024, height: 1964)
        )
        XCTAssertEqual(result?.origin, .zero)
    }

    func testTheSizeCapScalesTheRegionWithTheImage() {
        let image = CGSize(width: 2048, height: 1330)
        let result = pixels(appKit: CGRect(x: 756, y: 491, width: 378, height: 245.5), display: laptop, image: image)
        // The middle of the screen stays the middle of the image, within a rounded pixel.
        XCTAssertEqual(result!.minX, 1024, accuracy: 1)
        XCTAssertEqual(result!.maxY, 665, accuracy: 1)
        XCTAssertEqual(result!.width, 512, accuracy: 2)
        XCTAssertEqual(result!.height, 332.5, accuracy: 2)
    }

    func testRoundsOutwardToWholePixels() {
        let result = pixels(
            appKit: CGRect(x: 10.3, y: 500.3, width: 20.2, height: 20.2),
            display: laptop,
            image: CGSize(width: 1512, height: 982)
        )!
        XCTAssertEqual(result, result.integral)
        XCTAssertLessThanOrEqual(result.minX, 10.3)
        XCTAssertGreaterThanOrEqual(result.maxX, 30.5)
    }

    /// A display to the left has negative x, and sits at its own height.
    func testDisplayToTheLeftOfTheMainOne() {
        let left = CGRect(x: -1920, y: -98, width: 1920, height: 1080)
        let result = pixels(
            appKit: CGRect(x: -1000, y: 500, width: 100, height: 50),
            display: left,
            image: CGSize(width: 1920, height: 1080)
        )
        XCTAssertEqual(result, CGRect(x: 920, y: 530, width: 100, height: 50))
    }

    /// A display above the main one has negative y in Quartz, and y above the main one in AppKit.
    func testDisplayAboveTheMainOne() {
        let above = CGRect(x: 0, y: -1080, width: 1920, height: 1080)
        let result = pixels(
            appKit: CGRect(x: 300, y: 1500, width: 200, height: 100),
            display: above,
            image: CGSize(width: 1920, height: 1080)
        )
        XCTAssertEqual(result, CGRect(x: 300, y: 462, width: 200, height: 100))
    }

    func testRetinaDisplayToTheRightThatGetsCapped() {
        let right = CGRect(x: 1512, y: 0, width: 1728, height: 1117)
        let image = ScreenGeometry.cappedPixelSize(points: right.size, scale: 2, longSide: 2048)
        XCTAssertEqual(image, CGSize(width: 2048, height: 1324))
        // The whole display, in AppKit's flipped terms, must come out as the whole image.
        let whole = ScreenGeometry.flipped(right, primaryHeight: primaryHeight)
        let result = pixels(appKit: whole, display: right, image: image)
        XCTAssertEqual(result, CGRect(origin: .zero, size: image))
    }

    func testClipsToTheDisplay() {
        let result = ScreenGeometry.pixelRect(
            of: CGRect(x: 1400, y: 900, width: 500, height: 500),
            onDisplay: laptop,
            imageSize: CGSize(width: 1512, height: 982)
        )
        XCTAssertEqual(result, CGRect(x: 1400, y: 900, width: 112, height: 82))
    }

    func testARegionOnAnotherDisplayMisses() {
        let result = ScreenGeometry.pixelRect(
            of: CGRect(x: 2000, y: 100, width: 50, height: 50),
            onDisplay: laptop,
            imageSize: CGSize(width: 1512, height: 982)
        )
        XCTAssertNil(result)
    }

    func testPicksTheDisplayShowingMost() {
        let right = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        let mostlyRight = CGRect(x: 1500, y: 100, width: 300, height: 100)
        XCTAssertEqual(ScreenGeometry.displayIndex(showing: mostlyRight, among: [laptop, right]), 1)
        let nowhere = CGRect(x: 9000, y: 9000, width: 10, height: 10)
        XCTAssertNil(ScreenGeometry.displayIndex(showing: nowhere, among: [laptop, right]))
    }

    func testWhereYouPointedDecidesTheDisplayBeforeTheFrontWindow() {
        let right = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        let displays = [laptop, right]
        let onLaptop = CGRect(x: 10, y: 10, width: 400, height: 400)
        let onRight = CGRect(x: 1600, y: 10, width: 50, height: 50)

        XCTAssertEqual(
            ScreenGeometry.displayToCapture(focusRegion: onRight, frontWindow: onLaptop, mouse: .zero, among: displays),
            1
        )
        XCTAssertEqual(
            ScreenGeometry.displayToCapture(focusRegion: nil, frontWindow: onRight, mouse: .zero, among: displays),
            1
        )
        XCTAssertEqual(
            ScreenGeometry.displayToCapture(focusRegion: nil, frontWindow: nil, mouse: CGPoint(x: 2000, y: 50), among: displays),
            1
        )
        XCTAssertEqual(
            ScreenGeometry.displayToCapture(focusRegion: nil, frontWindow: nil, mouse: CGPoint(x: -9, y: -9), among: displays),
            0
        )
        XCTAssertNil(ScreenGeometry.displayToCapture(focusRegion: nil, frontWindow: nil, mouse: .zero, among: []))
    }

    func testCapsTheLongSideOnly() {
        XCTAssertEqual(
            ScreenGeometry.cappedPixelSize(points: CGSize(width: 1512, height: 982), scale: 2, longSide: 2048),
            CGSize(width: 2048, height: 1330)
        )
        XCTAssertEqual(
            ScreenGeometry.cappedPixelSize(points: CGSize(width: 1080, height: 1920), scale: 2, longSide: 2048),
            CGSize(width: 1152, height: 2048)
        )
        XCTAssertEqual(
            ScreenGeometry.cappedPixelSize(points: CGSize(width: 1280, height: 800), scale: 1, longSide: 2048),
            CGSize(width: 1280, height: 800)
        )
    }
}
