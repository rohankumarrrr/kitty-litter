import AppKit
import ImageIO
import ShadesCore
import UniformTypeIdentifiers

/// Records what the demo does as a looping GIF, for the README. Each frame is the chosen windows as they draw themselves,
/// laid where they are on the screen over a drawn stand-in for the pricing page the demo pretends you're looking at,
/// so nothing is ever read from the real screen.
@MainActor
final class DemoRecorder {
    private static let framesPerSecond = 8.0
    private static let margin: CGFloat = 24
    /// Sharp on a Retina screen, which is where most people read the README.
    static let scale: CGFloat = 2

    private struct Shot {
        var windows: [(image: CGImage, frame: CGRect)]
        var phone: CGImage?
        /// When it was taken, since a phone's page takes longer to draw than a frame lasts.
        var at: Date
    }

    private let file: URL
    private let windows: () -> [(CGImage, CGRect)]
    /// Whether the cat's in it, out on the desktop, where the page it's looking at goes behind it.
    private let onPage: Bool
    private let phone: DemoPhone?
    private let now: () -> Date
    private var shots: [Shot] = []
    private var loop: Task<Void, Never>?

    /// `windows` gives what each chosen window shows now, and where. A phone is recorded on its own.
    init(file: URL, windows: @escaping () -> [(CGImage, CGRect)], onPage: Bool, phone: DemoPhone?, now: @escaping () -> Date = Date.init) {
        self.file = file
        self.windows = windows
        self.onPage = onPage
        self.phone = phone
        self.now = now
    }

    func start() {
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.shoot()
                try? await Task.sleep(nanoseconds: UInt64(1_000_000_000 / Self.framesPerSecond))
            }
        }
    }

    /// Writes the GIF, and says how many frames it kept and how big it is.
    func stop() -> String {
        loop?.cancel()
        let images = phone == nil ? scene() : shots.map { $0.phone.map(Self.framed) }
        guard images.contains(where: { $0 != nil }) else { return "nothing to record" }
        var frames: [(image: CGImage, seconds: Double)] = []
        // A frame lasts until the next was taken, and one that's the same as the one before only makes it last longer.
        for (index, image) in images.enumerated() {
            let seconds = index + 1 < shots.count ? shots[index + 1].at.timeIntervalSince(shots[index].at) : 1 / Self.framesPerSecond
            guard let image else {
                if !frames.isEmpty { frames[frames.count - 1].seconds += seconds }
                continue
            }
            if let last = frames.last, Self.same(last.image, image) {
                frames[frames.count - 1].seconds += seconds
            } else {
                frames.append((image, seconds))
            }
        }
        // The last frame holds a moment before it starts again.
        frames[frames.count - 1].seconds += 2
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else {
            return "couldn't write \(file.path)"
        }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in frames {
            let delay = [kCGImagePropertyGIFDelayTime: frame.seconds, kCGImagePropertyGIFUnclampedDelayTime: frame.seconds]
            CGImageDestinationAddImage(destination, frame.image, [kCGImagePropertyGIFDictionary: delay] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { return "couldn't write \(file.path)" }
        // Each frame as a picture too, so what the GIF holds can be looked at like any other demo picture.
        let pictures = URL(fileURLWithPath: ".verify/shades/record", isDirectory: true).appendingPathComponent(file.deletingPathExtension().lastPathComponent)
        try? FileManager.default.removeItem(at: pictures)
        try? FileManager.default.createDirectory(at: pictures, withIntermediateDirectories: true)
        for (index, frame) in frames.enumerated() {
            let png = NSBitmapImageRep(cgImage: frame.image).representation(using: .png, properties: [:])
            try? png?.write(to: pictures.appendingPathComponent(String(format: "%02d.png", index)))
        }
        let bytes = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
        return "recorded \(file.path) \(frames.count) frames \(bytes / 1024) KB"
    }

    private func shoot() async {
        let at = now()
        if let phone {
            let image = await phone.image(scale: Self.scale)
            shots.append(Shot(windows: [], phone: image, at: at))
        } else {
            shots.append(Shot(windows: windows(), phone: nil, at: at))
        }
    }

    /// Every frame cut to the same place: wherever the windows went, with a little room around them.
    private func scene() -> [CGImage?] {
        let screen = NSScreen.screens.first?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let seen = shots.flatMap { $0.windows.map(\.frame) }
        guard let first = seen.first else { return [] }
        let area = seen.reduce(first) { $0.union($1) }.insetBy(dx: -Self.margin, dy: -Self.margin).intersection(screen).integral
        return shots.map { shot in
            guard let context = CGContext(
                data: nil, width: Int(area.width * Self.scale), height: Int(area.height * Self.scale), bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            context.scaleBy(x: Self.scale, y: Self.scale)
            context.translateBy(x: -area.minX, y: -area.minY)
            context.interpolationQuality = .none
            if onPage {
                Self.drawPage(on: screen, in: context)
            } else {
                context.setFillColor(NSColor(white: 0.93, alpha: 1).cgColor)
                context.fill(area)
            }
            for window in shot.windows {
                context.saveGState()
                context.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: NSColor.black.withAlphaComponent(0.22).cgColor)
                context.draw(window.image, in: window.frame)
                context.restoreGState()
            }
            return context.makeImage()
        }
    }

    /// The pricing page in Safari that the demo's screen describes, with its heading, plan and trial button where the
    /// demo says they are, so the cat lands on them when it points.
    private static func drawPage(on screen: CGRect, in context: CGContext) {
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        NSColor(white: 0.97, alpha: 1).setFill()
        screen.fill()
        let bar = CGRect(x: screen.minX, y: screen.maxY - screen.height * 0.07, width: screen.width, height: screen.height * 0.07)
        NSColor(white: 0.9, alpha: 1).setFill()
        bar.fill()
        let elements = DemoContext.elements(on: screen)
        func frame(_ label: String) -> CGRect { elements.first { $0.label == label }?.frame ?? .zero }
        let address = CGRect(x: bar.midX - 220, y: bar.midY - 14, width: 440, height: 28)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: address, xRadius: 8, yRadius: 8).fill()
        text("example.com/pricing", in: address.insetBy(dx: 12, dy: 6), size: 13, color: NSColor(white: 0.45, alpha: 1))
        NSColor(white: 0.55, alpha: 1).setStroke()
        NSBezierPath(roundedRect: frame("Share").insetBy(dx: 6, dy: 4), xRadius: 3, yRadius: 3).stroke()
        text("Pricing", in: frame("Pricing"), size: 30, weight: .bold, color: NSColor(white: 0.12, alpha: 1))

        // Each plan as a card around its button, so its name and price sit just above where the cat lands.
        let trial = frame("Start free trial")
        let pro = CGRect(x: trial.minX - 40, y: trial.minY - 30, width: trial.width + 80, height: trial.height + 150)
        for (index, plan) in [("Free", "$0", "Choose Free"), ("Pro", "$12 a month", "Start free trial"), ("Team", "$30 a month", "Choose Team")].enumerated() {
            let card = pro.offsetBy(dx: CGFloat(index - 1) * (pro.width + 24), dy: 0)
            NSColor.white.setFill()
            NSBezierPath(roundedRect: card, xRadius: 14, yRadius: 14).fill()
            NSColor(white: 0.85, alpha: 1).setStroke()
            NSBezierPath(roundedRect: card, xRadius: 14, yRadius: 14).stroke()
            text(plan.0, in: CGRect(x: card.minX + 24, y: card.maxY - 46, width: card.width - 48, height: 26), size: 20, weight: .semibold, color: NSColor(white: 0.12, alpha: 1))
            text(plan.1, in: CGRect(x: card.minX + 24, y: card.maxY - 74, width: card.width - 48, height: 22), size: 15, color: NSColor(white: 0.45, alpha: 1))
            let button = trial.offsetBy(dx: card.minX - pro.minX, dy: 0)
            let isTrial = index == 1
            (isTrial ? NSColor(red: 0, green: 0.44, blue: 0.89, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
            NSBezierPath(roundedRect: button, xRadius: 10, yRadius: 10).fill()
            text(plan.2, in: button.insetBy(dx: 0, dy: 12), size: 15, weight: .semibold, color: isTrial ? .white : NSColor(white: 0.12, alpha: 1), centered: true)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func text(_ string: String, in rect: CGRect, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor, centered: Bool = false) {
        let style = NSMutableParagraphStyle()
        style.alignment = centered ? .center : .left
        NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: style,
        ]).draw(in: rect)
    }

    /// A phone's page with rounded corners on a plain ground, the way a phone frames it.
    private static func framed(_ page: CGImage) -> CGImage {
        let pad = Int(16 * scale)
        let width = page.width + pad * 2
        let height = page.height + pad * 2
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return page }
        context.setFillColor(NSColor(white: 0.93, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let screen = CGRect(x: pad, y: pad, width: page.width, height: page.height)
        context.addPath(CGPath(roundedRect: screen, cornerWidth: 28 * scale, cornerHeight: 28 * scale, transform: nil))
        context.clip()
        context.draw(page, in: screen)
        return context.makeImage() ?? page
    }

    private static func same(_ a: CGImage, _ b: CGImage) -> Bool {
        guard a.width == b.width, a.height == b.height, let x = a.dataProvider?.data, let y = b.dataProvider?.data else { return false }
        return (x as Data) == (y as Data)
    }
}
