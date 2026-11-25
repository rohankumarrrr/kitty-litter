import Foundation
import XCTest

final class TriageScriptTests: XCTestCase {
    private var root: URL!
    private var script: URL { root.appendingPathComponent("triage.sh") }
    private var logArguments: URL { root.appendingPathComponent("log-arguments") }
    private var logEnvironment: URL { root.appendingPathComponent("log-environment") }
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
            here=${0:h}
            print -rl -- "$@" > "$here/log-arguments"
            print -r -- "HOME=${HOME-} LOG_STYLE=${LOG_STYLE-} STANDIN=${STANDIN-}" > "$here/log-environment"
            if [[ -f "$here/log-refuses" ]]; then cat "$here/log-refuses" >&2; exit 64; fi
            lines=0
            [[ -f "$here/log-lines" ]] && lines=$(<"$here/log-lines")
            for (( i = 1; i <= lines; i++ )); do print "line $i"; done
            """#, to: root.appendingPathComponent("log"))
        try write(#"""
            #!/bin/zsh -f
            print -rl -- "$@" >> "$STANDIN/ps-ran"
            [[ -f "$STANDIN/ps-table" ]] || exit 0
            columns=(${(s:,:)${${@[(r)pid=*]}//=/}})
            while IFS=$'\t' read -r pid ppid etime ucomm args; do
              line=""
              for column in $columns; do
                case $column in
                  pid) line+="$(printf '%5s' "$pid") " ;;
                  ppid) line+="$(printf '%5s' "$ppid") " ;;
                  etime) line+="$(printf '%11s' "$etime") " ;;
                  ucomm) line+="$(printf '%-16s' "$ucomm") " ;;
                  args) line+="$args " ;;
                esac
              done
              print -r -- "${line% }"
            done < "$STANDIN/ps-table"
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
        func read(_ file: URL) throws -> String { String(decoding: try Data(contentsOf: file), as: UTF8.self) }
        return (process.terminationStatus, try read(out), try read(err))
    }

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

    private func given(_ name: String, _ text: String) throws {
        try text.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
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
        try given("log-lines", "3005")
        let result = try run("logs", "--start", Self.start, "--end", Self.end)
        XCTAssertEqual(result.status, 0, result.errors)
        let lines = result.output.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 3001)
        XCTAssertEqual(Array(lines.prefix(3000)), (1...3000).map { "line \($0)" })
        XCTAssertEqual(lines.last, "Cut 5 more lines. Narrow the window or name fewer processes.")
    }

    func testOutputUnderTheCapIsLeftWhole() throws {
        try given("log-lines", "3000")
        let result = try run("logs", "--start", Self.start, "--end", Self.end)
        XCTAssertEqual(result.status, 0, result.errors)
        XCTAssertEqual(result.output.split(separator: "\n").map(String.init), (1...3000).map { "line \($0)" })
    }

    func testWhatLogRefusesComesThroughAsLogSaidIt() throws {
        try given("log-refuses", "log: Cannot run while sandboxed\n")
        let result = try run("logs", "--start", Self.start, "--end", Self.end)
        XCTAssertEqual(result.status, 64)
        XCTAssertEqual(result.errors, "log: Cannot run while sandboxed\n")
        XCTAssertEqual(result.output, "")
    }

    func testLogGetsNothingFromTheCallersEnvironment() throws {
        try given(".logrc", "show:\n    --debug\n")
        let result = try run("logs", "--start", Self.start, "--end", Self.end, environment: ["LOG_STYLE": "json"])
        XCTAssertEqual(result.status, 0, result.errors)
        XCTAssertEqual(try String(contentsOf: logEnvironment, encoding: .utf8), "HOME=/var/empty LOG_STYLE= STANDIN=\n")
    }

    func testItIgnoresTheCallersToolsAndStartupFiles() throws {
        let tools = root.appendingPathComponent("tools")
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        for tool in ["awk", "env"] {
            try given("tools/\(tool)", "#!/bin/zsh -f\nprint -r -- planted \(tool) ran\n")
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tools.appendingPathComponent(tool).path)
        }
        try given(".zshenv", "print -r -- startup file ran; exit 9\n")
        try given("ps-table", "101\t1\t01:02:03\ttrustd\t/usr/libexec/trustd\n")
        try given("log-lines", "1")
        let environment = ["PATH": tools.path + ":/usr/bin:/bin", "ZDOTDIR": root.path]

        let listed = try run("processes", environment: environment)
        XCTAssertEqual(listed.status, 0, listed.errors)
        XCTAssertEqual(listed.output, "PID PPID ELAPSED NAME\n101 1 01:02:03 trustd\n")
        let logged = try run("logs", "--start", Self.start, "--end", Self.end, environment: environment)
        XCTAssertEqual(logged.status, 0, logged.errors)
        XCTAssertEqual(logged.output, "line 1\n")
    }

    private func table(_ rows: [(pid: String, ppid: String, elapsed: String, executable: String, arguments: String)]) throws {
        try given("ps-table", rows.map { [$0.pid, $0.ppid, $0.elapsed, $0.executable, $0.arguments].joined(separator: "\t") + "\n" }.joined())
    }

    func testProcessesListsOnlyTheListAndTheBuildByName() throws {
        try table([
            ("101", "1", "01:02:03", "trustd", "/usr/libexec/trustd"),
            ("202", "150", "10:05", "zsh", "/bin/zsh /Users/someone/shades/scripts/install.sh --pull"),
            ("203", "202", "09:59", "zsh", "/bin/zsh /Users/someone/shades/scripts/bundle.sh /tmp/next.abc"),
            ("204", "203", "08:00", "codesign", "codesign --force --sign 1111 --identifier example.app /tmp/next.abc/Shades.app"),
            ("205", "1", "2-03:04:05", "Shades", "/Applications/Shades.app/Contents/MacOS/Shades --ask what is on my screen"),
            ("206", "150", "00:10", "grep", "/usr/bin/grep codesign"),
            ("207", "1", "00:10", "Notes", "/Applications/Notes.app/Contents/MacOS/Notes codesign"),
            ("208", "150", "00:10", "python3", "/usr/bin/python3 /tmp/install.sh"),
            ("209", "150", "00:10", "zsh", "/bin/zsh -f /tmp/other.sh install.sh"),
            ("210", "150", "00:10", "vim", "/usr/bin/vim notes.txt"),
            ("something", "private", "00:10", "codesign", "codesign"),
            ("private-words", "150", "00:10", "codesign", "codesign"),
            ("215", "private-words", "00:10", "codesign", "codesign"),
            ("216", "150", "private-words", "codesign", "codesign"),
            ("211", "203", "00:20", "swift-frontend", "/usr/bin/swift-frontend -frontend -c a.swift"),
            ("212", "1", "00:30", "lsd", "/usr/libexec/lsd"),
            ("213", "150", "00:40", "shades", "shades --demo"),
            ("214", "150", "00:50", "bash", "/bin/bash -x ./scripts/install.sh"),
            ("217", "150", "00:10", "Google Chrome He", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"),
        ])
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
        XCTAssertEqual(
            try String(contentsOf: psRan, encoding: .utf8),
            "-axww\n-o\npid=,args=\n-axww\n-o\npid=,ppid=,etime=,ucomm=\n",
            "ps is asked for nothing more"
        )
        XCTAssertFalse(logRan)
    }

    func testAProgramThatOnlyCallsItselfAListedNameIsLeftOut() throws {
        try table([
            ("301", "1", "00:10", "sleep", "codesign 20"),
            ("302", "1", "00:10", "python3", "trustd"),
            ("303", "1", "00:10", "sleep", "/bin/zsh /tmp/install.sh"),
            ("304", "1", "00:10", "codesign", "codesign --verify x"),
        ])
        let result = try run("processes")
        XCTAssertEqual(result.output, "PID PPID ELAPSED NAME\n304 1 00:10 codesign\n", "only what the kernel says it runs counts, never the name it gives itself")
    }

    func testABrokenCharacterInAnArgumentNeitherShowsNorStopsTheList() throws {
        var rows = Data("101\t150\t00:10\tzsh\t/bin/zsh -c ".utf8) + [0xFF] + Data("private-words\n".utf8)
        rows += Data("102\t1\t00:10\tnote:".utf8) + [0xFF] + Data("x\tnote:".utf8) + [0xFF] + Data("private-words\n".utf8)
        rows += Data("103\t150\t00:10\tcodesign\tcodesign --force\n".utf8)
        try rows.write(to: root.appendingPathComponent("ps-table"))
        let result = try run("processes", environment: ["LC_ALL": "en_US.UTF-8"])
        XCTAssertEqual(result.errors, "")
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.output, "PID PPID ELAPSED NAME\n103 150 00:10 codesign\n")
    }

    func testALongArgumentDoesntHoldUpTheList() throws {
        let long = String(repeating: "a", count: 80_000)
        try table([
            ("101", "150", "00:10", "zsh", "/bin/zsh \(long)"),
            ("102", "1", "00:10", "a", long),
            ("103", "150", "00:10", "codesign", "codesign --force"),
        ])
        let started = Date()
        let result = try run("processes")
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        XCTAssertEqual(result.output, "PID PPID ELAPSED NAME\n103 150 00:10 codesign\n")
    }
}
