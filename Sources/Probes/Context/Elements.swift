import AppKit
import ShadesContext
import ShadesCore
import WebKit

// Reads what the cat could point at from a window of the probe's own, in another process,
// so nothing from your real screen is read.

private enum Sentinel {
    static let typed = "TYPEDSENTINEL"
    static let secret = "SECRETSENTINEL"
}

/// What's typed into a page's boxes is held in text inside them, unlike AppKit's fields.
private let page = """
<!doctype html><html><body style="font: 14px -apple-system">
<input placeholder="Web search" value="\(Sentinel.typed)input">
<textarea placeholder="Notes">\(Sentinel.typed)area</textarea>
<div contenteditable="true" aria-label="Message body" style="border:1px solid #999;min-height:24px">\(Sentinel.typed)editable words</div>
<div role="textbox" aria-label="Role box" contenteditable="true" style="border:1px solid #999">\(Sentinel.typed)rolebox words</div>
<input type="password" placeholder="Web password" value="\(Sentinel.secret)">
</body></html>
"""

/// Buttons and fields at known places, shown without taking focus. Prints the Export button's
/// frame in AppKit points, then quits by itself, so nothing stays running.
@MainActor
func serveButtons() async {
    let screens = NSScreen.screens
    let screen = screens[min(value(after: "--screen").flatMap(Int.init) ?? 0, screens.count - 1)].frame
    let window = NSWindow(
        contentRect: CGRect(x: screen.minX + 240, y: screen.minY + 220, width: 520, height: 420),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    window.title = "Shades elements test"
    // A window made with a frame is kept on the main display, but moving it afterwards isn't.
    window.setFrameOrigin(CGPoint(x: screen.minX + 240, y: screen.minY + 220))
    var export = NSButton()
    for (index, title) in ["Import", "Export", "Share"].enumerated() {
        let button = NSButton(title: title, target: nil, action: nil)
        button.frame = CGRect(x: 20 + CGFloat(index) * 120, y: 130, width: 100, height: 32)
        window.contentView?.addSubview(button)
        if title == "Export" { export = button }
    }
    let field = NSTextField(frame: CGRect(x: 20, y: 80, width: 220, height: 24))
    field.placeholderString = "Search"
    field.stringValue = "\(Sentinel.typed) words"
    let secure = NSSecureTextField(frame: CGRect(x: 260, y: 80, width: 220, height: 24))
    secure.placeholderString = "Password"
    secure.stringValue = Sentinel.secret
    let label = NSTextField(labelWithString: "Font size")
    label.frame = CGRect(x: 20, y: 30, width: 200, height: 20)
    let web = WKWebView(frame: CGRect(x: 20, y: 210, width: 480, height: 200))
    web.loadHTMLString(page, baseURL: nil)
    [field, secure, label, web].forEach { window.contentView?.addSubview($0) }
    window.orderFrontRegardless()
    window.makeKey()
    window.makeMain()
    // Long enough for the page to load and WebKit to build what Accessibility reads.
    try? await Task.sleep(for: .seconds(2))

    let frame = window.convertToScreen(export.convert(export.bounds, to: nil))
    print("ready \(frame.minX) \(frame.minY) \(frame.width) \(frame.height)")
    fflush(stdout)
    try? await Task.sleep(for: .seconds(8))
    window.orderOut(nil)
}

func runElementsCheck() async {
    guard Permissions.hasAccessibility else {
        print("needs Accessibility")
        return
    }
    let server = Process()
    server.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    server.arguments = ["--serve-buttons", "--screen", value(after: "--screen") ?? "0"]
    let ready = Pipe()
    server.standardOutput = ready
    guard (try? server.run()) != nil else {
        print("couldn't start the window")
        return
    }
    defer { server.terminate() }
    let line = String(decoding: ready.fileHandleForReading.availableData, as: UTF8.self)
    let numbers = line.split(separator: " ").dropFirst().compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    guard numbers.count == 4 else {
        print("the window didn't say where it is: \(line)")
        return
    }
    let expected = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
    try? await Task.sleep(for: .milliseconds(500))

    // WebKit can build its tree on the first ask, so the second is the one that counts.
    _ = await ScreenContextProvider.elements(ofApp: server.processIdentifier)
    try? await Task.sleep(for: .milliseconds(500))
    let clock = ContinuousClock()
    let started = clock.now
    let elements = await ScreenContextProvider.elements(ofApp: server.processIdentifier)
    let took = clock.now - started
    print("displays: \(await MainActor.run { NSScreen.screens.map { describe($0.frame) } })")
    print("read \(elements.count) elements in \(Int(Double(took.components.seconds) * 1000 + Double(took.components.attoseconds) / 1e15)) ms")
    for element in elements { print("  \(element.role) \"\(element.label)\" \(describe(element.frame))") }

    let screens = await MainActor.run { NSScreen.screens.map(\.frame) }
    print("Export button expected at \(describe(expected)), on display \(screens.firstIndex { $0.contains(expected) }.map(String.init) ?? "none")")
    // Accessibility gives the bezel you see, which sits inside the button's view, so it's the middles that match.
    if let export = elements.first(where: { $0.label == "Export" }) {
        let off = max(abs(export.frame.midX - expected.midX), abs(export.frame.midY - expected.midY))
        let inside = expected.contains(export.frame)
        print("  read at \(describe(export.frame)): middle within \(Int(off)) pt, inside the view: \(inside)  \(off <= 2 && inside ? "OK" : "WRONG")")
    } else {
        print("  not read  WRONG")
    }
    let labels = elements.map(\.label).joined(separator: " ")
    print("typed text left out: \(labels.contains(Sentinel.typed) ? "WRONG" : "OK")")
    print("password left out:   \(labels.contains(Sentinel.secret) || labels.contains("Password") || labels.contains("Web password") ? "WRONG" : "OK")")
    print("field named by its placeholder: \(elements.contains { $0.label == "Search" } ? "OK" : "WRONG")")
    print("page's boxes named: \(["Notes", "Message body"].allSatisfy { name in elements.contains { $0.label == name } } ? "OK" : "WRONG")")
    print("label read: \(elements.contains { $0.label == "Font size" } ? "OK" : "WRONG")")
}
