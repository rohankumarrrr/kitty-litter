import AppKit

@MainActor
enum PictureDrawing {
    private(set) static var space: CGColorSpace?

    static func into<Drawn>(_ rep: NSBitmapImageRep, _ work: () -> Drawn) -> Drawn {
        space = rep.colorSpace.cgColorSpace
        defer { space = nil }
        return work()
    }
}
