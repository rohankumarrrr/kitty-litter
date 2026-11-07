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
}

/// The same colours as the kitten view. An idle kitten has no dot, which keeps the sidebar calm.
extension KittenStatus.State {
    var dotColor: NSColor? {
        switch self {
        case .working: return Ink.hex(CatGlint.thinking(bright: true).color!)
        case .needsYou: return Ink.hex(CatGlint.attention(bright: true).color!)
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
    var jacket: UInt32?
    /// `nil` is the grey that the cat and anyone unknown get.
    var bubble: UInt32?
    /// The words on `bubble`. `nil` is the window's own text colour.
    var words: UInt32?

    init(_ speaker: Speaker, in book: ChannelBook) {
        name = book.name(of: speaker)
        isYou = speaker == .you
        hasCat = !isYou
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
    private static func faded(_ bubble: UInt32?, to alpha: Double, dark: Bool, theme: ColorTheme?) -> UInt32 {
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
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if isPressable, bounds.contains(convert(event.locationInWindow, from: nil)) { press() }
    }
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
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
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

/// A thread's title, so one conversation with a kitten reads as topics. Clicking opens it in T3.
final class SubjectRowView: ChannelRowView {
    var onPress: (() -> Void)?
    private let title: String
    private let project: String?

    init(title: String, project: String?) {
        self.title = title
        self.project = project
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel([title, project].compactMap { $0 }.joined(separator: ", "))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isPressable: Bool { onPress != nil }
    override func press() { onPress?() }
    override func fit(width: CGFloat) -> CGFloat { 30 }

    override func draw(_ dirtyRect: NSRect) {
        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        let label = NSMutableAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: hovering ? MessagesInk.text : MessagesInk.soft,
        ])
        if let project, !project.isEmpty {
            label.append(NSAttributedString(string: "  ·  \(project)", attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: MessagesInk.soft]))
        }
        if onPress != nil {
            label.append(NSAttributedString(string: "  ›", attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: MessagesInk.soft]))
        }
        label.addAttribute(.paragraphStyle, value: truncating, range: NSRange(location: 0, length: label.length))
        let left = Self.textLeft
        let room = bounds.width - left - Self.margin
        let width = min(ceil(label.size().width), room)
        let height: CGFloat = 16
        let top = bounds.height - height - 3
        if hovering, onPress != nil {
            MessagesInk.hover.setFill()
            NSBezierPath(roundedRect: NSRect(x: left - 6, y: top - 2, width: width + 12, height: height + 4), xRadius: 6, yRadius: 6).fill()
        }
        label.draw(in: NSRect(x: left, y: top, width: width, height: height))
    }
}

/// A message's words, read from markdown and laid out once. Messages keeps them while it's open, so a message that's
/// shown again, scrolled back to or kept through a refresh isn't read and measured again.
final class MessageWords {
    let message: ChannelMessage
    let words: ChannelTextBlock?
    let failure: ChannelTextBlock?
    /// The bubble and theme its words are coloured for.
    private var paint: (bubble: UInt32?, theme: ColorTheme?)

    init(_ message: ChannelMessage, look: ChannelSpeakerLook) {
        self.message = message
        paint = (look.bubble, MessagesInk.theme)
        let said = message.text ?? (message.isStillGoing ? CatWords.stillGoing : nil)
        words = said.map { ChannelTextBlock(ChannelMarkdown.attributed($0, color: Self.color(of: message, look: look))) }
        failure = message.failure.map { ChannelTextBlock(ChannelMarkdown.attributed($0, color: Ink.hex(0xff3b30))) }
    }

    /// Colours the words for `look` as it is now, which a theme can change.
    func paint(for look: ChannelSpeakerLook) {
        guard paint.bubble != look.bubble || paint.theme != MessagesInk.theme else { return }
        paint = (look.bubble, MessagesInk.theme)
        words?.recolor(Self.color(of: message, look: look))
    }

    private static func color(of message: ChannelMessage, look: ChannelSpeakerLook) -> NSColor {
        message.isStillGoing ? look.text(fadedTo: MessageRowView.stillGoingAlpha) : look.bubbleText
    }
}

/// One message as a bubble: yours on the right in blue, everyone else's on the left in their own colour.
final class MessageRowView: ChannelRowView {
    private static let clampedLines = 12
    private static let catSide: CGFloat = 28
    private static let pad: CGFloat = 5
    private static let headHeight: CGFloat = 18
    private static let insetX: CGFloat = 12
    private static let insetY: CGFloat = 7
    /// Of the pane's width, so a long message still reads as a bubble.
    private static let widest: CGFloat = 0.7
    static let stillGoingAlpha = 0.55

    var onOpen: (() -> Void)?
    var onReply: (() -> Void)?
    var onCopy: ((String) -> Void)?
    var onShowMore: (() -> Void)?
    var isExpanded = false

    private let message: ChannelMessage
    private let look: ChannelSpeakerLook
    private let words: ChannelTextBlock?
    private let failure: ChannelTextBlock?
    private var showMore: QuietButton?
    /// Made the first time you hover, since most messages never are.
    private var hoverButtons: (open: QuietButton, copy: QuietButton, reply: QuietButton)?
    private(set) var bubble = NSRect.zero
    private var failureTop: CGFloat = 0
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
        return [look.name, time, said, message.failure].compactMap { $0 }.joined(separator: ", ")
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        var actions: [NSAccessibilityCustomAction] = []
        if onReply != nil {
            actions.append(NSAccessibilityCustomAction(name: "Reply") { [weak self] in
                self?.onReply?()
                return self != nil
            })
        }
        if onOpen != nil {
            actions.append(NSAccessibilityCustomAction(name: "Open") { [weak self] in
                self?.onOpen?()
                return self != nil
            })
        }
        if message.text != nil {
            actions.append(NSAccessibilityCustomAction(name: "Copy") { [weak self] in
                self?.copyPressed()
                return self != nil
            })
        }
        return actions
    }

    override var textBlocks: [ChannelTextBlock] { [words, failure].compactMap { $0 } }
    var isCut: Bool { words?.isCut ?? false }
    var isYours: Bool { look.isYou }
    var fill: NSColor { look.bubbleFill }

    func pressShowMore() { onShowMore?() }

    private var time: String { message.at.formatted(date: .omitted, time: .shortened) }

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
                reply: QuietButton("Reply", style: .text) { [weak self] in self?.onReply?() }
            )
            [buttons.open, buttons.copy, buttons.reply].forEach(addSubview)
            hoverButtons = buttons
            placeHoverButtons(width: bounds.width)
        }
        hoverButtons?.copy.isHidden = !hovering || message.text == nil
        hoverButtons?.open.isHidden = !hovering || onOpen == nil
        hoverButtons?.reply.isHidden = !hovering || onReply == nil
        needsDisplay = true
    }

    private func placeHoverButtons(width: CGFloat) {
        guard let hoverButtons else { return }
        var right = width - Self.margin + 6
        for button in [hoverButtons.open, hoverButtons.copy, hoverButtons.reply] {
            right -= button.frame.width
            button.frame.origin = NSPoint(x: right, y: 0)
        }
    }

    override func fit(width: CGFloat) -> CGFloat {
        if let fitted, fitted.width == width, fitted.isExpanded == isExpanded { return fitted.height }
        let room = max(min(width * Self.widest, width - Self.textLeft - Self.margin) - Self.insetX * 2, 60)
        var bottom = Self.pad + Self.headHeight
        if let words {
            words.fit(width: room, maxLines: isExpanded ? nil : Self.clampedLines)
            let size = NSSize(width: words.width + Self.insetX * 2, height: words.height + Self.insetY * 2)
            let left = look.isYou ? width - Self.margin - size.width : Self.textLeft
            bubble = NSRect(origin: NSPoint(x: left, y: bottom), size: size)
            words.place(at: NSPoint(x: bubble.minX + Self.insetX, y: bubble.minY + Self.insetY), in: self)
            bottom = bubble.maxY
        } else {
            bubble = NSRect(x: look.isYou ? width - Self.margin : Self.textLeft, y: bottom, width: 0, height: 0)
        }
        if let failure {
            failure.fit(width: room + Self.insetX * 2)
            failureTop = bottom + (words == nil ? 0 : 4)
            failure.place(at: NSPoint(x: look.isYou ? bubble.maxX - failure.width : bubble.minX, y: failureTop), in: self)
            bottom = failureTop + failure.height
        }
        showMore?.isHidden = !isCut
        if isCut {
            let showMore = showMore ?? QuietButton("Show more", style: .text) { [weak self] in self?.onShowMore?() }
            if showMore.superview == nil { addSubview(showMore) }
            self.showMore = showMore
            showMore.frame.origin = NSPoint(x: look.isYou ? bubble.maxX - showMore.frame.width + 6 : bubble.minX - 6, y: bottom + 1)
            bottom += showMore.frame.height + 2
        }
        placeHoverButtons(width: width)
        let height = max(bottom + Self.pad, look.hasCat ? Self.pad * 2 + Self.headHeight + Self.catSide : 0)
        fitted = (width, isExpanded, height)
        return height
    }

    override func draw(_ dirtyRect: NSRect) {
        if look.hasCat {
            let top = max(Self.pad + Self.headHeight, bubble.maxY - Self.catSide)
            CatStamp.draw(CatPose(frame: .sit), jacket: look.jacket, in: NSRect(x: Self.catLeft, y: top, width: Self.catSide, height: Self.catSide), on: self)
        }
        drawHead()
        if bubble.height > 0 {
            let radius = min(16, bubble.height / 2)
            (message.isStillGoing ? look.fill(fadedTo: Self.stillGoingAlpha) : fill).setFill()
            NSBezierPath(roundedRect: bubble, xRadius: radius, yRadius: radius).fill()
        }
    }

    /// Who said it and when, over the bubble. Yours only needs the time.
    private func drawHead() {
        let small = NSFont.systemFont(ofSize: 11)
        let timeLabel = NSAttributedString(string: time, attributes: [.font: small, .foregroundColor: MessagesInk.soft])
        let timeWidth = ceil(timeLabel.size().width)
        let baseline = Self.pad + 1
        guard !look.isYou else {
            if !hovering { timeLabel.draw(at: NSPoint(x: bounds.width - Self.margin - timeWidth, y: baseline)) }
            return
        }
        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        var head = look.name
        if message.earlierNotes > 0 { head += "  ·  \(CatWords.earlierNotes(message.earlierNotes))" }
        if !hovering { head += "  ·  \(time)" }
        NSAttributedString(string: head, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: MessagesInk.soft,
            .paragraphStyle: truncating,
        ]).draw(in: NSRect(x: Self.textLeft + 2, y: baseline, width: max(bounds.width - Self.textLeft - Self.margin - 150, 60), height: 15))
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

    override func fit(width: CGFloat) -> CGFloat { 52 }

    override func draw(_ dirtyRect: NSRect) {
        CatStamp.draw(status.pose(tick: 0), jacket: ChannelSpeakerLook.color(of: status.kitten), in: NSRect(x: Self.catLeft, y: 14, width: 32, height: 32), on: self)
        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        let width = bounds.width - Self.textLeft - Self.margin
        NSAttributedString(string: status.kitten.name, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: MessagesInk.text,
            .paragraphStyle: truncating,
        ]).draw(in: NSRect(x: Self.textLeft, y: 14, width: width, height: 17))
        NSAttributedString(string: "\(status.kitten.role) · \(CatWords.kittenState(status.state))", attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: MessagesInk.soft,
            .paragraphStyle: truncating,
        ]).draw(in: NSRect(x: Self.textLeft, y: 32, width: width, height: 14))
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
    override func fit(width: CGFloat) -> CGFloat { 30 }

    override func draw(_ dirtyRect: NSRect) {
        let left = Self.textLeft
        if hovering {
            MessagesInk.hover.setFill()
            NSBezierPath(roundedRect: NSRect(x: left - 8, y: 1, width: bounds.width - left - Self.margin + 16, height: bounds.height - 2), xRadius: 7, yRadius: 7).fill()
        }
        thread.dotColor.setFill()
        NSBezierPath(rect: NSRect(x: left, y: bounds.midY - 4, width: 8, height: 8)).fill()

        var edge = bounds.width - Self.margin
        let details = [CatWords.age(of: thread.updatedAt, now: now()), CatWords.status(thread), thread.pullRequest.map(CatWords.pullRequest)]
        for text in details.compactMap({ $0 }) {
            let label = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: MessagesInk.soft])
            let size = label.size()
            edge -= ceil(size.width)
            label.draw(at: NSPoint(x: edge, y: bounds.midY - size.height / 2))
            edge -= Self.gap
        }

        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        NSAttributedString(string: thread.title, attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: MessagesInk.text,
            .paragraphStyle: truncating,
        ]).draw(in: NSRect(x: left + 16, y: 6, width: max(edge - left - 16, 40), height: 17))
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
            .font: NSFont.systemFont(ofSize: 13),
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
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
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
        var action: () -> Void
    }

    private static let catSide: CGFloat = 32
    private static let pad: CGFloat = 8
    private static let wordsTop: CGFloat = 28
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
        self.buttons = buttons.map { QuietButton($0.title, style: $0.isWayOut ? .text : .plain, onPress: $0.action) }
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
            bottom = footerTop + 16
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
            let time = NSAttributedString(string: CatWords.age(of: at, now: Date()), attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: MessagesInk.soft])
            right -= ceil(time.size().width)
            time.draw(at: NSPoint(x: right, y: Self.pad + 2))
            right -= 8
        }
        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        NSAttributedString(string: heading, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: MessagesInk.text,
            .paragraphStyle: truncating,
        ]).draw(in: NSRect(x: left, y: Self.pad, width: max(right - left, 40), height: 18))

        if let answer {
            MessagesInk.line.setFill()
            NSRect(x: left, y: answerTop, width: 2, height: answer.height).fill()
        }
        if let footer {
            NSAttributedString(string: footer, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: MessagesInk.soft])
                .draw(at: NSPoint(x: left, y: footerTop))
        }
    }
}
