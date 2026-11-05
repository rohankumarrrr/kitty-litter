import AppKit
import ApplicationServices
import AVFoundation
import Foundation
import ShadesCore
import ShadesVoice

/// The parts that need a real Mac: microphone, keys and other apps.
enum Hardware {
    static func permissions() {
        let mic: String
        switch MicrophoneSource.authorization {
        case .granted: mic = "granted"
        case .denied: mic = "denied"
        case .notAsked: mic = "not asked yet"
        }
        print("Microphone: \(mic)")
        print("Accessibility: \(TextInserter.hasPermission)")
        print("Input Monitoring: \(KeyHoldMonitor.hasPermission)")
        let globe = KeyHoldMonitor.globeAction.map { "\($0)" } ?? "never changed, so the Mac's default"
        print("Press Globe key to: \(globe)")
    }

    /// How fast the mic opens, cold start included. Nothing is kept: samples are only counted and measured.
    static func microphone(_ args: [String]) async throws {
        guard MicrophoneSource.authorization == .granted || args.contains("--ask") else {
            print("This opens the real microphone. Run it with --ask to allow the system prompt.")
            return
        }
        if MicrophoneSource.authorization == .notAsked, await !MicrophoneSource.requestAccess() {
            print("Microphone permission denied.")
            return
        }
        let runs = args.firstIndex(of: "--runs").flatMap { Int(args[$0 + 1]) } ?? 10
        for (name, engineOnly) in [("Core Audio unit", false), ("AVAudioEngine", true)] {
            let source = MicrophoneSource()
            source.useEngineOnly = engineOnly
            try source.prepare()
            var latencies: [Double] = []
            var callReturns: [Double] = []
            var peak: Float = 0
            for _ in 0..<runs {
                let started = Date()
                try source.start { samples in
                    peak = max(peak, samples.map(abs).max() ?? 0)
                }
                callReturns.append(Date().timeIntervalSince(started) * 1000)
                while source.lastStartLatency == nil, Date().timeIntervalSince(started) < 2 {
                    try await Task.sleep(nanoseconds: 2_000_000)
                }
                latencies.append((source.lastStartLatency ?? 2) * 1000)
                try await Task.sleep(nanoseconds: 300_000_000)
                source.stop()
                try await Task.sleep(nanoseconds: 300_000_000)
            }
            print("\(name) [\(source.lastBackend)]: start() returns p50 \(Int(Metrics.percentile(callReturns, 50))) ms; first audio p50 \(Int(Metrics.percentile(latencies, 50))) ms, p95 \(Int(Metrics.percentile(latencies, 95))) ms, max \(Int(latencies.max() ?? 0)) ms. Peak level \(peak).")
        }
    }

    /// The whole feature with a real microphone and real keys, without the app around it.
    static func dictate(_ args: [String]) async throws {
        if MicrophoneSource.authorization == .notAsked { _ = await MicrophoneSource.requestAccess() }
        let source = MicrophoneSource()
        let engine = ParakeetVoiceEngine(source: source)
        engine.onSetupProgress = { progress in
            if progress.stage != .ready { print("\(progress.stage.rawValue) \(Int(progress.fraction * 100))%", terminator: "\r") }
        }
        print("Loading…")
        try await engine.prepare()
        engine.setVocabulary(Settings.load().vocabulary)
        print("Ready. Hold fn or right Option, talk, let go. Control-C to stop.")

        let inserter = TextInserter()
        let insert = !args.contains("--no-insert")
        let monitor = KeyHoldMonitor()
        Task { for await partial in engine.partials where !partial.isEmpty { print("… \(partial)") } }
        Task { for await _ in engine.levels {} }
        monitor.onPress = { _ in
            do { try engine.begin() } catch { print(error.localizedDescription) }
        }
        monitor.onCancel = { _ in
            engine.cancel()
            print("(called off)")
        }
        monitor.onRelease = { _ in
            Task {
                do {
                    let transcript = try await engine.end()
                    let timings = engine.lastTimings
                    print("heard:  \(transcript.raw)")
                    print("clean:  \(transcript.cleaned)")
                    print("\(Int(transcript.latencySeconds * 1000)) ms from release: tail \(Int(timings.tail * 1000)), live text \(Int(timings.waitForPartial * 1000)), recognition \(Int(timings.recognition * 1000)), cleanup \(Int(timings.cleanup * 1000)) by \(timings.cleanupSource.rawValue). Mic opened in \(source.lastStartLatency.map { "\(Int($0 * 1000)) ms" } ?? "?") by \(source.lastBackend).")
                    if insert, !transcript.cleaned.isEmpty {
                        try await inserter.insert(transcript.cleaned)
                        print("inserted by \(inserter.lastMethod.rawValue)")
                    }
                } catch {
                    print(error.localizedDescription)
                }
            }
        }
        try monitor.start(keys: [.fn, .rightOption])
        if let action = KeyHoldMonitor.globeAction, action != .doNothing {
            print("Heads up: the Globe key is set to \(action), which can pop up when you let go of fn.")
        }
        await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
    }

    static func downloadTest() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("shades-download-test")
        try? FileManager.default.removeItem(at: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        let started = Date()
        let lock = NSLock()
        var lastTenth = -1
        let file = try await CleanupModelProbe.downloadModel(to: folder) { fraction in
            let tenth = Int(fraction * 10)
            lock.withLock {
                if tenth != lastTenth {
                    lastTenth = tenth
                    print("\(tenth * 10)%")
                }
            }
        }
        let size = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0
        print("Downloaded \(size / 1_000_000) MB and checked its checksum in \(Int(Date().timeIntervalSince(started))) s.")
    }

    static func keys(_ args: [String]) async throws {
        let monitor = KeyHoldMonitor()
        let started = Date()
        func stamp() -> String { String(format: "%6.2f", Date().timeIntervalSince(started)) }
        monitor.onPress = { print("\(stamp()) press \($0.rawValue)") }
        monitor.onRelease = { print("\(stamp()) release \($0.rawValue)") }
        monitor.onCancel = { print("\(stamp()) cancel \($0.rawValue)") }
        try monitor.start(keys: [.fn, .rightOption, .rightCommand, .rightControl])
        print("Hold fn, right Option, right Command or right Control. Control-C to stop.")
        await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
    }

    /// Posts modifier events and checks the tap hears the right key. They're quick and carry no letter.
    static func keysSelfTest() async throws {
        guard KeyHoldMonitor.hasPermission else {
            print("Needs Input Monitoring.")
            return
        }
        let monitor = KeyHoldMonitor()
        var events: [String] = []
        let lock = NSLock()
        func log(_ text: String) { lock.withLock { events.append(text) } }
        monitor.onPress = { log("press \($0.rawValue)") }
        monitor.onRelease = { log("release \($0.rawValue)") }
        monitor.onCancel = { log("cancel \($0.rawValue)") }
        try monitor.start(keys: [.fn, .rightOption, .rightCommand, .rightControl])

        // Device bits tell left from right, the same as a real keyboard reports them.
        let cases: [(name: String, code: CGKeyCode, flags: UInt64, expected: String?)] = [
            ("right Option", 61, CGEventFlags.maskAlternate.rawValue | 0x40, "rightOption"),
            ("left Option", 58, CGEventFlags.maskAlternate.rawValue | 0x20, nil),
            ("right Command", 54, CGEventFlags.maskCommand.rawValue | 0x10, "rightCommand"),
            ("left Command", 55, CGEventFlags.maskCommand.rawValue | 0x08, nil),
            ("right Control", 62, CGEventFlags.maskControl.rawValue | 0x2000, "rightControl"),
            ("left Control", 59, CGEventFlags.maskControl.rawValue | 0x01, nil),
            ("fn", 63, CGEventFlags.maskSecondaryFn.rawValue, "fn"),
        ]
        var failures = 0
        let source = CGEventSource(stateID: .privateState)
        for item in cases {
            lock.withLock { events.removeAll() }
            let down = CGEvent(keyboardEventSource: source, virtualKey: item.code, keyDown: true)!
            down.type = .flagsChanged
            down.flags = CGEventFlags(rawValue: item.flags)
            down.post(tap: .cgSessionEventTap)
            try await Task.sleep(nanoseconds: 300_000_000)
            let up = CGEvent(keyboardEventSource: source, virtualKey: item.code, keyDown: false)!
            up.type = .flagsChanged
            up.flags = []
            up.post(tap: .cgSessionEventTap)
            try await Task.sleep(nanoseconds: 100_000_000)
            let seen = lock.withLock { events }
            let wanted = item.expected.map { ["press \($0)", "release \($0)"] } ?? []
            let ok = seen == wanted
            if !ok { failures += 1 }
            print("\(ok ? "ok  " : "FAIL") \(item.name): \(seen)")
        }
        monitor.stop()
        print(failures == 0 ? "All keys told apart correctly." : "\(failures) failed.")
    }

    /// Real insertion into a real app, on a temp file that gets deleted. Refuses to send a keystroke
    /// unless TextEdit is in front, so a stray paste can never land in something else.
    static func insertTest() async throws {
        guard TextInserter.hasPermission else {
            print("Needs Accessibility.")
            return
        }
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any], session["CGSSessionScreenIsLocked"] as? Bool == true {
            print("The screen is locked, so nothing can come to the front. Try again when it's unlocked.")
            return
        }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").isEmpty else {
            print("TextEdit is already open. Close it first, so this can't touch your documents.")
            return
        }
        let previous = NSWorkspace.shared.frontmostApplication
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("shades-insert-test.txt")
        try "".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let opened = Process()
        opened.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        opened.arguments = ["-a", "TextEdit", file.path]
        try opened.run()
        opened.waitUntilExit()

        var app: NSRunningApplication?
        for _ in 0..<100 {
            app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first
            if app != nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        guard let app else {
            print("TextEdit didn't open.")
            return
        }
        defer {
            Self.closeWindows(of: app)
            app.terminate()
            usleep(300_000)
            if !app.isTerminated { app.forceTerminate() }
            previous?.activate()
        }

        func inFront() async -> Bool {
            for _ in 0..<60 {
                let front = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier }
                if front == app.processIdentifier, Self.fieldValue(of: app) != nil { return true }
                app.activate()
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            return false
        }

        var failures = 0
        func check(_ name: String, _ passed: Bool, _ detail: String = "") {
            if !passed { failures += 1 }
            print("\(passed ? "ok  " : "FAIL") \(name)\(detail.isEmpty ? "" : ": \(detail)")")
        }

        guard await inFront() else {
            print("TextEdit never came to the front, so nothing was sent.")
            return
        }

        let inserter = TextInserter()
        let pasteboard = NSPasteboard.general
        let clipboardCount = pasteboard.changeCount

        // Accessibility, into an empty document.
        try await inserter.insert("The build is green.")
        var value = Self.fieldValue(of: app) ?? ""
        check("Accessibility inserted the text", value == "The build is green.", "\(inserter.lastMethod.rawValue) in \(Int(inserter.lastSeconds * 1000)) ms: \(value)")
        check("Clipboard untouched by Accessibility", pasteboard.changeCount == clipboardCount)

        // Continuing a sentence: a space, and no capital in the middle.
        try await inserter.insert("Then we ship.")
        value = Self.fieldValue(of: app) ?? ""
        check("Next sentence gets a space", value == "The build is green. Then we ship.", value)

        // Replacing a selection, the way typing would.
        guard await inFront() else {
            print("TextEdit lost the front, so the rest was skipped.")
            return
        }
        Self.select(in: app, location: 13, length: 5)
        try await inserter.insert("ready")
        value = Self.fieldValue(of: app) ?? ""
        check("Replaces the selection", value.hasPrefix("The build is ready."), value)

        // Undo has to take dictated text back out, or a bad take can't be fixed.
        guard await inFront() else {
            print("TextEdit lost the front, so the rest was skipped.")
            return
        }
        Self.postCommand(key: "z")
        try await Task.sleep(nanoseconds: 300_000_000)
        let undone = Self.fieldValue(of: app) ?? ""
        check("Command-Z undoes an Accessibility insert", undone.hasPrefix("The build is green."), undone)

        // Paste, keeping whatever was on the clipboard.
        guard await inFront() else {
            print("TextEdit lost the front, so the paste test was skipped.")
            return
        }
        Self.select(in: app, location: (Self.fieldValue(of: app) ?? "").utf16.count, length: 0)
        let snapshotBefore = Self.clipboardFingerprint(pasteboard)
        let pasting = TextInserter()
        pasting.pasteOnly = true
        try await pasting.insert("Pasted with a transient clipboard.")
        try await Task.sleep(nanoseconds: 200_000_000)
        value = Self.fieldValue(of: app) ?? ""
        check("Paste inserted the text", value.hasSuffix("Then we ship. Pasted with a transient clipboard."), "\(pasting.lastMethod.rawValue): \(value)")
        await pasting.finishRestoring()
        check("Clipboard restored after paste", Self.clipboardFingerprint(pasteboard) == snapshotBefore)

        guard await inFront() else {
            print("TextEdit lost the front, so the rest was skipped.")
            return
        }
        Self.postCommand(key: "z")
        try await Task.sleep(nanoseconds: 300_000_000)
        let pasteUndone = Self.fieldValue(of: app) ?? ""
        check("Command-Z undoes a paste", !pasteUndone.contains("Pasted"), pasteUndone)

        print(failures == 0 ? "All insertion checks passed." : "\(failures) checks failed.")
    }

    private static func select(in app: NSRunningApplication, location: Int, length: Int) {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &focused) == .success, let focused else { return }
        var range = CFRange(location: location, length: length)
        guard let value = AXValueCreate(.cfRange, &range) else { return }
        // swiftlint:disable:next force_cast
        AXUIElementSetAttributeValue(focused as! AXUIElement, kAXSelectedTextRangeAttribute as CFString, value)
    }

    private static func postCommand(key: Character) {
        let codes: [Character: CGKeyCode] = ["z": 6]
        guard let code = codes[key], let source = CGEventSource(stateID: .privateState) else { return }
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: isDown)
            event?.flags = .maskCommand
            event?.post(tap: .cgSessionEventTap)
        }
    }

    private static func fieldValue(of app: NSRunningApplication) -> String? {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &focused) == .success, let focused else { return nil }
        var value: CFTypeRef?
        // swiftlint:disable:next force_cast
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXValueAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// Closes the test window. Its temp file autosaves, so TextEdit doesn't ask anything.
    private static func closeWindows(of app: NSRunningApplication) {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var windows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &windows) == .success,
              let list = windows as? [AXUIElement]
        else { return }
        for window in list {
            var close: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &close) == .success, let close {
                // swiftlint:disable:next force_cast
                AXUIElementPerformAction(close as! AXUIElement, kAXPressAction as CFString)
            }
        }
        usleep(500_000)
    }

    private static func clipboardFingerprint(_ pasteboard: NSPasteboard) -> [[String: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var result: [String: Data] = [:]
            for type in item.types where type != PasteboardMarkers.transient {
                result[type.rawValue] = item.data(forType: type)
            }
            return result
        }
    }

    static func insert(_ args: [String]) async throws {
        let text = args.joined(separator: " ")
        print("Inserting at the cursor in 3 seconds. Click into a text field.")
        try await Task.sleep(nanoseconds: 3_000_000_000)
        let inserter = TextInserter()
        try await inserter.insert(text)
        print("Inserted by \(inserter.lastMethod.rawValue) in \(Int(inserter.lastSeconds * 1000)) ms.")
    }
}

enum PasteboardMarkers {
    static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
}
