import AppKit

/// `opal <folder> [jacket...]` in the demo: every one of Opal's primitives on one sheet, drawn by the same helpers the
/// windows use, to `<folder>/opal.png`. Jackets given as hex, such as a kitten's colour from before, get a row of
/// cats of their own to set beside the palette's.
@MainActor
final class OpalSheet: NSView {
    static let width: CGFloat = 1180
    private let jackets: [UInt32]
    private var buttons: [(QuietButton, NSPoint, ring: Bool)] = []

    init(jackets: [UInt32]) {
        self.jackets = jackets
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: jackets.isEmpty ? 1010 : 1140))
        appearance = NSAppearance(named: .darkAqua)
        let disarmed = QuietButton("Send", style: .plain)
        disarmed.isArmed = false
        let listening = QuietButton.mic()
        listening.showListening(true)
        buttons = [
            (QuietButton("Allow", style: .filled), NSPoint(x: 40, y: 436), false),
            (QuietButton("Open in T3", style: .plain), NSPoint(x: 120, y: 436), false),
            (QuietButton("Copy", style: .text), NSPoint(x: 230, y: 436), false),
            (disarmed, NSPoint(x: 290, y: 436), false),
            (QuietButton("Focused", style: .plain), NSPoint(x: 370, y: 436), true),
            (listening, NSPoint(x: 466, y: 436), false),
        ]
        for (button, origin, ring) in buttons {
            button.frame.origin = origin
            addSubview(button)
            // The ring a button shows once Tab reaches it, which only a window with the keyboard draws on its own.
            if ring { addSubview(Ring(frame: button.frame)) }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    static func draw(to folder: String, jackets: [UInt32]) -> URL? {
        let url = URL(fileURLWithPath: folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let file = url.appendingPathComponent("opal.png")
        guard let png = ChannelImages.png(of: OpalSheet(jackets: jackets)), (try? png.write(to: file)) != nil else { return nil }
        return file
    }

    override func draw(_ dirtyRect: NSRect) {
        Ink.hex(Opal.page).setFill()
        bounds.fill()
        Opal.horizon(in: NSRect(x: 0, y: bounds.height - 120, width: bounds.width, height: 120))

        heading("Opal Horizon", "Every primitive, drawn by the helpers the windows use", y: 28)

        section("Cards", y: 92)
        card(NSRect(x: 40, y: 116, width: 260, height: 150), light: .shades, label: "Next up", rows: [("Pricing page review", "Now"), ("Pair a phone", "4:30")])
        figureCard(NSRect(x: 324, y: 116, width: 260, height: 150), light: .of(Opal.kittens[1]), label: "Sky", figure: "$42.10", fraction: 0.42)
        figureCard(NSRect(x: 608, y: 116, width: 260, height: 150), light: .of(Opal.kittens[4]), label: "Orchid", figure: "3 waiting", fraction: 0.8, over: true)
        figureCard(NSRect(x: 892, y: 116, width: 248, height: 150), light: .of(Opal.kittens[7]), label: "Sage", figure: "Done", fraction: 1)

        section("Rimlight tiles", y: 292)
        let names = ["Teal", "Sky", "Cornflower", "Indigo", "Orchid", "Plum", "Rosewood", "Sage"]
        for (index, color) in Opal.kittens.enumerated() {
            let tile = NSRect(x: 40 + CGFloat(index) * 84, y: 316, width: 64, height: 64)
            Opal.tile(in: tile, light: .of(color))
            CatStamp.draw(CatPose(frame: .sit), jacket: color, in: tile.insetBy(dx: 8, dy: 8), on: self)
            meta(names[index], centeredUnder: tile)
        }
        let symbols = ["bell", "bubble.left.and.bubble.right", "number", "gearshape", "moon"]
        for (index, symbol) in symbols.enumerated() {
            let tile = NSRect(x: 740 + CGFloat(index) * 84, y: 316, width: 64, height: 64)
            Opal.tile(in: tile, light: .drifting(index, of: symbols.count))
            glyph(symbol, in: tile)
            let hue: Int = 172 + (344 - 172) * index / (symbols.count - 1)
            meta("\(hue)°", centeredUnder: tile)
        }

        section("Controls", y: 412)
        Opal.field(in: NSRect(x: 540, y: 432, width: 280, height: 34), focused: false)
        words("Message #general", in: NSRect(x: 552, y: 441, width: 260, height: 18), color: MessagesInk.soft)
        Opal.field(in: NSRect(x: 844, y: 432, width: 296, height: 34), focused: true)
        words("Typing in a field", in: NSRect(x: 856, y: 441, width: 260, height: 18), color: MessagesInk.text)

        section("Meters and the rim", y: 492)
        Opal.meter(in: NSRect(x: 40, y: 516, width: 260, height: 12), fraction: 0.42, tick: 0.5)
        Opal.meter(in: NSRect(x: 324, y: 516, width: 260, height: 12), fraction: 0.8, over: true, tick: 0.6)
        Opal.rimLine(in: NSRect(x: 608, y: 521, width: 120, height: 2))
        words("Open tab", in: NSRect(x: 608, y: 500, width: 120, height: 18), color: MessagesInk.strong)
        Opal.rimLine(in: NSRect(x: 760, y: 522, width: 380, height: 1))

        section("Type", y: 552)
        var y: CGFloat = 576
        for (text, size, weight, color) in [
            ("Toolbar title 15", MessagesInk.toolbarTitle, NSFont.Weight.semibold, MessagesInk.strong),
            ("Title 14, a card's or a name", MessagesInk.title, .semibold, MessagesInk.strong),
            ("Body 13, what's said, in #E7E4EC", MessagesInk.body, .regular, MessagesInk.text),
            ("Meta 11, times and captions, in #A09AAD", MessagesInk.meta, .regular, MessagesInk.soft),
        ] {
            let line = NSAttributedString(string: text, attributes: [.font: MessagesInk.font(ofSize: size, weight: weight), .foregroundColor: color])
            line.draw(at: NSPoint(x: 40, y: y))
            y += line.size().height + 6
        }
        MessagesInk.label("Label 11, small capitals").draw(at: NSPoint(x: 40, y: y))
        NSAttributedString(string: "12:45", attributes: [.font: MessagesInk.font(ofSize: 32, weight: .light, tabular: true), .foregroundColor: MessagesInk.strong])
            .draw(at: NSPoint(x: 420, y: 576))
        meta("Figure 32, light, tabular", at: NSPoint(x: 420, y: 620))
        NSAttributedString(string: "Reply bar · 3 replies", attributes: [.font: MessagesInk.font(ofSize: MessagesInk.body, weight: .semibold), .foregroundColor: MessagesInk.link])
            .draw(at: NSPoint(x: 680, y: 580))
        NSAttributedString(string: "Couldn't send that", attributes: [.font: MessagesInk.font(ofSize: MessagesInk.body), .foregroundColor: MessagesInk.danger])
            .draw(at: NSPoint(x: 680, y: 604))

        section("Colour", y: 690)
        swatches([Opal.chrome, Opal.page, Opal.raised, Opal.control, Opal.controlHover, Opal.selected, Opal.border, Opal.fieldEdge], y: 714)
        swatches([Opal.white, Opal.body, Opal.secondary, Opal.dim, Opal.violet, Opal.primary, Opal.lilac, Opal.info, Opal.good, Opal.warning, Opal.error, Opal.rimCyan, Opal.rimViolet, Opal.rimPink], y: 764)

        section("Kittens as the cat", y: 822)
        cats(Opal.kittens, y: 846)
        if !jackets.isEmpty {
            section("Given jackets", y: 946)
            cats(jackets, y: 970)
        }
    }

    // MARK: - Pieces

    private func heading(_ title: String, _ line: String, y: CGFloat) {
        NSAttributedString(string: title, attributes: [.font: MessagesInk.font(ofSize: MessagesInk.toolbarTitle, weight: .semibold), .foregroundColor: MessagesInk.strong])
            .draw(at: NSPoint(x: 40, y: y))
        meta(line, at: NSPoint(x: 40, y: y + 22))
    }

    private func section(_ title: String, y: CGFloat) {
        MessagesInk.label(title).draw(at: NSPoint(x: 40, y: y))
    }

    private func card(_ rect: NSRect, light: Opal.Light, label: String, rows: [(String, String)]) {
        Opal.card(in: rect, radius: Opal.Corner.floatingCard, light: light)
        MessagesInk.label(label).draw(at: NSPoint(x: rect.minX + 18, y: rect.minY + 15))
        for (index, row) in rows.enumerated() {
            let y = rect.minY + 40 + CGFloat(index) * 27
            words(row.0, in: NSRect(x: rect.minX + 18, y: y, width: rect.width - 90, height: 18), color: index == 0 ? MessagesInk.strong : MessagesInk.text, weight: index == 0 ? .semibold : .regular)
            let time = NSAttributedString(string: row.1, attributes: [.font: MessagesInk.font(ofSize: 13, tabular: true), .foregroundColor: index == 0 ? MessagesInk.link : MessagesInk.soft])
            time.draw(at: NSPoint(x: rect.maxX - 18 - time.size().width, y: y))
        }
    }

    private func figureCard(_ rect: NSRect, light: Opal.Light, label: String, figure: String, fraction: CGFloat, over: Bool = false) {
        Opal.card(in: rect, radius: Opal.Corner.floatingCard, light: light)
        MessagesInk.label(label).draw(at: NSPoint(x: rect.minX + 18, y: rect.minY + 15))
        NSAttributedString(string: figure, attributes: [.font: MessagesInk.font(ofSize: 32, weight: .light, tabular: true), .foregroundColor: MessagesInk.strong])
            .draw(at: NSPoint(x: rect.minX + 18, y: rect.minY + 36))
        Opal.meter(in: NSRect(x: rect.minX + 18, y: rect.minY + 88, width: rect.width - 36, height: 10), fraction: fraction, over: over, tick: 0.6)
        meta("One short line under it", at: NSPoint(x: rect.minX + 18, y: rect.minY + 108))
    }

    private func glyph(_ symbol: String, in tile: NSRect) {
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 24, weight: .medium))
        else { return }
        let white = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            NSColor.white.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        white.draw(in: NSRect(x: tile.midX - image.size.width / 2, y: tile.midY - image.size.height / 2, width: image.size.width, height: image.size.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    private func swatches(_ colors: [UInt32], y: CGFloat) {
        for (index, color) in colors.enumerated() {
            let swatch = NSRect(x: 40 + CGFloat(index) * 78, y: y, width: 64, height: 26)
            Ink.hex(color).setFill()
            NSBezierPath(roundedRect: swatch, xRadius: 6, yRadius: 6).fill()
            NSColor(white: 1, alpha: 0.08).setStroke()
            NSBezierPath(roundedRect: swatch.insetBy(dx: 0.5, dy: 0.5), xRadius: 5.5, yRadius: 5.5).stroke()
            meta(Opal.hex(color).uppercased(), at: NSPoint(x: swatch.minX, y: swatch.maxY + 3))
        }
    }

    private func cats(_ colors: [UInt32], y: CGFloat) {
        for (index, color) in colors.enumerated() {
            let cat = NSRect(x: 40 + CGFloat(index) * 84, y: y, width: 64, height: 64)
            Ink.hex(Opal.chrome).setFill()
            NSBezierPath(roundedRect: cat.insetBy(dx: -4, dy: -4), xRadius: 9, yRadius: 9).fill()
            CatStamp.draw(CatPose(frame: .sit), jacket: color, in: cat, on: self)
            meta(Opal.hex(color).uppercased(), centeredUnder: cat)
        }
    }

    private func words(_ text: String, in rect: NSRect, color: NSColor, weight: NSFont.Weight = .regular) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        NSAttributedString(string: text, attributes: [.font: MessagesInk.font(ofSize: MessagesInk.body, weight: weight), .foregroundColor: color, .paragraphStyle: paragraph])
            .draw(in: rect)
    }

    private func meta(_ text: String, at point: NSPoint) {
        NSAttributedString(string: text, attributes: [.font: MessagesInk.font(ofSize: MessagesInk.meta), .foregroundColor: MessagesInk.soft]).draw(at: point)
    }

    private func meta(_ text: String, centeredUnder rect: NSRect) {
        let line = NSAttributedString(string: text, attributes: [.font: MessagesInk.font(ofSize: MessagesInk.meta), .foregroundColor: MessagesInk.soft])
        line.draw(at: NSPoint(x: rect.midX - line.size().width / 2, y: rect.maxY + 8))
    }
}

private final class Ring: NSView {
    override func draw(_ dirtyRect: NSRect) {
        QuietFocus.ring(bounds, radius: bounds.height / 2)
    }
}
