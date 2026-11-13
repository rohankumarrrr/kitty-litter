import AppKit
@testable import Shades
import XCTest

/// Words selected in Messages read on whatever they sit on, with or without the keyboard. Without it, which is most of
/// the time since Messages never makes Shades the active app, AppKit used to swap in its own grey, and black words on a
/// kitten's bubble went under it like a redaction.
@MainActor
final class SelectionTests: XCTestCase {
    /// Every surface words sit on in Messages, with the words on it.
    private var surfaces: [(name: String, surface: UInt32, words: UInt32)] {
        let opal: [(String, UInt32, UInt32)] = [
            ("body on the page", Opal.page, Opal.body),
            ("a note on the page", Opal.page, Opal.secondary),
            ("why it didn't send", Opal.page, Opal.errorText),
            ("your message", Opal.selected, Opal.body),
            ("the cat's grey bubble", Opal.controlHover, Opal.body),
            ("a hovered row", Opal.raised, Opal.body),
        ]
        // A kitten's bubble is in its colour, with whichever of black and white reads better on it.
        let kittens = Opal.kittens.map { ("a kitten's \(Opal.hex($0)) bubble", $0, Opal.contrast($0, 0x000000) >= Opal.contrast($0, 0xffffff) ? UInt32(0x000000) : 0xffffff) }
        return opal + kittens
    }

    func testSelectedWordsReadAndShowOnEverySurface() throws {
        for (name, surface, words) in surfaces {
            let selection = MessagesInk.selection(on: Ink.hex(words))
            let fill = try Self.hex(XCTUnwrap(selection[.backgroundColor] as? NSColor))
            let selected = try Self.hex(XCTUnwrap(selection[.foregroundColor] as? NSColor))
            XCTAssertGreaterThanOrEqual(Opal.contrast(selected, fill), 4.5, "selected \(name) is \(Opal.hex(selected)) on \(Opal.hex(fill))")
            // It has to look selected too: either the fill or the words stand out from what was there.
            let shows = max(Opal.contrast(fill, surface), Opal.contrast(selected, words))
            XCTAssertGreaterThanOrEqual(shows, 3, "a selection of \(name) hardly shows")
        }
    }

    func testASelectionLooksTheSameWithoutTheKeyboard() throws {
        for words in [Opal.body, 0x000000, 0xffffff] {
            let block = ChannelTextBlock(ChannelMarkdown.attributed("Selected words and the rest", color: Ink.hex(words)))
            block.fit(width: 300)
            let view = block.view
            view.frame = NSRect(x: 0, y: 0, width: block.width, height: block.height)
            let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: true)
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = view
            view.setSelectedRange(NSRange(location: 0, length: 14))
            XCTAssertFalse(window.isKeyWindow, "drawn as it is while you're in another app")

            let fill = try XCTUnwrap(MessagesInk.selection(on: Ink.hex(words))[.backgroundColor] as? NSColor)
            let layout = try XCTUnwrap(view.layoutManager)
            let rect = layout.boundingRect(forGlyphRange: NSRange(location: 0, length: 14), in: try XCTUnwrap(view.textContainer))
            let drawn = try Self.commonest(in: rect, of: XCTUnwrap(ChannelImages.bitmap(of: view, scale: 2)))
            XCTAssertLessThanOrEqual(Self.distance(drawn, Self.hex(fill)), 12, "selected \(Opal.hex(words)) words sit on \(Opal.hex(drawn)), not \(Opal.hex(Self.hex(fill)))")
        }
    }

    private static func hex(_ color: NSColor) -> UInt32 {
        let srgb = color.usingColorSpace(.sRGB)!
        return [srgb.redComponent, srgb.greenComponent, srgb.blueComponent].reduce(UInt32(0)) { $0 << 8 | UInt32((min(max($1, 0), 1) * 255).rounded()) }
    }

    /// The colour most of `rect` is drawn in, which behind a few words is what's under them.
    private static func commonest(in rect: NSRect, of bitmap: NSBitmapImageRep) -> UInt32 {
        let scale = CGFloat(bitmap.pixelsWide) / bitmap.size.width
        var counts: [UInt32: Int] = [:]
        for x in Int(rect.minX * scale)..<Int(rect.maxX * scale) {
            for y in Int(rect.minY * scale)..<Int(rect.maxY * scale) {
                if let color = bitmap.colorAt(x: x, y: y) { counts[hex(color), default: 0] += 1 }
            }
        }
        return counts.max { $0.value < $1.value }?.key ?? 0
    }

    /// The largest difference in any one channel, out of 255.
    private static func distance(_ a: UInt32, _ b: UInt32) -> Int {
        [16, 8, 0].map { abs(Int((a >> $0) & 0xff) - Int((b >> $0) & 0xff)) }.max() ?? 0
    }
}
