import XCTest

final class ContextColorSpaceTests: XCTestCase {
    func testNothingAsksAGraphicsContextForItsColourSpace() throws {
        let asking = try NSRegularExpression(pattern: #"[cC]ontext\??\.colorSpace\b"#)
        for file in try Repo.files(under: ["Sources"], endingIn: [".swift"]) {
            for match in SwiftLexer(try Repo.read(file)).matches(of: asking, in: .code) {
                XCTFail("""
                \(file):\(match.line) reads \(match.text). Only a bitmap's context has a colour space to give, and a \
                window's isn't one, so CoreGraphics logs `CGBitmapContextGetColorSpace: invalid context` on every draw \
                there. Use `PictureDrawing.space` while a picture is drawn, and the screen's colour space otherwise, as \
                `Opal` does.
                """)
            }
        }
    }
}
