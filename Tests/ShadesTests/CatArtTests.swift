@testable import Shades
import XCTest

final class CatArtTests: XCTestCase {
    func testEveryFrameIsSixteenBySixteen() {
        for frame in CatFrame.allCases {
            XCTAssertEqual(frame.rows.count, 16, frame.rawValue)
            for row in frame.rows {
                XCTAssertEqual(row.count, 16, frame.rawValue)
            }
        }
    }

    func testEveryPixelIsInThePalettes() {
        for theme in [CatTheme.light, .dark] {
            let keys = Set(theme.palette.keys).union(["."])
            for frame in CatFrame.allCases {
                for row in frame.rows {
                    XCTAssertTrue(Set(row).isSubset(of: keys), "\(frame.rawValue): \(row)")
                }
            }
        }
    }

    func testThePalettesAreTheSitesOwn() {
        XCTAssertEqual(CatTheme.light.palette["k"], 0x111113)
        XCTAssertEqual(CatTheme.dark.palette["k"], 0x8f8f95)
        XCTAssertEqual(CatTheme.light.palette["j"], 0x2a2a2e)
        XCTAssertEqual(CatTheme.dark.palette["j"], 0x232327)
    }

    func testDrawnAtAWholeNumberScale() {
        XCTAssertEqual(CatArt.scale, 4)
        XCTAssertEqual(CatArt.points, 64)
    }

    @MainActor
    func testTheGlintRecoloursOnlyTheGlint() {
        let plain = CatRenderer.pixels(for: CatPose(frame: .sit), theme: .light)
        let lit = CatRenderer.pixels(for: CatPose(frame: .sit, glint: .listening(loudness: 2)), theme: .light)
        var changed = 0
        for i in stride(from: 0, to: plain.count, by: 4) where plain[i..<i + 4] != lit[i..<i + 4] {
            let x = i / 4 % 16
            let y = i / 4 / 16
            XCTAssertEqual(Array(CatFrame.sit.rows[y])[x], "g")
            changed += 1
        }
        XCTAssertEqual(changed, 2)
    }

    @MainActor
    func testPixelsMatchTheArt() {
        let bytes = CatRenderer.pixels(for: CatPose(frame: .sit), theme: .dark)
        for (y, row) in CatFrame.sit.rows.enumerated() {
            for (x, ch) in row.enumerated() {
                let i = (y * 16 + x) * 4
                if ch == "." {
                    XCTAssertEqual(bytes[i + 3], 0)
                } else {
                    let color = CatTheme.dark.palette[ch]!
                    XCTAssertEqual(UInt32(bytes[i]) << 16 | UInt32(bytes[i + 1]) << 8 | UInt32(bytes[i + 2]), color)
                    XCTAssertEqual(bytes[i + 3], 255)
                }
            }
        }
    }

    @MainActor
    func testRunningLeftIsRunningRightFlipped() {
        let right = CatRenderer.pixels(for: CatPose(frame: .run1), theme: .light)
        let left = CatRenderer.pixels(for: CatPose(frame: .run1, flip: true), theme: .light)
        for y in 0..<16 {
            for x in 0..<16 {
                XCTAssertEqual(left[(y * 16 + x) * 4 + 3], right[(y * 16 + 15 - x) * 4 + 3])
            }
        }
    }

    func testOnlyVisiblePixelsCount() {
        let sit = CatPose(frame: .sit)
        // Empty corners.
        XCTAssertFalse(CatRenderer.isVisible(sit, x: 0, y: 0))
        XCTAssertFalse(CatRenderer.isVisible(sit, x: 15, y: 0))
        XCTAssertFalse(CatRenderer.isVisible(sit, x: 0, y: 15))
        // The middle of its face, and just outside the grid.
        XCTAssertTrue(CatRenderer.isVisible(sit, x: 7, y: 5))
        XCTAssertFalse(CatRenderer.isVisible(sit, x: -1, y: 5))
        XCTAssertFalse(CatRenderer.isVisible(sit, x: 16, y: 5))
    }

    func testTheHitAreaFlipsAndHopsWithTheArt() {
        // The first filled pixel of the run frame's top row is over on the right.
        XCTAssertTrue(CatRenderer.isVisible(CatPose(frame: .run1), x: 9, y: 1))
        XCTAssertFalse(CatRenderer.isVisible(CatPose(frame: .run1), x: 6, y: 1))
        XCTAssertTrue(CatRenderer.isVisible(CatPose(frame: .run1, flip: true), x: 6, y: 1))
        XCTAssertFalse(CatRenderer.isVisible(CatPose(frame: .sit), x: 4, y: 0))
        XCTAssertTrue(CatRenderer.isVisible(CatPose(frame: .sit, lift: 1), x: 4, y: 0))
    }
}
