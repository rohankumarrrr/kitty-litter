import ShadesCore
import XCTest

/// The focus and each kitten's backlog, read from the plain files kittens keep. Everything here is made up.
final class PrioritiesTests: XCTestCase {
    func testTheFocusIsTheFirstLineUnderRightNowWithItsBoldTakenOff() {
        let file = """
        # What comes first

        Every kitten reads this.

        ## Right now

        **Focus: the garden show, until Sat 9 AM**

        More about it.

        ## How it works
        """
        XCTAssertEqual(Priorities.focus(in: file), "Focus: the garden show, until Sat 9 AM")
    }

    func testNoFocusAnEmptySectionOrNoSectionShowsNothing() {
        XCTAssertNil(Priorities.focus(in: "## Right now\n\nNo focus. Work as usual.\n"))
        XCTAssertNil(Priorities.focus(in: "## Right now\n\n**No focus. Work as usual.**\n"))
        XCTAssertNil(Priorities.focus(in: "## Right now\n\n## How it works\nSomething else"), "the next heading isn't the focus")
        XCTAssertNil(Priorities.focus(in: "## Right now\n"))
        XCTAssertNil(Priorities.focus(in: "# What comes first\n\nFocus: not under the heading\n"))
        XCTAssertNil(Priorities.focus(in: ""))
    }

    func testABacklogsItemsComeUnderTheirLevelsWithEachField() {
        let backlog = Backlog(reading: """
        # Backlog

        What waits on a focus.

        ## Doing
        - 2026-01-02 · Paint the fence · "paint the fence · the blue one" · thread t-1

        ## Next
        - 2026-01-03 · Plant the bulbs · "bulbs before it freezes" · thread t-2
        - 2026-01-04 · Fix the gate

        ## Later
        """)
        XCTAssertEqual(backlog.items, [
            Backlog.Item(level: .doing, date: "2026-01-02", what: "Paint the fence", words: "paint the fence · the blue one", thread: "t-1"),
            Backlog.Item(level: .next, date: "2026-01-03", what: "Plant the bulbs", words: "bulbs before it freezes", thread: "t-2"),
            Backlog.Item(level: .next, date: "2026-01-04", what: "Fix the gate"),
        ])
    }

    func testALineInAnotherFormStillShowsAndNothingElseBreaks() {
        let backlog = Backlog(reading: """
        ## Later
        - Sweep the porch
        - “curly quotes kept apart” · thread t-9
        -
        * not an item
        Notes under a level aren't items.

        ## Next
          - 2026-01-05 · Indented, still an item

        ## Someday
        - Under a heading it doesn't know
        """)
        XCTAssertEqual(backlog.items, [
            Backlog.Item(level: .next, date: "2026-01-05", what: "Indented, still an item"),
            Backlog.Item(level: .later, what: "Sweep the porch"),
            Backlog.Item(level: .later, what: "“curly quotes kept apart”", thread: "t-9"),
        ], "Next comes before Later, whatever order the file has")
        XCTAssertEqual(Backlog(reading: "").items, [])
        XCTAssertEqual(Backlog(reading: "## Doing\n\n## Next\n\n## Later\n").items, [])
    }

    func testReadingLeavesOutWhatsMissingAndKeepsTheRest() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("priorities-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let filed = home.appendingPathComponent("filed", isDirectory: true)
        let empty = home.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: filed, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        try "## Next\n- 2026-01-03 · Plant the bulbs\n".write(to: filed.appendingPathComponent("backlog.md"), atomically: true, encoding: .utf8)
        let kittens = [
            Kitten(name: "Filed", role: "", covers: "", folder: filed.path),
            Kitten(name: "Empty", role: "", covers: "", folder: empty.path),
        ]

        var read = Priorities.read(for: kittens, in: home)
        XCTAssertNil(read.focus, "no FOCUS.md")
        XCTAssertEqual(read.backlogs[filed.path]?.items.map(\.what), ["Plant the bulbs"])
        XCTAssertNil(read.backlogs[empty.path], "no backlog.md")

        try "## Right now\n\n**Focus: the garden show**\n".write(to: home.appendingPathComponent("FOCUS.md"), atomically: true, encoding: .utf8)
        read = Priorities.read(for: kittens, in: home)
        XCTAssertEqual(read.focus, "Focus: the garden show")
    }
}
