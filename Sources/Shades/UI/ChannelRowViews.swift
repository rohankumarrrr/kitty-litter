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

    init(_ speaker: Speaker, in book: ChannelBook) {
        name = book.name(of: speaker)
        isYou = speaker == .you
        hasCat = !isYou
        let own = book.status(of: speaker).flatMap { Self.color(of: $0.kitten) }
        jacket = own ?? (speaker == .someoneElse ? Self.otherJacket : nil)
        bubble = isYou ? Self.yours : own
    }

    /// Its colour from kitten.json, or one picked from its folder so it's the same every time. The cat keeps its black jacket.
    static func color(of kitten: Kitten) -> UInt32? {
        if let color = kitten.color { return color }
        guard kitten != KittenBoard.shades else { return nil }
        let seed = kitten.id.unicodeScalars.reduce(UInt32(0)) { $0 &* 31 &+ $1.value }
        return palette[Int(seed % UInt32(palette.count))]
    }

    static let grey = NSColor(name: nil) { $0.isDark ? Ink.hex(0x3a3a3c) : Ink.hex(0xe9e9eb) }

    var bubbleFill: NSColor { bubble.map(Ink.hex) ?? Self.grey }

    /// Black or white, whichever reads better on the bubble.
    var bubbleText: NSColor {
        bubble.map { Self.readable(on: $0) } ?? Ink.text
    }

    /// A reply that's still coming is paler. It's worked out as one solid colour for light and dark, so its words can
    /// be picked to read on it too.
    func fill(fadedTo alpha: Double) -> NSColor {
        let bubble = bubble
        return NSColor(name: nil) { Ink.hex(Self.faded(bubble, to: alpha, dark: $0.isDark)) }
    }

    func text(fadedTo alpha: Double) -> NSColor {
        guard let bubble else { return Ink.text }
        return NSColor(name: nil) { Self.readable(on: Self.faded(bubble, to: alpha, dark: $0.isDark)) }
    }

    /// The colour over the window at `alpha`. `nil` is the grey.
    private static func faded(_ bubble: UInt32?, to alpha: Double, dark: Bool) -> UInt32 {
        let top = bubble ?? (dark ? 0x3a3a3c : 0xe9e9eb)
        let under: UInt32 = dark ? 0x1d1d1f : 0xf9f9f9
        return [16, 8, 0].reduce(UInt32(0)) { mixed, shift in
            let channel = Double((top >> shift) & 0xff) * alpha + Double((under >> shift) & 0xff) * (1 - alpha)
            return mixed | UInt32(channel.rounded()) << shift
        }
    }

    /// Whichever of black and white has more contrast with it.
    static func readable(on color: UInt32) -> NSColor {
        contrast(color, 0x000000) >= contrast(color, 0xffffff) ? .black : .white
    }

    /// As WCAG measures it, from 1 to 21.
    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    static func luminance(_ color: UInt32) -> Double {
        let channel = { (shift: UInt32) -> Double in
            let value = Double((color >> shift) & 0xff) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }
}

/// One row of the pane. It lays itself out at a width and says how tall that makes it.
class ChannelRowView: QuietView {
    static let textLeft: CGFloat = 64
    static let catLeft: CGFloat = 20
    static let margin: CGFloat = 20

    var hovering = false { didSet { if hovering != oldValue { hoverChanged() } } }

    func fit(width: CGFloat) -> CGFloat { 0 }
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
            .foregroundColor: Ink.soft,
        ])
        let size = label.size()
        let middle = bounds.midY.rounded() + 0.5
        let gap: CGFloat = 10
        Ink.line.setStroke()
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
            .foregroundColor: hovering ? Ink.text : Ink.soft,
        ])
        if let project, !project.isEmpty {
            label.append(NSAttributedString(string: "  ·  \(project)", attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: Ink.soft]))
        }
        if onPress != nil {
            label.append(NSAttributedString(string: "  ›", attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: Ink.soft]))
        }
        label.addAttribute(.paragraphStyle, value: truncating, range: NSRange(location: 0, length: label.length))
        let left = Self.textLeft
        let room = bounds.width - left - Self.margin
        let width = min(ceil(label.size().width), room)
        let height: CGFloat = 16
        let top = bounds.height - height - 3
        if hovering, onPress != nil {
            Ink.hover.setFill()
            NSBezierPath(roundedRect: NSRect(x: left - 6, y: top - 2, width: width + 12, height: height + 4), xRadius: 6, yRadius: 6).fill()
        }
        label.draw(in: NSRect(x: left, y: top, width: width, height: height))
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
    private static let stillGoingAlpha = 0.55

    var onOpen: (() -> Void)? { didSet { setActions() } }
    var onReply: (() -> Void)? { didSet { setActions() } }
    var onCopy: ((String) -> Void)?
    var onShowMore: (() -> Void)?
    var isExpanded = false

    private let message: ChannelMessage
    private let look: ChannelSpeakerLook
    private let words: ChannelTextBlock?
    private let failure: ChannelTextBlock?
    private let showMore = QuietButton("Show more", style: .text)
    private let copyButton = QuietButton("Copy", style: .text)
    private let openButton = QuietButton("Open", style: .text)
    private let replyButton = QuietButton("Reply", style: .text)
    private(set) var bubble = NSRect.zero
    private var failureTop: CGFloat = 0

    init(message: ChannelMessage, look: ChannelSpeakerLook) {
        self.message = message
        self.look = look
        let said = message.text ?? (message.isStillGoing ? CatWords.stillGoing : nil)
        let color = message.isStillGoing ? look.text(fadedTo: Self.stillGoingAlpha) : look.bubbleText
        words = said.map { ChannelTextBlock(ChannelMarkdown.attributed($0, color: color)) }
        failure = message.failure.map { ChannelTextBlock(ChannelMarkdown.attributed($0, color: Ink.hex(0xff3b30))) }
        super.init(frame: .zero)

        showMore.onPress = { [weak self] in self?.onShowMore?() }
        openButton.onPress = { [weak self] in self?.onOpen?() }
        replyButton.onPress = { [weak self] in self?.onReply?() }
        copyButton.onPress = { [weak self] in self?.copyPressed() }
        for button in [showMore, copyButton, openButton, replyButton] {
            button.isHidden = true
            addSubview(button)
        }

        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel([look.name, time, said, message.failure].compactMap { $0 }.joined(separator: ", "))
        setActions()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setActions() {
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
        setAccessibilityCustomActions(actions)
    }

    var isCut: Bool { words?.isCut ?? false }
    var isYours: Bool { look.isYou }
    var fill: NSColor { look.bubbleFill }

    func pressShowMore() { onShowMore?() }

    private var time: String { message.at.formatted(date: .omitted, time: .shortened) }

    private func copyPressed() {
        guard let text = message.text else { return }
        onCopy?(text)
        copyButton.flash("Copied")
    }

    override func hoverChanged() {
        copyButton.isHidden = !hovering || message.text == nil
        openButton.isHidden = !hovering || onOpen == nil
        replyButton.isHidden = !hovering || onReply == nil
        needsDisplay = true
    }

    override func fit(width: CGFloat) -> CGFloat {
        let room = max(min(width * Self.widest, width - Self.textLeft - Self.margin) - Self.insetX * 2, 60)
        var bottom = Self.pad + Self.headHeight
        if let words {
            words.fit(width: room, maxLines: isExpanded ? nil : Self.clampedLines)
            let size = NSSize(width: words.width + Self.insetX * 2, height: words.height + Self.insetY * 2)
            let left = look.isYou ? width - Self.margin - size.width : Self.textLeft
            bubble = NSRect(origin: NSPoint(x: left, y: bottom), size: size)
            bottom = bubble.maxY
        } else {
            bubble = NSRect(x: look.isYou ? width - Self.margin : Self.textLeft, y: bottom, width: 0, height: 0)
        }
        if let failure {
            failure.fit(width: room + Self.insetX * 2)
            failureTop = bottom + (words == nil ? 0 : 4)
            bottom = failureTop + failure.height
        }
        showMore.isHidden = !isCut
        if isCut {
            showMore.frame.origin = NSPoint(x: look.isYou ? bubble.maxX - showMore.frame.width + 6 : bubble.minX - 6, y: bottom + 1)
            bottom += showMore.frame.height + 2
        }
        var right = width - Self.margin + 6
        for button in [openButton, copyButton, replyButton] {
            right -= button.frame.width
            button.frame.origin = NSPoint(x: right, y: 0)
        }
        return max(bottom + Self.pad, look.hasCat ? Self.pad * 2 + Self.headHeight + Self.catSide : 0)
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
            words?.draw(at: NSPoint(x: bubble.minX + Self.insetX, y: bubble.minY + Self.insetY))
        }
        failure?.draw(at: NSPoint(x: look.isYou ? bubble.maxX - (failure?.width ?? 0) : bubble.minX, y: failureTop))
    }

    /// Who said it and when, over the bubble. Yours only needs the time.
    private func drawHead() {
        let small = NSFont.systemFont(ofSize: 11)
        let timeLabel = NSAttributedString(string: time, attributes: [.font: small, .foregroundColor: Ink.soft])
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
            .foregroundColor: Ink.soft,
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
            .foregroundColor: Ink.text,
            .paragraphStyle: truncating,
        ]).draw(in: NSRect(x: Self.textLeft, y: 14, width: width, height: 17))
        NSAttributedString(string: "\(status.kitten.role) · \(CatWords.kittenState(status.state))", attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: Ink.soft,
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
            Ink.hover.setFill()
            NSBezierPath(roundedRect: NSRect(x: left - 8, y: 1, width: bounds.width - left - Self.margin + 16, height: bounds.height - 2), xRadius: 7, yRadius: 7).fill()
        }
        thread.dotColor.setFill()
        NSBezierPath(rect: NSRect(x: left, y: bounds.midY - 4, width: 8, height: 8)).fill()

        var edge = bounds.width - Self.margin
        let details = [CatWords.age(of: thread.updatedAt, now: now()), CatWords.status(thread), thread.pullRequest.map(CatWords.pullRequest)]
        for text in details.compactMap({ $0 }) {
            let label = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: Ink.soft])
            let size = label.size()
            edge -= ceil(size.width)
            label.draw(at: NSPoint(x: edge, y: bounds.midY - size.height / 2))
            edge -= Self.gap
        }

        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        NSAttributedString(string: thread.title, attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: Ink.text,
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
            .foregroundColor: Ink.soft,
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

    override func fit(width: CGFloat) -> CGFloat {
        block.fit(width: max(width - left - Self.margin, 60)) + 12
    }

    override func draw(_ dirtyRect: NSRect) {
        block.draw(at: NSPoint(x: left, y: 6))
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
            .foregroundColor: Ink.soft,
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
        words = ChannelTextBlock(ChannelMarkdown.attributed(text, color: Ink.text))
        self.answer = answer.map { ChannelTextBlock(ChannelMarkdown.attributed($0, color: Ink.text)) }
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

    override func fit(width: CGFloat) -> CGFloat {
        let room = max(width - Self.textLeft - Self.margin, 60)
        var bottom = Self.wordsTop + words.fit(width: room)
        if let answer {
            answerTop = bottom + 6
            bottom = answerTop + answer.fit(width: room - 12)
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
            let time = NSAttributedString(string: CatWords.age(of: at, now: Date()), attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: Ink.soft])
            right -= ceil(time.size().width)
            time.draw(at: NSPoint(x: right, y: Self.pad + 2))
            right -= 8
        }
        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        NSAttributedString(string: heading, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: Ink.text,
            .paragraphStyle: truncating,
        ]).draw(in: NSRect(x: left, y: Self.pad, width: max(right - left, 40), height: 18))

        words.draw(at: NSPoint(x: left, y: Self.wordsTop))
        if let answer {
            Ink.line.setFill()
            NSRect(x: left, y: answerTop, width: 2, height: answer.height).fill()
            answer.draw(at: NSPoint(x: left + 12, y: answerTop))
        }
        if let footer {
            NSAttributedString(string: footer, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: Ink.soft])
                .draw(at: NSPoint(x: left, y: footerTop))
        }
    }
}
