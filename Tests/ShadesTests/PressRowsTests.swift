import AppKit
@testable import Shades
import ShadesCore
import XCTest

/// Everything on a message in Messages, pressed the way a mouse and keyboard press it, through `Press`, in a window
/// that's never shown.
@MainActor
final class PressRowsTests: XCTestCase {
    private let steve = Kitten(name: "Steve Pawsniak", role: "Professional", covers: "", folder: "/k/steve")
    private let at = Date(timeIntervalSince1970: 1_000_000)
    private let link = URL(string: "https://example.com/plan")!
    private let chart = URL(string: "https://example.com/chart.png")!

    private final class KeyWindow: NSWindow {
        override var isKeyWindow: Bool { true }
    }

    /// What the window's owner heard, which is all pressing anything in it does.
    private final class Heard {
        var actions: [String] = []
        var copied: [String] = []
        var openedInT3: [String] = []
        var links: [URL] = []
    }

    override func setUp() async throws {
        QuietFocus.fullKeyboardAccess = { false }
    }

    override func tearDown() async throws {
        QuietFocus.fullKeyboardAccess = { NSApplication.shared.isFullKeyboardAccessEnabled }
    }

    // MARK: What's shown

    private func exchange(_ id: String, _ seconds: TimeInterval, ask: String?, reply: String?, notes: Int = 0, failure: String? = nil) -> Exchange {
        Exchange(id: id, asker: .you, askedAt: at.addingTimeInterval(seconds), ask: ask, reply: reply, repliedAt: at.addingTimeInterval(seconds + 1), earlierNotes: notes, failure: failure)
    }

    /// Steve's channel: a thread Steve started, `k`, whose replies are `replies`, and one you started, `y`.
    private func book(replies: [Exchange]? = nil, sent: [SentMessage] = [], reactions: [String: [Reaction]] = [:]) -> ChannelBook {
        let threads = ["k", "y"].map { AgentThread(id: $0, title: $0 == "k" ? "Fonts" : "Pricing", projectTitle: "Steve", status: .completed, model: "m", updatedAt: at, projectPath: steve.folder) }
        let k = [exchange("k0", 0, ask: nil, reply: "Picked a heading font.", notes: 2)] + (replies ?? [exchange("k1", 60, ask: "Show me.", reply: "Here it is.")])
        let y = [exchange("y0", 300, ask: "Can you tidy the pricing page?", reply: "Tidied it.")]
        return ChannelBook.build(kittens: [steve], threads: threads, transcripts: ["k": k, "y": y], isReading: false, unreadable: 0, cantReachT3: false, sent: sent, reactions: reactions)
    }

    /// Messages in a window that's never shown, telling `heard` whatever it's asked to do.
    private func messages(width: CGFloat, keyed: Bool = false) -> (window: NSWindow, view: ChannelsView, heard: Heard) {
        let frame = NSRect(x: 0, y: 0, width: width, height: 640)
        let window = keyed ? KeyWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: true) : NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.autorecalculatesKeyViewLoop = true
        let view = ChannelsView(frame: frame)
        window.contentView = view
        let heard = Heard()
        view.onAction = { heard.actions.append(String(describing: $0)) }
        view.onCopy = { heard.copied.append($0) }
        view.onOpenThread = { heard.openedInT3.append($0) }
        view.onOpenLink = { heard.links.append($0) }
        return (window, view, heard)
    }

    private func showing(_ book: ChannelBook, thread: String? = nil, width: CGFloat = 1100, keyed: Bool = false) -> (window: NSWindow, view: ChannelsView, heard: Heard) {
        let shown = messages(width: width, keyed: keyed)
        shown.view.show(book)
        shown.view.select(thread.map { .thread($0, in: .channel(.of(steve))) } ?? .channel(.of(steve)))
        shown.view.layoutSubtreeIfNeeded()
        shown.heard.actions = []
        return shown
    }

    private func row(_ id: String, in pane: ChannelPane, file: StaticString = #filePath, line: UInt = #line) throws -> MessageRowView {
        try XCTUnwrap(pane.shownMessageRows.first { $0.message.id == id }, "\(id) shows", file: file, line: line)
    }

    private func described(_ action: MessagesAction) -> String { String(describing: action) }

    /// A press and release at `point` in `view`, handed to whatever the window finds there, as `Press.click` does at a
    /// view's centre. Gives back what it landed on.
    @discardableResult
    private func click(at point: NSPoint, in view: NSView, file: StaticString = #filePath, line: UInt = #line) throws -> NSView {
        let window = try XCTUnwrap(view.window, "it's in a window", file: file, line: line)
        window.contentView?.layoutSubtreeIfNeeded()
        let root = try XCTUnwrap(window.contentView?.superview ?? window.contentView, file: file, line: line)
        let spot = view.convert(point, to: nil)
        let target = try XCTUnwrap(root.hitTest(root.convert(spot, from: nil)), "something is under the pointer", file: file, line: line)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: spot, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1), file: file, line: line)
            type == .leftMouseDown ? target.mouseDown(with: event) : target.mouseUp(with: event)
        }
        return target
    }

    /// Tab into the list, then ↑ until the arrow keys are on `row`.
    private func arrow(to row: ChannelRowView, in pane: ChannelPane, file: StaticString = #filePath, line: UInt = #line) throws {
        let window = try XCTUnwrap(pane.window, file: file, line: line)
        XCTAssertTrue(window.makeFirstResponder(pane.list), "the list takes the keyboard", file: file, line: line)
        let up = String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
        for _ in 0..<20 where pane.currentRow !== row {
            try Press.key(up, keyCode: 126, on: pane.list, file: file, line: line)
        }
        XCTAssertTrue(pane.currentRow === row, "↑ comes to it", file: file, line: line)
    }

    /// Whether Tab, from the list's row the arrow keys are on, gets to `control`.
    private func tabs(from list: MessageList, to control: NSView) -> Bool {
        guard let window = list.window, window.makeFirstResponder(list) else { return false }
        for _ in 0..<12 {
            window.selectNextKeyView(nil)
            if window.firstResponder === control { return true }
        }
        return false
    }

    // MARK: The message toolbar

    private struct Case {
        var name: String
        var thread: String?
        var message: String
        var threadOfMessage: String
        var text: String
        /// The widths at which what doesn't fit in its bar goes under More.
        var folds: Set<CGFloat> = []
        var inThreadPane: Bool { thread != nil }
    }

    private var cases: [Case] {
        [
            Case(name: "a kitten's in the channel", thread: nil, message: "k0:reply", threadOfMessage: "k", text: "Picked a heading font."),
            Case(name: "yours in the channel", thread: nil, message: "y0:ask", threadOfMessage: "y", text: "Can you tidy the pricing page?"),
            Case(name: "a kitten's in its thread", thread: "k", message: "k1:reply", threadOfMessage: "k", text: "Here it is.", folds: [820]),
            Case(name: "yours in its thread", thread: "k", message: "k1:ask", threadOfMessage: "k", text: "Show me."),
            // Its name line has earlier notes too, which leave room in a thread's pane for only More.
            Case(name: "a kitten's with earlier notes in its thread", thread: "k", message: "k0:reply", threadOfMessage: "k", text: "Picked a heading font.", folds: [1100, 820]),
        ]
    }

    /// What each of its buttons, and each of More's items, is heard to do.
    private func expectations(_ c: Case, _ view: ChannelsView, _ heard: Heard) -> [String: () -> Bool] {
        [
            CatWords.react: { heard.actions == [self.described(.react(c.message, .eyes))] },
            "Reply": { view.selection.thread == c.threadOfMessage && !view.threadPane.isHidden },
            CatWords.threadTitle: { view.selection.thread == c.threadOfMessage && !view.threadPane.isHidden },
            "Copy": { heard.copied == [c.text] },
            CatWords.markUnread: { heard.actions == [self.described(.markUnread(c.threadOfMessage, from: c.message))] },
            CatWords.openInT3: { heard.openedInT3 == [c.threadOfMessage] },
        ]
    }

    private func setUpCase(_ c: Case, width: CGFloat, keyed: Bool = false) throws -> (NSWindow, ChannelsView, Heard, MessageRowView) {
        let (window, view, heard) = showing(book(reactions: [c.message: []]), thread: c.thread, width: width, keyed: keyed)
        let row = try row(c.message, in: c.inThreadPane ? view.threadPane : view.pane)
        return (window, view, heard, row)
    }

    func testEachButtonInAMessagesBarDoesWhatItSaysWhereverTheMessageIs() throws {
        for c in cases {
            for width: CGFloat in [1100, 820] {
                let names = try setUpCase(c, width: width).3.toolbarNames
                let wanted = c.inThreadPane ? [CatWords.react, "Copy", CatWords.markUnread, CatWords.openInT3] : [CatWords.react, "Reply", "Copy", CatWords.markUnread, CatWords.openInT3]
                XCTAssertEqual(names, wanted, "\(c.name), \(Int(width)) wide")
                XCTAssertEqual(try setUpCase(c, width: width).3.foldsUnderMore, c.folds.contains(width), "\(c.name), \(Int(width)) wide: whether some go under More")
                for name in names {
                    let label = "\(c.name), \(Int(width)) wide, \(name)"
                    let (_, view, heard, row) = try setUpCase(c, width: width)
                    row.hovering = true
                    let toolbar = try XCTUnwrap(row.toolbar, label)
                    let button = try XCTUnwrap(toolbar.button(name), label)
                    let menu = try XCTUnwrap(row.menu(for: NSEvent()), label)
                    if button.isHidden {
                        XCTAssertTrue(try Press.hit(toolbar.more) === toolbar.more, "\(label): folded under More, and a click lands on More")
                    } else if name == CatWords.react {
                        XCTAssertTrue(try Press.hit(button) === button, "\(label): a click lands on React")
                    } else {
                        XCTAssertTrue(try Press.click(button) === button, "\(label): the click lands on it")
                    }
                    // React and More open a menu, whose own loop would hold the test, so their items are chosen from
                    // the same menu, which is the one a right-click opens.
                    if name == CatWords.react {
                        let marks = try XCTUnwrap(menu.item(withTitle: CatWords.react)?.submenu, label)
                        marks.performActionForItem(at: marks.indexOfItem(withTitle: Reaction.eyes.emoji))
                    } else if button.isHidden {
                        menu.performActionForItem(at: menu.indexOfItem(withTitle: name))
                    }
                    XCTAssertTrue(try XCTUnwrap(expectations(c, view, heard)[name])(), "\(label): did what it says, heard \(heard.actions) copied \(heard.copied)")
                }
            }
        }
    }

    func testEveryItemInMoresMenuDoesWhatItSays() throws {
        for c in cases {
            for width: CGFloat in [1100, 820] {
                let titles = try XCTUnwrap(try setUpCase(c, width: width).3.menu(for: NSEvent())).items.map(\.title)
                let wanted = c.inThreadPane ? [CatWords.openInT3, CatWords.markUnread, "Copy", CatWords.react] : [CatWords.threadTitle, "Reply", CatWords.openInT3, CatWords.markUnread, "Copy", CatWords.react]
                XCTAssertEqual(titles, wanted, "\(c.name), \(Int(width)) wide: everything its bar does, and the thread for a parent")
                for title in titles {
                    let label = "\(c.name), \(Int(width)) wide, More's \(title)"
                    let (_, view, heard, row) = try setUpCase(c, width: width)
                    let menu = try XCTUnwrap(row.menu(for: NSEvent()), label)
                    if title == CatWords.react {
                        let marks = try XCTUnwrap(menu.item(withTitle: title)?.submenu, "\(label): the marks are a menu inside it")
                        marks.performActionForItem(at: marks.indexOfItem(withTitle: Reaction.eyes.emoji))
                    } else {
                        menu.performActionForItem(at: menu.indexOfItem(withTitle: title))
                    }
                    XCTAssertTrue(try XCTUnwrap(expectations(c, view, heard)[title], label)(), "\(label): did what it says")
                }
            }
        }
    }

    func testTabReachesEachButtonInABarAndSpacePressesIt() throws {
        QuietFocus.fullKeyboardAccess = { true }
        for c in cases {
            for width: CGFloat in [1100, 820] {
                let names = try setUpCase(c, width: width, keyed: true).3.toolbarNames
                for name in names {
                    let label = "\(c.name), \(Int(width)) wide, \(name)"
                    let (_, view, heard, row) = try setUpCase(c, width: width, keyed: true)
                    let pane = c.inThreadPane ? view.threadPane : view.pane
                    try arrow(to: row, in: pane)
                    let toolbar = try XCTUnwrap(row.toolbar, label)
                    let button = try XCTUnwrap(toolbar.button(name), label)
                    guard !button.isHidden else {
                        XCTAssertTrue(tabs(from: pane.list, to: toolbar.more), "\(label): folded under More, which Tab reaches")
                        continue
                    }
                    XCTAssertTrue(tabs(from: pane.list, to: button), "\(label): Tab reaches it")
                    // Space on React opens its menu, which the mouse test chooses from.
                    guard name != CatWords.react else { continue }
                    try Press.key(" ", keyCode: 49, on: button)
                    XCTAssertTrue(try XCTUnwrap(expectations(c, view, heard)[name])(), "\(label): Space did what it says")
                }
            }
        }
    }

    // MARK: Reactions

    func testPressingAReactionTakesItOffAndTheButtonAfterThemAddsOne() throws {
        for width: CGFloat in [1100, 820] {
            for keyboard in [false, true] {
                let label = "\(Int(width)) wide, by \(keyboard ? "keyboard" : "mouse")"
                QuietFocus.fullKeyboardAccess = { keyboard }
                let (_, view, heard) = showing(book(reactions: ["k0:reply": [.thumbsUp, .check]]), width: width, keyed: keyboard)
                let row = try row("k0:reply", in: view.pane)
                let chip = try XCTUnwrap(row.ownButtons.first { $0.accessibilityLabel() == "✅" }, label)
                let add = try XCTUnwrap(row.ownButtons.first { $0.accessibilityLabel() == CatWords.react }, "\(label): a way to add one after them")
                if keyboard {
                    try arrow(to: row, in: view.pane)
                    XCTAssertTrue(tabs(from: view.pane.list, to: chip), "\(label): Tab reaches a reaction")
                    try Press.key(" ", keyCode: 49, on: chip)
                    XCTAssertTrue(tabs(from: view.pane.list, to: add), "\(label): and the button after them")
                } else {
                    XCTAssertTrue(try Press.click(chip) === chip, "\(label): the click lands on the reaction")
                    XCTAssertTrue(try Press.hit(add) === add, "\(label): a click lands on the button after them")
                }
                XCTAssertEqual(heard.actions, [described(.react("k0:reply", .check))], "\(label): pressing it takes it off")
                // Its menu would hold the test in its own loop, so its mark is chosen from the same marks.
                let marks = try XCTUnwrap(row.menu(for: NSEvent())?.item(withTitle: CatWords.react)?.submenu, label)
                XCTAssertEqual(marks.items.filter { $0.state == .on }.map(\.title), ["👍", "✅"], "\(label): the ones it has are ticked")
                marks.performActionForItem(at: marks.indexOfItem(withTitle: Reaction.tada.emoji))
                XCTAssertEqual(heard.actions.last, described(.react("k0:reply", .tada)), label)
            }
        }
    }

    // MARK: Opening a thread from the channel

    func testPressingAParentsReplyBarOpensItsThread() throws {
        for width: CGFloat in [1100, 820] {
            let (_, view, _) = showing(book(), width: width)
            let row = try row("k0:reply", in: view.pane)
            // The bar is drawn at the bottom of the row, under where its bubble starts.
            let bar = NSPoint(x: ChannelRowView.textLeft + 12, y: row.bounds.maxY - 5 - ReplyBar.height / 2)
            XCTAssertTrue(try click(at: bar, in: row) === row, "\(Int(width)) wide: a click on the bar lands on the message")
            XCTAssertEqual(view.selection, .thread("k", in: .channel(.of(steve))), "\(Int(width)) wide")
            XCTAssertFalse(view.threadPane.isHidden)
        }
    }

    func testPressingAReplyAlsoSentToTheChannelOpensItsThread() throws {
        let also = SentMessage(channel: .of(steve), message: ChannelMessage(exchangeID: "s1", kind: .ask, speaker: .you, text: "Keep the FAQ as it is.", at: at.addingTimeInterval(120), threadID: "k", threadTitle: ""), alsoSent: true, isReply: true)
        for width: CGFloat in [1100, 820] {
            let (_, view, _) = showing(book(sent: [also]), width: width)
            let row = try row("s1:ask", in: view.pane)
            XCTAssertEqual(row.context, CatWords.repliedToThread("Picked a heading font."))
            let context = NSPoint(x: row.bounds.width - ChannelRowView.margin - 40, y: 5 + MessagesInk.meta / 2 + 2)
            XCTAssertTrue(try click(at: context, in: row) === row, "\(Int(width)) wide: a click on \"replied to a thread\" lands on the message")
            XCTAssertEqual(view.selection, .thread("k", in: .channel(.of(steve))), "\(Int(width)) wide")
        }
    }

    func testSpaceOnAParentOpensItsThreadAndTheArrowKeysMoveBetweenMessages() throws {
        QuietFocus.fullKeyboardAccess = { true }
        let (_, view, _) = showing(book(), keyed: true)
        let pane = view.pane
        let newest = try row("y0:ask", in: pane)
        let older = try row("k0:reply", in: pane)
        XCTAssertTrue(pane.window?.makeFirstResponder(pane.list) == true)
        XCTAssertTrue(pane.currentRow === newest, "Tab into a channel lands on its newest message")
        try Press.key(String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)), keyCode: 126, on: pane.list)
        XCTAssertTrue(pane.currentRow === older, "↑ goes to the one before")
        try Press.key(String(Character(UnicodeScalar(NSDownArrowFunctionKey)!)), keyCode: 125, on: pane.list)
        XCTAssertTrue(pane.currentRow === newest, "↓ comes back")
        try Press.key(String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)), keyCode: 126, on: pane.list)
        try Press.key(" ", keyCode: 49, on: pane.list)
        XCTAssertEqual(view.selection, .thread("k", in: .channel(.of(steve))), "Space opens the thread of the parent it's on")
    }

    func testCommandCCopiesTheMessageTheArrowKeysAreOn() throws {
        QuietFocus.fullKeyboardAccess = { true }
        let (window, view, heard) = showing(book(), thread: "k", keyed: true)
        let row = try row("k1:reply", in: view.threadPane)
        try arrow(to: row, in: view.threadPane)
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "c", charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8))
        // The panel sends an Edit key to whatever has the keyboard, as `NSApp.sendAction` does in the key window.
        let action = try XCTUnwrap(QuietPanel.editAction(for: event))
        XCTAssertTrue(window.firstResponder?.tryToPerform(action, with: window) == true, "the list takes ⌘C")
        XCTAssertEqual(heard.copied, ["Here it is."])
    }

    // MARK: Earlier notes

    func testEarlierNotesBesideAKittensNameOpenTheThreadInT3() throws {
        let size = MessagesInk.textSize
        defer { MessagesInk.textSize = size }
        for textSize in TextSize.allCases {
            MessagesInk.textSize = textSize
            for (width, thread) in [(1100, nil), (820, nil), (1100, "k"), (820, "k")] as [(CGFloat, String?)] {
                let label = "\(Int(width)) wide, \(thread == nil ? "in the channel" : "in its thread"), \(textSize) text"
                let (_, view, heard) = showing(book(), thread: thread, width: width)
                let row = try row("k0:reply", in: thread == nil ? view.pane : view.threadPane)
                let notes = try XCTUnwrap(try linkWords(in: row), "\(label): \"2 earlier notes\" is drawn in the link's colour")
                XCTAssertTrue(try click(at: notes, in: row) === row, "\(label): the click lands on the message")
                XCTAssertEqual(heard.openedInT3, ["k"], "\(label): they open the thread in T3, the only place they are")
                XCTAssertTrue(thread != nil || view.threadPane.isHidden, "\(label): and don't open the thread's pane as well")
            }
        }
    }

    /// The middle of the words drawn in the link's colour on the row's name line, as the row draws itself.
    private func linkWords(in row: MessageRowView) throws -> NSPoint? {
        let rep = try XCTUnwrap(row.bitmapImageRepForCachingDisplay(in: row.bounds))
        row.cacheDisplay(in: row.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / row.bounds.width
        let link = try XCTUnwrap(MessagesInk.link.usingColorSpace(.sRGB))
        let line = (5 + 1) * scale..<(5 + 1 + MessagesInk.meta + 4) * scale
        let columns = (0..<rep.pixelsWide).filter { x in
            stride(from: Int(line.lowerBound), to: Int(line.upperBound), by: 1).contains { y in
                guard let pixel = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), pixel.alphaComponent > 0.6 else { return false }
                return abs(pixel.redComponent - link.redComponent) + abs(pixel.greenComponent - link.greenComponent) + abs(pixel.blueComponent - link.blueComponent) < 0.25
            }
        }
        guard let first = columns.first, let last = columns.last else { return nil }
        return NSPoint(x: CGFloat(first + last) / 2 / scale, y: (line.lowerBound + line.upperBound) / 2 / scale)
    }

    // MARK: In a message's words

    func testACodeBlocksCopyCopiesItsCode() throws {
        for keyboard in [false, true] {
            QuietFocus.fullKeyboardAccess = { keyboard }
            let replies = [exchange("k1", 60, ask: "Show me the settings.", reply: "Here:\n\n```\nfont: Inter\n```")]
            let (_, view, heard) = showing(book(replies: replies), thread: "k", keyed: keyboard)
            let row = try row("k1:reply", in: view.threadPane)
            let copy = try XCTUnwrap(row.codeButtons.first)
            if keyboard {
                try arrow(to: row, in: view.threadPane)
                XCTAssertTrue(tabs(from: view.threadPane.list, to: copy), "Tab reaches it")
                try Press.key(" ", keyCode: 49, on: copy)
            } else {
                // Words under the pointer would start a selection, whose own loop waits for a real release.
                let hit = try Press.hit(copy)
                XCTAssertTrue(hit === copy, "the click lands on the code block's Copy, not on \(type(of: hit)) over it")
                guard hit === copy else { continue }
                try Press.click(copy)
            }
            XCTAssertEqual(heard.copied, ["font: Inter"], "by \(keyboard ? "keyboard" : "mouse")")
        }
    }

    func testALinkShowsWhereItGoesAndOnlyOpenOpensIt() throws {
        let replies = [exchange("k1", 60, ask: "Where's the plan?", reply: "[The plan](https://example.com/plan)")]
        for width: CGFloat in [1100, 820] {
            for keyboard in [false, true] {
                for pressing in [CatWords.openLink, "Cancel"] {
                    let label = "\(Int(width)) wide, \(pressing) by \(keyboard ? "keyboard" : "mouse")"
                    QuietFocus.fullKeyboardAccess = { keyboard }
                    let (window, view, heard) = showing(book(replies: replies), thread: "k", width: width, keyed: keyboard)
                    let pane = view.threadPane
                    let words = try XCTUnwrap(try row("k1:reply", in: pane).subviews.compactMap { $0 as? ChannelTextView }.first, label)
                    let centre = NSPoint(x: words.bounds.midX, y: words.bounds.midY)
                    XCTAssertTrue(try Press.hit(words) === words, "\(label): the click lands on the link's words")
                    XCTAssertEqual(words.link(at: centre), link, "\(label): and on the link, so no selection starts")
                    guard words.link(at: centre) != nil else { continue }
                    try Press.click(words)
                    XCTAssertEqual(pane.linkBar.link, link, "\(label): the bar shows where it goes")
                    XCTAssertTrue(heard.links.isEmpty, "\(label): and nothing opens yet")
                    view.layoutSubtreeIfNeeded()
                    let button = pressing == CatWords.openLink ? pane.linkBar.open : pane.linkBar.cancel
                    if keyboard {
                        window.makeFirstResponder(pane.list)
                        XCTAssertTrue(tabs(from: pane.list, to: button), "\(label): Tab reaches it")
                        try Press.key(" ", keyCode: 49, on: button)
                    } else {
                        XCTAssertTrue(try Press.click(button) === button, "\(label): the click lands on it")
                    }
                    XCTAssertEqual(heard.links, pressing == CatWords.openLink ? [link] : [], label)
                    XCTAssertTrue(pane.linkBar.isHidden, "\(label): and the bar goes")
                }
            }
        }
    }

    func testAWebPictureAsksFirstAndShowFetchesIt() throws {
        let replies = [exchange("k1", 60, ask: "And the chart?", reply: "![Chart](https://example.com/chart.png)")]
        for keyboard in [false, true] {
            let label = "by \(keyboard ? "keyboard" : "mouse")"
            QuietFocus.fullKeyboardAccess = { keyboard }
            let (_, view, heard) = showing(book(replies: replies), thread: "k", keyed: keyboard)
            let pane = view.threadPane
            let row = try row("k1:reply", in: pane)
            let picture = try XCTUnwrap(row.ownButtons.first { $0.accessibilityLabel()?.contains("example.com") == true }, label)
            if keyboard {
                try arrow(to: row, in: pane)
                XCTAssertTrue(tabs(from: pane.list, to: picture), "\(label): Tab reaches the picture")
                try Press.key(" ", keyCode: 49, on: picture)
            } else {
                XCTAssertTrue(try Press.click(picture) === picture, "\(label): the click lands on the picture")
            }
            XCTAssertEqual(pane.linkBar.link, chart, "\(label): the bar shows its whole address")
            XCTAssertEqual(pane.linkBar.open.accessibilityLabel(), CatWords.showPicture)
            XCTAssertTrue(heard.actions.isEmpty, "\(label): nothing's fetched yet")
            view.layoutSubtreeIfNeeded()
            if keyboard {
                XCTAssertTrue(tabs(from: pane.list, to: pane.linkBar.open), "\(label): Tab reaches Show")
                try Press.key(" ", keyCode: 49, on: pane.linkBar.open)
            } else {
                XCTAssertTrue(try Press.click(pane.linkBar.open) === pane.linkBar.open, "\(label): the click lands on Show")
            }
            XCTAssertEqual(heard.actions, [described(.showPicture(chart))], label)
        }
    }

    // MARK: Under a message

    func testShowMoreShowsTheWholeOfALongMessage() throws {
        let long = (1...60).map { "Line \($0) of something long." }.joined(separator: "\n")
        for keyboard in [false, true] {
            QuietFocus.fullKeyboardAccess = { keyboard }
            let (_, view, _) = showing(book(replies: [exchange("k1", 60, ask: "Tell me everything.", reply: long)]), thread: "k", keyed: keyboard)
            let pane = view.threadPane
            let row = try row("k1:reply", in: pane)
            XCTAssertTrue(row.isCut)
            let more = try XCTUnwrap(row.ownButtons.first { $0.accessibilityLabel() == "Show more" })
            let before = row.frame.height
            if keyboard {
                try arrow(to: row, in: pane)
                XCTAssertTrue(tabs(from: pane.list, to: more), "Tab reaches Show more")
                try Press.key(" ", keyCode: 49, on: more)
            } else {
                pane.scrollOffset = max(row.frame.maxY - pane.visibleHeight, 0)
                XCTAssertTrue(try Press.click(more) === more, "the click lands on Show more")
            }
            XCTAssertFalse(row.isCut, "by \(keyboard ? "keyboard" : "mouse"): all of it shows")
            XCTAssertGreaterThan(row.frame.height, before)
            XCTAssertTrue(more.isHidden, "and Show more goes")
        }
    }

    func testTryAgainSendsWordsThatWentNowhereAgain() throws {
        let failed = SentMessage(channel: .of(steve), message: ChannelMessage(exchangeID: "s2", kind: .ask, speaker: .you, text: "Ship it today?", at: at.addingTimeInterval(900), threadID: "", threadTitle: "", failure: "Couldn't send it."))
        for keyboard in [false, true] {
            QuietFocus.fullKeyboardAccess = { keyboard }
            let (_, view, heard) = showing(book(sent: [failed]), keyed: keyboard)
            let row = try row("s2:ask", in: view.pane)
            let again = try XCTUnwrap(row.ownButtons.first { $0.accessibilityLabel() == "Try again" })
            if keyboard {
                try arrow(to: row, in: view.pane)
                XCTAssertTrue(tabs(from: view.pane.list, to: again), "Tab reaches Try again")
                try Press.key(" ", keyCode: 49, on: again)
            } else {
                XCTAssertTrue(try Press.click(again) === again, "the click lands on Try again")
            }
            XCTAssertEqual(heard.actions, [described(.tryAgain("s2"))], "by \(keyboard ? "keyboard" : "mouse")")
        }
    }
}

private extension MessageRowView {
    /// Its own buttons, under and beside its words, rather than its bar's.
    var ownButtons: [QuietButton] { subviews.compactMap { $0 as? QuietButton } }

    /// The names on its bar, made as pointing at it makes them.
    var toolbarNames: [String] {
        hovering = true
        return toolbar?.buttons.map { $0.accessibilityLabel() ?? "" } ?? []
    }

    var foldsUnderMore: Bool {
        hovering = true
        return toolbar?.more.isHidden == false
    }
}
