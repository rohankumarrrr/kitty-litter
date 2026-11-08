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

    /// The first file, or else a picture, or else a web link. A browser's picture comes with its address too,
    /// and the picture is what was meant.
    public init?(_ pasteboard: NSPasteboard) {
        if let file = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])?.first as? URL {
            self = .file(file)
        } else if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            self = .picture(data)
        } else if let link = pasteboard.readObjects(forClasses: [NSURL.self])?.first as? URL, ["http", "https"].contains(link.scheme?.lowercased()) {
            self = .link(link)
        } else {
            return nil
        }
    }

    /// What it holds, in place of a look at the screen, or `nil` for anything but a PDF with text, a picture or a link.
    /// It reads the file, so keep it off the main thread.
    public func snapshot() -> ScreenSnapshot? {
        switch self {
        case .link(let url):
            return ScreenSnapshot(url: url, droppedName: url.host ?? url.absoluteString)
        case .picture(let data):
            return Self.jpeg(CGImageSourceCreateWithData(data as CFData, nil)).map { ScreenSnapshot(screenshotJPEG: $0, droppedName: "a picture") }
        case .file(let url):
            // By what's in it, since a file's name can leave its kind off.
            if let pdf = PDFDocument(url: url) {
                guard let text = pdf.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
                return ScreenSnapshot(url: url, pageText: text, droppedName: url.lastPathComponent)
            }
            guard let jpeg = Self.jpeg(CGImageSourceCreateWithURL(url as CFURL, nil)) else { return nil }
            return ScreenSnapshot(url: url, screenshotJPEG: jpeg, droppedName: url.lastPathComponent)
        case .bytes(let data, let name):
            if data.starts(with: Data("%PDF".utf8)), let pdf = PDFDocument(data: data) {
                guard let text = pdf.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
                return ScreenSnapshot(pageText: text, droppedName: name)
            }
            guard let jpeg = Self.jpeg(CGImageSourceCreateWithData(data as CFData, nil)) else { return nil }
            return ScreenSnapshot(screenshotJPEG: jpeg, droppedName: name)
        }
    }

    /// A file or picture, as opposed to a link, which in Messages is words like any other.
    public var isFile: Bool {
        if case .link = self { return false }
        return true
    }

    /// What it's called where it's shown.
    public var name: String {
        switch self {
        case .file(let url): return url.lastPathComponent
        case .picture: return "a picture"
        case .link(let url): return url.host ?? url.absoluteString
        case .bytes(_, let name): return name
        }
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
