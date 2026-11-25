import AppKit

public struct RegionLook {
    public var dim: NSColor
    public var halo: NSColor
    public var edge: NSColor
    public var pillFill: NSColor
    public var pillEdge: NSColor
    public var pillWords: NSColor
    public var hintFont: NSFont
    public var sizeFont: NSFont

    public init(dim: NSColor, halo: NSColor, edge: NSColor, pillFill: NSColor, pillEdge: NSColor, pillWords: NSColor, hintFont: NSFont, sizeFont: NSFont) {
        self.dim = dim
        self.halo = halo
        self.edge = edge
        self.pillFill = pillFill
        self.pillEdge = pillEdge
        self.pillWords = pillWords
        self.hintFont = hintFont
        self.sizeFont = sizeFont
    }
}
