import AppKit
import ImageIO
@testable import Shades
import ShadesContext
import UniformTypeIdentifiers
import XCTest

final class DropTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("drop-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: folder)
    }

    private func png(width: Int, height: Int, named name: String) throws -> URL {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let url = folder.appendingPathComponent(name)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    func testAPDFGivesItsTextAndWhereItIs() throws {
        let pdf = try XCTUnwrap(Demo.samplePDF())
        let snapshot = try XCTUnwrap(Drop.file(pdf).snapshot())
        XCTAssertEqual(snapshot.droppedName, "syllabus.pdf")
        XCTAssertEqual(snapshot.url, pdf)
        XCTAssertTrue(snapshot.pageText?.contains("Week 2: Probability") == true)
        XCTAssertNil(snapshot.screenshotJPEG)
        XCTAssertNil(snapshot.appName)
    }

    func testAPictureComesAsAJPEGNoBiggerThanAScreenshot() throws {
        let picture = try png(width: 4000, height: 1000, named: "wide.png")
        let snapshot = try XCTUnwrap(Drop.file(picture).snapshot())
        XCTAssertEqual(snapshot.droppedName, "wide.png")
        let jpeg = try XCTUnwrap(snapshot.screenshotJPEG)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(jpeg as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier)
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 2048)
        XCTAssertEqual(image.height, 512)
    }

    func testAPictureWithNoExtensionIsStillRead() throws {
        let picture = try png(width: 10, height: 10, named: "Screenshot")
        XCTAssertEqual(try XCTUnwrap(Drop.file(picture).snapshot()).droppedName, "Screenshot")
    }

    func testALinkIsOnlyItsAddress() throws {
        let link = try XCTUnwrap(URL(string: "https://jobs.example.com/listing/123"))
        let snapshot = try XCTUnwrap(Drop.link(link).snapshot())
        XCTAssertEqual(snapshot.url, link)
        XCTAssertEqual(snapshot.droppedName, "jobs.example.com")
        XCTAssertNil(snapshot.pageText)
        XCTAssertNil(snapshot.screenshotJPEG)
    }

    func testAnythingElseIsntRead() throws {
        let notes = folder.appendingPathComponent("notes.zip")
        try Data("not a picture".utf8).write(to: notes)
        XCTAssertNil(Drop.file(notes).snapshot())

        let blank = folder.appendingPathComponent("blank.pdf")
        var page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let pdf = try XCTUnwrap(CGContext(blank as CFURL, mediaBox: &page, nil))
        pdf.beginPDFPage(nil)
        pdf.endPDFPage()
        pdf.closePDF()
        XCTAssertNil(Drop.file(blank).snapshot(), "a PDF with no text in it")

        XCTAssertNil(Drop.file(folder).snapshot(), "a folder")
    }

    func testAFileComesFirstThenAPictureThenALink() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("shades-drop-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let file = try png(width: 10, height: 10, named: "small.png")
        let link = try XCTUnwrap(URL(string: "https://example.com/page"))
        let picture = try Data(contentsOf: file)

        pasteboard.clearContents()
        pasteboard.writeObjects([link as NSURL, file as NSURL])
        XCTAssertEqual(Drop(pasteboard), .file(file))

        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(link.absoluteString, forType: .URL)
        item.setData(picture, forType: .png)
        pasteboard.writeObjects([item])
        XCTAssertEqual(Drop(pasteboard), .picture(picture), "a picture from a browser comes with its address")

        pasteboard.clearContents()
        pasteboard.writeObjects([link as NSURL])
        XCTAssertEqual(Drop(pasteboard), .link(link))

        pasteboard.clearContents()
        pasteboard.writeObjects([URL(string: "mailto:someone@example.com")! as NSURL])
        XCTAssertNil(Drop(pasteboard), "only web links")

        pasteboard.clearContents()
        pasteboard.setString("some words", forType: .string)
        XCTAssertNil(Drop(pasteboard))
    }
}
