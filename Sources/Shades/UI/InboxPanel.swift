import AppKit
import ShadesCore

/// What shipped and what needs you, over the cat. Only there when you ask for it. It never takes
/// the keyboard, and everything in it came from an agent, so it's only there to be read.
@MainActor
final class InboxPanel {
    private static let width: CGFloat = 340
    private static let padding: CGFloat = 12
    private static let headerHeight: CGFloat = 26
    private static let buttonHeight: CGFloat = 26
    private static let rowGap: CGFloat = 10
    private static let tallestShare: CGFloat = 0.6

    let panel = QuietPanel()
    private let balloon = BalloonView()
    private let scroll = NSScrollView()
    private let list = FlippedView()
    private let empty = NSTextField(labelWithString: CatWords.inboxEmpty)
    private var entries: [InboxEntry] = []
    private var buttons: [QuietButton] = []
    private var contentHeight: CGFloat = 0
    private var clickMonitor: Any?
    private var armTimer: Timer?

    var anchor: () -> (frame: NSRect, visible: NSRect) = { (.zero, .zero) }
    var onAction: ((InboxAction) -> Void)?
    var onChange: (() -> Void)?

    init() {
        panel.contentView = balloon
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = list
        balloon.addSubview(scroll)
        empty.font = .systemFont(ofSize: 13)
        empty.textColor = Ink.soft
        balloon.addSubview(empty)
    }

    var isVisible: Bool { panel.isVisible }
    var frame: NSRect { panel.frame }

    /// Opens the panel, or brings it up to date if it's already open.
    func show(_ entries: [InboxEntry]) {
        // The thread list comes round often, and starting over would lose your place.
        if panel.isVisible, entries == self.entries { return }
        self.entries = entries
        rebuild()
        place()
        holdButtons()
        if !panel.isVisible {
            panel.orderFrontRegardless()
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.hide() }
            }
        }
        onChange?()
    }

    func hide() {
        guard panel.isVisible else { return }
        armTimer?.invalidate()
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        panel.orderOut(nil)
        onChange?()
    }

    func reposition() {
        guard panel.isVisible else { return }
        place()
    }

    /// Rows move up when one goes, so a double click can't take out the next one too.
    private func holdButtons() {
        buttons.forEach { $0.isArmed = false }
        armTimer?.invalidate()
        armTimer = Timer.scheduledTimer(withTimeInterval: BubbleController.armDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.buttons.forEach { $0.isArmed = true } }
        }
    }

    private func rebuild() {
        list.subviews.forEach { $0.removeFromSuperview() }
        buttons = []
        empty.isHidden = !entries.isEmpty
        scroll.isHidden = entries.isEmpty

        var y: CGFloat = 0
        if entries.first?.needsYou == true { addHeader("Needs you", y: &y) }
        let firstShipped = entries.firstIndex { $0.kind == .shipped }
        let firstNote = entries.firstIndex { $0.kind == .note }
        for (index, entry) in entries.enumerated() {
            if index == firstShipped { addHeader("Shipped", y: &y, clearing: .shipped) }
            if index == firstNote { addHeader("Also", y: &y, clearing: .note) }
            addRow(entry, y: &y)
        }
        contentHeight = entries.isEmpty ? ceil(empty.intrinsicContentSize.height) : y - Self.rowGap
    }

    private var inner: CGFloat { Self.width - Self.padding * 2 }

    private func addHeader(_ title: String, y: inout CGFloat, clearing kind: InboxEntry.Kind? = nil) {
        let label = Self.label(title, font: .systemFont(ofSize: 11, weight: .semibold), color: Ink.soft)
        label.sizeToFit()
        // Labels carry 2 points of their own padding, so they sit that much further out.
        label.frame.origin = NSPoint(x: -2, y: y + (Self.headerHeight - label.frame.height) / 2)
        list.addSubview(label)
        if let kind {
            let button = addButton("Clear", .clear(kind))
            button.setFrameOrigin(NSPoint(x: inner + 6 - button.frame.width, y: y))
        }
        y += Self.headerHeight
    }

    private func addRow(_ entry: InboxEntry, y: inout CGFloat) {
        func addText(_ text: String, size: CGFloat, color: NSColor, indent: CGFloat = 0) {
            let width = inner - indent
            let label = Self.label(text, font: .systemFont(ofSize: size), color: color, wraps: true)
            let height = ceil(label.cell!.cellSize(
                forBounds: NSRect(x: 0, y: 0, width: width + 4, height: .greatestFiniteMagnitude)
            ).height)
            label.frame = NSRect(x: indent - 2, y: y, width: width + 4, height: height)
            list.addSubview(label)
            y += height
        }

        addText(entry.text, size: 13, color: entry.repliedAt == nil ? Ink.text : Ink.soft)
        if let answer = entry.answer {
            y += 4
            addText(answer, size: 12, color: Ink.text, indent: 10)
        }
        if entry.repliedAt != nil {
            y += 2
            addText(CatWords.inboxSent, size: 11, color: Ink.soft)
        }

        var right = inner + 6
        for button in rowButtons(for: entry).reversed() {
            right -= button.frame.width
            button.setFrameOrigin(NSPoint(x: right, y: y))
        }
        let line = Self.label("\(entry.threadTitle) · \(CatWords.ago(entry.at, now: Date()))", font: .systemFont(ofSize: 11), color: Ink.soft)
        // The time is at the end, and it's worth keeping when a title runs long.
        line.lineBreakMode = .byTruncatingMiddle
        line.sizeToFit()
        line.frame = NSRect(x: -2, y: y + (Self.buttonHeight - line.frame.height) / 2, width: right + 2, height: line.frame.height)
        list.addSubview(line)
        y += Self.buttonHeight + Self.rowGap
    }

    /// There's no button here that says anything. Reply and Ask only open the box for your own words.
    private func rowButtons(for entry: InboxEntry) -> [QuietButton] {
        let open = (title: "Open in T3", action: InboxAction.open(threadID: entry.threadID))
        let wanted: [(title: String, action: InboxAction)]
        if entry.questionID != nil {
            wanted = [open]
        } else if entry.kind == .decision {
            wanted = [("Reply", .reply(entry)), open, ("Done", .done(id: entry.id))]
        } else {
            wanted = [("Ask", .reply(entry)), open]
        }
        return wanted.map { addButton($0.title, $0.action) }
    }

    private func addButton(_ title: String, _ action: InboxAction) -> QuietButton {
        let button = QuietButton(title, style: .text) { [weak self] in self?.onAction?(action) }
        buttons.append(button)
        list.addSubview(button)
        return button
    }

    private static func label(_ text: String, font: NSFont, color: NSColor, wraps: Bool = false) -> NSTextField {
        let label = wraps ? NSTextField(wrappingLabelWithString: text) : NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.isSelectable = false
        return label
    }

    private func place() {
        let (over, visible) = anchor()
        let shown = min(contentHeight, visible.height * Self.tallestShare)
        let size = NSSize(width: Self.width, height: shown + Self.padding * 2 + BubbleLayout.tailHeight)
        let placement = BubbleLayout.place(size: size, over: over, in: visible)
        balloon.tailX = placement.tailX
        balloon.tailOnTop = placement.below
        panel.setFrame(placement.frame, display: true)
        balloon.frame = NSRect(origin: .zero, size: placement.frame.size)

        let body = balloon.body
        // The scroll bar lives in the right padding, so it never covers the words.
        let scrollWidth = Self.width - Self.padding - 3
        scroll.frame = NSRect(x: Self.padding, y: body.minY + Self.padding, width: scrollWidth, height: shown)
        list.frame = NSRect(x: 0, y: 0, width: scrollWidth, height: contentHeight)
        empty.frame = NSRect(x: Self.padding - 2, y: body.minY + Self.padding, width: inner + 4, height: shown)
        balloon.needsDisplay = true
        panel.invalidateShadow()
    }
}
