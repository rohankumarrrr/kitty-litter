import AppKit
@testable import Shades
import ShadesCore
import XCTest

@MainActor
final class AppIconTests: XCTestCase {
    private struct Pixel {
        var red, green, blue, alpha: CGFloat
        var isWhite: Bool { min(red, green, blue) > 0.9 && alpha > 0.99 }
        var isDark: Bool { max(red, green, blue) < 0.15 }
        var hue: CGFloat {
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
            NSColor(srgbRed: red, green: green, blue: blue, alpha: 1).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            return hue * 360
        }
    }

    private func pixel(_ picture: NSBitmapImageRep, _ x: Int, _ y: Int) -> Pixel {
        let color = picture.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
        return Pixel(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent, alpha: color.alphaComponent)
    }

    private func pixel(_ picture: NSBitmapImageRep, across x: CGFloat, down y: CGFloat) -> Pixel {
        pixel(picture, min(Int(x * CGFloat(picture.pixelsWide)), picture.pixelsWide - 1), min(Int(y * CGFloat(picture.pixelsHigh)), picture.pixelsHigh - 1))
    }

    private func assertTheCatOnARimlightTile(_ picture: NSBitmapImageRep, tileFrom start: CGFloat, to end: CGFloat, _ name: String, line: UInt = #line) {
        let span = end - start
        XCTAssertTrue(pixel(picture, across: 0.5, down: start + span * 0.08).isDark, "\(name): a black tile", line: line)
        let glow = pixel(picture, across: 0.5, down: end - span * 0.06)
        XCTAssertEqual(glow.hue, AppIcon.hue, accuracy: 8, "\(name): lit from below in the icon's own hue", line: line)
        XCTAssertGreaterThan(max(glow.red, glow.green, glow.blue), 0.25, "\(name): a glow you can see", line: line)
        let middle = (0..<picture.pixelsHigh).map { pixel(picture, picture.pixelsWide / 2, $0) }
        let fur = middle.indices.filter { middle[$0].isWhite }
        XCTAssertFalse(fur.isEmpty, "\(name): the cat is white", line: line)
        guard let head = fur.first, let foot = fur.last else { return }
        XCTAssertTrue(middle[head...foot].contains { $0.isDark }, "\(name): with its shades cut out of it", line: line)
    }

    func testTheDockIconIsTheWhiteCatOnARimlightTileWithRoomAroundIt() {
        let picture = AppIcon.picture(side: 1024)
        assertTheCatOnARimlightTile(picture, tileFrom: 100 / 1024, to: 924 / 1024, "the Dock icon")
        XCTAssertEqual(pixel(picture, 4, 4).alpha, 0, "room around the tile, as every Mac icon has")
        let rim = (100..<140).map { pixel(picture, 512, $0) }.filter { $0.red > 0.2 }.count
        XCTAssertEqual(CGFloat(rim), 824 * AppIcon.rimShare, accuracy: 2, "a rim as thin as the other Rimlight icons'")
    }

    func testTheAppsIconFileIsTheOneTheAppDraws() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("assets/AppIcon.icns")
        let saved = try XCTUnwrap(NSImage(contentsOf: file)).representations.compactMap { $0 as? NSBitmapImageRep }
        XCTAssertEqual(Set(saved.map(\.pixelsWide)), [16, 32, 64, 128, 256, 512, 1024])
        for picture in saved {
            let side = picture.pixelsWide
            let drawn = AppIcon.picture(side: side)
            let step = max(1, side / 128)
            var difference: CGFloat = 0, count: CGFloat = 0
            for y in stride(from: 0, to: side, by: step) {
                for x in stride(from: 0, to: side, by: step) {
                    let a = pixel(picture, x, y), b = pixel(drawn, x, y)
                    difference += abs(a.red * a.alpha - b.red * b.alpha) + abs(a.green * a.alpha - b.green * b.alpha) + abs(a.blue * a.alpha - b.blue * b.alpha) + abs(a.alpha - b.alpha)
                    count += 4
                }
            }
            XCTAssertLessThan(difference / count, 0.01, "assets/AppIcon.icns at \(side) px isn't what the app draws. Redraw it with `swift run shades --draw-icon assets`.")
        }
    }

    func testTheRunningAppShowsItsIconInTheDockWithTheBadgeOnTop() throws {
        defer { NSApp.applicationIconImage = nil }
        let controller = AppController(dependencies: AppDependencies(backend: FakeBackend(), context: FakeContext(log: Log()), voice: FakeVoice(), inserter: FakeInserter(), keys: FakeKeys(), settings: Settings(), saveSettings: { _ in }, kittens: { [] }, inbox: Inbox(since: .distantPast)), stage: FakeStage(log: Log()))
        AppDelegate(controller: controller, menuBar: MenuBar()).applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        let shown = try XCTUnwrap(NSApp.applicationIconImage?.cgImage(forProposedRect: nil, context: nil, hints: nil).map(NSBitmapImageRep.init(cgImage:)))
        assertTheCatOnARimlightTile(shown, tileFrom: 100 / 1024, to: 924 / 1024, "the Dock while it runs, which macOS's tinted icon styles leave in colour")
        let stage = AppStage()
        defer { stage.showNeedsYou(0) }
        stage.showNeedsYou(2)
        XCTAssertEqual(NSApp.dockTile.badgeLabel, "2", "the badge goes on top of it")
        stage.showNeedsYou(0)
        XCTAssertNil(NSApp.dockTile.badgeLabel)
    }

    func testThePhonePageServesTheIconFillingAnOpaqueSquareForTheHomeScreen() throws {
        let link = PhoneLink(keys: MemoryPhoneKeys(), grace: 0, hold: { nil }, release: {}, act: { _ in }, sendPush: { _ in nil }, now: { Date() })
        guard case .full(let status, let type, let body) = link.respond(to: PhoneServer.Request(method: "GET", path: "/icon.png", query: [:], headers: [:], body: Data())) else { return XCTFail("a whole picture") }
        XCTAssertEqual(status, 200)
        XCTAssertEqual(type, "image/png")
        let picture = try XCTUnwrap(NSBitmapImageRep(data: body))
        XCTAssertEqual([picture.pixelsWide, picture.pixelsHigh], [180, 180], "the size iOS asks a Home Screen icon for")
        assertTheCatOnARimlightTile(picture, tileFrom: 0, to: 1, "the Home Screen icon")
        let edges = (0..<180).flatMap { [(0, $0), (179, $0), ($0, 0), ($0, 179)] }
        XCTAssertTrue(edges.allSatisfy { pixel(picture, $0.0, $0.1).alpha == 1 }, "opaque to its edges, since iOS rounds the corners itself")
        XCTAssertTrue([(0, 0), (179, 0)].allSatisfy { pixel(picture, $0.0, $0.1).isDark }, "black in the corners iOS cuts away")
        XCTAssertTrue(PhonePage.html.contains(#"<link rel="apple-touch-icon" href="/icon.png">"#))
    }
}
