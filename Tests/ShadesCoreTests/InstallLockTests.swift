import Foundation
import XCTest

final class InstallLockTests: XCTestCase {
    private var root: URL!
    private var runs: [Run] = []

    private final class Run {
        let process = Process()
        let log: URL
        init(log: URL) { self.log = log }
        var pid: Int32 { process.processIdentifier }
        var output: String { (try? String(contentsOf: log, encoding: .utf8)) ?? "" }
    }

    private var scripts: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("scripts") }
    private var data: URL { root.appendingPathComponent("home/Library/Application Support/shades") }

    override func setUpWithError() throws {
        let files = FileManager.default
        root = files.temporaryDirectory.appendingPathComponent("install-lock-\(UUID().uuidString)")
        let copies = root.appendingPathComponent("scripts"), bin = root.appendingPathComponent("bin")
        for folder in [copies, bin, root.appendingPathComponent("tmp"), root.appendingPathComponent("Applications/Shades.app"), data.appendingPathComponent("last-good/Shades.app")] {
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try "old".write(to: root.appendingPathComponent("Applications/Shades.app/build"), atomically: true, encoding: .utf8)
        try "last good".write(to: data.appendingPathComponent("last-good/Shades.app/build"), atomically: true, encoding: .utf8)
        func write(_ text: String, to file: URL) throws {
            try text.write(to: file, atomically: true, encoding: .utf8)
            try files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }

        let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        let copy = try String(contentsOf: scripts.appendingPathComponent("install.sh"), encoding: .utf8)
            .replacingOccurrences(of: "app=/Applications/Shades.app", with: #"app="$root/Applications/Shades.app""#)
            .replacingOccurrences(of: lsregister, with: "lsregister")
        XCTAssertFalse(copy.contains("app=/Applications/Shades.app"), "the copy installs into its own folder")
        XCTAssertFalse(copy.contains("/System/"), "the copy leaves LaunchServices alone")
        try write(copy, to: copies.appendingPathComponent("install.sh"))
        try write(try String(contentsOf: scripts.appendingPathComponent("signing.sh"), encoding: .utf8), to: copies.appendingPathComponent("signing.sh"))
        try write("""
            #!/bin/zsh
            print -r -- "$BUILD" >> "$STANDIN/built"
            until [[ -e "$STANDIN/go" ]]; do sleep 0.05; done
            mkdir -p "$1/Shades.app"
            print -nr -- "$BUILD" > "$1/Shades.app/build"
            """, to: copies.appendingPathComponent("bundle.sh"))

        let tools = [
            "date": #"[[ -e "$STANDIN/slow-date" ]] && { touch "$STANDIN/dating"; sleep 0.5 }; exec /bin/date "$@""#,
            "codesign": #"[[ "$1" == --verify ]] || print "Executable=${@[-1]}/Contents/MacOS/Shades\nAuthority=Apple Development: Jane Appleseed (AB12CD34EF)\nTeamIdentifier=TEAM111111""#,
            "git": #"""
                [[ "$*" == *pull* ]] || exit 0
                print pulled
                if [[ -e "$STANDIN/pause-after-pull" ]]; then
                  s="$STANDIN/scripts/install.sh"
                  { print '#!/bin/zsh'; print "[[ \$\$ == $PPID ]] && { touch \"\$STANDIN/paused\"; until [[ -e \"\$STANDIN/go-on\" ]]; do sleep 0.05; done; }"; tail -n +2 "$s" } > "$s.pulled"
                  chmod +x "$s.pulled"
                  mv "$s.pulled" "$s"
                fi
                """#,
            "mktemp": #"[[ "$*" == -d ]] && exec /usr/bin/mktemp -d "$TMPDIR/next.XXXXXX"; exec /usr/bin/mktemp "$@""#,
            "lsregister": "",
            "open": #"touch "$STANDIN/running"; print '{}' > "$HOME/Library/Application Support/shades/health.json""#,
            "pkill": #"rm -f "$STANDIN/running""#,
            "pgrep": #"[[ -e "$STANDIN/running" ]]"#,
        ]
        for (name, body) in tools {
            try write("#!/bin/zsh\n\(body)\n", to: bin.appendingPathComponent(name))
        }
    }

    override func tearDownWithError() throws {
        letBuildsFinish()
        for run in runs where run.process.isRunning { run.process.terminate() }
        _ = waitUntil { runs.allSatisfy { !$0.process.isRunning } }
        try? FileManager.default.removeItem(at: root)
    }

    private func start(_ build: String, _ arguments: String...) throws -> Run {
        let run = Run(log: root.appendingPathComponent("\(build).log"))
        FileManager.default.createFile(atPath: run.log.path, contents: nil)
        let output = try FileHandle(forWritingTo: run.log)
        run.process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        run.process.arguments = ["-f", root.appendingPathComponent("scripts/install.sh").path] + arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = root.appendingPathComponent("bin").path + ":/usr/bin:/bin:/usr/sbin:/sbin"
        environment["HOME"] = root.appendingPathComponent("home").path
        environment["TMPDIR"] = root.appendingPathComponent("tmp").path
        environment["ZDOTDIR"] = nil
        environment["STANDIN"] = root.path
        environment["BUILD"] = build
        environment["SHADES_HEALTH_SECONDS"] = "5"
        run.process.environment = environment
        run.process.standardOutput = output
        run.process.standardError = output
        try run.process.run()
        runs.append(run)
        return run
    }

    private func waitUntil(_ seconds: Double = 10, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            if Date() > deadline { return false }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return true
    }

    private func letBuildsFinish() {
        FileManager.default.createFile(atPath: root.appendingPathComponent("go").path, contents: nil)
    }

    private func read(_ file: URL) -> String { (try? String(contentsOf: file, encoding: .utf8)) ?? "" }
    private var built: [String] { read(root.appendingPathComponent("built")).split(separator: "\n").map(String.init) }
    private var installed: String { read(root.appendingPathComponent("Applications/Shades.app/build")) }
    private var lastGood: String { read(data.appendingPathComponent("last-good/Shades.app/build")) }
    private func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path) }

    func testOfTwoInstallsStartedTogetherOnlyOneGoesAhead() throws {
        let first = try start("first", "--pull"), second = try start("second", "--pull")
        XCTAssertTrue(waitUntil { !first.process.isRunning || !second.process.isRunning }, "one stops while the other builds")
        letBuildsFinish()
        XCTAssertTrue(waitUntil { !first.process.isRunning && !second.process.isRunning })

        let (went, stopped) = first.process.terminationStatus == 0 ? (first, second) : (second, first)
        XCTAssertEqual(went.process.terminationStatus, 0, went.output)
        XCTAssertTrue(went.output.contains("Installed and running."), went.output)
        XCTAssertEqual(stopped.process.terminationStatus, 1, stopped.output)
        XCTAssertTrue(stopped.output.hasPrefix("Another install, process \(went.pid), has been running since "), stopped.output)
        XCTAssertTrue(stopped.output.contains(", so nothing was installed."), stopped.output)
        XCTAssertFalse(stopped.output.contains("pulled"), "the one that stopped didn't pull either")
        XCTAssertEqual(built.count, 1, "only one built")
        XCTAssertEqual(installed, built.first)
        XCTAssertEqual(lastGood, "old", "the copy kept is the one from before both")
    }

    func testARollbackDuringAnInstallStopsWithoutTouchingTheApp() throws {
        let install = try start("new", "--pull")
        XCTAssertTrue(waitUntil { built == ["new"] }, "the install pulled and is building")
        let rollback = try start("rollback", "--rollback")
        XCTAssertTrue(waitUntil { !rollback.process.isRunning }, "the rollback stops straight away")
        XCTAssertEqual(rollback.process.terminationStatus, 1, rollback.output)
        XCTAssertTrue(rollback.output.contains("Another install, process \(install.pid), has been running since "), rollback.output)
        XCTAssertTrue(rollback.output.contains(", so nothing was installed."), rollback.output)
        XCTAssertEqual(installed, "old", "the rollback left the app alone")
        XCTAssertEqual(lastGood, "last good")

        letBuildsFinish()
        XCTAssertTrue(waitUntil { !install.process.isRunning })
        XCTAssertEqual(install.process.terminationStatus, 0, install.output)
        XCTAssertEqual(installed, "new")
    }

    func testTheLockIsKeptThroughTheExecAfterPull() throws {
        FileManager.default.createFile(atPath: root.appendingPathComponent("pause-after-pull").path, contents: nil)
        let install = try start("new", "--pull")
        XCTAssertTrue(waitUntil { exists("paused") }, "the pulled copy is running")
        let other = try start("other")
        XCTAssertTrue(waitUntil { !other.process.isRunning }, "the other install stops straight away")
        XCTAssertEqual(other.process.terminationStatus, 1, other.output)
        XCTAssertTrue(other.output.contains("Another install, process \(install.pid), has been running since "), other.output)
        XCTAssertEqual(built, [])

        FileManager.default.createFile(atPath: root.appendingPathComponent("go-on").path, contents: nil)
        letBuildsFinish()
        XCTAssertTrue(waitUntil { !install.process.isRunning })
        XCTAssertEqual(install.process.terminationStatus, 0, install.output)
        XCTAssertEqual(installed, "new")
    }

    func testAnInstallThatWasKilledDoesntBlockTheNext() throws {
        let killed = try start("killed")
        XCTAssertTrue(waitUntil { built == ["killed"] }, "the first install is building")
        kill(killed.pid, SIGKILL)
        XCTAssertTrue(waitUntil { !killed.process.isRunning })
        letBuildsFinish()

        let next = try start("next")
        XCTAssertTrue(waitUntil { !next.process.isRunning })
        XCTAssertEqual(next.process.terminationStatus, 0, next.output)
        XCTAssertTrue(next.output.hasPrefix("The install that started "), next.output)
        XCTAssertTrue(next.output.contains(", process \(killed.pid), stopped without finishing, so this one is taking over."), next.output)
        XCTAssertTrue(next.output.contains("Installed and running."), next.output)
        XCTAssertEqual(installed, "next")
        let left = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("tmp").path)
        XCTAssertEqual(left.count, 1, "the killed install's build folder is left in the test's own folder, where it's cleaned up")
    }

    func testAnInstallStoppedJustAsAnotherTakesOverNamesTheOneThatDid() throws {
        let killed = try start("killed")
        XCTAssertTrue(waitUntil { built == ["killed"] })
        kill(killed.pid, SIGKILL)
        XCTAssertTrue(waitUntil { !killed.process.isRunning })
        FileManager.default.createFile(atPath: root.appendingPathComponent("slow-date").path, contents: nil)

        let next = try start("next")
        XCTAssertTrue(waitUntil { exists("dating") }, "next has the lock and is about to say so")
        let stopped = try start("stopped")
        XCTAssertTrue(waitUntil { !stopped.process.isRunning })
        XCTAssertEqual(stopped.process.terminationStatus, 1, stopped.output)
        XCTAssertTrue(stopped.output.contains("Another install, process \(next.pid), has been running since "), stopped.output)
        XCTAssertFalse(stopped.output.contains("\(killed.pid)"), stopped.output)
    }

    func testALockFileThatCantBeWrittenIsntTakenForAnotherInstall() throws {
        let lock = data.appendingPathComponent("install.lock")
        FileManager.default.createFile(atPath: lock.path, contents: nil, attributes: [.posixPermissions: 0o444])
        let blocked = try start("blocked")
        XCTAssertTrue(waitUntil { !blocked.process.isRunning })
        XCTAssertEqual(blocked.process.terminationStatus, 1, blocked.output)
        XCTAssertTrue(blocked.output.contains("install.lock can't be written, so nothing was installed."), blocked.output)
        XCTAssertFalse(blocked.output.contains("Another install"), blocked.output)
        XCTAssertEqual(built, [])
        XCTAssertEqual(installed, "old")
    }
}
