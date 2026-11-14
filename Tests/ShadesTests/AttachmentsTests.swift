import AppKit
@testable import Shades
import ShadesContext
import ShadesCore
import XCTest

@MainActor
final class AttachmentsTests: XCTestCase {
    private let steve = Kitten(name: "Steve", role: "Professional", covers: "", folder: "/k/steve")
    private let at = Date(timeIntervalSince1970: 1_000_000)

    private func png(_ side: Int = 8) -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return bitmap.representation(using: .png, properties: [:])!
    }

    private func book(ask: String = "Ask", files: [ExchangeFile] = [], reply: String = "Reply") -> ChannelBook {
        let thread = AgentThread(id: "t", title: "Work", projectTitle: "Steve", status: .completed, model: "m", updatedAt: at, projectPath: "/k/steve")
        let said = [Exchange(id: "e", asker: .you, askedAt: at, ask: ask, reply: reply, repliedAt: at, files: files)]
        return ChannelBook.build(kittens: [steve], threads: [thread], transcripts: ["t": said], isReading: false, unreadable: 0, cantReachT3: false)
    }

    // MARK: - What a reply can point at

    /// A reply is untrusted, so the only paths it can name are asked of T3 as ones in its own thread's folder.
    func testAReplyCanOnlyPointAtAPictureInItsOwnFolderOrOnTheWeb() {
        func source(_ text: String) -> PictureSource? { PictureSource(URL(string: text)!, inThread: "t") }
        XCTAssertEqual(source("out/chart%20one.png"), .workspace(threadID: "t", path: "out/chart one.png"))
        XCTAssertEqual(source("/Users/someone/wt/shot.JPG"), .workspace(threadID: "t", path: "/Users/someone/wt/shot.JPG"), "T3 keeps a full path to the thread's folder too")
        XCTAssertEqual(source("file:///tmp/a.png"), .workspace(threadID: "t", path: "/tmp/a.png"))
        XCTAssertEqual(source("https://example.com/a.png?x=1"), .web(URL(string: "https://example.com/a.png?x=1")!))
        XCTAssertNil(source("../other/secret.png"), "never out of the folder")
        XCTAssertNil(source("out/../../secret.png"))
        XCTAssertNil(source("notes.txt"), "only pictures")
        XCTAssertNil(source("out/page.html"), "T3 serves pages too, which aren't pictures")
        XCTAssertNil(source("javascript:alert(1)"))
        XCTAssertNil(source("t3code://threads/x.png"))
        XCTAssertNil(source("https://someone@example.com/a.png"), "a name before the host could hide where it goes")
        XCTAssertNil(PictureSource(URL(string: "a.png")!, inThread: ""), "a message with no thread has no folder")
    }

    func testOnlyAPublicWebAddressCanBeFetched() {
        for address in ["https://example.com/a.png", "http://images.example.org/b.jpg", "https://8.8.8.8/x.png"] {
            XCTAssertTrue(WebPicture.isPublic(URL(string: address)!), address)
        }
        for address in [
            "http://localhost:3773/api/assets/x", "http://127.0.0.1/a.png", "http://10.0.0.2/a.png", "http://192.168.1.1/a.png",
            "http://172.20.0.1/a.png", "http://169.254.169.254/latest", "http://100.101.102.103/a.png", "https://my-mac.tail1234.ts.net/a.png",
            "http://printer.local/a.png", "http://[::1]/a.png", "http://intranet/a.png", "file:///etc/hosts", "https://user@example.com/a.png",
        ] {
            XCTAssertFalse(WebPicture.isPublic(URL(string: address)!), address)
        }
    }

    /// A name anyone can register can lead to this Mac, so every address it leads to has to be on the web too.
    func testEveryAddressANameLeadsToHasToBeOnTheWeb() {
        XCTAssertTrue(WebPicture.isPublic(address: [93, 184, 215, 14]))
        for local in [[127, 0, 0, 1], [10, 1, 2, 3], [192, 168, 0, 9], [172, 16, 0, 1], [169, 254, 1, 1], [100, 100, 1, 1], [0, 0, 0, 0], [239, 1, 1, 1]] as [[UInt8]] {
            XCTAssertFalse(WebPicture.isPublic(address: local), "\(local)")
        }
        let loopback6 = [UInt8](repeating: 0, count: 15) + [1]
        let mappedLoopback = [UInt8](repeating: 0, count: 10) + [0xff, 0xff, 127, 0, 0, 1]
        let linkLocal: [UInt8] = [0xfe, 0x80] + [UInt8](repeating: 0, count: 13) + [1]
        let uniqueLocal: [UInt8] = [0xfd, 0x7a] + [UInt8](repeating: 1, count: 14)
        for local in [loopback6, mappedLoopback, linkLocal, uniqueLocal, [UInt8](repeating: 0, count: 16), []] {
            XCTAssertFalse(WebPicture.isPublic(address: local), "\(local)")
        }
        XCTAssertTrue(WebPicture.isPublic(address: [0x26, 0x06, 0x28, 0x00] + [UInt8](repeating: 0, count: 11) + [1]))
    }

    func testAReplysPicturesShowUnderItAndTheWordsKeepTheirDescriptions() throws {
        let reply = "Here it is:\n\n![Sales chart](out/chart.png)\n\n![](https://example.com/b.png) and ![nope](../x.png)"
        let message = try XCTUnwrap(book(reply: reply).threads["t"]?.replies.first)
        XCTAssertEqual(message.files.map(\.name), ["Sales chart", "b.png"])
        XCTAssertEqual(message.files.map(\.source), [.workspace(threadID: "t", path: "out/chart.png"), .web(URL(string: "https://example.com/b.png")!)])
        let words = Markup(reply).blocks.compactMap(\.spans).flatMap { $0 }.map(\.text).joined()
        XCTAssertTrue(words.contains("Sales chart"))
        XCTAssertFalse(words.contains("\u{FFFC}"), "a picture with no description leaves nothing in the words")
    }

    // MARK: - The shelf

    /// After a restart, what you sent was its name alone, though T3 keeps each picture.
    func testWhatYouSentComesBackFromT3AndAReplysPictureFromItsFolder() async throws {
        var asked: [PictureSource] = []
        let copy = png()
        let shelf = PictureShelf { source in
            asked.append(source)
            return source == .sent(attachmentID: "att-1") || source == .workspace(threadID: "t", path: "out/chart.png") ? copy : nil
        }
        var changed = 0
        shelf.onChange = { changed += 1 }
        let files = [ExchangeFile(name: "keyboard.png", attachmentID: "att-1"), ExchangeFile(name: "syllabus.pdf")]
        let reply = "![chart](out/chart.png) ![gone](out/gone.png) ![web](https://example.com/w.png)"
        var first = book(files: files, reply: reply)
        shelf.fill(&first)
        while changed < 2 { await Task.yield() }
        XCTAssertEqual(Set(asked), [.sent(attachmentID: "att-1"), .workspace(threadID: "t", path: "out/chart.png"), .workspace(threadID: "t", path: "out/gone.png")], "nothing on the web until you press Show")

        var again = book(files: files, reply: reply)
        shelf.fill(&again)
        let thread = try XCTUnwrap(again.threads["t"])
        XCTAssertEqual(thread.parent.files.map(\.thumbnail), [copy, nil], "a PDF stays its name")
        XCTAssertEqual(thread.replies.first?.files.map(\.name), ["chart", "web"], "a picture T3 wouldn't give comes off, and its description stays in the words")
        XCTAssertEqual(thread.replies.first?.files.first?.thumbnail, copy)
        XCTAssertNil(thread.replies.first?.files.last?.thumbnail)
        XCTAssertEqual(asked.count, 3, "each is asked for once")
    }

    /// Past what the shelf keeps, it let go of a picture still on screen, fetched it again, and let go of the next.
    func testAShelfFullerThanItKeepsFetchesEachPictureOnce() async {
        let files = (0..<310).map { ExchangeFile(name: "\($0).png", attachmentID: "att-\($0)") }
        var fetches = 0
        let copy = png()
        let shelf = PictureShelf { _ in
            fetches += 1
            return copy
        }
        // Each change publishes the book again, as the feed does.
        shelf.onChange = { [unowned shelf] in
            var again = self.book(files: files)
            shelf.fill(&again)
        }
        var first = book(files: files)
        shelf.fill(&first)
        for _ in 0..<3_000 { await Task.yield() }
        XCTAssertEqual(fetches, 310, "each picture is fetched once")
    }

    func testAWebPictureIsFetchedOnlyOncePressedAndSaysSoIfItDoesntCome() async throws {
        var asked: [PictureSource] = []
        let shelf = PictureShelf { source in
            asked.append(source)
            return nil
        }
        var changed = false
        shelf.onChange = { changed = true }
        let link = URL(string: "https://example.com/w.png")!
        var shown = book(reply: "![web](https://example.com/w.png)")
        shelf.fill(&shown)
        await Task.yield()
        XCTAssertTrue(asked.isEmpty)
        shelf.show(link)
        while !changed { await Task.yield() }
        XCTAssertEqual(asked, [.web(link)])
        shelf.fill(&shown)
        XCTAssertEqual(shown.threads["t"]?.replies.first?.files.first?.couldntShow, true)
    }

    // MARK: - Sending several

    func testSeveralFilesGoAsOneWithEveryNameAndEachPictureByItsOwn() throws {
        let pdf = try XCTUnwrap(Demo.samplePDF())
        let snapshot = try XCTUnwrap(Drop.snapshot(of: [.bytes(png(), name: "keyboard.png"), .file(pdf), .bytes(png(16), name: "desk.png")]))
        XCTAssertEqual(snapshot.droppedNames, ["keyboard.png", "syllabus.pdf", "desk.png"])
        XCTAssertEqual(snapshot.pictures.map(\.name), ["keyboard.png", "desk.png"])
        XCTAssertEqual(snapshot.screenshotJPEG, snapshot.pictures.first?.data)
        XCTAssertTrue(snapshot.pageText?.hasPrefix("syllabus.pdf:\n") == true, "each PDF's text under its name")
        XCTAssertNil(Drop.snapshot(of: [.bytes(png(), name: "keyboard.png"), .bytes(Data("notes".utf8), name: "notes.txt")]), "one that can't be read stops them all")
    }

    func testAPhoneSendsSeveralFilesOnlyByWhatItUploaded() throws {
        let thread = AgentThread(id: "t", title: "Work", projectTitle: "Steve", status: .completed, model: "m", updatedAt: at, runtimeMode: .auto, projectPath: "/k/steve")
        let book = ChannelBook.build(kittens: [steve], threads: [thread], transcripts: ["t": [Exchange(id: "e", asker: .you, askedAt: at, ask: "Ask")]], isReading: false, unreadable: 0, cantReachT3: false)
        let key = PhonePlace.key(.thread("t", in: .channel(.of(steve))))
        let uploads: [String: Drop] = ["a": .bytes(png(), name: "a.jpg"), "b": .bytes(png(), name: "b.jpg")]
        func ask(_ files: [String]) -> MessagesAction? {
            PhoneAsk(act: "send", key: key, text: "Look", files: files).action(in: book, newTopic: { "new" }, file: { uploads[$0] })?.action
        }
        guard case .send(_, _, _, _, let files, _) = ask(["a", "b"]) else { return XCTFail("both go") }
        XCTAssertEqual(files.map(\.name), ["a.jpg", "b.jpg"])
        XCTAssertNil(ask(["a", "made-up"]), "one it never sent stops the message")
        XCTAssertNil(ask(["a", "a"]), "nor the same one twice")
    }

    /// Show named a picture by its place, which moves when a picture before it comes off, so another could be fetched.
    func testAPhoneCanOnlyAskForAWebPictureOnAMessageMessagesShowsByTheAddressItShowed() throws {
        let book = book(reply: "![chart](out/missing.png) ![a](https://a.example.com/a.png) ![c](https://c.example.com/c.png)")
        let reply = try XCTUnwrap(book.threads["t"]?.replies.first)
        func ask(_ id: String, _ address: String) -> MessagesAction? {
            PhoneAsk(act: "picture", id: id, value: address).action(in: book, newTopic: { "new" })?.action
        }
        XCTAssertEqual(ask(reply.id, "https://a.example.com/a.png"), .showPicture(URL(string: "https://a.example.com/a.png")!))
        XCTAssertNil(ask(reply.id, "out/missing.png"), "a picture in a folder isn't fetched this way")
        XCTAssertNil(ask(reply.id, "https://elsewhere.example.com/x.png"), "only an address the message shows")
        XCTAssertNil(ask("made-up", "https://a.example.com/a.png"))
    }

    /// A thread of the cat's own work can be shown on the phone, but its folder can hold a copy of your screen, and what
    /// you sent in it counts as your screen, so the phone gets only its words.
    func testTheCatsOwnWorkShownOnThePhoneHasNoPictures() throws {
        let work = AgentThread(id: "fix", title: "Fix: the logo", projectTitle: nil, status: .completed, model: "m", updatedAt: at)
        let said = [Exchange(id: "e", asker: .you, askedAt: at, ask: "Fix the logo", reply: "Done. ![after](shot.png) ![before](https://example.com/b.png)", repliedAt: at, files: [ExchangeFile(name: "logo.png", attachmentID: "att-1")])]
        var book = ChannelBook.build(kittens: [steve], threads: [work], transcripts: ["fix": said], isReading: false, unreadable: 0, cantReachT3: false, catsWork: ["fix"], onPhone: ["fix"], hasPhone: true)
        let copy = png()
        PictureShelf { _ in copy }.fill(&book)
        XCTAssertEqual(book.threads["fix"]?.messages.flatMap(\.files).count, 3, "the Mac shows them")
        let page = PhonePlace.key(.thread("fix", in: .channel(.shades)))
        let view = PhoneView(PhonePlace(page, in: book), in: book, now: at)
        XCTAssertFalse(view.rows.isEmpty, "the thread is on the phone")
        XCTAssertTrue(view.rows.allSatisfy { $0.files == nil }, "but none of its pictures")
        let reply = try XCTUnwrap(book.threads["fix"]?.replies.first)
        XCTAssertNil(PhoneAsk(act: "picture", id: reply.id, value: "https://example.com/b.png").action(in: book, newTopic: { "new" }), "nor can a phone have the Mac fetch one")
    }

    /// Every photo from an iPhone's camera is called image.jpg, so two sent together both showed the first.
    func testEachPictureKeepsItsOwnSmallCopyWhenTwoShareAName() throws {
        let (red, blue) = (png(4), png(6))
        let thread = AgentThread(id: "t", title: "Work", projectTitle: "Steve", status: .completed, model: "m", updatedAt: at, projectPath: "/k/steve")
        let sent = SentMessage(channel: .of(steve), message: ChannelMessage(exchangeID: "sent-1", kind: .ask, speaker: .you, text: "These two", at: at, threadID: "t", threadTitle: "", files: [ChannelFile(name: "image.jpg", thumbnail: red), ChannelFile(name: "image.jpg", thumbnail: blue)]), isReply: true)
        let heard = Exchange(id: "e", asker: .you, askedAt: at.addingTimeInterval(1), ask: "These two", files: [ExchangeFile(name: "image.jpg", attachmentID: "a1"), ExchangeFile(name: "image.jpg", attachmentID: "a2")])
        let book = ChannelBook.build(kittens: [steve], threads: [thread], transcripts: ["t": [heard]], isReading: false, unreadable: 0, cantReachT3: false, sent: [sent])
        XCTAssertEqual(book.threads["t"]?.messages.last?.files.map(\.thumbnail), [red, blue])
    }

    // MARK: - On the Mac

    func testRecentFilesLeaveOutWhatsHiddenAndKeepTheNewest() {
        let home = URL(fileURLWithPath: "/Users/someone")
        func file(_ path: String, _ minutes: Double) -> (url: URL, used: Date) { (home.appendingPathComponent(path), at.addingTimeInterval(minutes * 60)) }
        let kept = RecentFiles.kept([
            file("Desktop/old.png", 1), file("Downloads/new.pdf", 9), file("Library/Application Support/shades/captures/x.jpg", 10),
            file(".t3/userdata/attachments/y.jpg", 11), file("code/.git/z.png", 12), file("Pictures/mid.jpg", 5),
        ], home: home)
        XCTAssertEqual(kept.map(\.lastPathComponent), ["new.pdf", "mid.jpg", "old.png"])
        XCTAssertEqual(RecentFiles.kept((0..<30).map { file("Desktop/\($0).png", Double($0)) }, home: home).count, RecentFiles.shown)
        let menu = RecentFiles().items(kept)
        XCTAssertEqual(menu.prefix(3).map(\.title), ["new.pdf", "mid.jpg", "old.png"])
        XCTAssertEqual(RecentFiles().items([]).first?.title, CatWords.noRecentFiles)
    }

    func testTheBoxHoldsSeveralFilesForWhereTheyWereAttachedOnly() {
        let composer = ChannelComposer(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
        composer.show(.thread(id: "t", title: "Work", report: nil))
        XCTAssertTrue(composer.attach([.bytes(png(), name: "a.png"), .bytes(png(), name: "b.png"), .link(URL(string: "https://example.com")!)]))
        XCTAssertEqual(composer.attachments.map(\.name), ["a.png", "b.png"], "a link is words, not a file")
        XCTAssertTrue(composer.attach((0..<20).map { .bytes(png(), name: "\($0).png") }))
        XCTAssertEqual(composer.attachments.count, Drop.mostAtOnce)
        composer.show(.thread(id: "u", title: "Other", report: nil))
        XCTAssertTrue(composer.attachments.isEmpty, "they never follow the box somewhere else")
        composer.show(.router)
        composer.attach([.bytes(png(), name: "cat.png")])
        composer.show(.newThread(steve))
        XCTAssertTrue(composer.attachments.isEmpty, "nor from the cat's box to a kitten's")
        let question = AgentQuestion(id: "q", threadID: "t", threadTitle: "Work", text: "Which?")
        composer.show(.question(question))
        XCTAssertFalse(composer.attach([.bytes(png(), name: "a.png")]), "an answer is only words")
    }

    func testPressingAWebPictureAsksBeforeShowingIt() throws {
        let view = ChannelsView(frame: NSRect(x: 0, y: 0, width: 820, height: 560))
        let book = book(reply: "![web](https://example.com/w.png)")
        var actions: [MessagesAction] = []
        view.onAction = { actions.append($0) }
        view.show(book)
        view.select(.thread("t", in: .channel(.of(steve))))
        view.layoutSubtreeIfNeeded()
        let row = try XCTUnwrap(view.threadPane.shownMessageRows.first { $0.onShowPicture != nil && !$0.isYours })
        row.onShowPicture?(URL(string: "https://example.com/w.png")!)
        XCTAssertFalse(view.threadPane.linkBar.isHidden)
        XCTAssertTrue(view.threadPane.linkBar.isPicture)
        XCTAssertEqual(view.threadPane.linkBar.title, CatWords.showPicture(from: "example.com"))
        XCTAssertTrue(actions.allSatisfy { if case .showPicture = $0 { false } else { true } }, "nothing's fetched yet")
        view.threadPane.linkBar.open.onPress?()
        XCTAssertEqual(actions.last, .showPicture(URL(string: "https://example.com/w.png")!))
        XCTAssertTrue(view.threadPane.linkBar.isHidden)
    }
}
