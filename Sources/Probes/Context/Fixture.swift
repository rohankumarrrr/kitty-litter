import AppKit
import ShadesContext
import ShadesCore

// Capture checks against a window the probe makes itself. Images are captured with only that
// window in them, so nothing from your real screen ever reaches the files this writes.

/// A window of known colours at a known place, with a cyan block to point at.
@MainActor
final class FixtureWindow {
    static let background = NSColor(srgbRed: 0.12, green: 0.14, blue: 0.20, alpha: 1)
    static let target = NSColor(srgbRed: 0, green: 0.85, blue: 0.85, alpha: 1)

    let window: NSWindow
    /// The cyan block, in AppKit global points.
    let targetRect: CGRect

    init(frame: CGRect, target local: CGRect) {
        window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .floating
        window.isReleasedWhenClosed = false
        // As Messages is, so the check below proves another app's capture can't see it.
        if arguments.contains("--unshared") { window.sharingType = .none }
        window.backgroundColor = Self.background
        let content = NSView(frame: CGRect(origin: .zero, size: frame.size))
        content.wantsLayer = true
        content.layer?.backgroundColor = Self.background.cgColor
        let block = NSView(frame: local)
        block.wantsLayer = true
        block.layer?.backgroundColor = Self.target.cgColor
        content.addSubview(block)
        window.contentView = content
        targetRect = local.offsetBy(dx: frame.minX, dy: frame.minY)
        window.orderFrontRegardless()
    }

    var id: CGWindowID { CGWindowID(window.windowNumber) }

    func close() { window.orderOut(nil) }
}

/// Where the fixture goes, so that two processes can agree on it.
private enum Layout {
    /// `--screen 1` puts everything on the second display, whose coordinates are the hard case.
    static var screen: CGRect {
        let screens = NSScreen.screens
        let chosen = value(after: "--screen").flatMap(Int.init) ?? 0
        return screens[min(chosen, screens.count - 1)].frame
    }
    static var frame: CGRect { CGRect(x: screen.minX + 200, y: screen.minY + 200, width: 900, height: 600) }
    static let target = CGRect(x: 300, y: 180, width: 240, height: 120)
    static var targetOnScreen: CGRect { target.offsetBy(dx: frame.minX, dy: frame.minY) }
}

/// Shows the fixture for another probe process to capture. Quits by itself, so nothing stays running.
func serveFixture() async {
    let fixture = await MainActor.run { FixtureWindow(frame: Layout.frame, target: Layout.target) }
    print("ready")
    fflush(stdout)
    try? await Task.sleep(for: .seconds(8))
    await MainActor.run { fixture.close() }
}

/// A real text field holding selected text, in a process of its own for another probe to read.
/// Quits by itself, so nothing stays running.
@MainActor
func serveField(secure: Bool) async {
    NSApp.setActivationPolicy(.regular)
    let window = NSWindow(
        contentRect: CGRect(x: 300, y: 300, width: 420, height: 90),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    window.title = "Shades field test"
    let field = secure ? NSSecureTextField() : NSTextField()
    field.frame = CGRect(x: 20, y: 30, width: 380, height: 24)
    field.stringValue = "FIELDSENTINEL words"
    window.contentView?.addSubview(field)
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    window.makeFirstResponder(field)
    field.selectText(nil)
    print("ready")
    fflush(stdout)
    try? await Task.sleep(for: .seconds(6))
    window.orderOut(nil)
}

func runSyntheticChecks(in directory: URL) async {
    guard Permissions.hasScreenRecording else {
        print("needs Screen Recording")
        return
    }
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let chosen = await MainActor.run { Layout.screen }
    print("screen: \(describe(chosen)) in AppKit points, \(NSScreen.screens.count) display(s)")

    // The normal path first, with the fixture in another process since it leaves out its own windows.
    await checkRealCapturePath()

    let (fixture, backdrop) = await MainActor.run {
        (FixtureWindow(frame: Layout.frame, target: Layout.target), Backdrop(screen: Layout.screen))
    }
    // ScreenCaptureKit only lists a window once the system has it on screen.
    try? await Task.sleep(for: .milliseconds(400))
    let windows = await MainActor.run { [fixture.id, backdrop.id] }

    await checkMarkLandsOnTarget(windows, target: Layout.targetOnScreen, in: directory)
    await checkCornerRegions(windows, frame: Layout.frame, in: directory)
    await checkOwnWindowsStayOut(target: Layout.targetOnScreen)
    await checkUnsharedWindowStaysOut()

    await MainActor.run {
        fixture.close()
        backdrop.close()
    }
    checkSavingToTheRealStore()
}

/// Goes through the real captures folder, with made-up bytes so none of your screen gets stored.
private func checkSavingToTheRealStore() {
    let provider = ScreenContextProvider()
    let bytes = Data([0xFF, 0xD8, 0xFF, 0xD9])
    do {
        guard let path = try provider.saveScreenshot(of: ScreenSnapshot(screenshotJPEG: bytes)) else {
            print("save: nothing saved")
            return
        }
        let files = FileManager.default
        let attributes = try files.attributesOfItem(atPath: path)
        let mode = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        let folder = URL(fileURLWithPath: path).deletingLastPathComponent()
        let folderMode = (try files.attributesOfItem(atPath: folder.path)[.posixPermissions] as? NSNumber)?.intValue ?? 0
        print("save: file mode \(String(mode, radix: 8)), folder mode \(String(folderMode, radix: 8)), in the settings folder \(path.hasPrefix(Settings.directory.path))")
        try files.removeItem(atPath: path)
        print("  test file removed")
    } catch {
        print("save: failed \(error)")
    }
    print("  private snapshots save nothing: \((try? provider.saveScreenshot(of: ScreenSnapshot(screenshotJPEG: bytes, isPrivate: true))) ?? nil == nil)")
}

/// An invisible window the size of the display. Captured alongside the fixture, it makes the
/// picture cover the whole display while holding nothing from it.
@MainActor
final class Backdrop {
    private let window: NSWindow

    init(screen: CGRect) {
        window = NSWindow(contentRect: screen, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.setFrame(screen, display: false)
        window.orderFrontRegardless()
    }

    var id: CGWindowID { CGWindowID(window.windowNumber) }

    func close() { window.orderOut(nil) }
}

/// Another app's window that isn't for sharing, as Messages isn't, never shows up in a capture. The same window
/// shared has to, or a fixture that never came up would pass.
private func checkUnsharedWindowStaysOut() async {
    let shared = await cyanInAnotherAppsFixture(unshared: false)
    let unshared = await cyanInAnotherAppsFixture(unshared: true)
    let works = (shared ?? 0) > 0 && unshared == 0
    print("unshared window: \(unshared.map(String.init) ?? "no capture") cyan pixels, against \(shared.map(String.init) ?? "no capture") shared  \(works ? "OK" : "WRONG")")
}

private func cyanInAnotherAppsFixture(unshared: Bool) async -> Int? {
    guard let server = await startFixture(unshared: unshared) else { return nil }
    defer { server.terminate() }
    let target = await MainActor.run { Layout.targetOnScreen }
    guard let result = try? await ScreenCapture.capture(ScreenCapture.Request(focusRegion: target)), let region = result.focusRegion else { return nil }
    let inner = region.insetBy(dx: region.width * 0.2, dy: region.height * 0.2)
    return count(in: inner, of: decode(result.jpeg)) { $0.red < 60 && $0.green > 170 && $0.blue > 170 }
}

/// The fixture in a process of its own, once it's on the screen.
private func startFixture(unshared: Bool = false) async -> Process? {
    let server = Process()
    server.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    server.arguments = ["--serve-fixture", "--screen", value(after: "--screen") ?? "0"] + (unshared ? ["--unshared"] : [])
    let ready = Pipe()
    server.standardOutput = ready
    guard (try? server.run()) != nil else { return nil }
    _ = ready.fileHandleForReading.availableData
    try? await Task.sleep(for: .milliseconds(500))
    return server
}

/// A true full-display capture, with your real screen around the fixture. It only gets counted
/// in memory here, never saved or shown.
private func checkRealCapturePath() async {
    guard let server = await startFixture() else {
        print("real path: couldn't start the fixture")
        return
    }
    defer { server.terminate() }

    let target = await MainActor.run { Layout.targetOnScreen }
    do {
        let result = try await ScreenCapture.capture(ScreenCapture.Request(focusRegion: target))
        guard let region = result.focusRegion else {
            print("real path: no region")
            return
        }
        let image = decode(result.jpeg)
        print("real path: full display \(image.width)x\(image.height), \(result.jpeg.count / 1024) KB")
        print("  reported region: \(describe(region))")
        // Only near the region, as the rest of the picture is your screen.
        let near = region.insetBy(dx: -40, dy: -40)
        let cyan = extent(in: near, of: image) { $0.red < 70 && $0.green > 170 && $0.blue > 170 }
        print("  cyan found at:   \(describe(cyan))")
        let red = extent(in: near, of: image) { $0.red > 190 && $0.green < 90 && $0.blue < 90 }
        print("  red found at:    \(describe(red))")
        if let cyan {
            let off = max(
                abs(cyan.minX - region.minX), abs(cyan.minY - region.minY),
                abs(cyan.maxX - region.maxX), abs(cyan.maxY - region.maxY)
            )
            print("  cyan vs reported region: within \(Int(off)) px  \(off <= 3 ? "OK" : "WRONG")")
        }
        if let red {
            let surrounds = red.minX < region.minX && red.minY < region.minY && red.maxX > region.maxX && red.maxY > region.maxY
            print("  red surrounds the region: \(surrounds ? "OK" : "WRONG")")
        }
    } catch {
        print("real path: capture failed \(error)")
    }
}

private func capture(_ windows: [CGWindowID], focus: CGRect?) async throws -> ScreenCapture.Result {
    try await ScreenCapture.capture(ScreenCapture.Request(focusRegion: focus, onlyWindows: windows))
}

/// Finds the cyan block in the picture by colour and compares it with the rect the code reported.
private func checkMarkLandsOnTarget(_ windows: [CGWindowID], target: CGRect, in directory: URL) async {
    do {
        let result = try await capture(windows, focus: target)
        let path = directory.appendingPathComponent("mark-\(value(after: "--screen") ?? "0").jpg")
        try result.jpeg.write(to: path)
        let image = decode(result.jpeg)
        print("mark: image \(image.width)x\(image.height), \(result.jpeg.count / 1024) KB")
        print("  reported region: \(describe(result.focusRegion))")
        let cyan = extent(of: image) { $0.red < 60 && $0.green > 170 && $0.blue > 170 }
        print("  cyan found at:   \(describe(cyan))")
        let red = extent(of: image) { $0.red > 200 && $0.green < 90 && $0.blue < 90 }
        print("  red found at:    \(describe(red))")
        if let cyan, let region = result.focusRegion {
            let off = max(
                abs(cyan.minX - region.minX), abs(cyan.minY - region.minY),
                abs(cyan.maxX - region.maxX), abs(cyan.maxY - region.maxY)
            )
            print("  cyan vs reported region: within \(Int(off)) px  \(off <= 3 ? "OK" : "WRONG")")
        }
        if let red, let region = result.focusRegion {
            let surrounds = red.minX < region.minX && red.minY < region.minY && red.maxX > region.maxX && red.maxY > region.maxY
            print("  red surrounds the region: \(surrounds ? "OK" : "WRONG")")
        }
        print("  wrote \(path.lastPathComponent)")
    } catch {
        print("mark: capture failed \(error)")
    }
}

/// Regions touching each corner of the fixture catch a flip that a centred region wouldn't.
private func checkCornerRegions(_ windows: [CGWindowID], frame: CGRect, in directory: URL) async {
    let size = CGSize(width: 150, height: 90)
    let corners: [(String, CGPoint)] = [
        ("top-left", CGPoint(x: frame.minX, y: frame.maxY - size.height)),
        ("top-right", CGPoint(x: frame.maxX - size.width, y: frame.maxY - size.height)),
        ("bottom-left", CGPoint(x: frame.minX, y: frame.minY)),
        ("bottom-right", CGPoint(x: frame.maxX - size.width, y: frame.minY)),
    ]
    for (name, origin) in corners {
        guard let result = try? await capture(windows, focus: CGRect(origin: origin, size: size)) else {
            print("corner \(name): capture failed")
            continue
        }
        let image = decode(result.jpeg)
        guard let region = result.focusRegion else {
            print("corner \(name): nothing found")
            continue
        }
        // Inside the region must be the fixture's own dark background, on the side we asked for.
        let inner = region.insetBy(dx: 12, dy: 12)
        let dark = count(in: inner, of: image) { $0.red < 60 && $0.green < 60 && $0.blue > 25 && $0.blue < 80 }
        let total = Int(inner.width) * Int(inner.height)
        print("corner \(name): region \(describe(region)), \(dark * 100 / max(total, 1))% on the fixture  \(dark * 10 >= total * 9 ? "OK" : "WRONG")")
    }
}

/// The normal capture path must leave the probe's own window out. The picture holds your real
/// screen here, so it only gets counted in memory, never saved or shown.
private func checkOwnWindowsStayOut(target: CGRect) async {
    guard let result = try? await ScreenCapture.capture(ScreenCapture.Request(focusRegion: target)),
          let region = result.focusRegion
    else {
        print("own window: capture failed")
        return
    }
    // Sample inside the cyan block, away from the mark.
    let image = decode(result.jpeg)
    let inner = region.insetBy(dx: region.width * 0.2, dy: region.height * 0.2)
    let cyan = count(in: inner, of: image) { $0.red < 60 && $0.green > 170 && $0.blue > 170 }
    print("own window: \(cyan) of the probe's cyan pixels in a normal capture  \(cyan == 0 ? "OK" : "WRONG")")
}

func describe(_ rect: CGRect?) -> String {
    guard let rect else { return "none" }
    return "x \(Int(rect.minX)) y \(Int(rect.minY)) w \(Int(rect.width)) h \(Int(rect.height))"
}

struct Pixels {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    func at(_ x: Int, _ y: Int) -> (red: UInt8, green: UInt8, blue: UInt8) {
        let offset = (y * width + x) * 4
        return (bytes[offset], bytes[offset + 1], bytes[offset + 2])
    }
}

func decode(_ jpeg: Data) -> Pixels {
    guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return Pixels(width: 0, height: 0, bytes: []) }
    return pixels(of: image)
}

func pixels(of image: CGImage) -> Pixels {
    let width = image.width
    let height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    bytes.withUnsafeMutableBytes { buffer in
        let context = CGContext(
            data: buffer.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return Pixels(width: width, height: height, bytes: bytes)
}

func extent(
    in area: CGRect? = nil,
    of image: Pixels,
    where matches: ((red: UInt8, green: UInt8, blue: UInt8)) -> Bool
) -> CGRect? {
    let box = (area ?? CGRect(x: 0, y: 0, width: image.width, height: image.height))
        .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
    for y in Int(box.minY)..<Int(box.maxY) {
        for x in Int(box.minX)..<Int(box.maxX) where matches(image.at(x, y)) {
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }
    }
    guard maxX >= 0 else { return nil }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

func count(in rect: CGRect, of image: Pixels, where matches: ((red: UInt8, green: UInt8, blue: UInt8)) -> Bool) -> Int {
    var total = 0
    for y in Int(rect.minY)..<min(Int(rect.maxY), image.height) {
        for x in Int(rect.minX)..<min(Int(rect.maxX), image.width) where matches(image.at(x, y)) {
            total += 1
        }
    }
    return total
}
