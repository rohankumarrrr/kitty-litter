import AppKit
import ImageIO
import PDFKit
import ShadesCore

/// Something dragged onto the cat: a file, a picture with no file behind it, or a web link. In Messages it's
/// something attached to a message, and from a phone it comes as the file's bytes and name.
public enum Drop: Sendable, Equatable {
    case file(URL)
    case picture(Data)
    case link(URL)
    case bytes(Data, name: String)

    public static let types: [NSPasteboard.PasteboardType] = [.fileURL, .png, .tiff, .URL]

    /// Most that go with one message, as Slack has it.
    public static let mostAtOnce = 10

    /// The first file, or else a picture, or else a web link. A browser's picture comes with its address too,
    /// and the picture is what was meant.
    public init?(_ pasteboard: NSPasteboard) {
        guard let first = Self.all(pasteboard).first else { return nil }
        self = first
    }

    /// Every file, or else a picture, or else a web link.
    public static func all(_ pasteboard: NSPasteboard) -> [Drop] {
        let files = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !files.isEmpty { return files.map(Drop.file) }
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) { return [.picture(data)] }
        if let link = pasteboard.readObjects(forClasses: [NSURL.self])?.first as? URL, ["http", "https"].contains(link.scheme?.lowercased()) {
            return [.link(link)]
        }
        return []
    }

    /// Several dropped or attached together, as one stand-in for the screen: every name, each PDF's text under its
    /// name, and each picture. `nil` if any of them can't be read, so none goes without the rest.
    public static func snapshot(of drops: [Drop]) -> ScreenSnapshot? {
        let read = drops.compactMap { $0.snapshot() }
        guard !read.isEmpty, read.count == drops.count else { return nil }
        if read.count == 1 { return read[0] }
        let pictures = read.flatMap(\.pictures)
        let texts = read.compactMap { part in part.pageText.map { "\(part.droppedNames.joined()):\n\($0)" } }
        return ScreenSnapshot(
            pageText: texts.isEmpty ? nil : texts.joined(separator: "\n\n"),
            screenshotJPEG: pictures.first?.data,
            droppedNames: read.flatMap(\.droppedNames),
            pictures: pictures
        )
    }

    /// What it holds, in place of a look at the screen, or `nil` for anything but a PDF with text, a picture or a link.
    /// It reads the file, so keep it off the main thread.
    public func snapshot() -> ScreenSnapshot? {
        switch self {
        case .link(let url):
            return ScreenSnapshot(url: url, droppedNames: [name])
        case .picture(let data):
            return Self.picture(CGImageSourceCreateWithData(data as CFData, nil), named: name)
        case .file(let url):
            // By what's in it, since a file's name can leave its kind off.
            if let pdf = PDFDocument(url: url) {
                guard let text = pdf.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
                return ScreenSnapshot(url: url, pageText: text, droppedNames: [name])
            }
            var snapshot = Self.picture(CGImageSourceCreateWithURL(url as CFURL, nil), named: name)
            snapshot?.url = url
            return snapshot
        case .bytes(let data, _):
            if data.starts(with: Data("%PDF".utf8)), let pdf = PDFDocument(data: data) {
                guard let text = pdf.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
                return ScreenSnapshot(pageText: text, droppedNames: [name])
            }
            return Self.picture(CGImageSourceCreateWithData(data as CFData, nil), named: name)
        }
    }

    private static func picture(_ source: CGImageSource?, named name: String) -> ScreenSnapshot? {
        guard let jpeg = jpeg(source) else { return nil }
        return ScreenSnapshot(screenshotJPEG: jpeg, droppedNames: [name], pictures: [AgentAttachment(name: name, mimeType: "image/jpeg", data: jpeg)])
    }

    /// A file or picture, as opposed to a link, which in Messages is words like any other.
    public var isFile: Bool {
        if case .link = self { return false }
        return true
    }

    /// What it's called where it's shown, on one line and short enough for T3 to keep as the picture's name.
    public var name: String {
        let name: String
        switch self {
        case .file(let url): name = url.lastPathComponent
        case .picture: name = "a picture"
        case .link(let url): name = url.host ?? url.absoluteString
        case .bytes(_, let named): name = named
        }
        let line = name.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return line.isEmpty ? "a file" : String(line.prefix(120))
    }

    /// A small picture of these bytes, or `nil` if they aren't a picture macOS can open.
    public static func thumbnail(of data: Data, side: CGFloat) -> Data? {
        jpeg(CGImageSourceCreateWithData(data as CFData, nil), side: side)
    }

    /// A small picture of it, for a picture, or `nil` for anything else.
    public func thumbnail(side: CGFloat = 240) -> Data? {
        let source: CGImageSource?
        switch self {
        case .file(let url): source = CGImageSourceCreateWithURL(url as CFURL, nil)
        case .picture(let data), .bytes(let data, _): source = CGImageSourceCreateWithData(data as CFData, nil)
        case .link: return nil
        }
        return Self.jpeg(source, side: side)
    }

    /// Any picture macOS can open, as a JPEG no bigger than a screenshot, since that's all T3 takes.
    private static func jpeg(_ source: CGImageSource?, side: CGFloat = ScreenshotImage.longSide) -> Data? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: side,
        ] as CFDictionary
        guard let source, let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return ScreenshotImage.jpeg(image)
    }
}
