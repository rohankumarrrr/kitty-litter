import AppKit

@MainActor
enum AppIcon {
    static let hue = Ink.hex(Opal.good).hueComponent * 360
    static let rimShare: CGFloat = 0.014
    static let catGridShare: CGFloat = 0.62
    private static let wash: [(downTheTile: CGFloat, alpha: CGFloat)] = [(0.57, 0), (0.704, 0.26), (0.8, 0.65)]

    static var dock: NSImage {
        let picture = picture(side: 512)
        let image = NSImage(size: NSSize(width: picture.pixelsWide, height: picture.pixelsHigh))
        image.addRepresentation(picture)
        return image
    }

    static var phone: Data {
        picture(side: 180, fillsItsSquare: true).representation(using: .png, properties: [:]) ?? Data()
    }

    static func picture(side: Int, fillsItsSquare: Bool = false) -> NSBitmapImageRep {
        let picture = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!.retagging(with: .sRGB)!
        guard let context = NSGraphicsContext(bitmapImageRep: picture) else { return picture }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        let square = NSRect(x: 0, y: 0, width: side, height: side)
        // Outside the repo: Apple's icon grid puts the tile at 824 of 1024 pixels, with room around it.
        let inset = fillsItsSquare || side <= 32 ? 0 : (CGFloat(side) * 100 / 1024).rounded()
        let tile = square.insetBy(dx: inset, dy: inset)
        if fillsItsSquare {
            Ink.hex(Opal.cardBottom).setFill()
            square.fill()
        }
        Opal.drawTile(in: tile, light: .hue(hue), rimShare: rimShare)
        drawCat(on: tile, in: context.cgContext, cell: side <= 32 ? side / CatArt.grid : max(1, Int((tile.height * catGridShare / CGFloat(CatArt.grid)).rounded())))
        return picture
    }

    static func save(to folder: URL) throws {
        let files = FileManager.default
        let iconset = files.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset", isDirectory: true)
        try files.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: iconset) }
        for points in [16, 32, 128, 256, 512] {
            for (scale, suffix) in [(1, ""), (2, "@2x")] {
                try picture(side: points * scale).representation(using: .png, properties: [:])?.write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
            }
        }
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        let iconutil = Process()
        iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        iconutil.arguments = ["-c", "icns", iconset.path, "-o", folder.appendingPathComponent("AppIcon.icns").path]
        try iconutil.run()
        iconutil.waitUntilExit()
        guard iconutil.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
    }

    private static func drawCat(on tile: NSRect, in context: CGContext, cell: Int) {
        let grid = CGFloat(CatArt.grid * cell)
        let spot = CGRect(x: (tile.midX - grid / 2).rounded(.down), y: (tile.midY - grid / 2).rounded(.down), width: grid, height: grid)
        let cat = CatRenderer.uncached(for: CatPose(frame: .sit), theme: .rimlight)
        let light = Ink.hex(Opal.Light.hue(hue).rim)
        let top = tile.maxY, bottom = tile.maxY - tile.height * wash[wash.count - 1].downTheTile
        let reach = wash[wash.count - 1].downTheTile - wash[0].downTheTile
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: wash.map { light.withAlphaComponent($0.alpha).cgColor } as CFArray,
            locations: wash.map { ($0.downTheTile - wash[0].downTheTile) / reach }
        ) else { return }
        context.saveGState()
        context.interpolationQuality = .none
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.draw(cat, in: spot)
        context.setBlendMode(.sourceAtop)
        context.drawLinearGradient(gradient, start: CGPoint(x: tile.midX, y: top - tile.height * wash[0].downTheTile), end: CGPoint(x: tile.midX, y: bottom), options: [.drawsAfterEndLocation])
        context.endTransparencyLayer()
        context.restoreGState()
    }
}
