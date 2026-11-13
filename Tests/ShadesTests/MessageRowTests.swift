import AppKit
@testable import Shades
import ShadesCore
import XCTest

/// A message's actions float over the top of its row as icons, the way Slack's and Discord's do. Showing them moves
/// nothing and covers nothing that's drawn, and the rest of a row stays where those apps put it.
@MainActor
final class MessageRowTests: XCTestCase {
    private let steve = Kitten(name: "Steve Pawsniak", role: "Professional", covers: "", folder: "/k/steve")
    private let at = Date(timeIntervalSince1970: 1_000_000)

    /// A window that says it has the keyboard, since a test can't make a real one key.
    private final class KeyWindow: NSWindow {
        override var isKeyWindow: Bool { true }
    }

    override func setUp() async throws {
        QuietFocus.fullKeyboardAccess = { false }
    }

    override func tearDown() async throws {
        QuietFocus.fullKeyboardAccess = { NSApplication.shared.isFullKeyboardAccessEnabled }
    }

    private func row(_ speaker: Speaker, text: String = "Sure.", notes: Int = 0, reactions: [Reaction] = []) -> MessageRowView {
        let thread = AgentThread(id: "t", title: "Work", projectTitle: "Steve", status: .completed, model: "m", updatedAt: at, projectPath: steve.folder)
        let book = ChannelBook.build(kittens: [steve], threads: [thread], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false)
        var message = ChannelMessage(exchangeID: "e", kind: speaker == .you ? .ask : .reply, speaker: speaker, text: text, at: at, threadID: "t", threadTitle: "Work")
        message.earlierNotes = notes
        message.reactions = reactions
        let row = MessageRowView(message: message, look: ChannelSpeakerLook(speaker, in: book))
        row.onReact = { _ in }
        row.onReply = {}
        row.onMarkUnread = {}
        row.onOpen = {}
        return row
    }

    /// The row drawn at `width`, then drawn again while hovered, on a see-through ground.
    private func drawn(_ row: MessageRowView, width: CGFloat) throws -> (still: NSBitmapImageRep, hovered: NSBitmapImageRep) {
        let height = row.fit(width: width)
        let host = QuietView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        host.appearance = NSAppearance(named: .aqua)
        host.addSubview(row)
        row.frame = host.bounds
        let still = try XCTUnwrap(ChannelImages.bitmap(of: host, scale: 2))
        row.hovering = true
        XCTAssertEqual(row.fit(width: width), height, "the same height while hovered")
        return (still, try XCTUnwrap(ChannelImages.bitmap(of: host, scale: 2)))
    }

    /// Every pixel that's different, as one rect in points.
    private func changed(from a: NSBitmapImageRep, to b: NSBitmapImageRep) -> NSRect? {
        var box: NSRect?
        for y in 0..<a.pixelsHigh {
            for x in 0..<a.pixelsWide where pixel(a, x, y) != pixel(b, x, y) {
                box = (box ?? NSRect(x: x, y: y, width: 1, height: 1)).union(NSRect(x: x, y: y, width: 1, height: 1))
            }
        }
        return box.map { NSRect(x: $0.minX / 2, y: $0.minY / 2, width: $0.width / 2, height: $0.height / 2) }
    }

    private func pixel(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> [UInt8] {
        let start = y * rep.bytesPerRow + x * rep.bitsPerPixel / 8
        return (0..<rep.samplesPerPixel).map { rep.bitmapData![start + $0] }
    }

    /// Whether anything at all is drawn inside `rect` in points.
    private func hasInk(_ rep: NSBitmapImageRep, in rect: NSRect) -> Bool {
        let pixels = NSRect(x: rect.minX * 2, y: rect.minY * 2, width: rect.width * 2, height: rect.height * 2).integral
        for y in Int(pixels.minY)..<min(Int(pixels.maxY), rep.pixelsHigh) {
            for x in Int(pixels.minX)..<min(Int(pixels.maxX), rep.pixelsWide) where pixel(rep, x, y).last != 0 {
                return true
            }
        }
        return false
    }

    func testTheToolbarFloatsOverTheRowWithoutMovingOrCoveringAnythingDrawn() throws {
        let cases: [(name: String, row: () -> MessageRowView, width: CGFloat)] = [
            ("a kitten's, in a channel", { self.row(.kitten(self.steve.id)) }, 640),
            ("yours, whose time is at the right", { self.row(.you) }, 640),
            ("a kitten's, in the narrowest thread pane", { self.row(.kitten(self.steve.id)) }, ChannelsView.threadWidths.lowerBound),
            ("a kitten's with earlier notes, too long for its line", { self.row(.kitten(self.steve.id), notes: 2) }, ChannelsView.threadWidths.lowerBound),
            ("yours, in the narrowest thread pane", { self.row(.you) }, ChannelsView.threadWidths.lowerBound),
            ("yours, also sent to a channel", {
                let row = self.row(.you)
                row.context = CatWords.repliedToThread("Rewrite the pricing copy so it sounds like a person wrote it")
                return row
            }, 640),
        ]
        for (name, make, width) in cases {
            let row = make()
            let (still, hovered) = try drawn(row, width: width)
            let toolbar = try XCTUnwrap(changed(from: still, to: hovered), "\(name): the toolbar shows")
            // It may float over the bubble's top edge, as Slack's does over a message, but stops where the words start.
            let overTheBubble = NSRect(x: toolbar.minX, y: toolbar.minY, width: toolbar.width, height: max(row.bubble.minY - toolbar.minY, 0))
            XCTAssertFalse(hasInk(still, in: overTheBubble), "\(name): nothing it covers over the bubble is drawn, such as the name or the time, at \(toolbar)")
            for words in row.subviews.compactMap({ $0 as? ChannelTextView }) {
                XCTAssertFalse(toolbar.intersects(words.frame), "\(name): never over the words, at \(toolbar)")
            }
        }
    }

    func testItsButtonsAreIconsThatSayWhatTheyDoAndWhatDoesntFitIsUnderMore() throws {
        let wide = row(.kitten(steve.id))
        _ = try drawn(wide, width: 640)
        let toolbar = try XCTUnwrap(wide.toolbar)
        XCTAssertEqual(toolbar.buttons.map { $0.accessibilityLabel() ?? "" }, [CatWords.react, "Reply", "Copy", CatWords.markUnread, CatWords.openInT3], "as Slack orders them, the most used first")
        for button in toolbar.buttons {
            XCTAssertFalse(button.isHidden)
            XCTAssertNotNil(button.symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }, "\(button.accessibilityLabel() ?? "") draws a symbol this Mac has")
            XCTAssertEqual(button.toolTip, button.accessibilityLabel(), "and says its name when you hover it")
        }
        XCTAssertTrue(toolbar.more.isHidden, "nothing to fold when it all fits")
        XCTAssertLessThanOrEqual(toolbar.frame.maxX, 640 - ChannelRowView.margin, "at the row's right end")

        let narrow = row(.kitten(steve.id), notes: 2)
        _ = try drawn(narrow, width: ChannelsView.threadWidths.lowerBound)
        let folded = try XCTUnwrap(narrow.toolbar)
        XCTAssertFalse(folded.more.isHidden, "what doesn't fit is under More")
        XCTAssertEqual(folded.more.toolTip, "More")
        XCTAssertTrue(narrow.bounds.contains(folded.frame))
    }

    func testTabReachesTheToolbarAndShowsIt() throws {
        QuietFocus.fullKeyboardAccess = { true }
        let window = KeyWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 200), styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let row = row(.kitten(steve.id))
        row.frame = NSRect(x: 0, y: 0, width: 640, height: row.fit(width: 640))
        window.contentView?.addSubview(row)
        row.hovering = false
        let toolbar = try XCTUnwrap(row.toolbar, "there for Tab before any hover")
        let first = try XCTUnwrap(toolbar.buttons.first)
        XCTAssertTrue(first.canBecomeKeyView)
        let hidden = try XCTUnwrap(ChannelImages.png(of: row))

        XCTAssertTrue(window.makeFirstResponder(first))
        XCTAssertNotEqual(ChannelImages.png(of: row), hidden, "shown while one of its buttons has the keyboard")

        window.makeFirstResponder(nil)
        XCTAssertEqual(ChannelImages.png(of: row), hidden, "and gone once Tab moves on")
    }

    func testReactionsEndWithAWayToAddOneUnderTheMessage() throws {
        let row = row(.kitten(steve.id), reactions: [.thumbsUp, .check])
        _ = try drawn(row, width: 640)
        let chips = row.subviews.compactMap { $0 as? QuietButton }.filter { $0.frame.minY >= row.bubble.maxY }.sorted { $0.frame.minX < $1.frame.minX }
        XCTAssertEqual(chips.map { $0.accessibilityLabel() ?? "" }, ["👍", "✅", CatWords.react], "after the reactions, as in Slack")
        XCTAssertEqual(chips.last?.symbol, "face.smiling")
        XCTAssertEqual(chips.first?.frame.minX, row.bubble.minX, "from the bubble's side")
    }
}
