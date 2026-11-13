import AppKit
import ShadesCore

/// Takes clicks in a window that isn't key, and never takes the keyboard.
class QuietView: NSView {
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { false }
}

final class QuietScrollView: NSScrollView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        drawsBackground = false
        verticalScroller = QuietScroller()
        hasVerticalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        borderType = .noBorder
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

/// Dragging it doesn't take the keyboard from the app you're in.
final class QuietScroller: NSScroller {
    override var acceptsFirstResponder: Bool { false }
    override var needsPanelToBecomeKey: Bool { false }
}

/// The pixel cat, with no smoothing, in anyone's jacket.
@MainActor
enum CatStamp {
    private static let renderer = CatRenderer()

    static func draw(_ pose: CatPose, jacket: UInt32?, in rect: NSRect, on view: NSView, fraction: CGFloat = 1) {
        let theme: CatTheme = view.effectiveAppearance.isDark ? .dark : .light
        let cgImage = renderer.image(for: pose, theme: theme, jacket: jacket)
        NSImage(cgImage: cgImage, size: rect.size).draw(
            in: rect,
            from: .zero,
            operation: .sourceOver,
            fraction: fraction,
            respectFlipped: true,
            hints: [.interpolation: NSNumber(value: NSImageInterpolation.none.rawValue)]
        )
    }

    /// The same cat as a PNG for the phone, each art pixel `scale` pixels square, so it scales up crisply there.
    @MainActor
    static func png(_ pose: CatPose, jacket: UInt32?, dark: Bool, scale: Int) -> Data? {
        let art = CatRenderer.uncached(for: pose, theme: dark ? .dark : .light, jacket: jacket)
        let side = art.width * scale
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .none
        context.draw(art, in: CGRect(x: 0, y: 0, width: side, height: side))
        return context.makeImage().flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) }
    }
}

/// Your picture as a circle, cropped to fill it, with a hairline so a pale photo keeps its edge on a pale window.
@MainActor
enum PictureStamp {
    static func draw(_ picture: NSImage, in rect: NSRect) {
        let side = min(picture.size.width, picture.size.height)
        let middle = NSRect(x: (picture.size.width - side) / 2, y: (picture.size.height - side) / 2, width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: rect).addClip()
        picture.draw(in: rect, from: middle, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)])
        NSGraphicsContext.restoreGraphicsState()
        let edge = NSBezierPath(ovalIn: rect.insetBy(dx: 0.25, dy: 0.25))
        edge.lineWidth = 0.5
        MessagesInk.line.setStroke()
        edge.stroke()
    }
}

/// The same colours as the kitten view. An idle kitten has no dot, which keeps the sidebar calm.
extension KittenStatus.State {
    var dotColor: NSColor? { dot.map(Ink.hex) }

    /// As 0xRRGGBB, which a phone is sent.
    var dot: UInt32? {
        switch self {
        case .working: return CatGlint.thinking(bright: true).color
        case .needsYou: return CatGlint.attention(bright: true).color
        case .idle, .notSetUp: return nil
        }
    }
}

struct ChannelSpeakerLook {
    static let otherJacket: UInt32 = 0x8f8f95
    /// Yours, as in iMessage, a shade deeper so white words on it read well.
    static let yours: UInt32 = 0x0071e3
    /// For a kitten with no colour of its own. Blue is left for you.
    static let palette: [UInt32] = [0x34c759, 0xff9500, 0xaf52de, 0xff2d55, 0x30b0c7, 0xa2845e, 0x5856d6, 0xffcc00]

    var name: String
    var hasCat: Bool
    var isYou: Bool
    /// Yours, where a kitten's cat goes, if you've given it one.
    var picture: NSImage?
    var jacket: UInt32?
    /// `nil` is the grey that the cat and anyone unknown get.
    var bubble: UInt32?
    /// The words on `bubble`. `nil` is the window's own text colour.
    var words: UInt32?

    init(_ speaker: Speaker, in book: ChannelBook) {
        name = book.name(of: speaker)
        isYou = speaker == .you
        hasCat = !isYou
        picture = isYou ? MessagesInk.pictureImage : nil
        let own = book.status(of: speaker).flatMap { Self.color(of: $0.kitten) }
        jacket = own ?? (speaker == .someoneElse ? Self.otherJacket : nil)
        // A theme tints your bubbles, and never a kitten's, so each kitten still looks like itself.
        if isYou, let theme = MessagesInk.theme {
            bubble = theme.yours
            words = theme.words(on: theme.yours)
        } else {
            bubble = isYou ? Self.yours : own
            words = bubble.map { Self.blackOrWhite(on: $0) }
        }
    }

    /// Its colour from kitten.json, or one picked from its folder so it's the same every time. The cat keeps its black jacket.
    static func color(of kitten: Kitten) -> UInt32? {
        if let color = kitten.color { return color }
        guard kitten != KittenBoard.shades else { return nil }
        let seed = kitten.id.unicodeScalars.reduce(UInt32(0)) { $0 &* 31 &+ $1.value }
        return palette[Int(seed % UInt32(palette.count))]
    }

    static var grey: NSColor {
        if let theme = MessagesInk.theme { return Ink.hex(theme.bubble) }
        return NSColor(name: nil) { $0.isDark ? Ink.hex(0x3a3a3c) : Ink.hex(0xe9e9eb) }
    }

    var bubbleFill: NSColor { bubble.map(Ink.hex) ?? Self.grey }

    /// Where a kitten's cat goes, when you have no picture. A theme's tint for your messages can be too close to its
    /// window to see, so then it gets an edge, at the 3:1 a shape needs.
    static func drawYourSquare(in rect: NSRect, radius: CGFloat) {
        Ink.hex(MessagesInk.theme?.yours ?? yours).setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        guard let theme = MessagesInk.theme, ColorTheme.contrast(theme.yours, theme.paper) < 3 else { return }
        MessagesInk.link.setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius - 0.5, yRadius: radius - 0.5).stroke()
    }

    /// Whichever reads better on the bubble.
    var bubbleText: NSColor {
        guard let bubble else { return MessagesInk.text }
        if isYou, let theme = MessagesInk.theme { return Ink.hex(theme.words(on: bubble)) }
        return Self.readable(on: bubble)
    }

    /// A reply that's still coming is paler. It's worked out as one solid colour for light and dark, so its words can
    /// be picked to read on it too.
    func fill(fadedTo alpha: Double) -> NSColor {
        let bubble = bubble
        let theme = MessagesInk.theme
        return NSColor(name: nil) { Ink.hex(Self.faded(bubble, to: alpha, dark: $0.isDark, theme: theme)) }
    }

    func text(fadedTo alpha: Double) -> NSColor {
        guard let bubble else { return MessagesInk.text }
        let theme = MessagesInk.theme
        return NSColor(name: nil) { Self.readable(on: Self.faded(bubble, to: alpha, dark: $0.isDark, theme: theme)) }
    }

    /// The colour over the window at `alpha`. `nil` is the grey.
    static func faded(_ bubble: UInt32?, to alpha: Double, dark: Bool, theme: ColorTheme?) -> UInt32 {
        let top = bubble ?? theme?.bubble ?? (dark ? 0x3a3a3c : 0xe9e9eb)
        let under: UInt32 = theme?.paper ?? (dark ? 0x1d1d1f : 0xf9f9f9)
        return ColorTheme.mix(under, top, alpha)
    }

    /// Whichever of black and white has more contrast with it.
    static func readable(on color: UInt32) -> NSColor {
        blackOrWhite(on: color) == 0x000000 ? .black : .white
    }

    static func blackOrWhite(on color: UInt32) -> UInt32 {
        contrast(color, 0x000000) >= contrast(color, 0xffffff) ? 0x000000 : 0xffffff
    }

    /// As WCAG measures it, from 1 to 21.
    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        ColorTheme.contrast(a, b)
    }

    static func luminance(_ color: UInt32) -> Double {
        ColorTheme.luminance(color)
    }
}

/// One row of the pane. It lays itself out at a width and says how tall that makes it.
class ChannelRowView: QuietView {
    static let textLeft: CGFloat = 64
    static let catLeft: CGFloat = 20
    static let margin: CGFloat = 20

    var hovering = false { didSet { if hovering != oldValue { hoverChanged() } } }
    /// Held down on a row that does something when pressed, so it shows before you let go.
    private(set) var isPressed = false { didSet { if isPressed != oldValue { needsDisplay = true } } }
    /// Hover's fill, or press's while it's held.
    var highlight: NSColor? { isPressed ? MessagesInk.press : hovering ? MessagesInk.hover : nil }

    func fit(width: CGFloat) -> CGFloat { 0 }
    /// Words that only get their views once the row is shown.
    var textBlocks: [ChannelTextBlock] { [] }
    func press() {}
    var isPressable: Bool { false }
    func hoverChanged() { needsDisplay = true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        // A refresh can put a new row under a pointer that hasn't moved.
        if let window { hovering = bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)) }
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        super.viewWillMove(toSuperview: newSuperview)
        if newSuperview != nil { textBlocks.forEach { $0.show(in: self) } }
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { isPressed = isPressable }
    override func mouseDragged(with event: NSEvent) { isPressed = isPressable && isOver(event) }
    override func mouseUp(with event: NSEvent) {
        isPressed = false
        if isPressable, isOver(event) { press() }
    }
    private func isOver(_ event: NSEvent) -> Bool { bounds.contains(convert(event.locationInWindow, from: nil)) }
    override func accessibilityPerformPress() -> Bool {
        guard isPressable else { return false }
        press()
        return true
    }
}

final class DayRowView: ChannelRowView {
    private let date: Date
    private let now: () -> Date

    init(date: Date, now: @escaping () -> Date) {
        self.date = date
        self.now = now
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(CatWords.day(date, now: now()))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func fit(width: CGFloat) -> CGFloat { 36 }

    override func draw(_ dirtyRect: NSRect) {
        let label = NSAttributedString(string: CatWords.day(date, now: now()), attributes: [
            .font: MessagesInk.font(ofSize: MessagesInk.meta, weight: .medium),
            .foregroundColor: MessagesInk.soft,
        ])
        let size = label.size()
        let middle = bounds.midY.rounded() + 0.5
        let gap: CGFloat = 10
        MessagesInk.line.setStroke()
        for (from, to) in [(Self.margin, bounds.midX - size.width / 2 - gap), (bounds.midX + size.width / 2 + gap, bounds.width - Self.margin)] {
            let line = NSBezierPath()
            line.move(to: NSPoint(x: from, y: middle))
            line.line(to: NSPoint(x: to, y: middle))
            line.stroke()
        }
        label.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
    }
}

/// The line over what's new to you, as Slack's red New line.
final class NewRowView: ChannelRowView {
    init(count: Int) {
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(CatWords.newMessages(count))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func fit(width: CGFloat) -> CGFloat { 24 }

    override func draw(_ dirtyRect: NSRect) {
        let label = NSAttributedString(string: CatWords.new, attributes: [
            .font: MessagesInk.font(ofSize: MessagesInk.meta, weight: .semibold),
            .foregroundColor: MessagesInk.badge,
        ])
        let size = label.size()
        let right = bounds.width - Self.margin
        let middle = bounds.midY.rounded() + 0.5
        MessagesInk.badge.setStroke()
        let line = NSBezierPath()
        line.move(to: NSPoint(x: Self.margin, y: middle))
        line.line(to: NSPoint(x: right - size.width - 8, y: middle))
        line.stroke()
        label.draw(at: NSPoint(x: right - size.width, y: bounds.midY - size.height / 2))
    }
}

/// What a thread's reply bar shows, as Slack draws it: who replied, how many replies, and when the last one was.
@MainActor
struct ReplyBar {
    enum Face {
        case cat(UInt32?)
        case you
    }

    static let height: CGFloat = 26
    private static let face: CGFloat = 16

    var count: Int
    var faces: [Face]
    var lastReply: Date?
    var isGoing: Bool
    var needsYou: Bool

    init(_ post: ThreadPost, in book: ChannelBook) {
        count = post.replies
        faces = post.repliers.prefix(4).map { speaker in
            speaker == .you ? .you : .cat(ChannelSpeakerLook(speaker, in: book).jacket)
        }
        lastReply = post.lastReply
        isGoing = post.isGoing
        needsYou = post.needsYou
    }

    var isEmpty: Bool { count == 0 && !isGoing && !needsYou }

    private func words(now: Date) -> (strong: String, soft: String) {
        var soft: [String] = []
        if count > 0, let lastReply { soft.append(CatWords.lastReply(lastReply, now: now)) }
        if isGoing { soft.append(CatWords.workingOnIt) }
        return (count > 0 ? CatWords.replies(count) : "", soft.joined(separator: "  ·  "))
    }

    func accessibilityWords(now: Date) -> String {
        let (strong, soft) = words(now: now)
        return [needsYou ? CatWords.needsYouLabel : nil, strong, soft].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// How wide it draws, so it can sit under yours on the right.
    func width(now: Date) -> CGFloat {
        let (strong, soft) = words(now: now)
        var width = CGFloat(faces.count) * (Self.face + 3) + 8
        if needsYou { width += ceil(Self.attributed(CatWords.needsYouLabel, color: MessagesInk.badge, bold: true).size().width) + 10 }
        if !strong.isEmpty { width += ceil(Self.attributed(strong, color: MessagesInk.link, bold: true).size().width) + 8 }
        if !soft.isEmpty { width += ceil(Self.attributed(soft, color: MessagesInk.soft, bold: false).size().width) }
        return width + 8
    }

    func draw(in rect: NSRect, on view: NSView, hovering: Bool, now: Date) {
        if hovering {
            MessagesInk.hover.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        }
        var x = rect.minX + 4
        let faceTop = rect.midY - Self.face / 2
        for face in faces {
            let frame = NSRect(x: x, y: faceTop, width: Self.face, height: Self.face)
            switch face {
            case .cat(let jacket):
                CatStamp.draw(CatPose(frame: .sit), jacket: jacket, in: frame, on: view)
            case .you:
                if let picture = MessagesInk.pictureImage { PictureStamp.draw(picture, in: frame); break }
                ChannelSpeakerLook.drawYourSquare(in: frame.insetBy(dx: 1, dy: 1), radius: 4)
            }
            x += Self.face + 3
        }
        if !faces.isEmpty { x += 5 }
        let (strong, soft) = words(now: now)
        for (text, color, bold) in [
            (needsYou ? CatWords.needsYouLabel : "", MessagesInk.badge, true),
            (strong, MessagesInk.link, true),
            (soft, MessagesInk.soft, false),
        ] where !text.isEmpty {
            let label = Self.attributed(text, color: color, bold: bold)
            let size = label.size()
            label.draw(at: NSPoint(x: x, y: rect.midY - size.height / 2))
            x += ceil(size.width) + 8
        }
    }

    private static func attributed(_ text: String, color: NSColor, bold: Bool) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: MessagesInk.font(ofSize: MessagesInk.meta + 1, weight: bold ? .semibold : .regular, tabular: true), .foregroundColor: color])
    }
}

/// A message's words, read from markdown and laid out once. Messages keeps them while it's open, so a message that's
/// shown again, scrolled back to or kept through a refresh isn't read and measured again.
final class MessageWords {
    let message: ChannelMessage
    /// The state of each pull request it was drawn with, since a chip shows it.
    let pulls: [String: String]
    let words: ChannelTextBlock?
    let failure: ChannelTextBlock?
    private let markup: Markup?
    /// The bubble, theme, text size and font its words are drawn for.
    private var paint: (bubble: UInt32?, theme: ColorTheme?, size: TextSize, font: String?)

    init(_ message: ChannelMessage, look: ChannelSpeakerLook, pulls: [String: String] = [:]) {
        self.message = message
        self.pulls = pulls
        paint = (look.bubble, MessagesInk.theme, MessagesInk.textSize, MessagesInk.fontFamily)
        let said = message.text ?? (message.isStillGoing ? CatWords.stillGoing : nil)
        markup = said.map { Markup($0, pulls: pulls) }
        words = markup.map { ChannelTextBlock(ChannelMarkdown.attributed($0, color: Self.color(of: message, look: look))) }
        failure = message.failure.map { ChannelTextBlock(ChannelMarkdown.attributed($0, color: MessagesInk.danger)) }
    }

    /// Draws the words for `look` as it is now, which a theme, text size or font can change.
    func paint(for look: ChannelSpeakerLook) {
        let now = (look.bubble, MessagesInk.theme, MessagesInk.textSize, MessagesInk.fontFamily)
        guard paint != now, let markup else { return }
        paint = now
        words?.restyle(ChannelMarkdown.attributed(markup, color: Self.color(of: message, look: look)))
        failure?.restyle(ChannelMarkdown.attributed(message.failure ?? "", color: MessagesInk.danger))
    }

    private static func color(of message: ChannelMessage, look: ChannelSpeakerLook) -> NSColor {
        message.isStillGoing || message.isSending ? look.text(fadedTo: MessageRowView.stillGoingAlpha) : look.bubbleText
    }
}

/// One message as a bubble: yours on the right in blue, everyone else's on the left in their own colour.
final class MessageRowView: ChannelRowView {
    /// About a screenful, which is all a long message shows until you press Show more.
    private static let clampedLines = 30
    private static let catSide: CGFloat = 28
    private static let pad: CGFloat = 5
    private static var headHeight: CGFloat { MessagesInk.meta + 7 }
    private static var contextHeight: CGFloat { MessagesInk.meta + 5 }
    private static let insetX: CGFloat = 12
    private static let insetY: CGFloat = 7
    /// Of the pane's width, so a long message still reads as a bubble.
    private static let widest: CGFloat = 0.7
    static let stillGoingAlpha = 0.55
    private static let pictureSide: CGFloat = 180
    /// Each of several pictures, cut square.
    private static let tileSide: CGFloat = 110
    private static let fileHeight: CGFloat = 36
    private static let fileGap: CGFloat = 4

    var onOpen: (() -> Void)?
    var onReply: (() -> Void)?
    var onCopy: ((String) -> Void)?
    var onShowMore: (() -> Void)?
    /// Sends your words again, under ones that went nowhere.
    var onTryAgain: (() -> Void)?
    /// Puts a reaction on it or takes it off, only on one T3 has. It's a mark, and says nothing to anyone.
    var onReact: ((Reaction) -> Void)?
    /// A web picture pressed, which only shows its address until you press Show.
    var onShowPicture: ((URL) -> Void)?
    /// Opens its thread: a parent, or a reply also sent to the channel.
    var onPress: (() -> Void)?
    /// Makes it, and everything after it in its thread, new to you again.
    var onMarkUnread: (() -> Void)?
    var isExpanded = false
    /// Under a thread's parent, what's been said since.
    var replyBar: ReplyBar? { didSet { fitted = nil } }
    /// Over a reply also sent to the channel, which thread it's in.
    var context: String? { didSet { fitted = nil } }
    /// The message Search found, picked out for a moment so your eye lands on it.
    private(set) var isFound = false { didSet { needsDisplay = true } }
    private var foundTimer: Timer?

    let message: ChannelMessage
    private let look: ChannelSpeakerLook
    private let words: ChannelTextBlock?
    private let failure: ChannelTextBlock?
    private var showMore: QuietButton?
    private var tryAgain: QuietButton?
    /// Made the first time you hover, since most messages never are.
    private var hoverButtons: (open: QuietButton, copy: QuietButton, reply: QuietButton, unread: QuietButton, react: QuietButton)?
    /// Your reactions, under what it said. Pressing one takes it off.
    private var reactionChips: [QuietButton] = []
    /// A Copy on each code block.
    private(set) var codeButtons: [QuietButton] = []
    private(set) var bubble = NSRect.zero
    /// The files and pictures that came with it, or that its words point at, under its words.
    private var fileFrames: [NSRect] = []
    private lazy var pictures: [NSImage?] = message.files.map { $0.thumbnail.flatMap(NSImage.init(data:)) }
    /// A web picture waiting on Show is a button of its own.
    private var webButtons: [Int: QuietButton] = [:]
    /// The web pictures it shows that are waiting on Show.
    var webPictures: [URL] { message.files.compactMap { $0.thumbnail == nil ? $0.source?.webAddress : nil } }
    private var failureTop: CGFloat = 0
    private var replyBarFrame = NSRect.zero
    private var headTop: CGFloat { context == nil ? Self.pad : Self.pad + Self.contextHeight }
    /// A row is laid out again each time the rows around it are, so it keeps its answer until something it depends on changes.
    private var fitted: (width: CGFloat, isExpanded: Bool, height: CGFloat)?

    init(message: ChannelMessage, look: ChannelSpeakerLook, words laidOut: MessageWords? = nil) {
        self.message = message
        self.look = look
        let laidOut = laidOut ?? MessageWords(message, look: look)
        words = laidOut.words
        failure = laidOut.failure
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // Worked out when VoiceOver asks, rather than for every row of a long conversation as it's laid out.
    override func accessibilityLabel() -> String? {
        let said = message.text ?? (message.isStillGoing ? CatWords.stillGoing : nil)
        let reactions = message.reactions?.map(\.emoji).joined(separator: " ")
        return ([context, look.name, time, said] + message.files.map { CatWords.attached($0.name) } + [message.failure, reactions.flatMap { $0.isEmpty ? nil : $0 }, replyBar?.accessibilityWords(now: Date())]).compactMap { $0 }.joined(separator: ", ")
    }

    override var isPressable: Bool { onPress != nil }
    override func press() { onPress?() }

    /// What you can do to it, which VoiceOver and a right-click both offer, in this order.
    private var actions: [(name: String, run: () -> Void)] {
        let all: [(name: String, run: (() -> Void)?)] = [
            (CatWords.threadTitle, onPress),
            ("Try again", onTryAgain),
            ("Reply", onReply),
            (CatWords.openInT3, onOpen),
            (CatWords.markUnread, onMarkUnread),
            ("Copy", message.text == nil ? nil : { [weak self] in self?.copyPressed() }),
            (CatWords.react, onReact == nil ? nil : { [weak self] in self?.showReactions() }),
        ]
        return all.compactMap { action in action.run.map { (action.name, $0) } }
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        actions.map { action in
            NSAccessibilityCustomAction(name: action.name) {
                action.run()
                return true
            }
        }
    }

    /// Everything the buttons over it do on hover, with React's marks as a menu inside it. A right-click menu opens
    /// without making The Kitty Litter the active app.
    override func menu(for event: NSEvent) -> NSMenu? {
        let actions = actions
        guard !actions.isEmpty else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        for action in actions {
            let item = NSMenuItem(title: action.name, action: #selector(chose(_:)), keyEquivalent: "")
            item.target = self
            if action.name == CatWords.react { item.submenu = reactionsMenu() }
            menu.addItem(item)
        }
        return menu
    }

    @objc private func chose(_ item: NSMenuItem) {
        actions.first { $0.name == item.title }?.run()
    }

    override var textBlocks: [ChannelTextBlock] { [words, failure].compactMap { $0 } }
    var isCut: Bool { words?.isCut ?? false }
    var isYours: Bool { look.isYou }
    var fill: NSColor { look.bubbleFill }

    func pressShowMore() { onShowMore?() }

    private var time: String { message.isSending ? CatWords.sending : message.at.formatted(date: .omitted, time: .shortened) }

    /// Where yours end on the right: at the margin, or short of your picture, as a kitten's start after its cat.
    private func end(in width: CGFloat) -> CGFloat {
        width - (look.picture == nil ? Self.margin : Self.textLeft)
    }

    private func copyPressed() {
        guard let text = message.text else { return }
        onCopy?(text)
        hoverButtons?.copy.flash("Copied")
    }

    override func hoverChanged() {
        if hovering, hoverButtons == nil {
            let buttons = (
                open: QuietButton("Open", style: .text) { [weak self] in self?.onOpen?() },
                copy: QuietButton("Copy", style: .text) { [weak self] in self?.copyPressed() },
                reply: QuietButton("Reply", style: .text) { [weak self] in self?.onReply?() },
                unread: QuietButton(CatWords.markUnread, style: .text) { [weak self] in self?.onMarkUnread?() },
                react: QuietButton(CatWords.react, style: .text) { [weak self] in self?.showReactions() }
            )
            [buttons.open, buttons.copy, buttons.reply, buttons.unread, buttons.react].forEach(addSubview)
            hoverButtons = buttons
        }
        hoverButtons?.copy.isHidden = !hovering || message.text == nil
        hoverButtons?.open.isHidden = !hovering || onOpen == nil
        hoverButtons?.reply.isHidden = !hovering || onReply == nil
        hoverButtons?.unread.isHidden = !hovering || onMarkUnread == nil
        hoverButtons?.react.isHidden = !hovering || onReact == nil
        placeHoverButtons(width: bounds.width)
        needsDisplay = true
    }

    /// Where the buttons showing on hover start, so the head can stop short of them.
    private var hoverLeft: CGFloat {
        guard let hoverButtons else { return bounds.width - Self.margin }
        return [hoverButtons.open, hoverButtons.copy, hoverButtons.reply, hoverButtons.unread, hoverButtons.react].filter { !$0.isHidden }.map(\.frame.minX).min() ?? bounds.width - Self.margin
    }

    /// A menu of the marks. A menu opens without making The Kitty Litter the active app.
    func showReactions() {
        guard onReact != nil, message.reactions != nil else { return }
        let anchor = hoverButtons.flatMap { $0.react.isHidden ? nil : $0.react.frame } ?? NSRect(x: bubble.minX, y: bubble.maxY, width: 0, height: 0)
        reactionsMenu().popUp(positioning: nil, at: NSPoint(x: anchor.minX, y: anchor.maxY), in: self)
    }

    /// The marks, with the ones it has ticked.
    private func reactionsMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for reaction in Reaction.allCases {
            let item = NSMenuItem(title: reaction.emoji, action: #selector(picked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = reaction.rawValue
            item.state = message.reactions?.contains(reaction) == true ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    @objc private func picked(_ item: NSMenuItem) {
        guard let reaction = (item.representedObject as? String).flatMap(Reaction.init(rawValue:)) else { return }
        onReact?(reaction)
    }

    /// At the top right of each code block, inside it. A block that a cut message stops before has none.
    private func placeCodeButtons() {
        guard let words else { return }
        let blocks = words.codeBlocks
        while codeButtons.count < blocks.count {
            let button = QuietButton("Copy", style: .text)
            addSubview(button)
            codeButtons.append(button)
        }
        for (index, button) in codeButtons.enumerated() {
            button.isHidden = index >= blocks.count
            guard index < blocks.count else { continue }
            let block = blocks[index]
            button.onPress = { [weak self, weak button] in
                self?.onCopy?(block.code)
                button?.flash("Copied")
            }
            button.frame.origin = NSPoint(x: bubble.minX + Self.insetX + block.frame.maxX - button.frame.width, y: bubble.minY + Self.insetY + block.frame.minY + (ChannelMarkdown.copyRoom - button.frame.height) / 2 + 1)
        }
    }

    private func placeHoverButtons(width: CGFloat) {
        guard let hoverButtons else { return }
        var right = width - Self.margin + 6
        for button in [hoverButtons.open, hoverButtons.copy, hoverButtons.reply, hoverButtons.unread, hoverButtons.react] where !button.isHidden {
            right -= button.frame.width
            button.frame.origin = NSPoint(x: right, y: headTop - Self.pad)
        }
    }

    override func fit(width: CGFloat) -> CGFloat {
        if let fitted, fitted.width == width, fitted.isExpanded == isExpanded { return fitted.height }
        let room = max(min(width * Self.widest, width - Self.textLeft - Self.margin) - Self.insetX * 2, 60)
        var bottom = headTop + Self.headHeight
        let right = end(in: width)
        if let words {
            words.fit(width: room, maxLines: isExpanded ? nil : Self.clampedLines)
            let size = NSSize(width: words.width + Self.insetX * 2, height: words.height + Self.insetY * 2)
            let left = look.isYou ? right - size.width : Self.textLeft
            bubble = NSRect(origin: NSPoint(x: left, y: bottom), size: size)
            words.place(at: NSPoint(x: bubble.minX + Self.insetX, y: bubble.minY + Self.insetY), in: self)
            bottom = bubble.maxY
        } else {
            bubble = NSRect(x: look.isYou ? right : Self.textLeft, y: bottom, width: 0, height: 0)
        }
        layOutFiles(top: bottom + (words == nil ? 0 : 4), room: room + Self.insetX * 2, right: right)
        if let lowest = fileFrames.map(\.maxY).max() { bottom = lowest }
        if let failure {
            failure.fit(width: room + Self.insetX * 2)
            failureTop = bottom + (words == nil ? 0 : 4)
            failure.place(at: NSPoint(x: look.isYou ? bubble.maxX - failure.width : bubble.minX, y: failureTop), in: self)
            bottom = failureTop + failure.height
        }
        if onTryAgain != nil {
            let tryAgain = tryAgain ?? QuietButton("Try again", style: .text) { [weak self] in self?.onTryAgain?() }
            if tryAgain.superview == nil { addSubview(tryAgain) }
            self.tryAgain = tryAgain
            tryAgain.frame.origin = NSPoint(x: look.isYou ? bubble.maxX - tryAgain.frame.width + 6 : bubble.minX - 6, y: bottom + 1)
            bottom += tryAgain.frame.height + 2
        }
        showMore?.isHidden = !isCut
        if isCut {
            let showMore = showMore ?? QuietButton("Show more", style: .text) { [weak self] in self?.onShowMore?() }
            if showMore.superview == nil { addSubview(showMore) }
            self.showMore = showMore
            showMore.frame.origin = NSPoint(x: look.isYou ? bubble.maxX - showMore.frame.width + 6 : bubble.minX - 6, y: bottom + 1)
            bottom += showMore.frame.height + 2
        }
        bottom = placeReactions(below: bottom, right: right)
        if let replyBar, !replyBar.isEmpty {
            let barWidth = min(replyBar.width(now: Date()), width - Self.textLeft - Self.margin)
            let left = look.isYou ? right - barWidth : Self.textLeft - 4
            replyBarFrame = NSRect(x: left, y: bottom + 3, width: barWidth, height: ReplyBar.height)
            bottom = replyBarFrame.maxY
        } else {
            replyBarFrame = .zero
        }
        placeHoverButtons(width: width)
        placeCodeButtons()
        let height = max(bottom + Self.pad, look.hasCat || look.picture != nil ? headTop + Self.pad + Self.headHeight + Self.catSide : 0)
        fitted = (width, isExpanded, height)
        return height
    }

    /// In a row under what it said, from the bubble's side.
    private func placeReactions(below top: CGFloat, right: CGFloat) -> CGFloat {
        let reactions = message.reactions ?? []
        guard !reactions.isEmpty else { return top }
        if reactionChips.isEmpty {
            reactionChips = reactions.map { reaction in
                let chip = QuietButton(reaction.emoji, style: .plain) { [weak self] in self?.onReact?(reaction) }
                chip.isArmed = onReact != nil
                addSubview(chip)
                return chip
            }
        }
        var x = look.isYou ? right - reactionChips.reduce(0) { $0 + $1.frame.width + 4 } + 4 : bubble.minX
        for chip in reactionChips {
            chip.frame.origin = NSPoint(x: x, y: top + 4)
            x += chip.frame.width + 4
        }
        return top + 4 + (reactionChips.first?.frame.height ?? 0)
    }

    /// Each reveal gets the whole time, however soon after the last one it comes.
    func flash() {
        isFound = true
        foundTimer?.invalidate()
        foundTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.isFound = false }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if isFound {
            MessagesInk.accent.withAlphaComponent(0.16).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 1), xRadius: 8, yRadius: 8).fill()
        }
        if isPressed {
            MessagesInk.press.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 1), xRadius: 8, yRadius: 8).fill()
        }
        if let context {
            // Over the bubble it's about: yours on the right, everyone else's on the left.
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            paragraph.alignment = look.isYou ? .right : .left
            NSAttributedString(string: context, attributes: [
                .font: MessagesInk.font(ofSize: MessagesInk.meta),
                .foregroundColor: hovering ? MessagesInk.text : MessagesInk.soft,
                .paragraphStyle: paragraph,
            ]).draw(in: NSRect(x: Self.textLeft + 2, y: Self.pad, width: max((look.isYou ? end(in: bounds.width) : bounds.width - Self.margin) - Self.textLeft - 2, 60), height: MessagesInk.meta + 4))
        }
        if let replyBar, replyBarFrame.width > 0 {
            replyBar.draw(in: replyBarFrame, on: self, hovering: hovering && onPress != nil, now: Date())
        }
        let top = max(headTop + Self.headHeight, bubble.maxY - Self.catSide)
        if look.hasCat {
            CatStamp.draw(CatPose(frame: .sit), jacket: look.jacket, in: NSRect(x: Self.catLeft, y: top, width: Self.catSide, height: Self.catSide), on: self)
        } else if let picture = look.picture {
            PictureStamp.draw(picture, in: NSRect(x: bounds.width - Self.catLeft - Self.catSide, y: top, width: Self.catSide, height: Self.catSide))
        }
        drawHead()
        if bubble.height > 0 {
            let radius = min(16, bubble.height / 2)
            (message.isStillGoing || message.isSending ? look.fill(fadedTo: Self.stillGoingAlpha) : fill).setFill()
            NSBezierPath(roundedRect: bubble, xRadius: radius, yRadius: radius).fill()
        }
        for (index, frame) in fileFrames.enumerated() where webButtons[index] == nil { drawFile(message.files[index], picture: pictures[index], in: frame) }
    }

    /// A file stays the size of the buttons beside it, whatever the text size.
    private static var fileFont: NSFont { MessagesInk.font(ofSize: 13) }

    private static func fileWidth(_ name: String) -> CGFloat {
        ceil(NSAttributedString(string: name, attributes: [.font: fileFont]).size().width) + 46
    }

    /// Left to right, onto as many lines as they need: one picture as itself, several as squares, and anything else
    /// as its name. A web picture waiting on Show is a button that asks first.
    private func layOutFiles(top: CGFloat, room: CGFloat, right: CGFloat) {
        let several = pictures.compactMap { $0 }.count > 1
        var lines: [[(index: Int, size: NSSize)]] = []
        var lineWidth: CGFloat = 0
        for (index, file) in message.files.enumerated() {
            var size = NSSize(width: min(Self.fileWidth(file.name), room), height: Self.fileHeight)
            if let picture = pictures[index], picture.size.width > 0, picture.size.height > 0 {
                let scale = min(Self.pictureSide / picture.size.width, Self.pictureSide / picture.size.height)
                size = several ? NSSize(width: Self.tileSide, height: Self.tileSide) : NSSize(width: floor(picture.size.width * scale), height: floor(picture.size.height * scale))
            } else if let link = file.source?.webAddress {
                let button = webButtons[index] ?? QuietButton(file.couldntShow ? "\(file.name) · \(CatWords.couldntShow)" : "🖼 \(CatWords.pictureFrom(link.host ?? ""))") { [weak self] in
                    self?.onShowPicture?(link)
                }
                if button.superview == nil { addSubview(button) }
                webButtons[index] = button
                size = NSSize(width: min(button.frame.width, room), height: button.frame.height)
            }
            if lines.isEmpty || lineWidth + Self.fileGap + size.width > room {
                lines.append([])
                lineWidth = -Self.fileGap
            }
            lines[lines.count - 1].append((index, size))
            lineWidth += Self.fileGap + size.width
        }
        fileFrames = Array(repeating: .zero, count: message.files.count)
        var y = top
        for line in lines {
            let width = line.map(\.size.width).reduce(0, +) + Self.fileGap * CGFloat(line.count - 1)
            var x = look.isYou ? right - width : Self.textLeft
            for (index, size) in line {
                fileFrames[index] = NSRect(x: x, y: y, width: size.width, height: size.height)
                webButtons[index]?.frame = fileFrames[index]
                x += size.width + Self.fileGap
            }
            y += (line.map(\.size.height).max() ?? 0) + Self.fileGap
        }
    }

    /// A picture as itself, cut square when it's one of several, and any other file as its mark and name.
    private func drawFile(_ file: ChannelFile, picture: NSImage?, in fileFrame: NSRect) {
        let shape = NSBezierPath(roundedRect: fileFrame, xRadius: 10, yRadius: 10)
        if let picture {
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            let size = picture.size
            let fill = max(fileFrame.width / max(size.width, 1), fileFrame.height / max(size.height, 1))
            let cut = NSSize(width: fileFrame.width / fill, height: fileFrame.height / fill)
            let from = NSRect(x: (size.width - cut.width) / 2, y: (size.height - cut.height) / 2, width: cut.width, height: cut.height)
            picture.draw(in: fileFrame, from: from, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
            return
        }
        MessagesInk.hover.setFill()
        shape.fill()
        MessagesInk.line.setStroke()
        shape.stroke()
        let mark = NSImage(systemSymbolName: file.source == nil ? "doc.fill" : "photo", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
        mark?.isTemplate = true
        if let mark {
            let tinted = NSImage(size: mark.size, flipped: false) { rect in
                mark.draw(in: rect)
                MessagesInk.soft.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: fileFrame.minX + 11, y: fileFrame.midY - mark.size.height / 2, width: mark.size.width, height: mark.size.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingMiddle
        NSAttributedString(string: file.name, attributes: [.font: Self.fileFont, .foregroundColor: MessagesInk.text, .paragraphStyle: truncating])
            .draw(in: NSRect(x: fileFrame.minX + 34, y: fileFrame.midY - 9, width: fileFrame.width - 42, height: 18))
    }

    /// Who said it and when, over the bubble. Yours only needs the time.
    private func drawHead() {
        let small = MessagesInk.font(ofSize: MessagesInk.meta)
        let timeLabel = NSAttributedString(string: time, attributes: [.font: small, .foregroundColor: MessagesInk.soft])
        let timeWidth = ceil(timeLabel.size().width)
        let baseline = headTop + 1
        guard !look.isYou else {
            if !hovering { timeLabel.draw(at: NSPoint(x: end(in: bounds.width) - timeWidth, y: baseline)) }
            return
        }
        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        // While the buttons show, it's only who said it, in the room they leave. A stub of a name says nothing the cat
        // beside it doesn't, so with room for less than a few letters it waits until they go.
        var head = look.name
        if !hovering {
            if message.earlierNotes > 0 { head += "  ·  \(CatWords.earlierNotes(message.earlierNotes))" }
            head += "  ·  \(time)"
        }
        let room = (hovering ? hoverLeft - 4 : bounds.width - Self.margin) - Self.textLeft - 2
        guard !hovering || room >= 40 else { return }
        NSAttributedString(string: head, attributes: [
            .font: MessagesInk.font(ofSize: MessagesInk.meta, weight: .medium),
            .foregroundColor: MessagesInk.soft,
            .paragraphStyle: truncating,
        ]).draw(in: NSRect(x: Self.textLeft + 2, y: baseline, width: max(room, 0), height: MessagesInk.meta + 4))
    }
}

/// The line in a thread's pane between its parent and its replies.
final class RepliesRowView: ChannelRowView {
    private let count: Int

    init(count: Int) {
        self.count = count
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(CatWords.replies(count))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func fit(width: CGFloat) -> CGFloat { 30 }

    override func draw(_ dirtyRect: NSRect) {
        let label = NSAttributedString(string: CatWords.replies(count), attributes: [
            .font: MessagesInk.font(ofSize: MessagesInk.meta, weight: .medium),
            .foregroundColor: MessagesInk.soft,
        ])
        let size = label.size()
        label.draw(at: NSPoint(x: Self.margin, y: bounds.midY - size.height / 2))
        MessagesInk.line.setFill()
        NSRect(x: Self.margin + ceil(size.width) + 10, y: bounds.midY.rounded(), width: max(bounds.width - Self.margin * 2 - size.width - 10, 0), height: 1).fill()
    }
}

/// One thread you're in, as Threads lists it: its channel, its parent, its latest reply and how many more there are.
/// Clicking it opens the thread beside the list.
final class ThreadDigestRowView: ChannelRowView {
    private static let catSide: CGFloat = 22
    private static let lines = 2

    var onPress: (() -> Void)?
    private let digest: ThreadDigest
    private let channel: String
    private let said: [(look: ChannelSpeakerLook, message: ChannelMessage)]
    private let now: () -> Date
    private var blocks: [(top: CGFloat, height: CGFloat)] = []

    init(digest: ThreadDigest, in book: ChannelBook, now: @escaping () -> Date) {
        self.digest = digest
        self.now = now
        channel = book.title(of: digest.channel)
        said = ([digest.parent] + [digest.latest].compactMap { $0 }).map { (ChannelSpeakerLook($0.speaker, in: book), $0) }
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        let words = said.map { "\($0.look.name): \($0.message.text ?? "")" }
        setAccessibilityLabel(([channel, digest.isUnread ? "unread" : nil] + words + [digest.more > 0 ? CatWords.moreReplies(digest.more) : nil]).compactMap { $0 }.joined(separator: ", "))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isPressable: Bool { true }
    override func press() { onPress?() }

    private static var textFont: NSFont { MessagesInk.font(ofSize: MessagesInk.body) }
    /// Who said each and when, over its words.
    private static var headHeight: CGFloat { MessagesInk.meta + 7 }

    private func text(_ message: ChannelMessage) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let words = (message.text ?? message.failure ?? CatWords.stillGoing).replacingOccurrences(of: "\n", with: " ")
        return NSAttributedString(string: words, attributes: [.font: Self.textFont, .foregroundColor: MessagesInk.text, .paragraphStyle: paragraph])
    }

    override func fit(width: CGFloat) -> CGFloat {
        let room = max(width - Self.textLeft - Self.margin, 60)
        let most = ceil(Self.textFont.boundingRectForFont.height) * CGFloat(Self.lines)
        var y = MessagesInk.meta + 21
        blocks = said.map { _, message in
            let measured = text(message).boundingRect(with: NSSize(width: room, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin]).height
            let height = min(ceil(measured), most)
            defer { y += Self.headHeight + height + 8 }
            return (y + Self.headHeight, height)
        }
        if digest.more > 0 { y += Self.headHeight }
        return y + 8
    }

    override func draw(_ dirtyRect: NSRect) {
        if let highlight {
            highlight.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 2), xRadius: 8, yRadius: 8).fill()
        }
        MessagesInk.line.setFill()
        NSRect(x: Self.margin, y: bounds.height - 1, width: bounds.width - Self.margin * 2, height: 1).fill()

        var x = Self.catLeft
        let name = NSAttributedString(string: channel, attributes: [
            .font: MessagesInk.font(ofSize: MessagesInk.meta + 1, weight: digest.isUnread ? .bold : .semibold),
            .foregroundColor: MessagesInk.text,
        ])
        if digest.isUnread {
            MessagesInk.badge.setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: 10 + (name.size().height - 7) / 2, width: 7, height: 7)).fill()
            x += 13
        }
        name.draw(at: NSPoint(x: x, y: 10))

        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        let room = max(bounds.width - Self.textLeft - Self.margin, 60)
        for ((look, message), block) in zip(said, blocks) {
            let cat = NSRect(x: Self.catLeft + 8, y: block.top - 16, width: Self.catSide, height: Self.catSide)
            if look.hasCat {
                CatStamp.draw(CatPose(frame: .sit), jacket: look.jacket, in: cat, on: self)
            } else if let picture = look.picture {
                PictureStamp.draw(picture, in: cat.insetBy(dx: 1, dy: 1))
            } else {
                ChannelSpeakerLook.drawYourSquare(in: cat.insetBy(dx: 3, dy: 3), radius: 5)
            }
            let head = NSMutableAttributedString(string: look.name, attributes: [.font: MessagesInk.font(ofSize: MessagesInk.meta + 1, weight: .semibold), .foregroundColor: MessagesInk.text])
            head.append(NSAttributedString(string: "  \(message.at.formatted(date: .omitted, time: .shortened))", attributes: [.font: MessagesInk.font(ofSize: MessagesInk.meta), .foregroundColor: MessagesInk.soft]))
            head.addAttribute(.paragraphStyle, value: truncating, range: NSRange(location: 0, length: head.length))
            head.draw(in: NSRect(x: Self.textLeft, y: block.top - Self.headHeight + 1, width: room, height: Self.headHeight - 2))
            text(message).draw(with: NSRect(x: Self.textLeft, y: block.top, width: room, height: block.height), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
        if digest.more > 0, let last = blocks.last {
            NSAttributedString(string: CatWords.moreReplies(digest.more), attributes: [
                .font: MessagesInk.font(ofSize: MessagesInk.meta + 1, weight: .semibold, tabular: true),
                .foregroundColor: MessagesInk.link,
            ]).draw(at: NSPoint(x: Self.textLeft, y: last.top + last.height + 6))
        }
    }
}

final class HeadingRowView: ChannelRowView {
    private let status: KittenStatus

    init(status: KittenStatus) {
        self.status = status
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("\(status.kitten.name), \(status.kitten.role), \(CatWords.kittenState(status.state))")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private static var subTop: CGFloat { 14 + MessagesInk.body + 5 }

    override func fit(width: CGFloat) -> CGFloat { Self.subTop + MessagesInk.meta + 9 }

    override func draw(_ dirtyRect: NSRect) {
        CatStamp.draw(status.pose(tick: 0), jacket: ChannelSpeakerLook.color(of: status.kitten), in: NSRect(x: Self.catLeft, y: 14, width: 32, height: 32), on: self)
        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        let width = bounds.width - Self.textLeft - Self.margin
        NSAttributedString(string: status.kitten.name, attributes: [
            .font: MessagesInk.font(ofSize: MessagesInk.body, weight: .semibold),
            .foregroundColor: MessagesInk.text,
            .paragraphStyle: truncating,
        ]).draw(in: NSRect(x: Self.textLeft, y: 14, width: width, height: MessagesInk.body + 4))
        NSAttributedString(string: "\(status.kitten.role) · \(CatWords.kittenState(status.state))", attributes: [
            .font: MessagesInk.font(ofSize: MessagesInk.meta),
            .foregroundColor: MessagesInk.soft,
            .paragraphStyle: truncating,
        ]).draw(in: NSRect(x: Self.textLeft, y: Self.subTop, width: width, height: MessagesInk.meta + 3))
    }
}

/// One thing a kitten is on. It only needs a title, a status and something to open.
final class IssueRowView: ChannelRowView {
    private static let gap: CGFloat = 14

    var onPress: (() -> Void)?
    private let thread: AgentThread
    private let now: () -> Date

    init(thread: AgentThread, now: @escaping () -> Date) {
        self.thread = thread
        self.now = now
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("\(thread.title), \(CatWords.status(thread))")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isPressable: Bool { true }
    override func press() { onPress?() }
    override func fit(width: CGFloat) -> CGFloat { MessagesInk.body + 17 }

    override func draw(_ dirtyRect: NSRect) {
        let left = Self.textLeft
        if let highlight {
            highlight.setFill()
            NSBezierPath(roundedRect: NSRect(x: left - 8, y: 1, width: bounds.width - left - Self.margin + 16, height: bounds.height - 2), xRadius: 7, yRadius: 7).fill()
        }
        thread.dotColor.setFill()
        NSBezierPath(rect: NSRect(x: left, y: bounds.midY - 4, width: 8, height: 8)).fill()

        var edge = bounds.width - Self.margin
        let details = [CatWords.age(of: thread.updatedAt, now: now()), CatWords.status(thread), thread.pullRequest.map(CatWords.pullRequest)]
        for text in details.compactMap({ $0 }) {
            let label = NSAttributedString(string: text, attributes: [.font: MessagesInk.font(ofSize: MessagesInk.meta, tabular: true), .foregroundColor: MessagesInk.soft])
            let size = label.size()
            edge -= ceil(size.width)
            label.draw(at: NSPoint(x: edge, y: bounds.midY - size.height / 2))
            edge -= Self.gap
        }

        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        NSAttributedString(string: thread.title, attributes: [
            .font: MessagesInk.font(ofSize: MessagesInk.body),
            .foregroundColor: MessagesInk.text,
            .paragraphStyle: truncating,
        ]).draw(in: NSRect(x: left + 16, y: 6, width: max(edge - left - 16, 40), height: MessagesInk.body + 4))
    }
}

final class NoteRowView: ChannelRowView {
    private let block: ChannelTextBlock
    private let isCentered: Bool

    init(text: String, isCentered: Bool) {
        self.isCentered = isCentered
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = isCentered ? .center : .left
        block = ChannelTextBlock(NSAttributedString(string: text, attributes: [
            .font: MessagesInk.font(ofSize: MessagesInk.body),
            .foregroundColor: MessagesInk.soft,
            .paragraphStyle: paragraph,
        ]))
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(text)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private var left: CGFloat { isCentered ? Self.margin : Self.textLeft }
    override var textBlocks: [ChannelTextBlock] { [block] }

    override func fit(width: CGFloat) -> CGFloat {
        let height = block.fit(width: max(width - left - Self.margin, 60))
        block.place(at: NSPoint(x: left, y: 6), in: self)
        return height + 12
    }
}

/// The top of a channel with older posts. Scrolling back to it loads them, and so does pressing it.
final class OlderRowView: ChannelRowView {
    private let button: QuietButton

    init(isLoading: Bool, onPress: @escaping () -> Void) {
        button = QuietButton(isLoading ? CatWords.loadingOlder : CatWords.loadOlder, style: .text, onPress: onPress)
        button.isArmed = !isLoading
        super.init(frame: .zero)
        addSubview(button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func fit(width: CGFloat) -> CGFloat {
        button.frame.origin = NSPoint(x: ((width - button.frame.width) / 2).rounded(), y: 6)
        return button.frame.height + 12
    }
}

/// A heading in Needs you, with a way to clear a section of reports.
final class SectionRowView: ChannelRowView {
    private let title: String
    let clear: QuietButton?

    init(title: String, onClear: (() -> Void)?) {
        self.title = title
        clear = onClear.map { QuietButton("Clear", style: .text, onPress: $0) }
        super.init(frame: .zero)
        if let clear { addSubview(clear) }
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func fit(width: CGFloat) -> CGFloat {
        clear?.frame.origin = NSPoint(x: width - Self.margin - (clear?.frame.width ?? 0) + 6, y: 10)
        return 36
    }

    override func draw(_ dirtyRect: NSRect) {
        NSAttributedString(string: title.uppercased(), attributes: [
            .font: MessagesInk.font(ofSize: MessagesInk.meta - 1, weight: .semibold),
            .foregroundColor: MessagesInk.soft,
            .kern: 0.5,
        ]).draw(at: NSPoint(x: Self.catLeft, y: 16))
    }
}

/// Something waiting on you: an approval, a question or a report. The buttons only ever answer it as
/// asked or take you somewhere, and none of them is the one Return would press.
final class CardRowView: ChannelRowView {
    struct Button {
        var title: String
        /// Somewhere else to go rather than an answer, so it stays quiet.
        var isWayOut = false
        /// An option you can pick several of, and whether it's picked. `nil` for a button that just does something.
        var isPicked: Bool? = nil
        var isArmed = true
        var action: () -> Void
    }

    private static let catSide: CGFloat = 32
    private static let pad: CGFloat = 8
    private static var wordsTop: CGFloat { pad + MessagesInk.body + 7 }
    private static let buttonHeight: CGFloat = 26

    let buttons: [QuietButton]
    private let look: ChannelSpeakerLook
    private let heading: String
    private let at: Date?
    private let words: ChannelTextBlock
    private let answer: ChannelTextBlock?
    private let footer: String?
    private var answerTop: CGFloat = 0
    private var footerTop: CGFloat = 0

    init(look: ChannelSpeakerLook, heading: String, at: Date?, text: String, answer: String? = nil, footer: String? = nil, buttons: [Button]) {
        self.look = look
        self.heading = heading
        self.at = at
        words = ChannelTextBlock(ChannelMarkdown.attributed(text, color: MessagesInk.text))
        self.answer = answer.map { ChannelTextBlock(ChannelMarkdown.attributed($0, color: MessagesInk.text)) }
        self.footer = footer
        self.buttons = buttons.map { button in
            let view = QuietButton(button.title, style: button.isWayOut ? .text : button.isPicked == true ? .filled : .plain, onPress: button.action)
            view.isArmed = button.isArmed
            if let picked = button.isPicked {
                view.setAccessibilityRole(.checkBox)
                view.setAccessibilityValue(picked ? 1 : 0)
            }
            return view
        }
        super.init(frame: .zero)
        self.buttons.forEach(addSubview)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel([heading, text, answer, footer].compactMap { $0 }.joined(separator: ", "))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var textBlocks: [ChannelTextBlock] { [words, answer].compactMap { $0 } }

    override func fit(width: CGFloat) -> CGFloat {
        let room = max(width - Self.textLeft - Self.margin, 60)
        var bottom = Self.wordsTop + words.fit(width: room)
        words.place(at: NSPoint(x: Self.textLeft, y: Self.wordsTop), in: self)
        if let answer {
            answerTop = bottom + 6
            bottom = answerTop + answer.fit(width: room - 12)
            answer.place(at: NSPoint(x: Self.textLeft + 12, y: answerTop), in: self)
        }
        if footer != nil {
            footerTop = bottom + 2
            bottom = footerTop + MessagesInk.meta + 5
        }
        bottom += 8
        var x = Self.textLeft
        for button in buttons {
            if x > Self.textLeft, x + button.frame.width > width - Self.margin {
                x = Self.textLeft
                bottom += Self.buttonHeight + 4
            }
            button.frame.origin = NSPoint(x: x, y: bottom)
            x += button.frame.width + 6
        }
        if !buttons.isEmpty { bottom += Self.buttonHeight }
        return max(bottom + Self.pad + 4, Self.pad * 2 + Self.catSide)
    }

    override func draw(_ dirtyRect: NSRect) {
        let cat = NSRect(x: Self.catLeft, y: Self.pad + 1, width: Self.catSide, height: Self.catSide)
        CatStamp.draw(CatPose(frame: .sit, glint: .attention(bright: true)), jacket: look.jacket, in: cat, on: self)

        let left = Self.textLeft
        var right = bounds.width - Self.margin
        if let at {
            let time = NSAttributedString(string: CatWords.age(of: at, now: Date()), attributes: [.font: MessagesInk.font(ofSize: MessagesInk.meta, tabular: true), .foregroundColor: MessagesInk.soft])
            right -= ceil(time.size().width)
            time.draw(at: NSPoint(x: right, y: Self.pad + 2))
            right -= 8
        }
        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        NSAttributedString(string: heading, attributes: [
            .font: MessagesInk.font(ofSize: MessagesInk.body, weight: .semibold),
            .foregroundColor: MessagesInk.text,
            .paragraphStyle: truncating,
        ]).draw(in: NSRect(x: left, y: Self.pad, width: max(right - left, 40), height: MessagesInk.body + 5))

        if let answer {
            MessagesInk.line.setFill()
            NSRect(x: left, y: answerTop, width: 2, height: answer.height).fill()
        }
        if let footer {
            NSAttributedString(string: footer, attributes: [.font: MessagesInk.font(ofSize: MessagesInk.meta), .foregroundColor: MessagesInk.soft])
                .draw(at: NSPoint(x: left, y: footerTop))
        }
    }
}
