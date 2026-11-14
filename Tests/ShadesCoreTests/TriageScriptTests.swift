import Foundation
import XCTest

/// Runs a copy of scripts/triage.sh whose `log` and `ps` are stand-ins, to check it only ever reads the processes on
/// its list. The stand-in `log` writes down what it was asked and prints made-up lines, and `ps` prints a made-up table.
final class TriageScriptTests: XCTestCase {
    private var root: URL!
    private var script: URL { root.appendingPathComponent("triage.sh") }
    private var logArguments: URL { root.appendingPathComponent("log-arguments") }
    private var psRan: URL { root.appendingPathComponent("ps-ran") }

    private static let start = "2026-01-31 09:00:00", end = "2026-01-31 10:00:00"
    private static let wholeList = [
        "codesign", "trustd", "securityd", "SecurityAgent", "syspolicyd", "amfid", "tccd", "runningboardd",
        "launchservicesd", "lsd", "Shades",
    ]

    override func setUpWithError() throws {
        let files = FileManager.default
        root = files.temporaryDirectory.appendingPathComponent("triage-\(UUID().uuidString)")
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        func write(_ text: String, to file: URL) throws {
            try text.write(to: file, atomically: true, encoding: .utf8)
            try files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        try write(#"""
            #!/bin/zsh -f
            print -rl -- "$@" > "$STANDIN/log-arguments"
            if [[ -n "${LOG_REFUSES:-}" ]]; then print -r -- "$LOG_REFUSES" >&2; exit 64; fi
            for (( i = 1; i <= ${LOG_LINES:-0}; i++ )); do print "line $i"; done
            """#, to: root.appendingPathComponent("log"))
        try write(#"""
            #!/bin/zsh -f
            touch "$STANDIN/ps-ran"
            [[ -f "$STANDIN/ps-table" ]] && cat "$STANDIN/ps-table"
            """#, to: root.appendingPathComponent("ps"))

        let real = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/triage.sh")
        let copy = try String(contentsOf: real, encoding: .utf8)
            .replacingOccurrences(of: "/usr/bin/log ", with: root.appendingPathComponent("log").path + " ")
            .replacingOccurrences(of: "/bin/ps ", with: root.appendingPathComponent("ps").path + " ")
        XCTAssertFalse(copy.contains("/usr/bin/log") || copy.contains("/bin/ps"), "the copy runs only the stand-ins")
        try write(copy, to: script)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func run(_ arguments: String..., environment extra: [String: String] = [:]) throws -> (status: Int32, output: String, errors: String) {
        let out = root.appendingPathComponent("out"), err = root.appendingPathComponent("err")
        FileManager.default.createFile(atPath: out.path, contents: nil)
        FileManager.default.createFile(atPath: err.path, contents: nil)
        let process = Process()
        process.executableURL = script
        process.arguments = arguments
        process.environment = ["STANDIN": root.path, "HOME": root.path].merging(extra) { $1 }
        process.standardOutput = try FileHandle(forWritingTo: out)
        process.standardError = try FileHandle(forWritingTo: err)
        try process.run()
        process.waitUntilExit()
        return (process.terminationStatus, try String(contentsOf: out, encoding: .utf8), try String(contentsOf: err, encoding: .utf8))
    }

    /// What the stand-in `log` was asked, as flag and value, after `show`.
    private func askedLog() throws -> [String: String] {
        let arguments = try String(contentsOf: logArguments, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init)
        XCTAssertEqual(arguments.first, "show")
        var asked: [String: String] = [:]
        var rest = arguments.dropFirst()
        while let flag = rest.popFirst() {
            asked[flag] = flag == "--info" ? "" : rest.popFirst() ?? "missing"
        }
        return asked
    }

    private func predicate(_ names: [String]) -> String {
        names.map { "process == \"\($0)\"" }.joined(separator: " OR ")
    }

    private var logRan: Bool { FileManager.default.fileExists(atPath: logArguments.path) }

    private func assertRefused(_ result: (status: Int32, output: String, errors: String), _ why: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(result.status, 2, "\(why): \(result.errors)", file: file, line: line)
        XCTAssertEqual(result.output, "", why, file: file, line: line)
        XCTAssertFalse(logRan, "\(why): log never ran", file: file, line: line)
        XCTAssertFalse(FileManager.default.fileExists(atPath: psRan.path), "\(why): ps never ran", file: file, line: line)
    }

    // MARK: logs

    func testWithNoProcessNamedItReadsTheWholeListAndNothingElse() throws {
        let result = try run("logs", "--start", Self.start, "--end", Self.end)
        XCTAssertEqual(result.status, 0, result.errors)
        XCTAssertEqual(try askedLog(), [
            "--info": "", "--style": "compact", "--start": Self.start, "--end": Self.end, "--predicate": predicate(Self.wholeList),
        ])
    }

    func testNamingProcessesReadsOnlyThose() throws {
        let result = try run("logs", "--process", "trustd", "--start", Self.start, "--end", Self.end, "--process", "Shades")
        XCTAssertEqual(result.status, 0, result.errors)
        XCTAssertEqual(try askedLog()["--predicate"], predicate(["trustd", "Shades"]))
    }

    func testAProcessNotOnTheListIsRefused() throws {
        for name in ["WindowServer", "Safari", "shades", "codesign ", " codesign", "codesign\n", "*", ""] {
            assertRefused(try run("logs", "--start", Self.start, "--end", Self.end, "--process", name), "process \(name.debugDescription)")
        }
    }

    func testATimeInAnyOtherShapeIsRefused() throws {
        let times = [
            "2026-01-31 09:00", "2026-01-31T09:00:00", "2026-01-31 09:00:00 ", "2026-01-31 09:00:00\n", "2026-01-31  09:00:00",
            "2026-01-31 09:00:00.000", "yesterday", "-1h", "", "２026-01-31 09:00:00",
        ]
        for time in times {
            assertRefused(try run("logs", "--start", time, "--end", Self.end), "start \(time.debugDescription)")
            assertRefused(try run("logs", "--start", Self.start, "--end", time), "end \(time.debugDescription)")
        }
    }

    func testAQuoteOrBraceIsRefusedInEveryArgument() throws {
        for mark in ["\"", "'", "{", "}"] {
            assertRefused(try run("logs\(mark)", "--start", Self.start, "--end", Self.end), "subcommand with \(mark)")
            assertRefused(try run("logs", "--start\(mark)", Self.start, "--end", Self.end), "flag with \(mark)")
            assertRefused(try run("logs", "--start", Self.start + mark, "--end", Self.end), "start with \(mark)")
            assertRefused(try run("logs", "--start", Self.start, "--end", mark + Self.end), "end with \(mark)")
            assertRefused(try run("logs", "--start", Self.start, "--end", Self.end, "--process", "codesign\(mark)"), "process with \(mark)")
            assertRefused(try run("processes", mark), "processes with \(mark)")
        }
        assertRefused(try run("logs", "--start", Self.start, "--end", Self.end, "--process", #"codesign" OR process != "x"#), "a predicate slipped into a name")
        assertRefused(try run("logs", "--start", Self.start, "--end", Self.end, "--process", "{codesign,WindowServer}"), "a brace list")
    }

    func testAnythingElseIsRefused() throws {
        assertRefused(try run(), "nothing")
        assertRefused(try run("show"), "another subcommand")
        assertRefused(try run("logs", "--end", Self.end), "no start")
        assertRefused(try run("logs", "--start", Self.start), "no end")
        assertRefused(try run("logs", "--start", Self.start, "--end", Self.end, "--process"), "a process with no name")
        assertRefused(try run("logs", "--start", Self.start, "--end", Self.end, "--predicate", "1 == 1"), "a predicate")
        assertRefused(try run("logs", "--last", "1h"), "another flag")
        assertRefused(try run("logs", "--start", Self.start, "--end", Self.end, "/var/db/diagnostics"), "a log archive")
        assertRefused(try run("processes", "--all"), "anything after processes")
    }

    func testOutputStopsAtThreeThousandLinesAndSaysHowManyWereCut() throws {
        let result = try run("logs", "--start", Self.start, "--end", Self.end, environment: ["LOG_LINES": "3005"])
        XCTAssertEqual(result.status, 0, result.errors)
        let lines = result.output.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 3001)
        XCTAssertEqual(Array(lines.prefix(3000)), (1...3000).map { "line \($0)" })
        XCTAssertEqual(lines.last, "Cut 5 more lines. Narrow the window or name fewer processes.")
    }

    func testOutputUnderTheCapIsLeftWhole() throws {
        let result = try run("logs", "--start", Self.start, "--end", Self.end, environment: ["LOG_LINES": "3000"])
        XCTAssertEqual(result.status, 0, result.errors)
        XCTAssertEqual(result.output.split(separator: "\n").map(String.init), (1...3000).map { "line \($0)" })
    }

    /// So an agent can tell `log` refusing to run from the script refusing what it was asked.
    func testWhatLogRefusesComesThroughAsLogSaidIt() throws {
        let result = try run("logs", "--start", Self.start, "--end", Self.end, environment: ["LOG_REFUSES": "log: Cannot run while sandboxed"])
        XCTAssertEqual(result.status, 64)
        XCTAssertEqual(result.errors, "log: Cannot run while sandboxed\n")
        XCTAssertEqual(result.output, "")
    }

    // MARK: processes

    func testProcessesListsOnlyTheListAndTheBuildByName() throws {
        try """
              101     1   01:02:03 /usr/libexec/trustd
              202   150      10:05 /bin/zsh /Users/someone/shades/scripts/install.sh --pull
              203   202      09:59 /bin/zsh /Users/someone/shades/scripts/bundle.sh /tmp/next.abc
              204   203      08:00 codesign --force --sign 1111 --identifier example.app /tmp/next.abc/Shades.app
              205     1 2-03:04:05 /Applications/Shades.app/Contents/MacOS/Shades --ask what is on my screen
              206   150      00:10 /usr/bin/grep codesign
              207     1      00:10 /Applications/Notes.app/Contents/MacOS/Notes codesign
              208   150      00:10 /usr/bin/python3 /tmp/install.sh
              209   150      00:10 /bin/zsh -f /tmp/other.sh install.sh
              210   150      00:10 /usr/bin/vim notes.txt
            something private 00:10 codesign
              211   203      00:20 /usr/bin/swift-frontend -frontend -c a.swift
              212     1      00:30 /usr/libexec/lsd
              213   150      00:40 shades --demo
              214   150      00:50 /bin/bash -x ./scripts/install.sh

            """.write(to: root.appendingPathComponent("ps-table"), atomically: true, encoding: .utf8)
        let result = try run("processes")
        XCTAssertEqual(result.status, 0, result.errors)
        XCTAssertEqual(result.output, """
            PID PPID ELAPSED NAME
            101 1 01:02:03 trustd
            202 150 10:05 install.sh
            203 202 09:59 bundle.sh
            204 203 08:00 codesign
            205 1 2-03:04:05 Shades
            211 203 00:20 swift-frontend
            212 1 00:30 lsd
            214 150 00:50 install.sh

            """)
        XCTAssertFalse(logRan)
    }
}
