import AppKit
import ShadesContext
import ShadesCore

// Tries the context module without the app. It only ever prints timings, sizes, lengths,
// hostnames and permission status, because your screen may hold private things.
//
//   probe-context                    one snapshot of whatever's in front
//   probe-context --runs 10          several, with min, median and max
//   probe-context --front <pid>      brings that app forward first, then gives focus back
//   probe-context --front <pid> --freeze   the same, with that app stopped, to see how a hang goes
//   probe-context --has <text>       says whether the page text contains this (test pages only)
//   probe-context --permissions      permission status
//   probe-context --ask <bundle id>  shows the automation dialog for a browser
//   probe-context --pick             the real region picker, for you to drag
//   probe-context --synthetic <dir>  capture checks against a window of its own (see Fixture.swift)
//                                    (add --screen 1 for the second display)
//   probe-context --elements          reads what the cat could point at in a window of its own
//                                    (add --screen 1 for the second display)
//   probe-context --picker-test <dir>  drives the picker with events handed to its own windows
//                                      (add --real-mouse for one real drag through the window server)

let arguments = Array(CommandLine.arguments.dropFirst())

func value(after flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

func values(after flag: String) -> [String] {
    arguments.indices.filter { arguments[$0] == flag && $0 + 1 < arguments.count }.map { arguments[$0 + 1] }
}

func printPermissions() async {
    print("screen recording: \(Permissions.hasScreenRecording)")
    print("accessibility:    \(Permissions.hasAccessibility)")
    for id in ["net.imput.helium", "com.google.Chrome", "company.thebrowser.Browser", "com.apple.Safari"] {
        print("automation \(id): \(await Permissions.browserAutomation(bundleID: id))")
    }
    print("denied browsers:  \(await Permissions.browsersDeniedAutomation().count)")
}

func format(_ value: Double?) -> String {
    value.map { String(format: "%6.1f", $0) } ?? "     -"
}

func summarize(_ name: String, _ samples: [Double]) {
    guard !samples.isEmpty else { return }
    let sorted = samples.sorted()
    let min = format(sorted.first)
    let median = format(sorted[sorted.count / 2])
    let max = format(sorted.last)
    print("  \(name.padding(toLength: 18, withPad: " ", startingAt: 0)) min \(min)  median \(median)  max \(max)  ms")
}

func runSnapshots() async {
    let provider = ScreenContextProvider()
    let runs = value(after: "--runs").flatMap(Int.init) ?? 1
    var reports: [CaptureReport] = []
    var last = ScreenSnapshot()

    let previous = NSWorkspace.shared.frontmostApplication
    let forward = value(after: "--front").flatMap(Int32.init).flatMap(NSRunningApplication.init(processIdentifier:))
    if let forward {
        forward.activate(options: [])
        for _ in 0..<40 where NSWorkspace.shared.frontmostApplication != forward {
            try? await Task.sleep(for: .milliseconds(25))
        }
        print("brought forward: \(NSWorkspace.shared.frontmostApplication == forward)")
        if arguments.contains("--freeze") { kill(forward.processIdentifier, SIGSTOP) }
    }

    for _ in 0..<runs {
        do {
            last = try await provider.snapshot(CaptureOptions())
            reports.append(provider.lastReport)
        } catch {
            print("snapshot threw")
        }
        if runs > 1 { try? await Task.sleep(for: .milliseconds(150)) }
    }

    if let forward {
        if arguments.contains("--freeze") { kill(forward.processIdentifier, SIGCONT) }
        previous?.activate(options: [])
        try? await Task.sleep(for: .milliseconds(150))
        print("focus returned:  \(NSWorkspace.shared.frontmostApplication == previous)")
    }

    print("private:          \(last.isPrivate)")
    print("app name:         \(last.appName == nil ? "none" : "yes")")
    print("bundle id:        \(last.bundleID == nil ? "none" : "yes")")
    print("window title:     \(last.windowTitle?.count ?? 0) chars")
    print("selected text:    \(last.selectedText?.count ?? 0) chars")
    print("page text:        \(last.pageText?.count ?? 0) chars")
    print("url host:         \(last.url.map { $0.host ?? "(\($0.scheme ?? "?") url, no host)" } ?? "none")")
    print("screenshot:       \(last.screenshotJPEG.map { "\($0.count / 1024) KB, \(pixelSize(of: $0))" } ?? "none")")
    if let report = reports.last {
        print("browser status:   \(report.browser)")
        print("screen recording: \(report.screenRecording)")
        print("accessibility:    \(report.accessibility)")
    }
    for text in values(after: "--has") {
        print("page has \(text): \(last.pageText?.contains(text) == true)  selected has it: \(last.selectedText?.contains(text) == true)")
    }

    print("timings over \(reports.count) run(s):")
    if let first = reports.first { print("  first run in this process: \(format(first.timings.total)) ms") }
    summarize("total", reports.map(\.timings.total))
    summarize("focus (AX)", reports.compactMap(\.timings.focus))
    summarize("browser location", reports.compactMap(\.timings.browserLocation))
    summarize("page", reports.compactMap(\.timings.page))
    summarize("screenshot", reports.compactMap(\.timings.screenshot))
    summarize("  list displays", reports.compactMap(\.timings.screenshotList))
    summarize("  grab", reports.compactMap(\.timings.screenshotGrab))
    summarize("  mark + encode", reports.compactMap(\.timings.screenshotEncode))
    if let tip = provider.takeJavaScriptTip() { print("tip offered: \(tip.count) chars") }
}

func pixelSize(of jpeg: Data) -> String {
    guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth],
          let height = properties[kCGImagePropertyPixelHeight]
    else { return "?" }
    return "\(width)x\(height)"
}

func runPick() async {
    let region = await ScreenContextProvider().pickRegion()
    print(region.map { "picked \(describe($0))" } ?? "cancelled")
}

/// AppKit's events need the main run loop, so the work happens beside it.
NSApplication.shared.setActivationPolicy(.accessory)
Task {
    if arguments.contains("--permissions") {
        await printPermissions()
    } else if let id = value(after: "--ask") {
        print("automation: \(await Permissions.requestBrowserAutomation(bundleID: id))")
    } else if arguments.contains("--pick") {
        await runPick()
    } else if arguments.contains("--serve-fixture") {
        await serveFixture()
    } else if arguments.contains("--serve-secure-field") {
        await serveField(secure: true)
    } else if arguments.contains("--serve-text-field") {
        await serveField(secure: false)
    } else if arguments.contains("--serve-buttons") {
        await serveButtons()
    } else if arguments.contains("--elements") {
        await runElementsCheck()
    } else if let directory = value(after: "--synthetic") {
        await runSyntheticChecks(in: URL(fileURLWithPath: directory))
    } else if let directory = value(after: "--picker-test") {
        await runPickerTest(in: URL(fileURLWithPath: directory))
    } else {
        await runSnapshots()
    }
    exit(0)
}
NSApplication.shared.run()
