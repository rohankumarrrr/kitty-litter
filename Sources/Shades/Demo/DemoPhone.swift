import AppKit
import WebKit

/// The phone page at a phone's size, in a web view off the edge of every screen, so the demo can use it and draw it the
/// way the windows draw themselves. What it presses are the page's own buttons, pressed inside the page, so nothing
/// reaches the desktop.
@MainActor
final class DemoPhone {
    static let size = NSSize(width: 390, height: 844)

    let view: WKWebView
    private let panel: NSPanel

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        view = WKWebView(frame: NSRect(origin: .zero, size: Self.size), configuration: configuration)
        panel = NSPanel(contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: Self.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.sharingType = .none
        panel.isReleasedWhenClosed = false
        panel.contentView = view
        // A web view only draws while it's in a window that's out, and this one is far off every screen.
        panel.orderFrontRegardless()
    }

    func open(_ url: URL) {
        view.load(URLRequest(url: url))
    }

    /// Pairs the way the page does, with the code that's showing. A browser keeps the server's cookie only over HTTPS,
    /// which a phone has and the demo doesn't, so the web view is handed the same token as a plain cookie.
    func pair(at address: URL, code: String) async -> Bool {
        var request = URLRequest(url: address.appendingPathComponent("pair"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "X-Shades")
        request.httpBody = Data("{\"code\":\(Self.quoted(code))}".utf8)
        guard let (_, response) = try? await URLSession(configuration: .ephemeral).data(for: request),
              let set = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Set-Cookie"),
              let token = set.split(separator: ";").first?.split(separator: "=", maxSplits: 1).last,
              let host = address.host,
              let cookie = HTTPCookie(properties: [.name: PhoneDoor.cookie, .value: String(token), .domain: host, .path: "/"])
        else { return false }
        await view.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
        return true
    }

    /// Runs a line of the page's own script and says what came back. The async form can't come back with nothing.
    func run(_ script: String) async -> String {
        await withCheckedContinuation { continuation in
            view.evaluateJavaScript(script) { result, error in
                continuation.resume(returning: error.map { "failed: \($0.localizedDescription)" } ?? result.map { "\($0)" } ?? "done")
            }
        }
    }

    func draw(to file: URL) async -> Bool {
        guard let image = try? await view.takeSnapshot(configuration: nil),
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return false }
        return (try? png.write(to: file)) != nil
    }

    func close() {
        view.load(URLRequest(url: URL(string: "about:blank")!))
        panel.close()
    }

    /// A string as a script can read it.
    static func quoted(_ text: String) -> String {
        (try? JSONSerialization.data(withJSONObject: text, options: .fragmentsAllowed)).map { String(decoding: $0, as: UTF8.self) } ?? "''"
    }
}
