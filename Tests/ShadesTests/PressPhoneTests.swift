import AppKit
@testable import Shades
import ShadesContext
import ShadesCore
import WebKit
import XCTest

/// Every control on the phone page, pressed the way a finger and a phone's hardware keyboard press it. A tap goes
/// where the control's centre is, only if nothing is over it, as the events a tap fires, made inside the page. A key
/// is handed straight to the web view, as `Press.key` does, so the page gets it as a real key. Nothing is posted, so
/// nothing reaches the desktop, and a link the page would follow is only noted, never opened.
@MainActor
final class PressPhoneTests: XCTestCase {
    private let steve = Kitten(name: "Steve Pawsniak", role: "Professional", covers: "", folder: "/k/steve")
    private let pepper = Kitten(name: "Pepper", role: "Finance", covers: "", folder: "/k/pepper")
    private let noon = Date(timeIntervalSince1970: 1_000_000)
    private var phone: Phone!

    override func tearDown() async throws {
        phone?.close()
        phone = nil
    }

    private func thread(_ id: String, of kitten: Kitten, _ status: AgentStatus = .completed) -> AgentThread {
        AgentThread(id: id, title: "Work", projectTitle: kitten.name, status: status, model: "m", updatedAt: noon, projectPath: kitten.folder)
    }

    /// Steve's thread `a`, working, with your ask and a reply with a link, a web picture and code, and `n`, which
    /// nobody has answered. Pepper's `p`, which Steve started, has a long reply. Activity has one of everything.
    private func book() -> ChannelBook {
        let command = ApprovalRequest(id: "ap", threadID: "a", threadTitle: "Work", kind: .command, summary: "Run: ls", createdAt: noon)
        let font = AnswerForm(parts: [AnswerForm.Part(key: "font", text: "Which font?", options: ["Silkscreen", "System"], values: ["s", "y"], takesOwnWords: false)])
        let question = AgentQuestion(id: "q", threadID: "p", threadTitle: "Work", text: "Which font?", form: font)
        let pages = AnswerForm(parts: [
            AnswerForm.Part(key: "pages", text: "Which pages?", options: ["Home", "Blog"], values: ["h", "b"], takesOwnWords: false, picksSeveral: true),
            AnswerForm.Part(key: "else", text: "Anything else?", options: [], values: [], takesOwnWords: true),
        ])
        let twoParts = AgentQuestion(id: "q2", threadID: "p", threadTitle: "Work", text: "Which pages?", form: pages)
        let decision = InboxEntry(id: "r1", kind: .decision, text: "Ship it?", threadID: "p", threadTitle: "Work", at: noon)
        let shipped = InboxEntry(id: "s1", kind: .shipped, text: "Live.", threadID: "a", threadTitle: "Work", at: noon)
        var waiting = Waiting(approvals: [command], questions: [question, twoParts], reports: [decision, shipped])
        waiting.owners = ["ap": steve.id, "q": pepper.id, "q2": pepper.id, "r1": pepper.id, "s1": steve.id]
        var failed = ChannelMessage(exchangeID: "sent-1", kind: .ask, speaker: .you, text: "And then?", at: noon, threadID: "a", threadTitle: "Work")
        failed.failure = "I can't reach T3 Code. Open it and try again."
        let forEveryone = ChannelMessage(exchangeID: "sent-2", kind: .ask, speaker: .you, text: "For everyone", at: noon, threadID: "a", threadTitle: "Work")
        var book = ChannelBook.build(
            kittens: [steve, pepper],
            threads: [thread("a", of: steve, .running), thread("p", of: pepper), thread("n", of: steve)],
            transcripts: [
                "a": [Exchange(id: "e1", asker: .you, askedAt: noon, ask: "How's it going?", reply: "See https://example.com/docs and ![a cat](https://example.com/cat.png)\n\n```\nswift test\n```", repliedAt: noon)],
                "p": [Exchange(id: "e2", asker: .agent(threadID: "a"), askedAt: noon, ask: "Numbers?", reply: (1...60).map { "Line \($0)" }.joined(separator: "\n\n"), repliedAt: noon)],
                "n": [Exchange(id: "e3", asker: .you, askedAt: noon, ask: "Nobody answered. See https://example.com/notes")],
            ],
            isReading: false, unreadable: 0, cantReachT3: false,
            waiting: waiting,
            sent: [SentMessage(channel: .of(steve), message: failed, isReply: true), SentMessage(channel: .of(steve), message: forEveryone, alsoSent: true, isReply: true)],
            reactions: ["e1:reply": [.eyes]]
        )
        if let steves = book.channels.firstIndex(where: { $0.id == .of(steve) }) { book.channels[steves].isCut = true }
        book.newFrom["p"] = "e2:reply"
        return book
    }

    private var steveKey: String { PhonePlace.key(.channel(.of(steve))) }
    private var threadKey: String { PhonePlace.key(.thread("a", in: .channel(.of(steve)))) }

    private func open(at key: String = PhonePlace.home, paired: Bool = true) async throws {
        phone = Phone(book: book(), now: noon, paired: paired)
        phone.open(key)
        if paired { try await shows(key) }
    }

    private func shows(_ key: String, file: StaticString = #filePath, line: UInt = #line) async throws {
        try await phone.until("the page shows \(key)", file: file, line: line) { try await phone.read("!window.stale && view && view.key") as? String == key }
    }

    /// What the Mac would do about the last time the page asked it to `act`, or a failure if it never asked.
    private func did(_ act: String, file: StaticString = #filePath, line: UInt = #line) async throws -> MessagesAction? {
        try await phone.until("the page asks the Mac to \(act)", file: file, line: line) { phone.acts.contains { $0.ask.act == act } }
        let asked = try XCTUnwrap(phone.acts.last { $0.ask.act == act }, file: file, line: line)
        XCTAssertNotNil(asked.action, "the Mac takes \(act) as the page sent it", file: file, line: line)
        return asked.action
    }

    private func asked(_ act: String) -> Int {
        phone.acts.filter { $0.ask.act == act }.count
    }

    private func isOpen(_ sheet: String) async throws -> Bool {
        try await phone.read("$('\(sheet)').open") as? Bool == true
    }

    private let focus = "document.activeElement && (document.activeElement.id || document.activeElement.textContent.trim())"

    private func expect<Value: Equatable>(_ expression: String, _ expected: Value, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) async throws {
        let value = try await phone.read(expression) as? Value
        XCTAssertEqual(value, expected, message, file: file, line: line)
    }

    private func expectOpen(_ sheet: String, _ open: Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) async throws {
        try await expect("$('\(sheet)').open", open, message, file: file, line: line)
    }

    private func did(_ act: String, _ expected: MessagesAction, file: StaticString = #filePath, line: UInt = #line) async throws {
        let action = try await did(act, file: file, line: line)
        XCTAssertEqual(action, expected, file: file, line: line)
    }

    // MARK: - The finger

    /// What's under a sheet can't be tapped, which is what proves the rest of these taps landed on what they meant to.
    func testNothingUnderASheetTakesATap() async throws {
        try await open(at: threadKey)
        try await phone.tap(".bubble .link")
        let reached = try await phone.reach("#back")
        XCTAssertTrue(reached.hasPrefix("covered by <dialog id=\"linksheet\""), reached)
    }

    // MARK: - Pairing

    func testTheCodeFieldAndPairPairThisPhone() async throws {
        try await open(paired: false)
        try await phone.until("the page asks for a code") { try await phone.read("!$('pair').hidden") as? Bool == true }
        try await phone.tap("#code")
        try await phone.type("WXYZ-1234")
        try await phone.tap("#pairform button", "Pair")
        try await phone.until("a wrong code says so") { try await phone.read("$('pairnote').textContent") as? String != "" }
        try await expect("!$('pair').hidden", true, "still asking")

        try await phone.run("$('code').value = ''")
        try await phone.tap("#code")
        try await phone.type(Phone.code)
        try await phone.press(.returnKey)
        try await shows(PhonePlace.home)
        try await expect("$('pair').hidden", true)
        try await expect("document.querySelectorAll('.place').length", 5)
    }

    func testScanningTheCodeOpensThePagePaired() async throws {
        try await open(paired: false)
        phone.open(PhonePlace.home, hash: "#pair=\(Phone.code)")
        try await shows(PhonePlace.home)
        try await expect("location.hash", "", "the code doesn't stay in the address")
    }

    func testPairTakesATap() async throws {
        try await open(paired: false)
        try await phone.until("the page asks for a code") { try await phone.read("!$('pair').hidden") as? Bool == true }
        try await phone.tap("#code")
        try await phone.type(Phone.code)
        try await phone.tap("#pairform button", "Pair")
        try await shows(PhonePlace.home)

        try await phone.run("localStorage.clear()")
        phone.open(PhonePlace.home)
        try await phone.until("the page asks again") { try await phone.read("!window.stale && !$('pair').hidden") as? Bool == true }
        try await phone.tap("#code")
        try await phone.type(Phone.code)
        try await phone.press(.space, on: "#pairform button", "Pair")
        try await shows(PhonePlace.home)
    }

    // MARK: - Places, Back and the title bar

    func testTappingAPlaceOpensItAndBackComesHome() async throws {
        try await open()
        try await phone.tap(".place", "steve-pawsniak")
        try await shows(steveKey)
        try await expect("$('title').textContent", "#steve-pawsniak")
        try await phone.tap("#back")
        try await shows(PhonePlace.home)
        try await phone.press(.returnKey, on: ".place", "steve-pawsniak")
        try await shows(steveKey)
        try await phone.press(.space, on: "#back")
        try await shows(PhonePlace.home)
        for place in ["Activity", "Threads", "general", "pepper"] {
            try await phone.tap(".place", place)
            try await phone.until("\(place) opens") { try await phone.read("$('title').textContent") as? String != CatWords.appName }
            try await phone.tap("#back")
            try await shows(PhonePlace.home)
        }
    }

    func testTheBarTakesTheTitleOnceItsScrolledUnder() async throws {
        try await open(at: PhonePlace.key(.thread("p", in: .channel(.of(pepper)))))
        try await phone.run("window.scrollTo(0, 0)")
        try await phone.until("the large title shows under the bar") { try await phone.read("$('top').classList.contains('collapsed')") as? Bool == false }
        try await phone.run("window.scrollTo(0, document.body.scrollHeight)")
        try await phone.until("the bar takes the title") { try await phone.read("$('top').classList.contains('collapsed')") as? Bool == true }
        try await expect("getComputedStyle($('bartitle')).visibility", "visible")
        try await expect("$('bartitle').textContent", "Thread")
    }

    // MARK: - A channel

    func testAChannelsInProgressOpensActivity() async throws {
        try await open(at: steveKey)
        try await expect("$('link').textContent", "1 in progress")
        try await phone.tap("#link")
        try await shows("activity")
        try await phone.tap("#back")
        try await shows(PhonePlace.home)
        try await phone.tap(".place", "steve-pawsniak")
        try await shows(steveKey)
        try await phone.press(.returnKey, on: "#link")
        try await shows("activity")
    }

    func testAParentOpensItsThreadFromItsWordsOrItsReplyBar() async throws {
        try await open(at: steveKey)
        try await phone.tap(".msg .bubble", "How's it going?")
        try await shows(threadKey)
        try await phone.tap("#back")
        try await shows(steveKey)
        try await phone.tap(".replybar")
        try await shows(threadKey)
        try await phone.tap("#back")
        try await shows(steveKey)
        try await phone.press(.returnKey, on: ".replybar")
        try await shows(threadKey)
    }

    func testAReplyAlsoSentToTheChannelOpensItsThread() async throws {
        try await open(at: steveKey)
        try await phone.tap(".context")
        try await shows(threadKey)
        try await phone.tap("#back")
        try await shows(steveKey)
        try await phone.press(.returnKey, on: ".context")
        try await shows(threadKey)
    }

    func testTheWayUpGoesToTheNewLine() async throws {
        try await open(at: PhonePlace.key(.thread("p", in: .channel(.of(pepper)))))
        try await phone.until("the way up shows") { try await phone.read("!$('jumpnew').hidden") as? Bool == true }
        try await phone.tap("#jumpnew")
        try await phone.until("the New line is in sight") { try await phone.read("$('jumpnew').hidden") as? Bool == true }
        try await expect("document.querySelector('.new').getBoundingClientRect().top >= $('top').getBoundingClientRect().bottom", true)
        try await phone.run("window.scrollTo(0, document.body.scrollHeight)")
        try await phone.until("the way up shows again") { try await phone.read("!$('jumpnew').hidden") as? Bool == true }
        try await phone.press(.returnKey, on: "#jumpnew")
        try await phone.until("Return goes up too") { try await phone.read("$('jumpnew').hidden") as? Bool == true }
    }

    func testLoadOlderAsksForOlderPosts() async throws {
        try await open(at: steveKey)
        try await phone.tap(".older")
        try await did("older", .older(.of(steve)))
        try await phone.press(.returnKey, on: ".older")
        try await phone.until("Return asks again") { asked("older") == 2 }
    }

    // MARK: - Search

    func testSearchFindsAMessageAndOpensItsPage() async throws {
        try await open(at: steveKey)
        try await phone.tap("#find")
        try await expect("$('search').hidden", false)
        try await expect(focus, "query", "the keyboard goes to the field")
        try await phone.type("going")
        try await phone.until("it finds the message") { try await phone.read("document.querySelectorAll('#found .hit').length") as? Int ?? 0 > 0 }
        XCTAssertEqual(phone.searches.last, "going")
        try await phone.press(.returnKey)
        try await expect("document.querySelectorAll('#found .hit').length > 0", true, "Return keeps what it found")
        try await phone.tap("#found .hit")
        try await phone.until("Search goes away") { try await phone.read("$('search').hidden") as? Bool == true }
        try await phone.until("its page shows it") { try await phone.read("!!document.querySelector('.msg.landed')") as? Bool == true }
    }

    func testSearchFromTheKeyboard() async throws {
        try await open(at: steveKey)
        try await phone.press(.returnKey, on: "#find")
        try await phone.until("Search opens") { try await phone.read("$('search').hidden") as? Bool == false }
        try await phone.type("going")
        try await phone.until("it finds the message") { try await phone.read("document.querySelectorAll('#found .hit').length") as? Int ?? 0 > 0 }
        try await phone.press(.returnKey, on: "#found .hit")
        try await phone.until("its page shows it") { try await phone.read("!!document.querySelector('.msg.landed')") as? Bool == true }
    }

    func testCancelPutsSearchAway() async throws {
        try await open(at: steveKey)
        let seen = asked("seen")
        try await phone.tap("#find")
        try await phone.tap("#searchcancel")
        try await expect("$('search').hidden", true)
        try await expect("$('bar').hidden", false)
        try await expect("view.key", steveKey)
        try await phone.until("the channel counts as seen again") { asked("seen") > seen }
        try await phone.tap("#find")
        try await phone.press(.space, on: "#searchcancel")
        try await phone.until("Space puts it away too") { try await phone.read("$('search').hidden") as? Bool == true }
    }

    // MARK: - The box

    func testTheArrowSendsWhatYouTyped() async throws {
        try await open(at: threadKey)
        try await expect("$('send').disabled", true, "nothing to send yet")
        try await phone.tap("#words")
        try await phone.type("Ship it")
        try await phone.tap("#send")
        guard case .send(let words, _, _, let also, let files)? = try await did("send") else { return XCTFail("not a reply") }
        XCTAssertEqual(words, "Ship it")
        XCTAssertFalse(also)
        XCTAssertEqual(files, [])
        try await phone.until("the box empties") { try await phone.read("$('words').value") as? String == "" }
    }

    func testReturnMakesANewLineAndTheArrowTakesTheKeyboard() async throws {
        try await open(at: threadKey)
        try await phone.tap("#words")
        try await phone.type("One")
        try await phone.press(.returnKey)
        try await phone.type("Two")
        try await expect("$('words').value", "One\nTwo")
        XCTAssertEqual(asked("send"), 0, "Return didn't send")
        try await phone.press(.returnKey, on: "#send")
        guard case .send(let words, _, _, _, _)? = try await did("send") else { return XCTFail("not a reply") }
        XCTAssertEqual(words, "One\nTwo")
    }

    func testAlsoSendToTheChannelGoesWithTheReply() async throws {
        try await open(at: threadKey)
        try await expect("$('alsotext').textContent", "Also send to #steve-pawsniak")
        try await phone.tap("#alsolabel")
        try await expect("$('also').checked", true)
        try await phone.tap("#words")
        try await phone.type("For everyone")
        try await phone.tap("#send")
        guard case .send(_, _, _, let also, _)? = try await did("send") else { return XCTFail("not a reply") }
        XCTAssertTrue(also)
        try await expect("$('also').checked", false, "it's for one message")
        try await phone.press(.space, on: "#also")
        try await expect("$('also').checked", true, "Space ticks it")
    }

    func testPlusAttachesAPhotoThatGoesWithTheMessage() async throws {
        try await open(at: threadKey)
        phone.picks = [try picture()]
        try await phone.tap("#attach")
        try await phone.until("the photo is attached") { try await phone.read("document.querySelectorAll('.attachment').length") as? Int == 1 }
        XCTAssertEqual(phone.panels, 1)
        XCTAssertEqual(phone.uploads.map(\.type), ["image/jpeg"], "made smaller here first")
        try await expect("$('send').disabled", false, "a photo alone can go")
        try await phone.tap(".attachment button")
        try await phone.until("✕ takes it off") { try await phone.read("document.querySelectorAll('.attachment').length") as? Int == 0 }

        try await phone.press(.returnKey, on: "#attach")
        try await phone.until("Return attaches one too") { try await phone.read("document.querySelectorAll('.attachment').length") as? Int == 1 }
        XCTAssertEqual(phone.panels, 2)
        try await phone.press(.returnKey, on: ".attachment button")
        try await phone.until("Return on ✕ takes it off") { try await phone.read("document.querySelectorAll('.attachment').length") as? Int == 0 }
        try await phone.tap("#attach")
        try await phone.until("and on again") { try await phone.read("document.querySelectorAll('.attachment').length") as? Int == 1 }
        try await phone.tap("#send")
        guard case .send(_, _, _, _, let files)? = try await did("send") else { return XCTFail("not a reply") }
        XCTAssertEqual(files.count, 1)
    }

    private func picture() throws -> URL {
        let image = NSImage(size: NSSize(width: 40, height: 30), flipped: false) { rect in
            NSColor.systemTeal.setFill()
            rect.fill()
            return true
        }
        let png = try XCTUnwrap(image.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0) }?.representation(using: .png, properties: [:]))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("PressPhoneTests-\(UUID().uuidString).png")
        try png.write(to: file)
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        return file
    }

    // MARK: - Activity

    func testAnApprovalsButtonsAnswerIt() async throws {
        try await open(at: "activity")
        try await phone.tap(".card.approval button", "Allow")
        guard case .approval(let request, let decision)? = try await did("approval") else { return XCTFail("not an approval") }
        XCTAssertEqual(request.id, "ap")
        XCTAssertEqual(decision, .accept)
        try await expect("[...document.querySelectorAll('.card.approval button')].every((b) => b.disabled)", true)

        phone.open("activity")
        try await shows("activity")
        try await phone.press(.returnKey, on: ".card.approval button", "Deny")
        try await phone.until("Return denies it") { asked("approval") == 2 }
        guard case .approval(_, .decline)? = phone.acts.last?.action else { return XCTFail("not denied") }

        phone.open("activity")
        try await shows("activity")
        try await phone.press(.space, on: ".card.approval button", "Allow for this session")
        try await phone.until("Space allows it for the session") { asked("approval") == 3 }
        guard case .approval(_, .acceptForSession)? = phone.acts.last?.action else { return XCTFail("not for the session") }
    }

    func testAQuestionsChoiceAnswersItOnTheTap() async throws {
        try await open(at: "activity")
        try await phone.tap(".card.question button", "System")
        guard case .answer(let question, let answers)? = try await did("answer") else { return XCTFail("not an answer") }
        XCTAssertEqual(question.id, "q")
        XCTAssertEqual(answers, [["y"]])

        phone.open("activity")
        try await shows("activity")
        try await phone.press(.returnKey, on: ".card.question button", "Silkscreen")
        try await phone.until("Return answers it") { asked("answer") == 2 }
        guard case .answer(_, [["s"]])? = phone.acts.last?.action else { return XCTFail("not Silkscreen") }
    }

    func testAQuestionWithPartsTakesEveryPartAndThenSendAnswer() async throws {
        try await open(at: "activity")
        try await expect("[...document.querySelectorAll('.card.question button')].find((b) => b.textContent === 'Send answer').disabled", true)
        try await phone.tap(".card.question button", "Home")
        try await phone.tap(".card.question button", "Blog")
        try await phone.tap(".card.question input")
        try await phone.type("No")
        try await phone.tap(".card.question button", "Send answer")
        guard case .answer(let question, let answers)? = try await did("answer") else { return XCTFail("not an answer") }
        XCTAssertEqual(question.id, "q2")
        XCTAssertEqual(answers, [["h", "b"], ["No"]])

        phone.open("activity")
        try await shows("activity")
        try await phone.press(.space, on: ".card.question button", "Blog")
        try await expect("[...document.querySelectorAll('.card.question button')].find((b) => b.textContent === 'Blog').getAttribute('aria-pressed')", "true")
        try await phone.tap(".card.question input")
        try await phone.type("Yes")
        try await phone.press(.returnKey, on: ".card.question button", "Send answer")
        try await phone.until("Return sends the answer") { asked("answer") == 2 }
        guard case .answer(_, [["b"], ["Yes"]])? = phone.acts.last?.action else { return XCTFail("not the second answer") }
    }

    func testAReportsReplyOpensItsThreadAndDoneClearsIt() async throws {
        try await open(at: "activity")
        try await phone.tap(".card.report button", "Done")
        try await did("done", .inbox(.done(id: "r1")))
        try await phone.tap(".card.report button", "Reply")
        try await shows("r:r1")
        try await expect("$('box').hidden", false, "with a box to reply in")
        try await phone.tap("#back")
        try await shows("activity")
        try await phone.press(.returnKey, on: ".card.report button", "Ask")
        try await shows("r:s1")
    }

    func testClearAndAnIssueInActivity() async throws {
        try await open(at: "activity")
        try await phone.tap(".section button", "Clear")
        try await did("clear", .inbox(.clear(.shipped)))
        try await phone.press(.space, on: ".section button", "Clear")
        try await phone.until("Space clears too") { asked("clear") == 2 }
        try await phone.tap(".issue")
        try await shows(PhonePlace.key(.thread("a", in: .activity)))
        try await phone.tap("#back")
        try await shows("activity")
        try await phone.press(.returnKey, on: ".issue")
        try await shows(PhonePlace.key(.thread("a", in: .activity)))
    }

    func testThreadsOpensEachThread() async throws {
        try await open(at: "threads")
        try await phone.tap(".digest")
        try await phone.until("a thread opens") { (try await phone.read("view.key") as? String)?.hasPrefix("t:") == true }
        try await phone.tap("#back")
        try await shows("threads")
        try await phone.press(.returnKey, on: ".digest")
        try await phone.until("Return opens it too") { (try await phone.read("view.key") as? String)?.hasPrefix("t:") == true }
    }

    // MARK: - A thread

    func testMarkUnreadMarksTheLatestReplyNew() async throws {
        try await open(at: threadKey)
        try await phone.tap("#unread")
        try await did("unread", .markUnread("a", from: "e1:reply"))
        try await phone.press(.returnKey, on: "#unread")
        try await phone.until("Return marks it too") { asked("unread") == 2 }
    }

    func testTryAgainSendsItAgain() async throws {
        try await open(at: threadKey)
        try await phone.tap(".retry")
        try await did("retry", .tryAgain("sent-1"))
        phone.open(threadKey)
        try await shows(threadKey)
        try await phone.press(.returnKey, on: ".retry")
        try await phone.until("Return tries again") { asked("retry") == 2 }
    }

    func testShowMoreOpensALongMessageAndShowLessCutsIt() async throws {
        try await open(at: PhonePlace.key(.thread("p", in: .channel(.of(pepper)))))
        try await expect("document.querySelectorAll('.bubble.cut').length", 1)
        try await phone.tap(".more", "Show more")
        try await expect("document.querySelectorAll('.bubble.cut').length", 0)
        try await phone.press(.returnKey, on: ".more", "Show less")
        try await expect("document.querySelectorAll('.bubble.cut').length", 1)
        try await phone.press(.space, on: ".more", "Show more")
        try await expect("document.querySelectorAll('.bubble.cut').length", 0)
    }

    func testCopyCopiesTheCode() async throws {
        try await open(at: threadKey)
        // Kept in the page, so nothing reaches the Mac's own clipboard.
        try await phone.run("window.copied = []; Object.defineProperty(navigator, 'clipboard', { value: { writeText: async (text) => { copied.push(text); } } });")
        try await phone.tap(".copy")
        try await phone.until("Copy copies the code") { try await phone.read("copied.join()") as? String == "swift test" }
        try await expect("document.querySelector('.copy').textContent", "Copied")
        XCTAssertEqual(asked("react"), 0, "and doesn't offer reactions")
        try await phone.press(.returnKey, on: ".copy")
        try await phone.until("Return copies it too") { try await phone.read("copied.length") as? Int == 2 }
    }

    // MARK: - Reactions

    func testTappingAMessageOffersReactionsAndOneReacts() async throws {
        try await open(at: threadKey)
        try await phone.tap(".msg:not(.mine) .bubble pre")
        try await expectOpen("reactsheet", true)
        try await expect(focus, "👍", "the keyboard goes to the first mark")
        try await phone.tap("#marks button", "🎉")
        try await did("react", .react("e1:reply", .tada))
        try await expectOpen("reactsheet", false)
        try await phone.tap(".reactions button", "👀")
        try await phone.until("a reaction's pill takes it off") { asked("react") == 2 }
        XCTAssertEqual(phone.acts.last?.action, .react("e1:reply", .eyes))
        try await phone.press(.returnKey, on: ".reactions button", "👀")
        try await phone.until("Return on a pill does too") { asked("react") == 3 }
    }

    func testReactFromTheKeyboardAndPutTheSheetAway() async throws {
        try await open(at: threadKey)
        try await phone.press(.returnKey, on: ".msg:not(.mine) .react")
        try await phone.until("React opens the marks") { try await isOpen("reactsheet") }
        try await phone.press(.escape)
        try await phone.until("Escape puts them away") { try await isOpen("reactsheet") == false }
        try await phone.press(.space, on: ".msg:not(.mine) .react")
        try await phone.until("Space opens them") { try await isOpen("reactsheet") }
        try await phone.tap("#reactsheet", at: CGPoint(x: Phone.size.width / 2, y: 40))
        try await phone.until("a tap on the dimmed page puts them away") { try await isOpen("reactsheet") == false }
        try await phone.press(.returnKey, on: ".msg:not(.mine) .react")
        try await phone.until("React opens the marks again") { try await isOpen("reactsheet") }
        try await phone.press(.returnKey, on: "#marks button", "❤️")
        try await did("react", .react("e1:reply", .heart))
    }

    // MARK: - The link sheet

    func testALinkAsksBeforeItOpens() async throws {
        try await open(at: threadKey)
        try await phone.tap(".bubble .link")
        try await expectOpen("linksheet", true)
        try await expect("$('linktitle').textContent", "Open a link to example.com?")
        try await expect("$('linkaddress').textContent", "https://example.com/docs")
        try await expect(focus, "linkcancel", "the keyboard is on Cancel, never Open")
        XCTAssertEqual(asked("react"), 0)
        try await phone.tap("#linkcancel")
        try await expectOpen("linksheet", false)
        XCTAssertEqual(phone.followed, [])

        try await phone.tap(".bubble .link")
        try await phone.tap("#linkopen")
        try await phone.until("Open goes to the link") { phone.followed == [URL(string: "https://example.com/docs")!] }
        try await expectOpen("linksheet", false)

        try await phone.tap(".bubble .link")
        try await phone.tap("#linksheet", at: CGPoint(x: Phone.size.width / 2, y: 40))
        try await phone.until("a tap on the dimmed page puts it away") { try await isOpen("linksheet") == false }

        try await phone.press(.returnKey, on: ".bubble .link")
        try await phone.until("Return on a link asks too") { try await isOpen("linksheet") }
        try await expect(focus, "linkcancel")
        try await expectOpen("reactsheet", false, "and the same Return doesn't press anything else")
        try await phone.press(.escape)
        try await phone.until("Escape puts it away") { try await isOpen("linksheet") == false }
        try await phone.press(.returnKey, on: ".bubble .link")
        try await phone.until("Return on a link asks again") { try await isOpen("linksheet") }
        try await phone.press(.returnKey)
        try await phone.until("Return on Cancel puts it away") { try await isOpen("linksheet") == false }
        XCTAssertEqual(phone.followed.count, 1, "only Open went anywhere")
        try await phone.press(.returnKey, on: ".bubble .link")
        try await phone.until("Return on a link asks once more") { try await isOpen("linksheet") }
        try await phone.press(.returnKey, on: "#linkopen")
        try await phone.until("Return on Open goes there") { phone.followed.count == 2 }
        try await phone.until("and puts the sheet away") { try await isOpen("linksheet") == false }
    }

    func testAWebPictureShowsOnlyOnceYouPressShow() async throws {
        try await open(at: threadKey)
        try await phone.tap(".file.web")
        try await expect("$('linktitle').textContent", "Show a picture from example.com?")
        try await expect("$('linkopen').hidden && !$('linkshow').hidden", true)
        try await phone.tap("#linkcancel")
        XCTAssertEqual(asked("picture"), 0)
        try await phone.tap(".file.web")
        try await phone.tap("#linkshow")
        try await did("picture", .showPicture(URL(string: "https://example.com/cat.png")!))
        try await expectOpen("linksheet", false)
        try await phone.press(.returnKey, on: ".file.web")
        try await phone.until("Return asks too") { try await isOpen("linksheet") }
        try await phone.press(.returnKey, on: "#linkshow")
        try await phone.until("Return on Show shows it") { asked("picture") == 2 }
        XCTAssertEqual(phone.followed, [], "the page never goes there itself")
    }
}

/// The page at a phone's size, in a web view off the edge of every screen, with a stand-in for the Mac behind it. The
/// stand-in answers from a book through the same `PhonePlace`, `PhoneView`, `PhoneAsk` and `PhoneFound` the Mac uses,
/// and keeps what the page asked and what the Mac would have done about it.
@MainActor
private final class Phone: NSObject, WKNavigationDelegate, WKUIDelegate {
    static let pass = "a-paired-phone"
    static let code = "ABCD-EFGH"
    static let size = NSSize(width: 390, height: 844)

    enum Key {
        case returnKey, space, escape

        var characters: String {
            switch self {
            case .returnKey: return "\r"
            case .space: return " "
            case .escape: return "\u{1b}"
            }
        }

        var code: UInt16 {
            switch self {
            case .returnKey: return 36
            case .space: return 49
            case .escape: return 53
            }
        }
    }

    var book: ChannelBook
    let view: WKWebView
    /// What the page asked the Mac to do, and what the Mac would do about it, which is `nil` where it turned it away.
    private(set) var acts: [(ask: PhoneAsk, action: MessagesAction?)] = []
    private(set) var searches: [String] = []
    private(set) var uploads: [(name: String, type: String)] = []
    /// Each place the page asked to be shown, in order.
    private(set) var watched: [String] = []
    /// Addresses the page tried to go to, which are never gone to.
    private(set) var followed: [URL] = []
    /// How often the page asked for a photo or file, and what's picked when it does.
    private(set) var panels = 0
    var picks: [URL] = []
    private let now: Date
    private let panel: NSPanel
    private var streams: [(task: WKURLSchemeTask, key: String)] = []
    private var files: [String: Drop] = [:]

    init(book: ChannelBook, now: Date, paired: Bool) {
        self.book = book
        self.now = now
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let handler = SchemeHandler()
        configuration.setURLSchemeHandler(handler, forURLScheme: "phone")
        if paired {
            configuration.userContentController.addUserScript(WKUserScript(source: "localStorage.setItem('shades.key', '\(Self.pass)')", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        view = WKWebView(frame: NSRect(origin: .zero, size: Self.size), configuration: configuration)
        panel = NSPanel(contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: Self.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        handler.phone = self
        view.navigationDelegate = self
        view.uiDelegate = self
        panel.sharingType = .none
        panel.isReleasedWhenClosed = false
        panel.contentView = view
        // A web view only lays out and runs its timers while its window is out, and this one is off every screen. Off
        // every screen, its page would say it can't be seen, and a page that can't be seen marks nothing seen.
        panel.orderFrontRegardless()
        let seeEvenOffScreen = NSSelectorFromString("_setWindowOcclusionDetectionEnabled:")
        if view.responds(to: seeEvenOffScreen) { view.perform(seeEvenOffScreen, with: false) }
    }

    /// Loads the page fresh at `key`. Whatever was loaded before is marked stale, so nothing waits on it by mistake.
    func open(_ key: String, hash: String = "") {
        view.evaluateJavaScript("window.stale = true")
        view.load(URLRequest(url: URL(string: "phone://mac/?key=\(key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")\(hash)")!))
    }

    func close() {
        for stream in streams { stream.task.didFinish() }
        streams = []
        view.stopLoading()
        panel.close()
    }

    /// Sends each open page what it shows now, as the Mac does when the book changes.
    func push() {
        for stream in streams { send(stream.task, key: stream.key) }
    }

    // MARK: Pressing

    /// Taps the first `selector` that shows, saying `text` or labelled with it, at its centre, or at `point` on the
    /// page, and fails if anything else is there to take the tap.
    func tap(_ selector: String, _ text: String? = nil, at point: CGPoint? = nil, file: StaticString = #filePath, line: UInt = #line) async throws {
        let said = try await run(Self.finger, ["selector": selector, "text": text ?? NSNull(), "point": point.map { [$0.x, $0.y] } ?? NSNull()]) as? String
        XCTAssertEqual(said, "tapped", "tapping \(selector) \(text ?? "")", file: file, line: line)
    }

    /// What a tap at the centre of the first `selector` would land on, without tapping.
    func reach(_ selector: String) async throws -> String {
        try await run(Self.finger.replacingOccurrences(of: "const at =", with: "return 'tapped';\nconst at ="), ["selector": selector, "text": NSNull(), "point": NSNull()]) as? String ?? ""
    }

    /// Puts the keyboard on the first `selector` saying `text`, as Tab would, and presses `key` there.
    func press(_ key: Key, on selector: String, _ text: String? = nil, file: StaticString = #filePath, line: UInt = #line) async throws {
        let focused = try await run(Self.find + "if (!node) return 'nothing is ' + selector; node.focus(); return document.activeElement === node ? 'focused' : 'focus is on ' + (document.activeElement && document.activeElement.outerHTML.slice(0, 120));", ["selector": selector, "text": text ?? NSNull()]) as? String
        XCTAssertEqual(focused, "focused", "focusing \(selector) \(text ?? "")", file: file, line: line)
        try await press(key, file: file, line: line)
    }

    /// Typed a key at a time wherever the page has the keyboard.
    func type(_ text: String, file: StaticString = #filePath, line: UInt = #line) async throws {
        for character in text { try await stroke(String(character), file: file, line: line) }
    }

    /// A key pressed and let go wherever the page has the keyboard, once the page has had both. Space presses a button
    /// as it's let go, which reaches the page after anything asked of it in between.
    func press(_ key: Key, file: StaticString = #filePath, line: UInt = #line) async throws {
        try await stroke(key.characters, code: key.code, file: file, line: line)
    }

    private func stroke(_ characters: String, code: UInt16 = 0, file: StaticString, line: UInt) async throws {
        let before = try await run("if (!window.letGo) { window.letGo = 0; addEventListener('keyup', () => { letGo += 1; }, true); } return letGo;") as? Int ?? 0
        try Press.key(characters, keyCode: code, on: view, file: file, line: line)
        try await until("the page has the key", file: file, line: line) { try await run("return letGo;") as? Int ?? 0 > before }
    }

    /// What `expression` comes to in the page.
    func read(_ expression: String) async throws -> Any? {
        try await run("return \(expression);")
    }

    @discardableResult
    func run(_ body: String, _ arguments: [String: Any] = [:]) async throws -> Any? {
        try await view.callAsyncJavaScript(body, arguments: arguments, in: nil, contentWorld: .page)
    }

    func until(_ what: String, file: StaticString = #filePath, line: UInt = #line, _ check: () async throws -> Bool) async throws {
        for _ in 0..<250 {
            if (try? await check()) == true { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("waited for \(what)", file: file, line: line)
        throw CancellationError()
    }

    private static let find = """
        const nodes = [...document.querySelectorAll(selector)].filter((node) => text == null
          || node.textContent.trim() === text || (node.getAttribute('aria-label') || '').split(', ')[0] === text);
        const node = nodes.find((node) => node.getClientRects().length) || nodes[0];

        """

    /// Where a finger lands is whatever's on top there, which has to be the control or inside it. A tap there fires
    /// the pointer's down and up, then the mouse's, then the click, as a phone's browser does.
    private static let finger = find + """
        if (!node) return 'nothing is ' + selector + (text == null ? '' : ' saying ' + text);
        let box = node.getBoundingClientRect();
        if (!box.width || !box.height) return 'it takes up no room';
        if (!point && (box.top < 0 || box.bottom > innerHeight)) { node.scrollIntoView({ block: 'center' }); box = node.getBoundingClientRect(); }
        const x = point ? point[0] : box.left + box.width / 2, y = point ? point[1] : box.top + box.height / 2;
        const hit = document.elementFromPoint(x, y);
        if (!hit || !(hit === node || node.contains(hit))) return 'covered by ' + (hit ? hit.outerHTML.slice(0, 160) : 'nothing');
        const at = { bubbles: true, cancelable: true, composed: true, view: window, clientX: x, clientY: y, button: 0 };
        const touch = { ...at, pointerId: 1, pointerType: 'touch', isPrimary: true };
        hit.dispatchEvent(new PointerEvent('pointerdown', touch));
        hit.dispatchEvent(new PointerEvent('pointerup', touch));
        // A tap puts the keyboard in a field, as a made-up event doesn't on its own.
        if (hit.dispatchEvent(new MouseEvent('mousedown', at))) hit.closest('textarea, input:not([type=checkbox], [type=radio], [type=file])')?.focus();
        hit.dispatchEvent(new MouseEvent('mouseup', at));
        hit.dispatchEvent(new MouseEvent('click', at));
        return 'tapped';
        """

    // MARK: The Mac

    fileprivate func start(_ task: WKURLSchemeTask) {
        let request = task.request
        guard let url = request.url else { return answer(task, 400) }
        let path = url.path.isEmpty ? "/" : url.path
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read) ?? Data()
        let admitted = request.value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.pass)"
        switch (request.httpMethod ?? "GET", path) {
        case ("GET", "/"):
            answer(task, 200, "text/html; charset=utf-8", Data(PhonePage.html.utf8))
        case ("GET", "/app.js"):
            answer(task, 200, "text/javascript; charset=utf-8", Data(PhonePage.script.utf8))
        case ("GET", "/app.css"):
            answer(task, 200, "text/css; charset=utf-8", Data((PhonePage.style + PhonePage.colors).utf8))
        case ("GET", let path) where path.hasPrefix("/cat/"):
            if let drawn = PhoneCat.png(at: path) { answer(task, 200, "image/png", drawn) } else { answer(task, 404) }
        case ("GET", "/hello"):
            answer(task, admitted ? 204 : 401)
        case ("POST", "/pair"):
            let code = (try? JSONSerialization.jsonObject(with: body) as? [String: String])?["code"]
            if code == Self.code { json(task, ["key": Self.pass]) } else { answer(task, 403) }
        case ("GET", "/events"):
            guard admitted else { return answer(task, 401) }
            let key = query.first { $0.name == "key" }?.value ?? PhonePlace.home
            watched.append(key)
            streams.append((task, key))
            task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"])!)
            send(task, key: key)
        case ("POST", "/act"):
            guard admitted else { return answer(task, 401) }
            guard let ask = try? JSONDecoder().decode(PhoneAsk.self, from: body) else { return answer(task, 400) }
            if ask.act == "unattach" { return answer(task, 204) }
            let done = ask.action(in: book, newTopic: { "topic-1" }, file: { [files] in files[$0] })
            acts.append((ask, done?.action))
            guard let done else { return answer(task, 409) }
            json(task, done.opens.map { ["open": $0] } ?? [:])
        case ("POST", "/search"):
            guard admitted else { return answer(task, 401) }
            let words = (try? JSONSerialization.jsonObject(with: body) as? [String: String])?["words"] ?? ""
            searches.append(words)
            answer(task, 200, "application/json", (try? JSONEncoder().encode(PhoneFound(words, in: book, now: now))) ?? Data())
        case ("POST", "/file"):
            guard admitted else { return answer(task, 401) }
            let name = request.value(forHTTPHeaderField: "X-Name")?.removingPercentEncoding ?? ""
            uploads.append((name, request.value(forHTTPHeaderField: "Content-Type") ?? ""))
            let id = "file-\(uploads.count)"
            files[id] = .bytes(body, name: name)
            json(task, ["id": id])
        default:
            answer(task, 404)
        }
    }

    fileprivate func stop(_ task: WKURLSchemeTask) {
        streams.removeAll { $0.task === task }
    }

    private func send(_ task: WKURLSchemeTask, key: String) {
        let shown = PhoneView(PhonePlace(key, in: book), in: book, now: now, newFrom: book.newFrom)
        guard let json = try? JSONEncoder().encode(shown) else { return }
        task.didReceive(Data("data: ".utf8) + json + Data("\n\n".utf8))
    }

    private func json(_ task: WKURLSchemeTask, _ value: [String: String]) {
        answer(task, 200, "application/json", (try? JSONSerialization.data(withJSONObject: value)) ?? Data())
    }

    private func answer(_ task: WKURLSchemeTask, _ status: Int, _ type: String = "text/plain", _ body: Data = Data()) {
        guard let url = task.request.url else { return }
        task.didReceive(HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": type, "Content-Length": "\(body.count)"])!)
        task.didReceive(body)
        task.didFinish()
    }

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while case let count = stream.read(&buffer, maxLength: buffer.count), count > 0 { data.append(buffer, count: count) }
        return data
    }

    // MARK: Going anywhere else

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url, url.scheme != "phone" else { return decisionHandler(.allow) }
        followed.append(url)
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url { followed.append(url) }
        return nil
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor ([URL]?) -> Void) {
        panels += 1
        completionHandler(picks.isEmpty ? nil : picks)
    }
}

/// Held by the web view's configuration, which would otherwise keep the phone alive.
@MainActor
private final class SchemeHandler: NSObject, WKURLSchemeHandler {
    weak var phone: Phone?

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        phone?.start(task)
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        phone?.stop(task)
    }
}
