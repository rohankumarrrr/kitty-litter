#!/usr/bin/env swift
// Draws the app icon from the cat's sitting frame, every pixel crisp at every size.
//
//   swift scripts/make-icon.swift [output-folder] [background-hex]
//
// Writes AppIcon.icns, for the app, and cat.png, which is just the cat on nothing,
// for places like T3 Code's sidebar. The output is checked in under assets/.
//
// The tile is off-white because macOS's Tinted and Clear icon styles recolor plain icons
// by brightness. Colors wash out, but the cat's dark outline on a light tile survives.
import AppKit

let frame = [
    "................",
    "....k......k....",
    "...kwk....kwk...",
    "...kpwk..kwpk...",
    "...kwwkkkkwwk...",
    "...kwwwwwwwwk...",
    "...kssssssssk...",
    "...ksgswwsgsk...",
    "...kwwwppwwwk...",
    "....kwwwwwwk....",
    "....kjjzzjjk..k.",
    "...kjjjzzjjjkkwk",
    "...kjkjzzjkjkkwk",
    "...kwkjjjjkwkwk.",
    "....kkkkkkkkkk..",
    "................",
]
let lightPalette: [Character: UInt32] = [
    "k": 0x111113, "w": 0xfbfaf6, "j": 0x2a2a2e, "z": 0xc9ccd2, "s": 0x0a0a0b, "g": 0xffffff, "p": 0xff5fa2,
]
// On something dark the outline has to be the light thing, or there's no cat.
let darkPalette: [Character: UInt32] = [
    "k": 0x8f8f95, "w": 0xfbfaf6, "j": 0x232327, "z": 0xc9ccd2, "s": 0x0a0a0b, "g": 0xffffff, "p": 0xff5fa2,
]

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets", isDirectory: true)
let background = CommandLine.arguments.count > 2 ? UInt32(CommandLine.arguments[2], radix: 16)! : 0xfbfaf6
let tileIsDark = (background >> 16 & 0xff) + (background >> 8 & 0xff) + (background & 0xff) < 200
let palette = tileIsDark ? darkPalette : lightPalette

func color(_ hex: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat(hex >> 16 & 0xff) / 255,
        green: CGFloat(hex >> 8 & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: 1
    )
}

/// Where the cat's visible pixels are, so it's centered by what you see rather than by its grid.
let cells = frame.enumerated().flatMap { y, row in
    row.enumerated().compactMap { x, ch in palette[ch].map { (x, y, $0) } }
}
let left = cells.map(\.0).min()!, right = cells.map(\.0).max()!
let top = cells.map(\.1).min()!, bottom = cells.map(\.1).max()!
let catWidth = right - left + 1, catHeight = bottom - top + 1

func drawCat(scale: Int, centeredIn box: NSRect) {
    let originX = Int(box.midX) - catWidth * scale / 2
    let originY = Int(box.midY) - catHeight * scale / 2
    for (x, y, hex) in cells {
        color(hex).setFill()
        // AppKit counts up from the bottom, and the art counts down from the top.
        NSRect(
            x: originX + (x - left) * scale,
            y: originY + (bottom - y) * scale,
            width: scale,
            height: scale
        ).fill()
    }
}

func render(_ size: Int, _ draw: () -> Void) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

/// The tile follows Apple's icon grid: 824 of 1024, with room around it. At the smallest
/// sizes that would leave the cat under a pixel per square, so the tile fills the canvas.
func icon(_ size: Int) -> Data {
    render(size) {
        let inset = size <= 32 ? 0 : Int((CGFloat(size) * 100 / 1024).rounded())
        let tile = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
        color(background).setFill()
        NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225).fill()
        NSGraphicsContext.current?.shouldAntialias = false
        let wanted = tile.height * 0.72 / CGFloat(catHeight)
        let scale = size <= 32 ? size / 16 : max(1, Int(wanted.rounded()))
        drawCat(scale: scale, centeredIn: tile)
    }
}

let fm = FileManager.default
try fm.createDirectory(at: output, withIntermediateDirectories: true)
let iconset = fm.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset", isDirectory: true)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: iconset) }

for points in [16, 32, 128, 256, 512] {
    try icon(points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try icon(points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }

// Just the cat, large enough that a sidebar can scale it down cleanly.
let catOnly = render(256) {
    NSGraphicsContext.current?.shouldAntialias = false
    drawCat(scale: 16, centeredIn: NSRect(x: 0, y: 0, width: 256, height: 256))
}
try catOnly.write(to: output.appendingPathComponent("cat.png"))

print("Wrote \(output.path)")
