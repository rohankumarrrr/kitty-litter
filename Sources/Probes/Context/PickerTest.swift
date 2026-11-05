import AppKit
import ShadesContext
import ShadesCore

// Drives the real picker with events handed straight to its own windows, so nothing reaches your
// apps and your real mouse stays where it is. Each run covers your screen for under a second.
// Pictures hold the overlay alone, never your screen.

/// Launching from a terminal can make the probe itself the active app, which would prove nothing,
/// so the test only runs once some other app is really in front.
@MainActor
private func someoneElseInFront() async -> pid_t? {
    let me = ProcessInfo.processInfo.processIdentifier
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    print("at launch: probe active \(NSApp.isActive), probe is frontmost \(NSWorkspace.shared.frontmostApplication?.processIdentifier == me)")
    if NSApp.isActive || NSWorkspace.shared.frontmostApplication?.processIdentifier == me {
        for window in list where window[kCGWindowLayer as String] as? Int == 0 {
            guard let owner = window[kCGWindowOwnerPID as String] as? Int32, owner != me,
                  let app = NSRunningApplication(processIdentifier: owner), app.activationPolicy == .regular
            else { continue }
            app.activate(options: [])
            break
        }
        for _ in 0..<40 where NSApp.isActive {
            try? await Task.sleep(for: .milliseconds(25))
        }
    }
    let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
    print("before the test: probe active \(NSApp.isActive), frontmost is another app \(front != nil && front != me)")
    return front == me ? nil : front
}

func runPickerTest(in directory: URL) async {
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    guard let frontBefore = await someoneElseInFront() else {
        print("couldn't get another app in front, so this wouldn't prove anything")
        return
    }
    let screens = await MainActor.run { NSScreen.screens.map(\.frame) }
    let screen = screens[0]

    let dragFrom = CGPoint(x: screen.minX + 400, y: screen.minY + 300)

    for (index, display) in screens.enumerated() {
        let from = CGPoint(x: display.minX + 400, y: display.minY + 300)
        let to = CGPoint(x: display.minX + 900, y: display.minY + 620)
        await run("drag on display \(index)", frontBefore: frontBefore) {
            await drive([
                (.leftMouseDown, from),
                (.leftMouseDragged, CGPoint(x: from.x + 200, y: from.y + 100)),
                (.leftMouseDragged, to),
            ])
            if index == 0 { await shoot("picker-dragging.jpg", in: directory) }
            await drive([(.leftMouseUp, to)])
        } check: { region in
            // Global points in AppKit's coordinates, exactly as dragged.
            let expected = CGRect(x: from.x, y: from.y, width: to.x - from.x, height: to.y - from.y)
            return region == expected ? "OK, \(describe(region))" : "WRONG, got \(describe(region)), wanted \(describe(expected))"
        }
    }

    // Past the edge of the display it started on, the box stops at that edge.
    if let last = screens.last, screens.count > 1 {
        let from = CGPoint(x: last.minX + 100, y: last.minY + 100)
        let beyond = CGPoint(x: last.maxX + 2000, y: last.maxY + 2000)
        await run("drag past the display's edge", frontBefore: frontBefore) {
            await drive([(.leftMouseDown, from), (.leftMouseDragged, beyond), (.leftMouseUp, beyond)])
        } check: { region in
            let expected = CGRect(x: from.x, y: from.y, width: last.maxX - from.x, height: last.maxY - from.y)
            return region == expected ? "OK, \(describe(region))" : "WRONG, got \(describe(region)), wanted \(describe(expected))"
        }
    }

    await run("click", frontBefore: frontBefore) {
        await shoot("picker-idle.jpg", in: directory)
        await drive([(.leftMouseDown, dragFrom), (.leftMouseUp, dragFrom)])
    } check: { region in
        region == nil ? "OK, cancelled" : "WRONG, got \(describe(region))"
    }

    await run("esc", frontBefore: frontBefore) {
        await pressEscape()
    } check: { region in
        region == nil ? "OK, cancelled" : "WRONG, got \(describe(region))"
    }

    await run("second request", frontBefore: frontBefore) {
        let second = await ScreenContextProvider().pickRegion()
        print("  a second request while one is open: \(second == nil ? "OK, nil" : "WRONG")")
        await pressEscape()
    } check: { region in
        region == nil ? "OK, cancelled" : "WRONG, got \(describe(region))"
    }

    await checkAnotherAppCancels()

    if arguments.contains("--real-mouse") {
        await runRealMouseTest(frontBefore: frontBefore)
    }
}

/// A stuck overlay would block the whole Mac, so switching apps has to clear it. A small app of
/// the probe's own comes forward for a moment, and the app you were in gets focus back.
private func checkAnotherAppCancels() async {
    print("another app comes forward:")
    let previous = NSWorkspace.shared.frontmostApplication
    let picking = Task { await ScreenContextProvider().pickRegion() }
    try? await Task.sleep(for: .milliseconds(250))

    let other = Process()
    other.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    other.arguments = ["--serve-text-field"]
    other.standardOutput = FileHandle.nullDevice
    try? other.run()

    let result = await waitForResult(of: picking)
    print("  result: \(result == nil ? "OK, cancelled" : "WRONG, got \(describe(result))")")
    other.terminate()
    previous?.activate(options: [])
    try? await Task.sleep(for: .milliseconds(300))
    print("  focus returned: \(NSWorkspace.shared.frontmostApplication == previous)")
}

private func run(
    _ name: String,
    frontBefore: pid_t,
    steps: @escaping () async -> Void,
    check: @escaping (CGRect?) -> String
) async {
    print("\(name):")
    let picking = Task { await ScreenContextProvider().pickRegion() }
    try? await Task.sleep(for: .milliseconds(250))

    await MainActor.run {
        let panels = NSApp.windows.filter { $0 is NSPanel && $0.isVisible }
        let key = panels.first { $0.isKeyWindow } != nil
        print("  panels up: \(panels.count), one is key: \(key), app active: \(NSApp.isActive)")
        printFocus(of: frontBefore, when: "while up")
    }

    await steps()

    let result = await waitForResult(of: picking)
    print("  result: \(check(result))")
    await MainActor.run {
        let visible = NSApp.windows.filter { $0.isVisible }.count
        print("  panels left up: \(visible)")
        print("  probe active after: \(NSApp.isActive)")
        printFocus(of: frontBefore, when: "after")
    }
    try? await Task.sleep(for: .milliseconds(120))
}

private func waitForResult(of picking: Task<CGRect?, Never>) async -> CGRect? {
    let watchdog = Task {
        // If an event never landed, get out of your way rather than leave the screen dimmed.
        try? await Task.sleep(for: .seconds(2))
        if !Task.isCancelled {
            print("  picker didn't finish on its own, pressing Esc")
            await pressEscape()
        }
    }
    let result = await picking.value
    watchdog.cancel()
    return result
}

/// Asks the other app and the system, since this process's own idea of being active isn't the question.
@MainActor
private func printFocus(of front: pid_t, when: String) {
    let app = NSRunningApplication(processIdentifier: front)
    var frontmost: CFTypeRef?
    AXUIElementCopyAttributeValue(AXUIElementCreateApplication(front), kAXFrontmostAttribute as CFString, &frontmost)
    var focused: CFTypeRef?
    AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute as CFString, &focused)
    var focusedPID: pid_t = 0
    if let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
        AXUIElementGetPid(focused as! AXUIElement, &focusedPID)
    }
    let me = ProcessInfo.processInfo.processIdentifier
    print("  \(when): workspace frontmost unchanged \(NSWorkspace.shared.frontmostApplication?.processIdentifier == front), "
        + "other app says active \(app?.isActive == true), AXFrontmost \(frontmost as? Bool ?? false), "
        + "AX focus \(focusedPID == front ? "other app" : focusedPID == me ? "PROBE" : "\(focusedPID)")")
}

/// Hot spots and image data both vary between copies of a cursor, so this compares what it looks like.
@MainActor
private func cursorReport() -> String {
    guard let cursor = NSCursor.currentSystem else { return "unknown" }
    func look(_ image: NSImage) -> [UInt8] {
        let size = 32
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            if let context {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
                image.draw(in: CGRect(x: 0, y: 0, width: size, height: size))
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        return bytes
    }
    let seen = look(cursor.image)
    func distance(_ other: NSCursor) -> Int {
        zip(seen, look(other.image)).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
    }
    let toCross = distance(.crosshair)
    let toArrow = distance(.arrow)
    let toIBeam = distance(.iBeam)
    let best = toCross <= min(toArrow, toIBeam) ? "crosshair" : (toArrow <= toIBeam ? "arrow" : "ibeam")
    return "\(best) (difference from crosshair \(toCross), arrow \(toArrow), ibeam \(toIBeam))"
}

@MainActor
private func who(before: pid_t) -> String {
    let me = ProcessInfo.processInfo.processIdentifier
    let front = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
    return front == before ? "same app" : front == me ? "PROBE" : "a different app"
}

/// One drag with the real mouse, through the window server, which events handed to a window can't
/// stand in for: it's the only proof a real click doesn't activate the app. It runs only once the
/// overlay is the top window under the pointer, and the pointer goes back where it was.
private func runRealMouseTest(frontBefore: pid_t) async {
    print("real mouse:")
    let picking = Task { await ScreenContextProvider().pickRegion() }
    try? await Task.sleep(for: .milliseconds(250))

    let height = CGDisplayBounds(CGMainDisplayID()).height
    let original = CGEvent(source: nil)?.location ?? .zero
    let screen = await MainActor.run { NSScreen.screens[0].frame }
    let ready = await MainActor.run { () -> Bool in
        let me = ProcessInfo.processInfo.processIdentifier
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        // The pointer is a window itself, above everything, and it doesn't take clicks.
        let pointerLevel = Int(CGWindowLevelForKey(.cursorWindow))
        // Both the pointer now and where the drag will happen have to be under the overlay.
        func topIsOurs(at point: CGPoint) -> Bool {
            let top = list.first {
                guard let box = $0[kCGWindowBounds as String], let rect = CGRect(dictionaryRepresentation: box as! CFDictionary)
                else { return false }
                return rect.contains(point) && ($0[kCGWindowLayer as String] as? Int ?? 0) < pointerLevel
            }
            return (top?[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == me
        }
        let dragPoint = CGPoint(x: screen.minX + 400, y: height - screen.minY - 620)
        let safe = topIsOurs(at: original) && topIsOurs(at: dragPoint)
        print("  overlay on top under the pointer and the drag: \(safe)")
        return safe
    }
    guard ready else {
        print("  overlay isn't the top window under the pointer, so no events were sent")
        await pressEscape()
        _ = await picking.value
        return
    }

    // Same place first: a real move is what prompts the system to update the cursor.
    func post(_ type: CGEventType, _ point: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    }
    print("  cursor with no move yet: \(await MainActor.run { cursorReport() })")
    print("  front with overlay up: \(await MainActor.run { who(before: frontBefore) })")
    post(.mouseMoved, original)
    try? await Task.sleep(for: .milliseconds(120))
    print("  cursor after a real move: \(await MainActor.run { cursorReport() })")
    print("  front after a real move: \(await MainActor.run { who(before: frontBefore) })")

    let start = CGPoint(x: screen.minX + 400, y: height - screen.minY - 620)
    let end = CGPoint(x: screen.minX + 900, y: height - screen.minY - 300)
    post(.mouseMoved, start)
    try? await Task.sleep(for: .milliseconds(60))
    print("  front after moving to the start: \(await MainActor.run { who(before: frontBefore) })")
    post(.leftMouseDown, start)
    try? await Task.sleep(for: .milliseconds(100))
    print("  front during the press: \(await MainActor.run { who(before: frontBefore) })")
    post(.leftMouseDragged, CGPoint(x: start.x + 250, y: start.y + 160))
    try? await Task.sleep(for: .milliseconds(30))
    post(.leftMouseDragged, end)
    try? await Task.sleep(for: .milliseconds(30))
    print("  front during the drag: \(await MainActor.run { who(before: frontBefore) })")
    post(.leftMouseUp, end)

    let result = await waitForResult(of: picking)
    CGWarpMouseCursorPosition(original)
    let wanted = CGRect(x: screen.minX + 400, y: screen.minY + 300, width: 500, height: 320)
    print("  result: \(result == wanted ? "OK" : "WRONG"), got \(describe(result)), wanted \(describe(wanted))")
    print("  front right after: \(await MainActor.run { who(before: frontBefore) })")
    try? await Task.sleep(for: .milliseconds(250))
    print("  front settled: \(await MainActor.run { who(before: frontBefore) })")
    await MainActor.run {
        print("  probe active after: \(NSApp.isActive)")
        printFocus(of: frontBefore, when: "after")
    }

    // The whole of "fix what I'm looking at": what you dragged goes straight into a snapshot.
    let provider = ScreenContextProvider()
    if let result, let snapshot = try? await provider.snapshot(CaptureOptions(focusRegion: result)) {
        print("  then a snapshot: \(Int(provider.lastReport.timings.total)) ms, \(snapshot.screenshotJPEG?.count ?? 0) bytes, marked at \(describe(snapshot.focusRegion))")
        print("  front after the snapshot: \(await MainActor.run { who(before: frontBefore) })")
    }
}

@MainActor
private func drive(_ steps: [(NSEvent.EventType, CGPoint)]) async {
    guard let start = steps.first?.1,
          let panel = NSApp.windows.first(where: { $0 is NSPanel && $0.isVisible && $0.frame.contains(start) })
    else { return }
    for (type, point) in steps {
        let event = NSEvent.mouseEvent(
            with: type,
            location: panel.convertPoint(fromScreen: point),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: panel.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )
        if let event { NSApp.postEvent(event, atStart: false) }
        try? await Task.sleep(for: .milliseconds(40))
    }
}

@MainActor
private func pressEscape() async {
    let me = ProcessInfo.processInfo.processIdentifier
    CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)?.postToPid(me)
    CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false)?.postToPid(me)
    try? await Task.sleep(for: .milliseconds(40))
}

private func shoot(_ name: String, in directory: URL) async {
    guard Permissions.hasScreenRecording else { return }
    try? await Task.sleep(for: .milliseconds(150))
    let ids = await MainActor.run {
        NSApp.windows.filter { $0 is NSPanel && $0.isVisible }.map { CGWindowID($0.windowNumber) }
    }
    guard let result = try? await ScreenCapture.capture(ScreenCapture.Request(onlyWindows: ids)) else {
        print("  picture failed")
        return
    }
    try? result.jpeg.write(to: directory.appendingPathComponent(name))
    print("  wrote \(name)")
}
