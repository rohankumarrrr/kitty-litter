import AppKit

/// A drawn stand-in for your picture, in Opal's violet, so the demo and tests never need anyone's photo.
enum DemoPicture {
    static let jpeg: Data = {
        let side: CGFloat = 128
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return Data() }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        Ink.hex(0x8a6cff).setFill()
        NSRect(x: 0, y: 0, width: side, height: side).fill()
        Ink.hex(0xe7e4ec).setFill()
        NSBezierPath(ovalIn: NSRect(x: side * 0.33, y: side * 0.44, width: side * 0.34, height: side * 0.34)).fill()
        NSBezierPath(ovalIn: NSRect(x: side * 0.14, y: -side * 0.3, width: side * 0.72, height: side * 0.66)).fill()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) ?? Data()
    }()
}
