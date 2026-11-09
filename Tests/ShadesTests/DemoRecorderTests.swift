import AppKit
import ImageIO
@testable import Shades
import XCTest

/// The recorder behind the README's GIFs: frames from the windows' own drawing, with repeats folded into one.
@MainActor
final class DemoRecorderTests: XCTestCase {
    private func square(_ white: CGFloat) -> CGImage {
        let context = CGContext(data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor(white: white, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        return context.makeImage()!
    }

    func testARecordingLoopsAndKeepsOnlyWhatChanged() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("shades-recording-\(UUID().uuidString).gif")
        defer { try? FileManager.default.removeItem(at: file) }
        let frame = CGRect(x: 100, y: 100, width: 20, height: 20)
        let (before, after) = (square(0.2), square(0.8))
        var taken = 0
        // A busy machine, where each frame is taken a quarter of a second after the last rather than the eighth asked for.
        let recorder = DemoRecorder(
            file: file,
            windows: { taken += 1; return [(taken <= 3 ? before : after, frame)] },
            onPage: false,
            phone: nil,
            now: { Date(timeIntervalSinceReferenceDate: Double(taken) * 0.25) }
        )
        recorder.start()
        for _ in 0..<1000 where taken < 6 { try await Task.sleep(nanoseconds: 10_000_000) }
        let said = recorder.stop()

        XCTAssertTrue(said.hasPrefix("recorded"), said)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(file as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 2, "one frame for each thing the window showed, however long it showed it")
        let gif = (CGImageSourceCopyProperties(source, nil) as? [CFString: Any])?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        XCTAssertEqual(gif?[kCGImagePropertyGIFLoopCount] as? Int, 0, "it loops forever")
        let first = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let seconds = try XCTUnwrap(first?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
        XCTAssertEqual(seconds, 0.75, accuracy: 0.01, "and lasts as long as it was shown, three frames a quarter of a second apart")
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, Int((20 + 48) * DemoRecorder.scale), "the window with room around it, sharp on a Retina screen")
    }
}
