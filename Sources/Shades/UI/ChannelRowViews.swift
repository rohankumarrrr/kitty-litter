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
        hasVerticalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        borderType = .noBorder
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
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

    var name: String
    var hasCat: Bool
    var jacket: UInt32?

    init(_ speaker: Speaker, in book: ChannelBook) {
        name = book.name(of: speaker)
        hasCat = speaker != .you
        jacket = book.status(of: speaker)?.kitten.color ?? (speaker == .someoneElse ? Self.otherJacket : nil)
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

    init(title: String) {
        self.title = title
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isPressable: Bool { true }
    override func press() { onPress?() }
    override func fit(width: CGFloat) -> CGFloat { 30 }

    override func draw(_ dirtyRect: NSRect) {
        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        let label = NSAttributedString(string: "\(title)  ↗", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: hovering ? Ink.text : Ink.soft,
            .paragraphStyle: truncating,
        ])
        let left = Self.textLeft
        let room = bounds.width - left - Self.margin
        let width = min(ceil(label.size().width), room)
        let height: CGFloat = 16
        let top = bounds.height - height - 3
        if hovering {
            Ink.hover.setFill()
            NSBezierPath(roundedRect: NSRect(x: left - 6, y: top - 2, width: width + 12, height: height + 4), xRadius: 6, yRadius: 6).fill()
        }
        label.draw(in: NSRect(x: left, y: top, width: width, height: height))
    }
}

final class MessageRowView: ChannelRowView {
    private static let clampedLines = 12
    private static let catSide: CGFloat = 32
    private static let pad: CGFloat = 8
    private static let wordsTop: CGFloat = 28

    var onOpen: (() -> Void)?
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
    private var failureTop: CGFloat = 0

    init(message: ChannelMessage, look: ChannelSpeakerLook) {
        self.message = message
        self.look = look
        let color = message.isStillGoing ? Ink.soft : Ink.text
        let said = message.text ?? (message.isStillGoing ? CatWords.stillGoing : nil)
        words = said.map { ChannelTextBlock(ChannelMarkdown.attributed($0, color: color)) }
        failure = message.failure.map { ChannelTextBlock(ChannelMarkdown.attributed($0, color: Ink.hex(0xff3b30))) }
        super.init(frame: .zero)

        showMore.onPress = { [weak self] in self?.onShowMore?() }
        openButton.onPress = { [weak self] in self?.onOpen?() }
        copyButton.onPress = { [weak self] in self?.copyPressed() }
        for button in [showMore, copyButton, openButton] {
            button.isHidden = true
            addSubview(button)
        }

        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel([look.name, time, said, message.failure].compactMap { $0 }.joined(separator: ", "))
        var actions = [NSAccessibilityCustomAction(name: "Open") { [weak self] in
            self?.onOpen?()
            return self != nil
        }]
        if message.text != nil {
            actions.append(NSAccessibilityCustomAction(name: "Copy") { [weak self] in
                self?.copyPressed()
                return self != nil
            })
        }
        setAccessibilityCustomActions(actions)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var isCut: Bool { words?.isCut ?? false }

    func pressShowMore() { onShowMore?() }

    private var time: String { message.at.formatted(date: .omitted, time: .shortened) }

    private func copyPressed() {
        guard let text = message.text else { return }
        onCopy?(text)
        copyButton.flash("Copied")
    }

    override func hoverChanged() {
        copyButton.isHidden = !hovering || message.text == nil
        openButton.isHidden = !hovering
        needsDisplay = true
    }

    override func fit(width: CGFloat) -> CGFloat {
        let room = max(width - Self.textLeft - Self.margin, 60)
        var bottom = Self.wordsTop
        bottom += words?.fit(width: room, maxLines: isExpanded ? nil : Self.clampedLines) ?? 0
        if let failure {
            bottom += words == nil ? 0 : 4
            failureTop = bottom
            bottom += failure.fit(width: room)
        }

        showMore.isHidden = !isCut
        if isCut {
            showMore.frame.origin = NSPoint(x: Self.textLeft - 6, y: bottom + 1)
            bottom += showMore.frame.height + 2
        }
        openButton.frame.origin = NSPoint(x: width - Self.margin - openButton.frame.width + 6, y: 4)
        copyButton.frame.origin = NSPoint(x: openButton.frame.minX - copyButton.frame.width, y: 4)
        return max(bottom + Self.pad, Self.pad * 2 + Self.catSide)
    }

    override func draw(_ dirtyRect: NSRect) {
        if look.hasCat {
            let cat = NSRect(x: Self.catLeft, y: Self.pad + 1, width: Self.catSide, height: Self.catSide)
            CatStamp.draw(CatPose(frame: .sit), jacket: look.jacket, in: cat, on: self)
        }

        let left = Self.textLeft
        let timeLabel = NSAttributedString(string: time, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: Ink.soft])
        let timeWidth = ceil(timeLabel.size().width)
        if !hovering { timeLabel.draw(at: NSPoint(x: bounds.width - Self.margin - timeWidth, y: Self.pad + 2)) }

        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        let name = NSAttributedString(string: look.name, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: Ink.text,
            .paragraphStyle: truncating,
        ])
        let nameRoom = bounds.width - left - Self.margin - max(timeWidth, 96) - 8
        let nameWidth = min(ceil(name.size().width), nameRoom)
        name.draw(in: NSRect(x: left, y: Self.pad, width: nameWidth, height: 18))
        if message.earlierNotes > 0 {
            let notes = NSAttributedString(string: CatWords.earlierNotes(message.earlierNotes), attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: Ink.soft,
                .paragraphStyle: truncating,
            ])
            let notesLeft = left + nameWidth + 8
            notes.draw(in: NSRect(x: notesLeft, y: Self.pad + 2, width: max(left + nameRoom - notesLeft, 0), height: 14))
        }

        words?.draw(at: NSPoint(x: left, y: Self.wordsTop))
        failure?.draw(at: NSPoint(x: left, y: failureTop))
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
        CatStamp.draw(status.pose(tick: 0), jacket: status.kitten.color, in: NSRect(x: Self.catLeft, y: 14, width: 32, height: 32), on: self)
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
