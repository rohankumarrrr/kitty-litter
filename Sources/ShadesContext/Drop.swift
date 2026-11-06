import AppKit
import ImageIO
import PDFKit
import ShadesCore

/// Something dragged onto the cat: a file, a picture with no file behind it, or a web link.
public enum Drop: Sendable, Equatable {
    case file(URL)
    case picture(Data)
    case link(URL)

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
        }
    }

    /// Any picture macOS can open, as a JPEG no bigger than a screenshot, since that's all T3 takes.
    private static func jpeg(_ source: CGImageSource?) -> Data? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: ScreenshotImage.longSide,
        ] as CFDictionary
        guard let source, let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return ScreenshotImage.jpeg(image)
    }
}
