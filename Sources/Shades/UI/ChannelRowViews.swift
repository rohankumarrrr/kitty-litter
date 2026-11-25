import AppKit
import ShadesCore

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

final class QuietScroller: NSScroller {
    override var acceptsFirstResponder: Bool { false }
    override var needsPanelToBecomeKey: Bool { false }
}

@MainActor
enum CatStamp {
    private static let renderer = CatRenderer()

    static func image(_ pose: CatPose, jacket: UInt32?, on view: NSView) -> CGImage {
        renderer.image(for: pose, theme: view.effectiveAppearance.isDark ? .dark : .light, jacket: jacket)
    }

    static func draw(_ pose: CatPose, jacket: UInt32?, in rect: NSRect, on view: NSView, fraction: CGFloat = 1) {
        NSImage(cgImage: image(pose, jacket: jacket, on: view), size: rect.size).draw(
            in: rect,
            from: .zero,
            operation: .sourceOver,
            fraction: fraction,
            respectFlipped: true,
            hints: [.interpolation: NSNumber(value: NSImageInterpolation.none.rawValue)]
        )
    }

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

extension KittenStatus.State {
    var dotColor: NSColor? { dot.map(Ink.hex) }

    var dot: UInt32? {
        switch self {
        case .working: return CatGlint.thinking(bright: true).color
        case .needsYou: return CatGlint.attention(bright: true).color
        case .idle, .notSetUp: return nil
        }
    }
}

struct ChannelSpeakerLook {
    static let otherJacket = Opal.dim
    static let yours = Opal.selected
    static let palette = Opal.kittens

    var name: String
    var hasCat: Bool
    var isYou: Bool
    var picture: NSImage?
    var jacket: UInt32?
    var bubble: UInt32?
    var words: UInt32?
    var light: Opal.Light?

    init(_ speaker: Speaker, in book: ChannelBook) {
        name = book.name(of: speaker)
        isYou = speaker == .you
        hasCat = !isYou
        picture = isYou ? MessagesInk.pictureImage : nil
        let own = book.status(of: speaker).flatMap { Self.color(of: $0.kitten) }
        jacket = own ?? (speaker == .someoneElse ? Self.otherJacket : nil)
        bubble = isYou ? Self.yours : own
        words = isYou ? Opal.body : bubble.map { Self.blackOrWhite(on: $0) }
        light = own.map(Opal.Light.of) ?? (speaker == .cat ? .shades : nil)
    }

    static func color(of kitten: Kitten) -> UInt32? {
        if let color = kitten.color { return color }
        guard kitten != KittenBoard.shades else { return nil }
        let seed = kitten.id.unicodeScalars.reduce(UInt32(0)) { $0 &* 31 &+ $1.value }
        return palette[Int(seed % UInt32(palette.count))]
    }

    static let grey = Ink.hex(Opal.controlHover)

    var bubbleFill: NSColor { Ink.hex(body) }
    private var body: UInt32 { isYou ? Self.yours : light != nil ? Opal.cardTop : Opal.controlHover }

    static func drawYourSquare(in rect: NSRect, radius: CGFloat) {
        Ink.hex(yours).setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        guard Opal.contrast(yours, Opal.page) < 3 else { return }
        MessagesInk.link.setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius - 0.5, yRadius: radius - 0.5).stroke()
    }

    var bubbleText: NSColor { MessagesInk.text }

    func fill(fadedTo alpha: Double) -> NSColor {
        Ink.hex(Opal.mix(Opal.page, body, alpha))
    }

    func text(fadedTo alpha: Double) -> NSColor { MessagesInk.soft }

    static func faded(_ bubble: UInt32?, to alpha: Double) -> UInt32 {
        Opal.mix(Opal.page, bubble ?? Opal.controlHover, alpha)
    }

    static func blackOrWhite(on color: UInt32) -> UInt32 {
        contrast(color, Opal.black) >= contrast(color, Opal.white) ? Opal.black : Opal.white
    }

    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        Opal.contrast(a, b)
    }

    static func luminance(_ color: UInt32) -> Double {
        Opal.luminance(color)
    }
}

class ChannelRowView: QuietView, TabGate {
    static let textLeft: CGFloat = 64
    static let catLeft: CGFloat = 20
    static let margin: CGFloat = 20

    var hovering = false { didSet { if hovering != oldValue { hoverChanged() } } }
    var isCurrent = false { didSet { if isCurrent != oldValue { focusChanged() } } }
    var isFocused = false { didSet { if isFocused != oldValue { focusChanged() } } }
    var takesFocus: Bool { isPressable }
    var letsTabIn: Bool { isCurrent }
    func focusChanged() { needsDisplay = true }

    func drawFocus() {
        if showsRing { QuietFocus.ring(bounds.insetBy(dx: 8, dy: 1), radius: Opal.Corner.control) }
    }

    var showsRing: Bool { isFocused && window?.isKeyWindow == true }
    private(set) var isPressed = false { didSet { if isPressed != oldValue { needsDisplay = true } } }
    var highlight: NSColor? { isPressed ? MessagesInk.press : hovering ? MessagesInk.hover : nil }

    func fit(width: CGFloat) -> CGFloat { 0 }
    var textBlocks: [ChannelTextBlock] { [] }
    func press() {}
    var isPressable: Bool { false }
    func hoverChanged() { needsDisplay = true }

    var actions: [(name: String, run: () -> Void)] { [] }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        actions.map { action in
            NSAccessibilityCustomAction(name: action.name) {
                action.run()
                return true
            }
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? { actionsMenu() }

    func actionsMenu() -> NSMenu? {
        let actions = actions
        guard !actions.isEmpty else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        for action in actions {
            let item = NSMenuItem(title: action.name, action: #selector(choseAction(_:)), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    @objc private func choseAction(_ item: NSMenuItem) {
        actions.first { $0.name == item.title }?.run()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        // Outside the repo: AppKit sends no mouseEntered to a view that appears under a pointer that hasn't moved.
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
        MessagesInk.line.setFill()
        NSRect(x: Self.margin, y: bounds.midY.rounded(), width: max(bounds.width - Self.margin * 2, 0), height: 1).fill()
        let pill = NSRect(x: (bounds.midX - size.width / 2 - 10).rounded(), y: (bounds.midY - 11).rounded(), width: ceil(size.width) + 20, height: 22)
        let shape = NSBezierPath(roundedRect: pill.insetBy(dx: 0.5, dy: 0.5), xRadius: 10.5, yRadius: 10.5)
        MessagesInk.paper.setFill()
        shape.fill()
        MessagesInk.line.setStroke()
        shape.stroke()
        label.draw(at: NSPoint(x: pill.midX - size.width / 2, y: pill.midY - size.height / 2))
    }
}

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
            .foregroundColor: MessagesInk.strong,
        ])
        let size = label.size()
        let right = bounds.width - Self.margin
        Opal.rimLine(in: NSRect(x: Self.margin, y: bounds.midY.rounded(), width: max(right - size.width - 8 - Self.margin, 0), height: 1))
        label.draw(at: NSPoint(x: right - size.width, y: bounds.midY - size.height / 2))
    }
}

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
    var isUnread: Bool
    private static let unreadDot: CGFloat = 8

    init(_ post: ThreadPost, in book: ChannelBook) {
        count = post.replies
        faces = post.repliers.prefix(4).map { speaker in
            speaker == .you ? .you : .cat(ChannelSpeakerLook(speaker, in: book).jacket)
        }
        lastReply = post.lastReply
        isGoing = post.isGoing
        needsYou = post.needsYou
        isUnread = post.isUnread
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
        return [needsYou ? CatWords.needsYouLabel : nil, isUnread ? CatWords.unreadLabel : nil, strong, soft].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    func width(now: Date) -> CGFloat {
        let (strong, soft) = words(now: now)
        var width = CGFloat(faces.count) * (Self.face + 3) + 8
        if isUnread { width += Self.unreadDot + 6 }
        if needsYou { width += ceil(Self.attributed(CatWords.needsYouLabel, color: MessagesInk.badge, bold: true).size().width) + 10 }
        if !strong.isEmpty { width += ceil(Self.attributed(strong, color: MessagesInk.link, bold: true).size().width) + 8 }
        if !soft.isEmpty { width += ceil(Self.attributed(soft, color: MessagesInk.soft, bold: false).size().width) }
        return width + 8
    }

    func draw(in rect: NSRect, on view: NSView, hovering: Bool, now: Date) {
        if hovering {
            Ink.hex(Opal.controlHover).setFill()
            NSBezierPath(roundedRect: rect, xRadius: Opal.Corner.control, yRadius: Opal.Corner.control).fill()
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
        if isUnread {
            MessagesInk.accent.setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: (rect.midY - Self.unreadDot / 2).rounded(), width: Self.unreadDot, height: Self.unreadDot)).fill()
            x += Self.unreadDot + 6
        }
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

final class MessageWords {
    let message: ChannelMessage
    let pulls: [String: String]
    let words: ChannelTextBlock?
    let failure: ChannelTextBlock?
    private let markup: Markup?
    private var paint: (bubble: UInt32?, size: TextSize, font: String?)

    init(_ message: ChannelMessage, look: ChannelSpeakerLook, pulls: [String: String] = [:]) {
        self.message = message
        self.pulls = pulls
        paint = (look.bubble, MessagesInk.textSize, MessagesInk.fontFamily)
        let said = message.text ?? (message.isStillGoing ? CatWords.stillGoing : nil)
        markup = said.map { Markup($0, pulls: pulls) }
        words = markup.map { ChannelTextBlock(ChannelMarkdown.attributed($0, color: Self.color(of: message, look: look))) }
        failure = message.failure.map { ChannelTextBlock(ChannelMarkdown.attributed($0, color: MessagesInk.danger)) }
    }

    func paint(for look: ChannelSpeakerLook) {
        let now = (look.bubble, MessagesInk.textSize, MessagesInk.fontFamily)
        guard paint != now, let markup else { return }
        paint = now
        words?.restyle(ChannelMarkdown.attributed(markup, color: Self.color(of: message, look: look)))
        failure?.restyle(ChannelMarkdown.attributed(message.failure ?? "", color: MessagesInk.danger))
    }

    private static func color(of message: ChannelMessage, look: ChannelSpeakerLook) -> NSColor {
        message.isStillGoing || message.isSending ? look.text(fadedTo: MessageRowView.stillGoingAlpha) : look.bubbleText
    }
}

final class MessageToolbar: QuietView {
    static let side: CGFloat = 26
    private static let inset: CGFloat = 1
    static var height: CGFloat { side + inset * 2 }

    let buttons: [QuietButton]
    let more: QuietButton
    var onFocus: (() -> Void)?
    private var focus: NSKeyValueObservation?

    var isShowing = false { didSet { if isShowing != oldValue { showOrHide() } } }

    var hasFocus: Bool { (window?.firstResponder as? NSView)?.isDescendant(of: self) == true }

    init(_ actions: [(name: String, symbol: String, run: () -> Void)], more: @escaping () -> Void) {
        buttons = actions.map { Self.button($0.name, symbol: $0.symbol, onPress: $0.run) }
        self.more = Self.button("More", symbol: "ellipsis", onPress: more)
        super.init(frame: .zero)
        (buttons + [self.more]).forEach(addSubview)
        let lift = NSShadow()
        lift.shadowColor = Ink.hex(Opal.black).withAlphaComponent(Opal.shadowAlpha)
        lift.shadowBlurRadius = 8
        lift.shadowOffset = NSSize(width: 0, height: -2)
        wantsLayer = true
        shadow = lift
        showOrHide()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // Outside the repo: Tab skips a view that's isHidden, but not one that's see-through.
    private func showOrHide() {
        alphaValue = isShowing ? 1 : 0
        (buttons + [more]).forEach { $0.setAccessibilityElement(isShowing) }
    }

    static func button(_ name: String, symbol: String, style: QuietButton.Style = .text, onPress: (() -> Void)? = nil) -> QuietButton {
        let button = QuietButton(name, style: style, onPress: onPress)
        button.symbol = symbol
        button.toolTip = name
        button.setFrameSize(NSSize(width: side, height: side))
        return button
    }

    func button(_ name: String) -> QuietButton? { buttons.first { $0.accessibilityLabel() == name } }

    func fit(room: CGFloat) {
        let fits = Int((room - Self.inset * 2) / Self.side)
        let shown = fits >= buttons.count ? buttons.count : max(fits - 1, 0)
        more.isHidden = shown == buttons.count
        var x = Self.inset
        for (index, button) in buttons.enumerated() {
            button.isHidden = index >= shown
            guard !button.isHidden else { continue }
            button.frame.origin = NSPoint(x: x, y: Self.inset)
            x += Self.side
        }
        if !more.isHidden {
            more.frame.origin = NSPoint(x: x, y: Self.inset)
            x += Self.side
        }
        setFrameSize(NSSize(width: x + Self.inset, height: Self.height))
    }

    static func width(of count: Int) -> CGFloat { CGFloat(count) * side + inset * 2 }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focus = window?.observe(\.firstResponder) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.onFocus?() }
        }
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}

    override func draw(_ dirtyRect: NSRect) {
        Opal.glass(NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: Opal.Corner.control, yRadius: Opal.Corner.control))
    }
}

final class MessageRowView: ChannelRowView {
    private static let clampedLines = 30
    private static let catSide: CGFloat = 32
    private static let pad: CGFloat = 5
    private static var headHeight: CGFloat { MessagesInk.meta + 7 }
    private static var contextHeight: CGFloat { MessagesInk.meta + 5 }
    private static let insetX: CGFloat = 12
    private static let insetY: CGFloat = 7
    private static let widest: CGFloat = 0.7
    static let stillGoingAlpha = 0.55
    private static let pictureSide: CGFloat = 180
    private static let tileSide: CGFloat = 110
    private static let fileHeight: CGFloat = 36
    private static let fileGap: CGFloat = 4
    private static let toolbarGap: CGFloat = 8
    private static let chipHeight: CGFloat = 22

    var onOpen: (() -> Void)?
    var onReply: (() -> Void)?
    var onCopy: ((String) -> Void)?
    var onShowMore: (() -> Void)?
    var onTryAgain: (() -> Void)?
    var onReact: ((Reaction) -> Void)?
    var onShowPicture: ((URL) -> Void)?
    var onPress: (() -> Void)?
    var onMarkUnread: (() -> Void)?
    var onMarkRead: (() -> Void)?
    var isExpanded = false
    var replyBar: ReplyBar? { didSet { fitted = nil } }
    var context: String? { didSet { fitted = nil } }
    private(set) var isFound = false { didSet { needsDisplay = true } }
    private var foundTimer: Timer?

    let message: ChannelMessage
    private let look: ChannelSpeakerLook
    private let words: ChannelTextBlock?
    private let failure: ChannelTextBlock?
    private var showMore: QuietButton?
    private var tryAgain: QuietButton?
    private(set) var toolbar: MessageToolbar?
    private var reactionChips: [QuietButton] = []
    private var addReaction: QuietButton?
    private(set) var codeButtons: [QuietButton] = []
    private(set) var bubble = NSRect.zero
    private var fileFrames: [NSRect] = []
    private lazy var pictures: [NSImage?] = message.files.map { $0.thumbnail.flatMap(NSImage.init(data:)) }
    private var webButtons: [Int: QuietButton] = [:]
    var webPictures: [URL] { message.files.compactMap { $0.thumbnail == nil ? $0.source?.webAddress : nil } }
    private var failureTop: CGFloat = 0
    private var replyBarFrame = NSRect.zero
    private var notesFrame: NSRect?
    private var headTop: CGFloat { context == nil ? Self.pad : Self.pad + Self.contextHeight }
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

    override func accessibilityLabel() -> String? {
        let said = message.text ?? (message.isStillGoing ? CatWords.stillGoing : nil)
        let reactions = message.reactions?.map(\.emoji).joined(separator: " ")
        let notes = message.earlierNotes > 0 ? CatWords.earlierNotes(message.earlierNotes) : nil
        return ([context, look.name, notes, time, said] + message.files.map { CatWords.attached($0.name) } + [message.failure, reactions.flatMap { $0.isEmpty ? nil : $0 }, replyBar?.accessibilityWords(now: Date())]).compactMap { $0 }.joined(separator: ", ")
    }

    override var isPressable: Bool { onPress != nil }
    override func press() { onPress?() }
    override var takesFocus: Bool { true }

    override var actions: [(name: String, run: () -> Void)] {
        let all: [(name: String, run: (() -> Void)?)] = [
            (CatWords.threadTitle, onPress),
            ("Try again", onTryAgain),
            ("Reply", onReply),
            (CatWords.openInT3, onOpen),
            (CatWords.markRead, onMarkRead),
            (CatWords.markUnread, onMarkUnread),
            ("Copy", message.text == nil ? nil : { [weak self] in self?.copyPressed() }),
            (CatWords.react, onReact == nil ? nil : { [weak self] in self?.showReactions() }),
        ]
        return all.compactMap { action in action.run.map { (action.name, $0) } }
    }

    override func actionsMenu() -> NSMenu? {
        let menu = super.actionsMenu()
        menu?.item(withTitle: CatWords.react)?.submenu = reactionsMenu()
        return menu
    }

    override var textBlocks: [ChannelTextBlock] { [words, failure].compactMap { $0 } }
    var isCut: Bool { words?.isCut ?? false }
    var isYours: Bool { look.isYou }
    var fill: NSColor { look.bubbleFill }
    var light: Opal.Light? { look.light }

    func pressShowMore() { onShowMore?() }

    private var time: String { message.isSending ? CatWords.sending : message.at.formatted(date: .omitted, time: .shortened) }

    private func end(in width: CGFloat) -> CGFloat {
        width - (look.picture == nil ? Self.margin : Self.textLeft)
    }

    private func copyPressed() {
        guard let text = message.text else { return }
        onCopy?(text)
        toolbar?.button("Copy").map(Self.showCopied)
    }

    func copyMessage() -> Bool {
        guard message.text != nil else { return false }
        copyPressed()
        return true
    }

    private static func showCopied(_ button: QuietButton) {
        let symbol = button.symbol
        button.symbol = "checkmark"
        Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak button] _ in
            MainActor.assumeIsolated { button?.symbol = symbol }
        }
    }

    private var toolbarActions: [(name: String, symbol: String, run: () -> Void)] {
        let all: [(name: String, symbol: String, run: (() -> Void)?)] = [
            (CatWords.react, "face.smiling", onReact == nil ? nil : { [weak self] in self?.showReactions(from: self?.toolbar?.button(CatWords.react)) }),
            ("Reply", "text.bubble", onReply),
            ("Copy", "doc.on.doc", message.text == nil ? nil : { [weak self] in self?.copyPressed() }),
            (CatWords.markUnread, "envelope.badge", onMarkUnread),
            (CatWords.openInT3, "arrow.up.forward.app", onOpen),
        ]
        return all.compactMap { action in action.run.map { (action.name, action.symbol, $0) } }
    }

    override func hoverChanged() {
        if hovering { makeToolbar() }
        showToolbar()
        needsDisplay = true
    }

    override func focusChanged() {
        if isCurrent { makeToolbar() }
        showToolbar()
        needsDisplay = true
    }

    private func makeToolbar() {
        guard toolbar == nil else { return }
        let actions = toolbarActions
        guard !actions.isEmpty else { return }
        let toolbar = MessageToolbar(actions) { [weak self] in self?.pressMore() }
        toolbar.onFocus = { [weak self] in self?.showToolbar() }
        addSubview(toolbar)
        self.toolbar = toolbar
        placeToolbar(width: bounds.width)
    }

    private func showToolbar() {
        guard let toolbar else { return }
        let focused = toolbar.hasFocus || (window?.firstResponder as? NSView)?.isDescendant(of: self) == true
        if focused, !toolbar.isShowing { toolbar.scrollToVisible(toolbar.bounds) }
        toolbar.isShowing = hovering || showsRing || focused
    }

    private func pressMore() {
        guard let menu = actionsMenu(), let more = toolbar?.more else { return }
        let anchor = convert(more.bounds, from: more)
        menu.popUp(positioning: nil, at: NSPoint(x: anchor.minX, y: anchor.maxY), in: self)
    }

    func showReactions(from opener: NSView? = nil) {
        guard onReact != nil, message.reactions != nil else { return }
        let anchor = opener.map { convert($0.bounds, from: $0) } ?? NSRect(x: bubble.minX, y: bubble.maxY, width: 0, height: 0)
        reactionsMenu().popUp(positioning: nil, at: NSPoint(x: anchor.minX, y: anchor.maxY), in: self)
    }

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

    private func placeCodeButtons() {
        guard let words else { return }
        let blocks = words.codeBlocks
        while codeButtons.count < blocks.count {
            let button = MessageToolbar.button("Copy", symbol: "doc.on.doc")
            addSubview(button)
            codeButtons.append(button)
        }
        for (index, button) in codeButtons.enumerated() {
            button.isHidden = index >= blocks.count
            guard index < blocks.count else { continue }
            let block = blocks[index]
            button.onPress = { [weak self, weak button] in
                self?.onCopy?(block.code)
                button.map(Self.showCopied)
            }
            button.frame.origin = NSPoint(x: bubble.minX + Self.insetX + block.frame.maxX - button.frame.width, y: bubble.minY + Self.insetY + block.frame.minY + (ChannelMarkdown.copyRoom - button.frame.height) / 2 + 1)
        }
    }

    private func placeToolbar(width: CGFloat) {
        guard let toolbar else { return }
        let head = head(width: width).frame
        let (left, right) = look.isYou ? (Self.textLeft, head.minX - Self.toolbarGap) : (head.maxX + Self.toolbarGap, width - Self.margin)
        toolbar.fit(room: right - left)
        toolbar.frame.origin = NSPoint(x: right - toolbar.frame.width, y: max(headTop + Self.headHeight + Self.insetY - MessageToolbar.height, 0))
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
        placeToolbar(width: width)
        placeCodeButtons()
        placeNotes(width: width)
        let height = max(bottom + Self.pad, look.hasCat || look.picture != nil ? headTop + Self.pad + Self.headHeight + Self.catSide : 0)
        fitted = (width, isExpanded, height)
        return height
    }

    private func placeReactions(below top: CGFloat, right: CGFloat) -> CGFloat {
        let reactions = message.reactions ?? []
        guard !reactions.isEmpty else { return top }
        if reactionChips.isEmpty {
            reactionChips = reactions.map { reaction in
                let chip = QuietButton(reaction.emoji, style: .plain) { [weak self] in self?.onReact?(reaction) }
                chip.isArmed = onReact != nil
                chip.setFrameSize(NSSize(width: chip.frame.width - 4, height: Self.chipHeight))
                addSubview(chip)
                return chip
            }
            if onReact != nil {
                let add = MessageToolbar.button(CatWords.react, symbol: "face.smiling", style: .plain)
                add.setFrameSize(NSSize(width: reactionChips[0].frame.width, height: Self.chipHeight))
                add.onPress = { [weak self, weak add] in self?.showReactions(from: add) }
                addSubview(add)
                addReaction = add
            }
        }
        let chips = reactionChips + [addReaction].compactMap { $0 }
        var x = look.isYou ? right - chips.reduce(0) { $0 + $1.frame.width + 4 } + 4 : bubble.minX
        for chip in chips {
            chip.frame.origin = NSPoint(x: x, y: top + 4)
            x += chip.frame.width + 4
        }
        return top + 4 + (chips.first?.frame.height ?? 0)
    }

    func flash() {
        isFound = true
        foundTimer?.invalidate()
        foundTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.isFound = false }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let ground = isFound ? MessagesInk.accent.withAlphaComponent(0.16) : highlight
        if let ground {
            ground.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 1), xRadius: Opal.Corner.control, yRadius: Opal.Corner.control).fill()
        }
        if let context {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            paragraph.alignment = look.isYou ? .right : .left
            NSAttributedString(string: context, attributes: [
                .font: MessagesInk.font(ofSize: MessagesInk.meta),
                .foregroundColor: hovering && onPress != nil ? MessagesInk.text : MessagesInk.soft,
                .paragraphStyle: paragraph,
            ]).draw(in: NSRect(x: Self.textLeft + 2, y: Self.pad, width: max((look.isYou ? end(in: bounds.width) : bounds.width - Self.margin) - Self.textLeft - 2, 60), height: MessagesInk.meta + 4))
        }
        if let replyBar, replyBarFrame.width > 0 {
            replyBar.draw(in: replyBarFrame, on: self, hovering: hovering && onPress != nil, now: Date())
        }
        let top = max(headTop + Self.headHeight, bubble.maxY - Self.catSide)
        if look.hasCat {
            let cat = NSRect(x: Self.catLeft, y: top, width: Self.catSide, height: Self.catSide)
            if let light = look.light {
                Opal.tile(in: cat, light: light)
                CatStamp.draw(CatPose(frame: .sit), jacket: look.jacket, in: cat.insetBy(dx: 4, dy: 4), on: self)
            } else {
                CatStamp.draw(CatPose(frame: .sit), jacket: look.jacket, in: cat, on: self)
            }
        } else if let picture = look.picture {
            PictureStamp.draw(picture, in: NSRect(x: bounds.width - Self.catLeft - Self.catSide, y: top, width: Self.catSide, height: Self.catSide))
        }
        drawHead()
        if bubble.height > 0 { drawBubble() }
        for (index, frame) in fileFrames.enumerated() where webButtons[index] == nil { drawFile(message.files[index], picture: pictures[index], in: frame) }
        drawFocus()
    }

    private func drawBubble() {
        let radius = min(16, bubble.height / 2)
        let context = NSGraphicsContext.current?.cgContext
        let isFaded = message.isStillGoing || message.isSending
        if isFaded {
            context?.saveGState()
            context?.setAlpha(Self.stillGoingAlpha)
            context?.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        if let light = look.light {
            Opal.card(in: bubble, radius: radius, light: light)
        } else {
            fill.setFill()
            NSBezierPath(roundedRect: bubble, xRadius: radius, yRadius: radius).fill()
        }
        if isFaded {
            context?.endTransparencyLayer()
            context?.restoreGState()
        }
    }

    private static var fileFont: NSFont { MessagesInk.font(ofSize: MessagesInk.body) }

    private static func fileWidth(_ name: String) -> CGFloat {
        ceil(NSAttributedString(string: name, attributes: [.font: fileFont]).size().width) + 46
    }

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

    private func head(width: CGFloat) -> (label: NSAttributedString, frame: NSRect) {
        let top = headTop + 1
        let height = MessagesInk.meta + 4
        guard !look.isYou else {
            let label = NSAttributedString(string: time, attributes: [.font: MessagesInk.font(ofSize: MessagesInk.meta), .foregroundColor: MessagesInk.soft])
            let wide = ceil(label.size().width)
            return (label, NSRect(x: end(in: width) - wide, y: top, width: wide, height: height))
        }
        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        let font = MessagesInk.font(ofSize: MessagesInk.meta, weight: .medium)
        let after = NSMutableAttributedString()
        if message.earlierNotes > 0 {
            after.append(NSAttributedString(string: "  ·  ", attributes: [.font: font, .foregroundColor: MessagesInk.soft]))
            after.append(NSAttributedString(string: CatWords.earlierNotes(message.earlierNotes), attributes: [.font: font, .foregroundColor: onOpen == nil ? MessagesInk.soft : MessagesInk.link, .earlierNotes: true]))
        }
        after.append(NSAttributedString(string: "  ·  \(time)", attributes: [.font: font, .foregroundColor: MessagesInk.soft]))
        let room = width - Self.margin - MessageToolbar.width(of: 1) - Self.toolbarGap - Self.textLeft - 2
        let label = NSMutableAttributedString(string: look.name, attributes: [.font: font, .foregroundColor: MessagesInk.soft])
        label.append(after)
        var wide = ceil(label.size().width)
        if wide > room {
            let name = Self.shortened(look.name, to: room - ceil(after.size().width), font: font)
            label.replaceCharacters(in: NSRange(location: 0, length: (look.name as NSString).length), with: name)
            wide = ceil(label.size().width)
        }
        label.addAttribute(.paragraphStyle, value: truncating, range: NSRange(location: 0, length: label.length))
        return (label, NSRect(x: Self.textLeft + 2, y: top, width: max(min(wide, room), 0), height: height))
    }

    private static func shortened(_ name: String, to width: CGFloat, font: NSFont) -> String {
        let fits = { (words: String) in ceil(NSAttributedString(string: words, attributes: [.font: font]).size().width) <= width }
        var kept = name
        while kept.count > 1, !fits(kept + "…") { kept.removeLast() }
        return kept.trimmingCharacters(in: .whitespaces) + "…"
    }

    private func drawHead() {
        let (label, frame) = head(width: bounds.width)
        label.draw(in: frame)
    }

    private func placeNotes(width: CGFloat) {
        removeAllToolTips()
        notesFrame = nil
        guard message.earlierNotes > 0, onOpen != nil else { return }
        let (label, frame) = head(width: width)
        var found: NSRange?
        label.enumerateAttribute(.earlierNotes, in: NSRange(location: 0, length: label.length)) { value, range, _ in
            if value != nil { found = range }
        }
        guard let range = found else { return }
        let before = label.attributedSubstring(from: NSRange(location: 0, length: range.location)).size().width
        let notes = NSRect(x: frame.minX + before, y: frame.minY, width: label.attributedSubstring(from: range).size().width, height: frame.height)
        guard notes.maxX <= frame.maxX else { return }
        notesFrame = notes
        addToolTip(notes, owner: CatWords.seeEarlierNotes as NSString, userData: nil)
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if let notesFrame { addCursorRect(notesFrame, cursor: .pointingHand) }
    }

    private var pressingNotes = false

    private func isOnNotes(_ event: NSEvent) -> Bool {
        notesFrame?.contains(convert(event.locationInWindow, from: nil)) == true
    }

    override func mouseDown(with event: NSEvent) {
        pressingNotes = isOnNotes(event)
        if !pressingNotes { super.mouseDown(with: event) }
    }

    override func mouseDragged(with event: NSEvent) {
        if !pressingNotes { super.mouseDragged(with: event) }
    }

    override func mouseUp(with event: NSEvent) {
        guard pressingNotes else { return super.mouseUp(with: event) }
        pressingNotes = false
        if isOnNotes(event) { onOpen?() }
    }
}

private extension NSAttributedString.Key {
    static let earlierNotes = NSAttributedString.Key("ShadesEarlierNotes")
}

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

final class ThreadDigestRowView: ChannelRowView {
    private static let catSide: CGFloat = 22
    private static let lines = 2

    var onPress: (() -> Void)?
    var onMarkRead: (() -> Void)?
    var onMarkUnread: (() -> Void)?
    private let digest: ThreadDigest
    private let channel: String
    private let said: [(look: ChannelSpeakerLook, message: ChannelMessage)]
    private let now: () -> Date
    private var blocks: [(top: CGFloat, height: CGFloat)] = []

    init(digest: ThreadDigest, in book: ChannelBook, now: @escaping () -> Date) {
        self.digest = digest
        self.now = now
        channel = book.name(of: digest.channel)
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

    override var actions: [(name: String, run: () -> Void)] {
        let all: [(name: String, run: (() -> Void)?)] = [
            (CatWords.threadTitle, onPress),
            (CatWords.markRead, onMarkRead),
            (CatWords.markUnread, onMarkUnread),
        ]
        return all.compactMap { action in action.run.map { (action.name, $0) } }
    }

    private static var textFont: NSFont { MessagesInk.font(ofSize: MessagesInk.body) }
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
            NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 2), xRadius: Opal.Corner.control, yRadius: Opal.Corner.control).fill()
        }
        MessagesInk.line.setFill()
        NSRect(x: Self.margin, y: bounds.height - 1, width: bounds.width - Self.margin * 2, height: 1).fill()

        var x = Self.catLeft
        let name = NSAttributedString(string: channel, attributes: [
            .font: MessagesInk.font(ofSize: MessagesInk.meta + 1, weight: digest.isUnread ? .bold : .semibold),
            .foregroundColor: digest.isUnread ? MessagesInk.strong : MessagesInk.text,
        ])
        if digest.isUnread {
            MessagesInk.accent.setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: 10 + (name.size().height - 8) / 2, width: 8, height: 8)).fill()
            x += 14
        }
        name.draw(at: NSPoint(x: x, y: 10))

        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        let room = max(bounds.width - Self.textLeft - Self.margin, 60)
        for ((look, message), block) in zip(said, blocks) {
            let cat = NSRect(x: Self.catLeft + 8, y: block.top - 16, width: Self.catSide, height: Self.catSide)
            if look.hasCat, let light = look.light {
                Opal.tile(in: cat, light: light)
                CatStamp.draw(CatPose(frame: .sit), jacket: look.jacket, in: cat.insetBy(dx: 3, dy: 3), on: self)
            } else if look.hasCat {
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
        drawFocus()
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
        let color = ChannelSpeakerLook.color(of: status.kitten)
        let tile = NSRect(x: Self.catLeft, y: 14, width: 32, height: 32)
        Opal.tile(in: tile, light: color.map(Opal.Light.of) ?? .shades)
        CatStamp.draw(status.pose(tick: 0), jacket: color, in: tile.insetBy(dx: 4, dy: 4), on: self)
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
            NSBezierPath(roundedRect: NSRect(x: left - 8, y: 1, width: bounds.width - left - Self.margin + 16, height: bounds.height - 2), xRadius: Opal.Corner.control, yRadius: Opal.Corner.control).fill()
        }
        thread.dotColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: left, y: (bounds.midY - 4).rounded(), width: 8, height: 8)).fill()

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
        if showsRing {
            QuietFocus.ring(NSRect(x: left - 8, y: 1, width: bounds.width - left - Self.margin + 16, height: bounds.height - 2), radius: Opal.Corner.control)
        }
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

final class OlderRowView: ChannelRowView {
    private let button: QuietButton

    init(isLoading: Bool, onPress: @escaping () -> Void) {
        button = QuietButton(isLoading ? CatWords.loadingOlder : CatWords.loadOlder, style: .text, onPress: onPress)
        button.isArmed = !isLoading
        super.init(frame: .zero)
        addSubview(button)
    }

    override var isPressable: Bool { button.isArmed }
    override func press() { button.onPress?() }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func fit(width: CGFloat) -> CGFloat {
        button.frame.origin = NSPoint(x: ((width - button.frame.width) / 2).rounded(), y: 6)
        return button.frame.height + 12
    }

    override func draw(_ dirtyRect: NSRect) {
        if showsRing { QuietFocus.ring(button.frame, radius: button.frame.height / 2) }
    }
}

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

    override var takesFocus: Bool { clear != nil }

    override func draw(_ dirtyRect: NSRect) {
        MessagesInk.label(title).draw(at: NSPoint(x: Self.catLeft, y: 16))
        drawFocus()
    }
}

final class CardRowView: ChannelRowView {
    struct Button {
        var title: String
        var isWayOut = false
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
        let drawn = ChannelMarkdown.attributed(text, color: MessagesInk.text)
        let answered = answer.map { ChannelMarkdown.attributed($0, color: MessagesInk.text) }
        words = ChannelTextBlock(drawn)
        self.answer = answered.map(ChannelTextBlock.init)
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
        setAccessibilityLabel([heading, drawn.string, answered?.string, footer].compactMap { $0 }.joined(separator: ", "))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var textBlocks: [ChannelTextBlock] { [words, answer].compactMap { $0 } }
    override var takesFocus: Bool { true }

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
        let tile = NSRect(x: Self.catLeft, y: Self.pad + 1, width: Self.catSide, height: Self.catSide)
        Opal.tile(in: tile, light: look.light ?? .shades)
        CatStamp.draw(CatPose(frame: .sit, glint: .attention(bright: true)), jacket: look.jacket, in: tile.insetBy(dx: 4, dy: 4), on: self)

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
        drawFocus()
    }
}
