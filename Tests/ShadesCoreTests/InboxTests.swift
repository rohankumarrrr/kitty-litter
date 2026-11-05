import ShadesCore
import XCTest

final class InboxTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    private func thread(
        _ id: String = "t",
        run: String? = "run-1",
        status: AgentStatus = .completed,
        ended: TimeInterval = 10
    ) -> AgentThread {
        AgentThread(
            id: id,
            title: "Clawde: Work",
            projectTitle: nil,
            status: status,
            model: "m",
            updatedAt: start.addingTimeInterval(ended),
            lastRunID: run,
            lastRunEndedAt: start.addingTimeInterval(ended)
        )
    }

    private func counter() -> () -> String {
        var count = 0
        return {
            count += 1
            return "row-\(count)"
        }
    }

    // MARK: - What's owed

    func testAFinishedRunIsOwedOnceWhetherItWorkedOrNot() {
        var inbox = Inbox(since: start)
        XCTAssertTrue(inbox.owes(thread()))
        XCTAssertTrue(inbox.owes(thread(status: .failed)))
        inbox.file(SortedReport(shipped: "Done."), from: thread(), at: start, id: counter())
        XCTAssertFalse(inbox.owes(thread()))
        XCTAssertTrue(inbox.owes(thread(run: "run-2")))
    }

    func testNothingOlderThanSinceIsOwed() {
        let inbox = Inbox(since: start)
        XCTAssertFalse(inbox.owes(thread(ended: -1)))
        XCTAssertTrue(inbox.owes(thread(ended: 0)))
    }

    func testARunStillGoingIsntOwed() {
        let inbox = Inbox(since: start)
        for status in [AgentStatus.starting, .running, .waitingForApproval, .waitingForAnswer, .idle, .interrupted] {
            XCTAssertFalse(inbox.owes(thread(status: status)), "\(status)")
        }
    }

    func testAThreadWithNoRunIDIsntOwed() {
        XCTAssertFalse(Inbox(since: start).owes(thread(run: nil)))
    }

    func testARunWithNoEndTimeGoesByTheLastUpdate() {
        var old = thread(ended: -1)
        old.lastRunEndedAt = nil
        XCTAssertFalse(Inbox(since: start).owes(old))
        var new = thread()
        new.lastRunEndedAt = nil
        XCTAssertTrue(Inbox(since: start).owes(new), "nothing would ever say it finished")
    }

    func testSkippingMeansItsNotOwed() {
        var inbox = Inbox(since: start)
        inbox.skip(thread())
        XCTAssertFalse(inbox.owes(thread()))
        XCTAssertTrue(inbox.entries.isEmpty)
    }

    // MARK: - Filing

    /// The rules for what a report does to the rows already there, as a table.
    func testFilingRules() {
        struct Case {
            var name: String
            var sorted: SortedReport
            var replied: Bool
            var kept: [String]
            var answerOn: String?
            var stillDim: [String]
        }
        let cases = [
            Case(name: "a decision replaces the thread's decisions", sorted: SortedReport(decision: "New?"), replied: true,
                 kept: ["old shipped", "other decision", "New?"], stillDim: []),
            Case(name: "shipped does too", sorted: SortedReport(shipped: "New."), replied: false,
                 kept: ["old shipped", "other decision", "New."], stillDim: []),
            Case(name: "both come through", sorted: SortedReport(shipped: "New.", decision: "New?"), replied: false,
                 kept: ["old shipped", "other decision", "New?", "New."], stillDim: []),
            Case(name: "a note goes on the row you replied on", sorted: SortedReport(note: "Because."), replied: true,
                 kept: ["old decision", "old shipped", "other decision"], answerOn: "old decision", stillDim: []),
            Case(name: "a note you didn't ask for goes under the thread's decision", sorted: SortedReport(note: "Because."), replied: false,
                 kept: ["old decision", "old shipped", "other decision"], answerOn: "old decision", stillDim: []),
        ]
        for test in cases {
            var inbox = Inbox(since: start)
            inbox.file(SortedReport(shipped: "old shipped", decision: "old decision"), from: thread(), at: start, id: counter())
            let otherID: () -> String = { "other" }
            inbox.file(SortedReport(decision: "other decision"), from: thread("o"), at: start, id: otherID)
            if test.replied { inbox.markReplied("row-1", at: start) }

            var nextID = 10
            inbox.file(test.sorted, from: thread(run: "run-2"), at: start) {
                nextID += 1
                return "row-\(nextID)"
            }

            XCTAssertEqual(inbox.entries.map(\.text), test.kept, test.name)
            XCTAssertEqual(inbox.entries.first { $0.answer != nil }?.text, test.answerOn, test.name)
            XCTAssertEqual(inbox.entries.filter { $0.repliedAt != nil }.map(\.text), test.stillDim, test.name)
        }
    }

    func testAnAnswerGoesOnTheNewestRowYouRepliedOn() {
        var inbox = Inbox(since: start)
        inbox.file(SortedReport(shipped: "A.", decision: "B?"), from: thread(), at: start, id: counter())
        inbox.markReplied("row-2", at: start.addingTimeInterval(5))
        inbox.markReplied("row-1", at: start.addingTimeInterval(1))
        inbox.file(SortedReport(note: "Because."), from: thread(run: "run-2"), at: start, id: counter())
        XCTAssertEqual(inbox.entries.first { $0.id == "row-2" }?.answer, "Because.")
        XCTAssertNil(inbox.entries.first { $0.id == "row-1" }?.answer)
        XCTAssertNotNil(inbox.entries.first { $0.id == "row-1" }?.repliedAt)
    }

    func testAFreshAnswerReplacesTheLastOneAndOtherNotesWaitWithIt() {
        var inbox = Inbox(since: start)
        inbox.file(SortedReport(decision: "B?"), from: thread(), at: start, id: counter())
        inbox.file(SortedReport(note: "One."), from: thread(run: "r2"), at: start, id: counter())
        inbox.file(SortedReport(note: "Two."), from: thread(run: "r3"), at: start, id: counter())
        XCTAssertEqual(inbox.entries[0].answer, "One.\n\nTwo.")
        inbox.markReplied("row-1", at: start)
        inbox.file(SortedReport(note: "Three."), from: thread(run: "r4"), at: start, id: counter())
        XCTAssertEqual(inbox.entries[0].answer, "Three.")
    }

    func testAnAnsweredDecisionNeedsYouAgain() {
        var inbox = Inbox(since: start)
        inbox.file(SortedReport(decision: "B?"), from: thread(), at: start, id: counter())
        inbox.markReplied("row-1", at: start)
        XCTAssertFalse(inbox.entries[0].needsYou)
        inbox.file(SortedReport(note: "Because."), from: thread(run: "run-2"), at: start, id: counter())
        XCTAssertTrue(inbox.entries[0].needsYou)
    }

    func testANoteGoesUnderTheThreadsLatestRowIfThatsAllItHas() {
        var inbox = Inbox(since: start)
        inbox.file(SortedReport(shipped: "A."), from: thread(), at: start, id: counter())
        inbox.file(SortedReport(note: "Because."), from: thread(run: "run-2"), at: start, id: counter())
        XCTAssertEqual(inbox.entries.map(\.text), ["A."])
        XCTAssertEqual(inbox.entries.map(\.answer), ["Because."])
    }

    func testANoteWithNoRowIsKeptWithoutBeingCalledShipped() {
        var inbox = Inbox(since: start)
        inbox.file(SortedReport(note: "Nothing to report."), from: thread(), at: start, id: counter())
        XCTAssertEqual(inbox.entries.map(\.kind), [.note])
        XCTAssertEqual(inbox.entries.map(\.text), ["Nothing to report."])
        XCTAssertFalse(inbox.entries[0].needsYou)
    }

    func testFilingSaysWhetherItsWorthTellingYou() {
        var inbox = Inbox(since: start)
        let ids = counter()
        XCTAssertFalse(inbox.file(SortedReport(note: "A."), from: thread("n"), at: start, id: ids), "a note can wait")
        XCTAssertTrue(inbox.file(SortedReport(shipped: "B."), from: thread("s"), at: start, id: ids))
        XCTAssertFalse(inbox.file(SortedReport(note: "C."), from: thread("s", run: "r2"), at: start, id: ids), "nor one under a row")
        XCTAssertTrue(inbox.file(SortedReport(decision: "D?"), from: thread("d"), at: start, id: ids))
        XCTAssertFalse(inbox.file(SortedReport(decision: "D?"), from: thread("d"), at: start, id: ids), "already filed")

        let shipped = inbox.entries.first { $0.threadID == "s" }!
        inbox.markReplied(shipped.id, at: start)
        XCTAssertTrue(inbox.file(SortedReport(note: "E."), from: thread("s", run: "r3"), at: start, id: ids), "you asked, so you hear")
    }

    func testClearingOneKindLeavesTheOthers() {
        var inbox = Inbox(since: start)
        inbox.file(SortedReport(shipped: "A."), from: thread("s"), at: start, id: counter())
        inbox.file(SortedReport(note: "B."), from: thread("n"), at: start, id: counter())
        inbox.clear(.shipped)
        XCTAssertEqual(inbox.entries.map(\.kind), [.note])
        inbox.clear(.note)
        XCTAssertTrue(inbox.entries.isEmpty)
    }

    func testANoteAlongsideRowsIsntLostOrSaidTwice() {
        var inbox = Inbox(since: start)
        inbox.file(SortedReport(shipped: "A.", note: "Also this."), from: thread(), at: start, id: counter())
        XCTAssertEqual(inbox.entries.map(\.text), ["A. Also this."])

        var both = Inbox(since: start)
        both.file(SortedReport(shipped: "A.", decision: "B?", note: "Also this."), from: thread(), at: start, id: counter())
        XCTAssertEqual(both.entries.map(\.text), ["B? Also this.", "A."])
    }

    func testFilingTheSameRunTwiceChangesNothing() {
        var inbox = Inbox(since: start)
        inbox.file(SortedReport(decision: "First?"), from: thread(), at: start, id: counter())
        let before = inbox
        inbox.file(SortedReport(shipped: "Again.", note: "Again."), from: thread(), at: start, id: counter())
        XCTAssertEqual(inbox, before)
    }

    func testRemovingOneAndClearingShipped() {
        var inbox = Inbox(since: start)
        inbox.file(SortedReport(shipped: "A.", decision: "B?"), from: thread(), at: start, id: counter())
        inbox.file(SortedReport(decision: "C?"), from: thread("o"), at: start, id: { "other" })
        inbox.remove("other")
        XCTAssertEqual(inbox.entries.map(\.text), ["B?", "A."])
        inbox.clear(.shipped)
        XCTAssertEqual(inbox.entries.map(\.text), ["B?"])
    }

    func testASendThatFailedPutsTheRowBack() {
        var inbox = Inbox(since: start)
        inbox.file(SortedReport(decision: "B?"), from: thread(), at: start, id: counter())
        inbox.markReplied("row-1", at: start)
        inbox.markReplied("row-1", at: nil)
        XCTAssertTrue(inbox.entries[0].needsYou)
    }

    func testThePanelsOrder() {
        func row(_ id: String, _ kind: InboxEntry.Kind, at: TimeInterval, replied: Bool = false) -> InboxEntry {
            InboxEntry(id: id, kind: kind, text: id, threadID: id, threadTitle: id, at: start.addingTimeInterval(at), repliedAt: replied ? start : nil)
        }
        let rows = [
            row("shipped old", .shipped, at: 1),
            row("replied old", .decision, at: 2, replied: true),
            row("needs old", .decision, at: 3),
            row("shipped new", .shipped, at: 4),
            row("replied new", .decision, at: 5, replied: true),
            row("needs new", .decision, at: 6),
            row("shipped replied", .shipped, at: 7, replied: true),
            row("note", .note, at: 8),
        ]
        XCTAssertEqual(Inbox.panelOrder(rows).map(\.id), [
            "needs new", "needs old", "replied new", "replied old", "shipped replied", "shipped new", "shipped old", "note",
        ])
    }

    func testRowsFromOneReportStayInOrderNewestFirst() {
        var rows: [InboxEntry] = []
        for id in ["a", "b"] {
            rows.append(InboxEntry(id: id, kind: .shipped, text: id, threadID: id, threadTitle: id, at: start))
        }
        XCTAssertEqual(Inbox.panelOrder(rows).map(\.id), ["b", "a"])
    }

    // MARK: - Reading a sorted reply

    func testTheMarkersAreRead() {
        let sorted = SortedReport(reply: """
        SHIPPED: The icon is live.
        DECISION: Ship the fix? Tests pass.
        NOTE: The risk is low.
        """)
        XCTAssertEqual(sorted, SortedReport(shipped: "The icon is live.", decision: "Ship the fix? Tests pass.", note: "The risk is low."))
    }

    func testContinuationLinesAreJoined() {
        let sorted = SortedReport(reply: """
        DECISION: Ship the fix?

          Tests pass.
        Say ship it.
        SHIPPED: Done.
        """)
        XCTAssertEqual(sorted?.decision, "Ship the fix? Tests pass. Say ship it.")
        XCTAssertEqual(sorted?.shipped, "Done.")
    }

    func testAMarkerSaidTwiceKeepsBoth() {
        XCTAssertEqual(SortedReport(reply: "SHIPPED: One.\nSHIPPED: Two.")?.shipped, "One. Two.")
    }

    func testPassedIsReadAndCountsAsAnAnswer() {
        XCTAssertEqual(SortedReport(reply: "PASSED: yes"), SortedReport(passedOn: true))
        XCTAssertEqual(SortedReport(reply: "PASSED: yes")?.hasLines, false)
        XCTAssertNil(SortedReport(reply: "PASSED: none"))
        XCTAssertNil(SortedReport(reply: "PASSED: no"))
        XCTAssertEqual(SortedReport(reply: "PASSED: no\nNOTE: Still going.")?.passedOn, false)
        XCTAssertEqual(SortedReport(reply: "PASSED: Yes.")?.passedOn, true)
    }

    func testAnythingBeforeTheFirstMarkerIsIgnored() {
        XCTAssertEqual(SortedReport(reply: "Here you go:\nSHIPPED: Done."), SortedReport(shipped: "Done."))
    }

    func testAMarkerIsReadInAnyCase() {
        XCTAssertEqual(SortedReport(reply: "Decision: Which one?"), SortedReport(decision: "Which one?"))
    }

    func testNoneAndEmptyAreDropped() {
        let sorted = SortedReport(reply: "SHIPPED: none\nDECISION:\nNOTE: None.\nSHIPPED:")
        XCTAssertNil(sorted, "nothing's left to file")
        XCTAssertEqual(SortedReport(reply: "SHIPPED: none\nDECISION: Which?"), SortedReport(decision: "Which?"))
    }

    func testNoMarkerIsNil() {
        XCTAssertNil(SortedReport(reply: "It went well, and I've shipped it."))
        XCTAssertNil(SortedReport(reply: ""))
    }

    func testAMarkerPartWayThroughALineIsJustWords() {
        XCTAssertNil(SortedReport(reply: "Not really SHIPPED: yet."))
    }

    func testEachLineIsCut() {
        let sorted = SortedReport(reply: "NOTE: " + String(repeating: "word ", count: 200))
        XCTAssertEqual(sorted?.note?.count, 400)
    }

    // MARK: - Saving

    private func folder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("inbox-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testSavingAndLoadingKeepsEverything() throws {
        let file = try folder().appendingPathComponent("deep/inbox.json")
        var inbox = Inbox(since: start)
        inbox.file(SortedReport(shipped: "A.", decision: "B?"), from: thread(), at: start, id: counter())
        inbox.markReplied("row-1", at: start)
        try inbox.save(to: file)

        let loaded = Inbox.load(from: file, now: start.addingTimeInterval(100))
        XCTAssertEqual(loaded, inbox)
        XCTAssertFalse(loaded.owes(thread()), "what's handled stays handled")
        XCTAssertTrue(loaded.owes(thread(run: "run-2")), "and since stays where it was")
    }

    // MARK: - What you've read

    func testAFinishedRunIsUnreadUntilYouveSeenIt() {
        var inbox = Inbox(since: start)
        XCTAssertTrue(inbox.isUnread(thread()))
        XCTAssertFalse(inbox.isUnread(thread(status: .running)), "one still going isn't news yet")
        XCTAssertFalse(inbox.isUnread(thread(run: nil)))
        XCTAssertFalse(inbox.isUnread(thread(ended: -1)), "nothing from before since")

        XCTAssertTrue(inbox.markRead([thread(), thread("other", status: .running)]))
        XCTAssertFalse(inbox.isUnread(thread()))
        XCTAssertTrue(inbox.isUnread(thread(run: "run-2")), "its next run is news again")
        XCTAssertFalse(inbox.markRead([thread()]), "seeing it twice changes nothing, so there's nothing to save")
    }

    func testWhatYouveReadIsSavedAsIDsAndAFileFromBeforeItStillLoads() throws {
        let file = try folder().appendingPathComponent("inbox.json")
        var inbox = Inbox(since: start)
        _ = inbox.markRead([thread()])
        try inbox.save(to: file)
        XCTAssertFalse(Inbox.load(from: file, now: start).isUnread(thread()))
        let saved = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(saved.contains(#""t" : "run-1""#))
        XCTAssertFalse(saved.contains("Clawde"), "no titles or words, only IDs")

        let older = #"{"entries":[],"handled":{},"since":-999999999}"#
        try older.write(to: file, atomically: true, encoding: .utf8)
        let loaded = Inbox.load(from: file, now: start)
        XCTAssertTrue(loaded.isUnread(thread()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.deletingLastPathComponent().appendingPathComponent("inbox.broken.json").path))
    }

    func testOnlyYouCanReadIt() throws {
        let file = try folder().appendingPathComponent("inbox.json")
        try Inbox(since: start).save(to: file)
        try Inbox(since: start).save(to: file)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
    }

    func testNoFileStartsFromNow() throws {
        let file = try folder().appendingPathComponent("inbox.json")
        let inbox = Inbox.load(from: file, now: start)
        XCTAssertTrue(inbox.entries.isEmpty)
        XCTAssertFalse(inbox.owes(thread(ended: -1)))
        XCTAssertTrue(inbox.owes(thread(ended: 1)))
    }

    func testABrokenFileIsMovedAsideAndNewsSinceThenStillCounts() throws {
        let root = try folder()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("inbox.json")
        let written = start.addingTimeInterval(50)
        try Data("not json".utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: written], ofItemAtPath: file.path)

        let inbox = Inbox.load(from: file, now: start.addingTimeInterval(500))

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("inbox.broken.json")), Data("not json".utf8))
        XCTAssertTrue(inbox.owes(thread(ended: 100)), "that ended after the file was last good")
        XCTAssertFalse(inbox.owes(thread(ended: 10)))
    }

    func testAFileThatCantBeReadIsntOverwritten() throws {
        let root = try folder()
        let file = root.appendingPathComponent("inbox.json")
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        _ = Inbox.load(from: file, now: start)
        var isFolder: ObjCBool = false
        let moved = root.appendingPathComponent("inbox.broken.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.path, isDirectory: &isFolder))
        XCTAssertTrue(isFolder.boolValue, "whatever was there is kept")
    }

    func testAKittenSaysWhetherItUsesTheInbox() throws {
        let root = try folder()
        for (name, json) in [
            ("yes", #"{"name":"Yes","role":"r","covers":"c","inbox":true}"#),
            ("no", #"{"name":"No","role":"r","covers":"c"}"#),
        ] {
            let home = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            try Data(json.utf8).write(to: home.appendingPathComponent("kitten.json"))
        }
        XCTAssertEqual(Kittens.load(from: root).map(\.usesInbox), [false, true])
    }

    func testTheFileIsNeverReadableByOthersEvenWhileSaving() throws {
        final class Modes: @unchecked Sendable {
            private let lock = NSLock()
            private var seen: Set<UInt16> = []
            private var running = true
            var isRunning: Bool { lock.withLock { running } }
            func add(_ mode: UInt16) { lock.withLock { _ = seen.insert(mode) } }
            func stop() -> Set<UInt16> {
                lock.withLock {
                    running = false
                    return seen
                }
            }
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("inbox.json")
        var inbox = Inbox(since: start)
        inbox.file(SortedReport(decision: String(repeating: "private ", count: 50)), from: thread(), at: start, id: counter())

        let modes = Modes()
        let watcher = Thread {
            while modes.isRunning {
                for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] {
                    var info = stat()
                    if stat(folder.appendingPathComponent(name).path, &info) == 0 { modes.add(info.st_mode & 0o777) }
                }
            }
        }
        watcher.start()
        for _ in 0..<500 { try inbox.save(to: file) }
        XCTAssertEqual(modes.stop(), [0o600])
    }
}
