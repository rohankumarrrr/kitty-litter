@testable import Shades
import ShadesCore
import XCTest

@MainActor
final class PhonePageTests: XCTestCase {
    private let steve = Kitten(name: "Steve Pawsniak", role: "Professional", covers: "", folder: "/k/steve")
    private let pepper = Kitten(name: "Pepper", role: "Finance", covers: "", folder: "/k/pepper")
    private let noon = Date(timeIntervalSince1970: 1_000_000)

    private func thread(_ id: String, of kitten: Kitten, _ status: AgentStatus = .completed) -> AgentThread {
        AgentThread(id: id, title: "Work", projectTitle: kitten.name, status: status, model: "m", updatedAt: noon, projectPath: kitten.folder)
    }

    private func book(reply: String = "Fine.", waiting: Waiting = Waiting(), sent: [SentMessage] = [], reactions: [String: [Reaction]] = ["e1:reply": [.eyes]]) -> ChannelBook {
        ChannelBook.build(
            kittens: [steve, pepper],
            threads: [thread("a", of: steve, .waitingForApproval), thread("p", of: pepper, .running)],
            transcripts: ["a": [Exchange(id: "e1", asker: .you, askedAt: noon, ask: "How's it going?", reply: reply, repliedAt: noon)]],
            isReading: false, unreadable: 0, cantReachT3: false,
            waiting: waiting, sent: sent, reactions: reactions
        )
    }

    private var steveKey: String { PhonePlace.key(.channel(.of(steve))) }
    private var threadKey: String { PhonePlace.key(.thread("a", in: .channel(.of(steve)))) }

    private func view(_ key: String, in book: ChannelBook) -> PhoneView {
        PhoneView(PhonePlace(key, in: book), in: book, now: noon, newFrom: book.newFrom, t3: "env 1")
    }

    private func json(_ value: some Encodable) -> Any {
        (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(value))) ?? [:]
    }

    private func text(_ value: Any) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: value)) ?? Data(), as: UTF8.self)
    }

    private final class Mac {
        var book: ChannelBook
        var refusing = false
        var acts: [PhoneAsk] = []
        var searches: [String] = []

        init(_ book: ChannelBook) { self.book = book }
    }

    private func open(_ key: String, _ mac: Mac, patch: @escaping ([String: Any]) -> [String: Any] = { $0 }) -> PhoneScript {
        let phone = PhoneScript(at: key)
        phone.mac = serve(mac, patch: patch)
        phone.settle()
        return phone
    }

    private func serve(_ mac: Mac, patch: @escaping ([String: Any]) -> [String: Any] = { $0 }) -> (PhoneScript.Request) -> PhoneScript.Reply? {
        { [unowned self] request in
            if mac.refusing, request.path != "/pair" { return .status(401) }
            switch request.path {
            case "/hello":
                return .status(204)
            case "/events":
                let shown = json(view(request.query["key"] ?? PhonePlace.home, in: mac.book)) as? [String: Any] ?? [:]
                return .stream(text(patch(shown)))
            case "/act":
                guard let ask = try? JSONDecoder().decode(PhoneAsk.self, from: Data(request.body.utf8)) else { return .status(400) }
                mac.acts.append(ask)
                guard let done = ask.action(in: mac.book, newTopic: { "topic-1" }) else { return .status(409) }
                return .json(done.opens.map { ["open": $0] } ?? [:])
            case "/search":
                let words = request.json["words"] as? String ?? ""
                mac.searches.append(words)
                return .json(json(PhoneFound(words, in: mac.book, now: noon)))
            default:
                return nil
            }
        }
    }

    private func row(_ id: String) -> String {
        "[...document.getElementById('rows').children].find((node) => node.dataset.id === '\(id)')"
    }

    func testThePlacesAreTheWindowsCatsAndIconsOnLitTilesAndSayWhatEachKittenIsDoing() throws {
        let command = ApprovalRequest(id: "ap", threadID: "a", threadTitle: "Work", kind: .command, summary: "Run: ls", createdAt: noon)
        let mac = Mac(book(waiting: Waiting(approvals: [command], owners: ["ap": steve.id])))
        let phone = open(PhonePlace.home, mac)
        let places = view(PhonePlace.home, in: mac.book).places
        let drawn = phone.read("""
            [...document.querySelectorAll('#rows .place')].map((place) => ({
              label: place.getAttribute('aria-label'), tile: place.children[0].className, light: place.children[0].style['--light'] || '',
              art: place.children[0].children[0].localName, src: place.children[0].children[0].getAttribute('src') || '' }))
            """) as? [[String: String]] ?? []
        XCTAssertEqual(drawn.map { $0["label"] }, ["Activity, 1 waiting", "Threads", "Steve Pawsniak, Needs you, 1 waiting", "Pepper, Working"], "as VoiceOver says the window's sidebar")
        XCTAssertEqual(drawn.map { $0["art"] }, ["svg", "svg", "img", "img"], "Activity and Threads drawn as the window's icons")
        XCTAssertEqual(drawn.dropFirst(2).map { $0["src"] }, places.dropFirst(2).map { "/cat/dark/\($0.cat ?? "").png" }, "each kitten the window's cat, with the outline it has on a dark page")
        XCTAssertEqual(drawn.map { $0["tile"] }, ["tile", "tile", "tile", "tile"])
        let jacket = { (kitten: Kitten) in Opal.hex(ChannelSpeakerLook.color(of: kitten)!) }
        XCTAssertEqual(drawn.map { $0["light"] }, ["hsl(172 100% 68%)", "hsl(344 100% 68%)", jacket(steve), jacket(pepper)], "lit teal to pink, and each kitten in its own colour")
        let words = phone.text("rows")
        for emoji in ["🔔", "💬"] { XCTAssertFalse(words.contains(emoji), "drawn to match the window instead") }
        XCTAssertEqual(phone.errors, [])
    }

    func testYourPictureIsDrawnFromWhatThePageWasSent() throws {
        MessagesInk.picture = DemoPicture.jpeg
        defer { MessagesInk.picture = nil }
        let earlier = noon.addingTimeInterval(-60)
        let mac = Mac(ChannelBook.build(
            kittens: [steve], threads: [thread("a", of: steve)],
            transcripts: ["a": [Exchange(id: "e1", asker: .you, askedAt: earlier, ask: "How's it going?", reply: "Fine.", repliedAt: earlier),
                                Exchange(id: "e2", asker: .you, askedAt: noon, ask: "Thanks", reply: nil, repliedAt: nil)]],
            isReading: false, unreadable: 0, cantReachT3: false
        ))
        let phone = open(steveKey, mac)
        let sent = try XCTUnwrap(view(steveKey, in: mac.book).you)
        XCTAssertEqual(phone.read("[...document.querySelectorAll('#rows .msg > .said > img.you')].map((node) => node.getAttribute('src'))") as? [String], [sent], "beside your message, from what the page was sent")
        XCTAssertEqual(phone.read("[...document.querySelectorAll('#rows .replybar img.you.small')].map((node) => node.getAttribute('src'))") as? [String], [sent], "and in the reply bar in place of your square")
        XCTAssertEqual(phone.read("document.querySelectorAll('#rows .face').length") as? Int, 0)
        XCTAssertFalse(phone.requests.contains { $0.path.contains("picture") || $0.path.contains("you") }, "never from an address of its own")
    }

    func testTheErrorStripStaysInTheHeaderWhereVoiceOverReadsItAndIsNeverHidden() {
        let mac = Mac(book())
        var here = true
        let phone = PhoneScript(at: threadKey)
        let served = serve(mac)
        phone.mac = { here ? served($0) : .unreachable }
        phone.settle()
        let strip = "document.getElementById('banner')"
        XCTAssertEqual(phone.read("\(strip).closest('#top') === document.getElementById('top')") as? Bool, true, "at the top of what you see")
        XCTAssertEqual(phone.read("\(strip).getAttribute('role')") as? String, "status", "which VoiceOver reads out")
        XCTAssertEqual(phone.text("banner"), "", "always there, empty, so it reads what comes to say")
        XCTAssertFalse(phone.isHidden("banner"), "and never hidden, from the start")
        phone.run("window.dispatchEvent(Object.assign(new Event('popstate'), { state: { key: '\(steveKey)' } }))")
        phone.settle()
        XCTAssertEqual(phone.key, steveKey)
        XCTAssertFalse(phone.isHidden("banner"), "going somewhere leaves it where it is")
        here = false
        phone.end(phone.streams[0])
        phone.settle()
        XCTAssertEqual(phone.text("banner"), "Can't reach your Mac. The Kitty Litter has to be running, and your Mac awake.")
        XCTAssertFalse(phone.isHidden("banner"))
        here = true
        mac.refusing = true
        phone.advance(5)
        XCTAssertFalse(phone.isHidden("pair"), "pairing again")
        XCTAssertFalse(phone.isHidden("banner"), "and the strip isn't hidden with what pairing hides")
    }

    func testAQuestionCardAsksEachPartOnce() {
        let font = AnswerForm.Part(key: "font", text: "Which font?", options: ["Silkscreen", "System"], values: ["s", "y"], takesOwnWords: false)
        let pages = AnswerForm.Part(key: "pages", text: "Which pages?", options: ["Home", "Blog"], values: ["h", "b"], takesOwnWords: false, picksSeveral: true)
        let mac = Mac(book(waiting: Waiting(questions: [
            AgentQuestion(id: "two", threadID: "a", threadTitle: "Work", text: "Which font?", form: AnswerForm(parts: [font, pages])),
            AgentQuestion(id: "one", threadID: "a", threadTitle: "Work", text: "Which font?", form: AnswerForm(parts: [font])),
            AgentQuestion(id: "t3", threadID: "a", threadTitle: "Work", text: "Which font?", form: nil),
        ])))
        let phone = open("activity", mac)
        func asks(_ id: String) -> [String] {
            phone.read("[...\(row(id)).querySelectorAll('.text')].map((node) => node.textContent).filter((text) => text.includes('Which'))") as? [String] ?? []
        }
        XCTAssertEqual(asks("two"), ["1 of 2: Which font?", "2 of 2: Which pages?"])
        XCTAssertEqual(asks("one"), ["Which font?"])
        XCTAssertEqual(asks("t3"), ["Which font?"], "and one answered in T3 still says it")
    }

    func testAllowIsTheOnePrimaryOnAnApprovalsCardLitInItsKittensColour() {
        let command = ApprovalRequest(id: "ap", threadID: "a", threadTitle: "Work", kind: .command, summary: "Run: ls", createdAt: noon)
        let mac = Mac(book(waiting: Waiting(approvals: [command], owners: ["ap": steve.id])))
        let phone = open("activity", mac)
        XCTAssertEqual(phone.read("[...\(row("ap")).querySelectorAll('.buttons button')].map((b) => b.textContent + ':' + (b.className || 'quiet')).join(', ')") as? String,
                       "Deny:quiet, Allow:go, Allow for this session:quiet, Ignore:quiet, Open in T3:quiet")
        XCTAssertEqual(phone.read("\(row("ap")).style['--light']") as? String, Opal.hex(ChannelSpeakerLook.color(of: steve)!))
    }

    func testAKittensMessageIsLitAtItsEdgeAndYoursIsFilled() {
        let going = SentMessage(channel: .of(steve), message: ChannelMessage(exchangeID: "c", kind: .reply, speaker: .cat, text: "Hi.", at: noon, threadID: "", threadTitle: "", isStillGoing: true))
        let mac = Mac(book(sent: [going]))
        let phone = open(steveKey, mac)
        let yours = view(steveKey, in: mac.book).rows.first { $0.kind == "parent" }
        let look = { (id: String) in self.read(phone, "\(self.row(id)).querySelector('.bubble')") }
        XCTAssertEqual(look("e1:ask"), "bubble \(text(["--fill": yours?.color ?? ""]))", "yours filled in your colour")
        XCTAssertEqual(look(going.message.id), "bubble lit faded {}", "the cat's own, in Shades' light, faded while it's still going")
        let thread = open(threadKey, mac)
        XCTAssertEqual(read(thread, "\(row("e1:reply")).querySelector('.bubble')"), "bubble lit \(text(["--light": Opal.hex(ChannelSpeakerLook.color(of: steve)!)]))", "a kitten's lit in its colour")
        XCTAssertEqual(thread.read("[...document.querySelectorAll('.bubble')].filter((node) => node.style.color).length") as? Int, 0, "and never words of its own colour")
    }

    private func read(_ phone: PhoneScript, _ bubble: String) -> String {
        phone.read("(() => { const b = \(bubble); const props = {}; for (const name of ['--fill', '--light']) if (b.style[name]) props[name] = b.style[name]; return b.className.split(' ').filter((name) => name !== 'measured').join(' ') + ' ' + JSON.stringify(props); })()") as? String ?? ""
    }

    func testTheBoxArmsSendOnlyWithSomethingToSendAndOnlyOnceTheMacSaysItsReady() {
        let mac = Mac(book())
        let phone = open(threadKey, mac)
        XCTAssertEqual(phone.read("document.getElementById('words').localName") as? String, "textarea", "so Return makes a new line")
        XCTAssertEqual(phone.read("document.getElementById('words').getAttribute('rows')") as? String, "1", "starting one line high, as iMessage's does")
        XCTAssertEqual(phone.read("document.querySelectorAll('input[type=file]').length") as? Int, 1, "one picker, which offers the camera")
        XCTAssertEqual(phone.read("document.querySelector('#send .unseen').textContent") as? String, "Send", "what VoiceOver says for the arrow")
        XCTAssertEqual(phone.read("document.getElementById('send').disabled") as? Bool, true, "nothing to send")
        phone.type("  ", into: "#words")
        XCTAssertEqual(phone.read("document.getElementById('send').disabled") as? Bool, true, "only spaces")
        phone.type("Hi", into: "#words")
        XCTAssertEqual(phone.read("document.getElementById('send').disabled") as? Bool, false)
        var starting = json(view(threadKey, in: mac.book)) as? [String: Any] ?? [:]
        starting["box"] = (starting["box"] as? [String: Any] ?? [:]).merging(["ready": false]) { $1 }
        phone.send(text(starting), on: phone.streams[0])
        phone.settle()
        XCTAssertEqual(phone.read("document.getElementById('send').disabled") as? Bool, true, "a new thread that's still starting")
    }

    func testReactionsComeUpInASheetSoNothingOnThePageMoves() {
        let mac = Mac(book())
        let phone = open(threadKey, mac)
        let before = phone.read("\(row("e1:reply")).outerHTML") as? String
        phone.tap(".msg:not(.mine) .bubble")
        XCTAssertEqual(phone.read("document.getElementById('reactsheet').open && document.getElementById('reactsheet').modal") as? Bool, true)
        XCTAssertEqual(phone.read("\(row("e1:reply")).outerHTML") as? String, before, "never into the page beside the message")
        XCTAssertEqual(phone.read("document.activeElement === document.querySelector('#marks button')") as? Bool, true, "the keyboard goes to the first mark")
        phone.tap("#marks button", "🎉")
        XCTAssertEqual(mac.acts.last?.act, "react")
        XCTAssertEqual(phone.read("document.getElementById('reactsheet').open") as? Bool, false)
        phone.press("Enter", on: ".msg:not(.mine) .react")
        XCTAssertEqual(phone.read("document.getElementById('reactsheet').open") as? Bool, true, "React does the same for a keyboard or VoiceOver")
    }

    private func withPicture(_ shown: [String: Any]) -> [String: Any] {
        var shown = shown
        shown["rows"] = (shown["rows"] as? [[String: Any]] ?? []).map { row in
            guard row["id"] as? String == "e1:ask" else { return row }
            var row = row
            row["files"] = [["name": "photo.jpg", "picture": "data:image/jpeg;base64,"]]
            return row
        }
        return shown
    }

    func testAPictureThatComesInLateKeepsAConversationAtItsFoot() {
        let mac = Mac(book())
        let phone = open(threadKey, mac, patch: withPicture)
        phone.run("document.body.scrollHeight = 1545; window.scrollY = 701; window.dispatchEvent(new Event('scroll'))")
        phone.run("document.body.scrollHeight = 1672")
        phone.send(text(withPicture(json(view(threadKey, in: mac.book)) as? [String: Any] ?? [:])), on: phone.streams[0])
        phone.settle()
        phone.run("document.querySelector('.picture').onload()")
        XCTAssertEqual(phone.read("window.scrollY") as? Int, 1672, "back to the foot once it's in, the page having grown under you")
        phone.run("window.scrollY = 400; window.dispatchEvent(new Event('scroll')); document.querySelector('.picture').onload()")
        XCTAssertEqual(phone.read("window.scrollY") as? Int, 400, "and never from where you'd scrolled to")
        phone.run("window.scrollY = 828; window.dispatchEvent(new Event('scroll')); document.querySelector('.picture').onload()")
        XCTAssertEqual(phone.read("window.scrollY") as? Int, 1672, "and scrolling back down comes back to it")
    }

    func testSearchHasTheBarAndCoveringAThreadIsntSeeingIt() {
        let mac = Mac(book())
        let phone = open(threadKey, mac)
        XCTAssertEqual(phone.read("document.getElementById('searchcancel').closest('form') === document.getElementById('search')") as? Bool, true, "Cancel beside its field")
        phone.tap("#find")
        XCTAssertFalse(phone.isHidden("search"))
        let seen = mac.acts.filter { $0.act == "seen" }.count
        phone.visible(false)
        phone.visible(true)
        phone.run("window.dispatchEvent(Object.assign(new Event('pageshow'), { persisted: true })); window.dispatchEvent(new Event('online')); window.dispatchEvent(new Event('focus'))")
        phone.run("document.body.scrollHeight = 2000; window.scrollY = 2000 - window.innerHeight; window.dispatchEvent(new Event('scroll'))")
        phone.settle()
        phone.send(text(json(view(threadKey, in: mac.book))), on: phone.streams[0])
        phone.settle()
        XCTAssertEqual(mac.acts.filter { $0.act == "seen" }.count, seen, "coming back by any way, or something new, isn't seeing a thread Search covers")
        phone.tap("#searchcancel")
        XCTAssertEqual(mac.acts.filter { $0.act == "seen" }.count, seen + 1, "until Search is put away")
    }

    func testGoingAnywhereBackIncludedPutsSearchAwayWithTheOldPagesTitleAndButtons() {
        let mac = Mac(book())
        let phone = open(threadKey, mac)
        phone.tap("#find")
        let held = phone.mac
        phone.mac = { $0.path == "/events" ? nil : held($0) }
        phone.run("window.dispatchEvent(Object.assign(new Event('popstate'), { state: { key: 'home' } }))")
        phone.settle()
        XCTAssertTrue(phone.isHidden("search"), "Back put Search away")
        XCTAssertEqual(["title", "subtitle", "bartitle"].map(phone.text).joined(), "", "and the old title")
        XCTAssertEqual(["back", "headcat", "link", "t3", "unread"].allSatisfy(phone.isHidden), true, "and the old buttons, before the new page comes")
    }

    func testPairingAgainTakesWhatSearchFoundWithIt() {
        let mac = Mac(book())
        let phone = open(steveKey, mac)
        phone.tap("#find")
        phone.type("going", into: "#query")
        phone.advance(0.3)
        XCTAssertEqual(mac.searches, ["going"])
        XCTAssertGreaterThan(phone.read("document.querySelectorAll('#found .hit').length") as? Int ?? 0, 0, "it found the message")
        mac.refusing = true
        phone.type(" fine", into: "#query")
        phone.advance(0.3)
        XCTAssertFalse(phone.isHidden("pair"), "the Mac no longer takes this phone's key")
        XCTAssertNil(phone.stored["shades.key"])
        XCTAssertEqual(phone.read("document.getElementById('found').childElementCount") as? Int, 0, "what it found goes with the pairing")
        XCTAssertEqual(["top", "head", "rows", "box", "search", "found"].allSatisfy(phone.isHidden), true, "and nothing kittens said shows")
    }

    func testWhatAMessageSaysIsTextAndNoAddressInItLoadsOrOpensByItself() {
        let reply = "See https://example.com/docs and ![a cat](https://example.com/cat.png)\n\n<img src=x onerror=alert(1)> [run me](javascript:alert(1))"
        let mac = Mac(book(reply: reply))
        let phone = open(threadKey, mac)
        let said = phone.text("rows")
        XCTAssertTrue(said.contains("<img src=x onerror=alert(1)>"), "markup in a message is words")
        XCTAssertEqual(phone.read("[...document.querySelectorAll('#rows img')].map((node) => node.getAttribute('src')).filter((src) => !src.startsWith('/cat/') && !src.startsWith('data:'))") as? [String], [], "no picture from anywhere else, the web picture included")
        XCTAssertEqual(phone.read("document.querySelectorAll('#rows a, #rows [href]').length") as? Int, 0, "and nothing in a message has an address to follow")
        XCTAssertEqual(phone.read("[...document.querySelectorAll('#rows .link')].map((node) => node.textContent)") as? [String], ["https://example.com/docs"], "only a web address is a link")
        phone.tap(".bubble .link")
        XCTAssertEqual(phone.text("linktitle"), "Open a link to example.com?", "tapping it shows where it goes")
        XCTAssertEqual(phone.read("document.getElementById('linkopen').getAttribute('href')") as? String, "https://example.com/docs")
        XCTAssertEqual(phone.followed, [], "and goes nowhere by itself")
        phone.tap("#linkcancel")
        phone.tap(".file.web")
        XCTAssertEqual(phone.text("linktitle"), "Show a picture from example.com?")
        XCTAssertNil(phone.read("document.getElementById('linkopen').getAttribute('href')") as? String, "Show has no address of its own")
        phone.tap("#linkshow")
        XCTAssertEqual(mac.acts.last?.act, "picture")
        XCTAssertEqual(mac.acts.last?.id, "e1:reply")
        XCTAssertEqual(mac.acts.last?.value, "https://example.com/cat.png", "the Mac fetches the address the sheet showed, for the message that shows it")
        XCTAssertFalse(phone.requests.contains { $0.path.contains("example.com") }, "and the page never does")
        XCTAssertEqual(phone.errors, [])
    }

    func testEveryCatOnEveryPageIsTheWindowsOnADarkPageAndNoneIsAnEmoji() {
        let command = ApprovalRequest(id: "ap", threadID: "a", threadTitle: "Work", kind: .command, summary: "Run: ls", createdAt: noon)
        let mac = Mac(book(waiting: Waiting(approvals: [command], owners: ["ap": steve.id])))
        for key in [PhonePlace.home, steveKey, threadKey, "activity", "threads"] {
            let phone = open(key, mac)
            let cats = phone.read("[...document.querySelectorAll('img.cat')].map((node) => node.getAttribute('src'))") as? [String] ?? []
            XCTAssertFalse(cats.isEmpty, key)
            XCTAssertEqual(cats.filter { !$0.hasPrefix("/cat/dark/") }, [], "with the outline the window draws on a dark page, small ones in reply bars included: \(key)")
            let words = phone.read("document.body.textContent") as? String ?? ""
            for emoji in ["🔔", "💬"] { XCTAssertFalse(words.contains(emoji), "drawn to match the window instead: \(key)") }
        }
        XCTAssertGreaterThan(open(steveKey, mac).read("document.querySelectorAll('.replybar img.cat.small').length") as? Int ?? 0, 0, "a reply bar's small cats are among them")
    }

    func testTheSheetsSayWhatTheyAreAndAKeyboardMeetsCancelBeforeOpen() {
        let phone = open(threadKey, Mac(book(reply: "See https://example.com/docs")))
        XCTAssertEqual(phone.read("document.getElementById('linksheet').getAttribute('aria-labelledby')") as? String, "linktitle", "VoiceOver reads the link sheet's question as its name")
        XCTAssertEqual(phone.read("document.getElementById('reactsheet').getAttribute('aria-label')") as? String, "React")
        XCTAssertEqual(phone.read("[...document.getElementById('linksheet').querySelectorAll('button, a')].map((node) => node.id)") as? [String], ["linkcancel", "linkopen", "linkshow"], "Tab meets Cancel before Open")
        phone.tap(".bubble .link")
        XCTAssertEqual(phone.read("document.activeElement.id") as? String, "linkcancel", "and the keyboard starts there")
    }
}
