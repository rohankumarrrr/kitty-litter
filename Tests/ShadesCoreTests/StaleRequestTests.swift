import Foundation
import XCTest
@testable import ShadesCore

final class StaleRequestTests: XCTestCase {
    private var home: URL!
    private var kitten: URL { home.appendingPathComponent("kittens/clawde") }
    private var settings: URL { kitten.appendingPathComponent(".claude/settings.json") }
    private var files: SettingsFiles { SettingsFiles(home: home.path, kittenFolders: [kitten.path]) }
    private let original = "{\n  \"permissions\": {\n    \"allow\": [\n      \"Bash(swift test)\",\n    ]\n  }\n}\n"
    private let at = Date(timeIntervalSince1970: 1_000)

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("stale-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: kitten.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try Data(original.utf8).write(to: settings)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func block(_ object: [String: String]) -> String {
        let json = String(decoding: try! JSONSerialization.data(withJSONObject: object, options: .sortedKeys), as: UTF8.self)
        return "Done.\n\n```shades-request\n\(json)\n```"
    }

    private func write(_ text: String) throws {
        try Data(text.utf8).write(to: settings)
    }

    private var commaFix: ChangeRequest {
        files.check(ChangeRequest(file: settings.path, replace: "\"Bash(swift test)\",\n", with: "\"Bash(swift test)\"\n", why: nil))
    }

    private func card(_ id: String, _ thread: String, change: ChangeRequest? = nil, ask: AskRequest? = nil) -> InboxEntry {
        InboxEntry(id: id, kind: .decision, text: id, threadID: thread, threadTitle: "Work \(thread)", at: at, change: change, ask: ask)
    }

    func testAWithdrawNamesWhatItTakesBackAndNothingElse() throws {
        let found = ChangeRequests.all(in: block(["withdraw": "~/kittens/clawde/.claude/settings.json"]))
        XCTAssertEqual(try XCTUnwrap(found.first).get(), .withdraw("~/kittens/clawde/.claude/settings.json"))
        XCTAssertEqual(try ChangeRequests.all(in: block(["withdraw": "Email the\ninvite."])).first?.get(), .withdraw("Email the invite."))
        for refused in [
            ["withdraw": "x", "why": "Not needed."],
            ["withdraw": "x", "file": "x"],
            ["withdraw": "x", "ask": "x"],
            ["withdraw": " "],
            ["withdraw": "Email\u{202E} it."],
            ["withdraw": String(repeating: "a", count: 501)],
        ] {
            guard case .failure? = ChangeRequests.all(in: block(refused)).first else { return XCTFail("\(refused)") }
        }
    }

    func testTheSorterAndBubbleHearAWithdrawIsntACard() {
        let reply = block(["withdraw": "x"]) + "\n" + block(["ask": "Merge it."])
        XCTAssertEqual(
            ChangeRequests.withoutBlocks(reply, saying: "(card)", withdrawn: "(taken back)"),
            "Done.\n\n(taken back)\nDone.\n\n(card)"
        )
    }

    func testAChangeStaysAllowableOnlyWhileItsFileIsAsTheCardShowedIt() throws {
        let change = commaFix
        XCTAssertNil(change.problem)
        XCTAssertNil(files.staleness(of: change))

        try write(original.replacingOccurrences(of: "permissions", with: "permissions\" : {}, \"other"))
        XCTAssertEqual(files.staleness(of: change), .cantBeMade("The file changed after it asked."))

        try write("{}")
        XCTAssertEqual(files.staleness(of: change), .cantBeMade("The file changed after it asked. What it asks to replace isn't in the file."))

        try FileManager.default.removeItem(at: settings)
        XCTAssertEqual(files.staleness(of: change), .cantBeMade("The file changed after it asked. There's no file there to change yet."))
    }

    func testAChangeSomeoneAlreadyMadeIsAlreadyMade() throws {
        let change = commaFix
        try write(original.replacingOccurrences(of: "\"Bash(swift test)\",\n", with: "\"Bash(swift test)\"\n"))
        XCTAssertEqual(files.staleness(of: change), .alreadyMade)

        try write("{\"permissions\": {\"allow\": [\"Bash(swift test)\"]}}")
        let adding = files.check(ChangeRequest(file: settings.path, replace: "\"Bash(swift test)\"", with: "\"Bash(swift test)\", \"Bash(ls)\"", why: nil))
        XCTAssertNil(adding.problem)
        try files.apply(adding)
        XCTAssertEqual(files.staleness(of: adding), .alreadyMade, "what it puts in keeps what it replaces")

        let fresh = home.appendingPathComponent("shades/.claude")
        try FileManager.default.createDirectory(at: fresh, withIntermediateDirectories: true)
        let making = files.check(ChangeRequest(file: "~/shades/.claude/settings.json", replace: nil, with: "{}", why: nil))
        XCTAssertNil(files.staleness(of: making))
        try Data("{}".utf8).write(to: fresh.appendingPathComponent("settings.json"))
        XCTAssertEqual(files.staleness(of: making), .alreadyMade)
        try Data("{\"a\": 1}".utf8).write(to: fresh.appendingPathComponent("settings.json"))
        XCTAssertEqual(files.staleness(of: making), .cantBeMade("The file changed after it asked. The file is already there, so it can't be made new."))
    }

    func testARemovalIsOnlyMadeWhenTheFileIsExactlyWhatItWouldHaveMade() throws {
        let three = "{\n  \"allow\": [\n    \"Bash(swift build)\",\n    \"Bash(curl *)\",\n    \"Bash(swift test)\"\n  ]\n}\n"
        try write(three)
        let keepingNeighbour = files.check(ChangeRequest(file: settings.path, replace: "    \"Bash(swift build)\",\n    \"Bash(curl *)\",\n", with: "    \"Bash(swift build)\",\n", why: nil))
        let emptyWith = files.check(ChangeRequest(file: settings.path, replace: "    \"Bash(curl *)\",\n", with: "", why: nil))
        XCTAssertNil(keepingNeighbour.problem)
        XCTAssertNil(emptyWith.problem)

        try write(three.replacingOccurrences(of: "\"Bash(swift build)\",\n", with: "\"Bash(swift build)\",\n    \"Bash(ls)\",\n"))
        XCTAssertEqual(files.staleness(of: keepingNeighbour), .cantBeMade("The file changed after it asked. What it asks to replace isn't in the file."), "curl is still allowed")
        try write(three.replacingOccurrences(of: "    \"Bash(curl *)\",\n    \"Bash(swift test)\"\n", with: "    \"Bash(curl *)\"\n"))
        XCTAssertNotEqual(files.staleness(of: emptyWith), .alreadyMade, "curl is still allowed")

        try write(three.replacingOccurrences(of: "    \"Bash(curl *)\",\n", with: ""))
        XCTAssertEqual(files.staleness(of: keepingNeighbour), .alreadyMade)
    }

    func testAFileThatCantBeFoundRightNowIsNoReasonToTakeAllowAway() {
        let change = commaFix
        XCTAssertNil(SettingsFiles(home: home.path, kittenFolders: []).staleness(of: change), "its kitten wasn't in one reading of the list")
        XCTAssertNil(files.staleness(of: change))
    }

    func testAListedFileIsNamedTheWayACardShowsIt() {
        XCTAssertEqual(files.shown(listed: settings.path), "~/kittens/clawde/.claude/settings.json")
        XCTAssertEqual(files.shown(listed: "~/kittens/clawde/.claude/settings.json"), "~/kittens/clawde/.claude/settings.json")
        XCTAssertNil(files.shown(listed: "~/.claude/settings.json"))
        XCTAssertNil(files.shown(listed: "Email the invite."))
    }

    func testANewerRequestFromTheSameThreadForTheSameThingReplacesTheOlderCard() {
        var inbox = Inbox(since: at)
        let first = ChangeRequest(file: "~/k/.claude/settings.json", replace: "a", with: "b", why: nil)
        var revised = first
        revised.with = "c"
        var elsewhere = first
        elsewhere.replace = "z"
        inbox.ask(card("c1", "t", change: first))
        inbox.ask(card("c2", "t", change: revised))
        XCTAssertEqual(inbox.entries.map(\.id), ["c2"])
        inbox.ask(card("c3", "t", change: elsewhere))
        inbox.ask(card("c4", "u", change: first))
        XCTAssertEqual(inbox.entries.map(\.id), ["c2", "c3", "c4"], "another place in the file, or another thread, is a card of its own")

        inbox.ask(card("a1", "t", ask: AskRequest(ask: "Merge it.", readFromWords: false)))
        inbox.ask(card("a2", "t", ask: AskRequest(ask: "Merge it.", readFromWords: false)))
        inbox.ask(card("a3", "t", ask: AskRequest(ask: "Send it.", readFromWords: false)))
        inbox.ask(card("a4", "u", ask: AskRequest(ask: "Merge it.", readFromWords: false)))
        XCTAssertEqual(inbox.entries.compactMap { $0.ask == nil ? nil : $0.id }, ["a2", "a3", "a4"])
    }

    func testANewerRequestReplacesAStaleOne() {
        var inbox = Inbox(since: at)
        let change = ChangeRequest(file: "~/k/.claude/settings.json", replace: "a", with: "b", why: nil)
        inbox.ask(card("old", "t", change: change))
        inbox.cantBeMade("old", because: "The file changed after it asked.", row: "Stale.")
        inbox.ask(card("new", "t", change: change))
        XCTAssertEqual(inbox.entries.map(\.id), ["new"])
        XCTAssertNil(inbox.entries.first?.change?.problem)
    }

    func testAThreadWithdrawsOnlyWhatItAskedForItself() {
        var inbox = Inbox(since: at)
        let mine = ChangeRequest(file: "~/k/.claude/settings.json", replace: "a", with: "b", why: nil)
        var notListed = ChangeRequest(file: "~/.claude/settings.json", replace: "a", with: "b", why: nil)
        notListed.problem = "It isn't listed."
        inbox.ask(card("c", "t", change: mine))
        inbox.ask(card("n", "t", change: notListed))
        inbox.ask(card("other", "u", change: ChangeRequest(file: "~/k/.claude/settings.json", replace: "x", with: "y", why: nil)))
        inbox.ask(card("a", "t", ask: AskRequest(ask: "Merge it.", readFromWords: false)))
        inbox.ask(card("theirs", "u", ask: AskRequest(ask: "Merge it.", readFromWords: false)))
        inbox.file(SortedReport(decision: "Merge it?"), from: AgentThread(id: "t", title: "Work t", projectTitle: nil, status: .completed, model: "m", updatedAt: at, lastRunID: "r"), at: at, id: { "decision" })
        _ = inbox.attach(AskRequest(ask: "Merge it.", readFromWords: true), to: "decision")
        let before = inbox.entries.map(\.id)

        inbox.withdraw("~/k/.claude/settings.json", file: nil, by: "nobody")
        inbox.withdraw("Merge it.", file: nil, by: "nobody")
        XCTAssertEqual(inbox.entries.map(\.id), before, "a thread that didn't ask takes nothing back")

        inbox.withdraw("/home/k/.claude/settings.json", file: "~/k/.claude/settings.json", by: "t")
        inbox.withdraw("~/.claude/settings.json", file: nil, by: "t")
        inbox.withdraw("Merge it.", file: nil, by: "t")
        XCTAssertEqual(inbox.entries.map(\.id), ["other", "theirs", "decision"], "only its own, and never a decision's reading")
        XCTAssertNotNil(inbox.entries.first { $0.id == "decision" }?.ask)
    }

    func testAShareOfACardIsTakenBackWithoutTakingTheCardFromAnotherThread() {
        var inbox = Inbox(since: at)
        let change = ChangeRequest(file: "~/k/.claude/settings.json", replace: "a", with: "b", why: nil)
        inbox.ask(card("c", "t", change: change))
        inbox.ask(card("c2", "u", change: change))
        inbox.ask(card("c3", "v", change: change))
        XCTAssertEqual(inbox.entries.first?.change?.alsoAskedIn, ["u", "v"])

        inbox.withdraw("~/k/.claude/settings.json", file: nil, by: "v")
        XCTAssertEqual(inbox.entries.map(\.id), ["c"])
        XCTAssertEqual(inbox.entries.first?.change?.alsoAskedIn, ["u"])

        inbox.withdraw("~/k/.claude/settings.json", file: nil, by: "t", title: { $0 == "u" ? "Steve: Simulator" : nil })
        XCTAssertEqual(inbox.entries.map(\.id), ["c"], "the card stays for the thread still asking")
        XCTAssertEqual(inbox.entries.first?.threadID, "u")
        XCTAssertEqual(inbox.entries.first?.threadTitle, "Steve: Simulator")
        XCTAssertEqual(inbox.entries.first?.change?.alsoAskedIn, [])

        inbox.withdraw("~/k/.claude/settings.json", file: nil, by: "u")
        XCTAssertTrue(inbox.entries.isEmpty)
    }

    func testAStaleChangeKeepsItsReasonAndLosesItsAllow() {
        var inbox = Inbox(since: at)
        var change = ChangeRequest(file: "~/k/.claude/settings.json", replace: "a", with: "b", why: nil)
        change.review = "I'd allow it."
        inbox.ask(card("c", "t", change: change))
        inbox.cantBeMade("c", because: "The file changed after it asked.", row: "Can't be done.")
        XCTAssertEqual(inbox.entries.first?.change?.problem, "The file changed after it asked.")
        XCTAssertNil(inbox.entries.first?.change?.review, "no look at it that says to allow it")
        XCTAssertEqual(inbox.entries.first?.text, "Can't be done.")
        inbox.cantBeMade("c", because: "Something else.", row: "Other.")
        XCTAssertEqual(inbox.entries.first?.change?.problem, "The file changed after it asked.", "the first reason stands")
    }

    func testAnInboxSavedBeforeTheseLoadsWhole() throws {
        let folder = home.appendingPathComponent("support")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("inbox.json")
        let older = #"""
            {"entries":[{"id":"c","kind":"decision","text":"Asks to change it.","threadID":"t","threadTitle":"Work","at":1000,
              "change":{"file":"~/k/.claude/settings.json","replace":"a","with":"b","before":"00","opensScreenBlock":[],"widens":[],"alsoAskedIn":["u"]}},
              {"id":"a","kind":"decision","text":"Merge it.","threadID":"t","threadTitle":"Work","at":1000,
              "ask":{"ask":"Merge it.","readFromWords":false}}],
             "handled":{"t":"run-1"},"since":0}
            """#
        try older.write(to: file, atomically: true, encoding: .utf8)
        let loaded = Inbox.load(from: file, now: at)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("inbox.broken.json").path))
        XCTAssertEqual(loaded.entries.map(\.id), ["c", "a"])
        XCTAssertEqual(loaded.entries.first?.change?.alsoAskedIn, ["u"])
    }
}
