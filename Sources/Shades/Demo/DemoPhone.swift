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

    /// Runs a line of the page's own script and says what came back. The async form can't come back with nothing.
    func run(_ script: String) async -> String {
        await withCheckedContinuation { continuation in
            view.evaluateJavaScript(script) { result, error in
                continuation.resume(returning: error.map { "failed: \($0.localizedDescription)" } ?? result.map { "\($0)" } ?? "done")
            }
        }
    }

    /// Runs the body of an async function in the page, so it can wait on the page's own requests.
    func runAsync(_ body: String) async -> String {
        await withCheckedContinuation { continuation in
            view.callAsyncJavaScript(body, arguments: [:], in: nil, in: .page) { result in
                switch result {
                case .success(let value): continuation.resume(returning: "\(value)")
                case .failure(let error): continuation.resume(returning: "failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// The page as it looks now, at a phone's size in points times `scale`.
    func image(scale: CGFloat) async -> CGImage? {
        guard let snapshot = try? await view.takeSnapshot(configuration: nil),
              let page = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(Self.size.width * scale), pixelsHigh: Int(Self.size.height * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        page.size = Self.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: page)
        snapshot.draw(in: NSRect(origin: .zero, size: Self.size))
        NSGraphicsContext.restoreGraphicsState()
        return page.cgImage
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

    /// A made-up photo, drawn on the page and attached the way its camera button attaches one.
    /// A made-up photo with `name` written on it, as the page's 📎 or 📷 would add one.
    static func attachPicture(named name: String) -> String {
        """
        const canvas = document.createElement('canvas');
        canvas.width = 1600; canvas.height = 1200;
        const pen = canvas.getContext('2d');
        pen.fillStyle = '#2f6f5e'; pen.fillRect(0, 0, 1600, 1200);
        pen.fillStyle = '#f4efe6'; pen.fillRect(200, 450, 1200, 360);
        pen.fillStyle = '#1d1d1f'; pen.font = 'bold 120px sans-serif'; pen.fillText(\(quoted(name)), 360, 670);
        const blob = await new Promise((resolve) => canvas.toBlob(resolve, 'image/png'));
        await attach([new File([blob], \(quoted(name + ".png")), { type: 'image/png' })]);
        return attached.length ? 'attached ' + attached.map((file) => file.name).join(', ') : 'not attached';
        """
    }
}
