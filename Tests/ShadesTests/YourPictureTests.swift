import AppKit
@testable import Shades
import XCTest

final class YourPictureTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func photo(width: Int, height: Int) throws -> URL {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let file = folder.appendingPathComponent("photo.png")
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: file)
        return file
    }

    func testItKeepsASmallCopySoTheOriginalCanGo() throws {
        let original = try photo(width: 848, height: 600)
        let kept = folder.appendingPathComponent("kept/picture.jpg")
        try YourPicture.save(from: original, to: kept)
        try FileManager.default.removeItem(at: original)

        let image = try XCTUnwrap(YourPicture.load(from: kept).flatMap(NSBitmapImageRep.init(data:)))
        XCTAssertEqual(max(image.pixelsWide, image.pixelsHigh), Int(YourPicture.side))
        XCTAssertLessThan(try Data(contentsOf: kept).count, 20_000, "small enough to go with each page a phone is sent")
    }

    func testNoneOrSomethingThatIsntAPictureLeavesYoursAsTheyWere() throws {
        XCTAssertNil(YourPicture.load(from: folder.appendingPathComponent("picture.jpg")))
        let words = folder.appendingPathComponent("notes.txt")
        try Data("not a picture".utf8).write(to: words)
        XCTAssertThrowsError(try YourPicture.save(from: words, to: folder.appendingPathComponent("picture.jpg")))
        XCTAssertNil(YourPicture.load(from: folder.appendingPathComponent("picture.jpg")))
    }
}
