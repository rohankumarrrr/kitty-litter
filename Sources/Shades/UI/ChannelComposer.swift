import AppKit
import ShadesContext
import ShadesCore

/// The box at the bottom of Messages, and the only thing in the window that takes the keyboard. What's typed goes
/// where the line above it says, and carries nothing but your words, and the files or pictures you drop, paste or pick
/// from Attach's recent files. There's no file picker, since one would make Shades the active app, and a menu doesn't.
final class ChannelComposer: QuietView, NSTextViewDelegate {
    private static let pad: CGFloat = 12
    private static let maxLines: CGFloat = 5
    private static let labelHeight: CGFloat = 22
    private static let fieldPad: CGFloat = 8
    private static let checkboxHeight: CGFloat = 24
    private static let fileHeight: CGFloat = 52
    private static let chipWidth: CGFloat = 220
    private static let narrowestChip: CGFloat = 130

    var onSend: ((String, MessageTarget, [Drop]) -> Void)?
    /// Attach, which offers recent files in a menu under it.
    var onAttach: ((NSView) -> Void)?
    var onResize: (() -> Void)?
    /// Esc in the box, which closes a thread's pane as it does anywhere else in the window.
    var onEscape: (() -> Void)?
    /// The mic, which starts saying something into this box, and then finishes it.
    var onMic: (() -> Void)?
    /// Esc while the mic is hearing you, which forgets what you said.
    var onStopListening: (() -> Void)?

    private(set) var target: MessageTarget?
    /// The line over the box as the place sets it, before anything typed changes it.
    private var standardLabel = ""
    /// Who an @ in the words can go straight to, which is only ever in #general.
    private var mentionable: [Kitten] = []
    /// Where the box is, since the cat's DM and #general both go to the router.
    private var channel: ChannelID?
    /// Words typed for somewhere that's gone wait in the box, and Return doesn't send them anywhere else.
    var isHeld = false
    /// A thread's "Also send to #channel", under its box, as Slack has it.
    let alsoSend = QuietCheckbox()
    private let label = NSTextField(labelWithString: "")
    private let scroll = NSScrollView()
    let textView = ComposerTextView()
    /// What goes with your words, until you send them or take them off.
    private(set) var attachments: [Drop] = []
    private var chips: [AttachmentChip] = []
    private let attachButton = QuietButton(CatWords.attach, style: .text)
    let mic = QuietButton.mic()

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = MessagesInk.font(ofSize: 11)
        label.lineBreakMode = .byTruncatingTail
        label.isSelectable = false
        addSubview(label)

        textView.delegate = self
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = MessagesInk.font(ofSize: MessagesInk.title)
        textView.insertionPointColor = Ink.accent
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = textView
        addSubview(scroll)
        alsoSend.isHidden = true
        addSubview(alsoSend)
        attachButton.onPress = { [weak self] in
            guard let self else { return }
            self.onAttach?(self.attachButton)
        }
        attachButton.setAccessibilityLabel(CatWords.attachRecent)
        addSubview(attachButton)
        mic.isThemed = true
        mic.onPress = { [weak self] in self?.onMic?() }
        addSubview(mic)
        textView.onAttach = { [weak self] in self?.attach($0) ?? false }
        registerForDraggedTypes(Drop.types)
        restyle()
    }

    /// Puts files or pictures with what you're typing, up to `Drop.mostAtOnce`. Only words go to a question, so it
    /// can't take any.
    @discardableResult
    func attach(_ drops: [Drop]) -> Bool {
        let files = drops.filter(\.isFile)
        guard let target, target.takesFiles, !files.isEmpty else { return false }
        for drop in files.prefix(Drop.mostAtOnce - attachments.count) where !attachments.contains(drop) {
            attachments.append(drop)
            let chip = AttachmentChip()
            chip.show(name: drop.name, thumbnail: drop.thumbnail(side: 96).flatMap(NSImage.init(data:)))
            chip.onRemove = { [weak self, weak chip] in
                guard let self, let chip, let index = self.chips.firstIndex(where: { $0 === chip }) else { return }
                self.remove(at: index)
            }
            addSubview(chip)
            chips.append(chip)
        }
        changedAttachments()
        return true
    }

    private func remove(at index: Int) {
        attachments.remove(at: index)
        chips.remove(at: index).removeFromSuperview()
        changedAttachments()
    }

    private func changedAttachments() {
        needsLayout = true
        onResize?()
    }

    /// What was attached, which goes with what's sent now.
    func takeAttachments() -> [Drop] {
        defer {
            attachments = []
            chips.forEach { $0.removeFromSuperview() }
            chips = []
            changedAttachments()
        }
        return attachments
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        target?.takesFiles == true && Drop.all(sender.draggingPasteboard).contains(where: \.isFile) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        attach(Drop.all(sender.draggingPasteboard))
    }

    func restyle() {
        label.textColor = MessagesInk.soft
        label.font = MessagesInk.font(ofSize: 11)
        textView.textColor = MessagesInk.text
        textView.font = MessagesInk.font(ofSize: MessagesInk.title)
        alsoSend.needsDisplay = true
        mic.needsDisplay = true
        needsDisplay = true
        // Another text size makes the box taller or shorter.
        onResize?()
    }

    /// Whether what you send next also shows in the thread's channel.
    var alsoSends: Bool {
        get { !alsoSend.isHidden && alsoSend.isOn }
        set { alsoSend.isOn = newValue }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// `channel` is where the box is, which says who the router's answers come from, and `name` is its name as the
    /// sidebar writes it. `alsoSendTo` offers a thread's reply to its channel too.
    func show(_ target: MessageTarget?, label: String? = nil, in channel: ChannelID? = nil, name: String? = nil, alsoSendTo: String? = nil, mentionable: [Kitten] = []) {
        let changed = target != self.target || (alsoSendTo == nil) != alsoSend.isHidden
        // A file is for where you attached it, so it never follows the box anywhere else.
        if target != self.target || channel != self.channel, !attachments.isEmpty { _ = takeAttachments() }
        self.target = target
        self.channel = channel
        isHidden = target == nil
        attachButton.isHidden = target?.takesFiles != true
        alsoSend.isHidden = alsoSendTo == nil
        if let alsoSendTo { alsoSend.title = alsoSendTo }
        guard let target else { return }
        standardLabel = label ?? CatWords.target(target, in: channel)
        // Words held for somewhere that's gone say so, whoever they name.
        self.mentionable = target == .router && channel == .general && label == nil ? mentionable : []
        showWhereWordsGo()
        textView.placeholder = CatWords.placeholder(target, in: channel, name: name)
        if changed { needsLayout = true }
    }

    /// Words that @ a kitten in #general go straight to it, and the line says so as you type.
    private func showWhereWordsGo() {
        label.stringValue = MessageTarget.mentioned(in: textView.string, among: mentionable).map(CatWords.mentioning) ?? standardLabel
    }

    var height: CGFloat {
        guard target != nil else { return 0 }
        return Self.pad + Self.labelHeight + filesHeight + textHeight + Self.fieldPad * 2 + (alsoSend.isHidden ? 0 : Self.checkboxHeight) + Self.pad
    }

    /// The chips wrap onto as many rows as they need, narrowing first so a narrow pane still takes two a row.
    private var chipsPerRow: Int {
        max(Int((bounds.width - ChannelRowView.margin * 2 + 8) / (Self.narrowestChip + 8)), 1)
    }

    private var chipSize: CGFloat {
        let columns = CGFloat(min(chipsPerRow, max(chips.count, 1)))
        return min(Self.chipWidth, (bounds.width - ChannelRowView.margin * 2 - 8 * (columns - 1)) / columns)
    }

    private var filesHeight: CGFloat {
        chips.isEmpty ? 0 : CGFloat((chips.count + chipsPerRow - 1) / chipsPerRow) * Self.fileHeight
    }

    /// A line of the font it's drawn in, so its words show whole at every text size.
    private var textLine: CGFloat {
        ceil(NSLayoutManager().defaultLineHeight(for: textView.font ?? .systemFont(ofSize: 14)))
    }

    private var textHeight: CGFloat {
        let line = textLine
        guard let manager = textView.layoutManager, let container = textView.textContainer else { return line }
        manager.ensureLayout(for: container)
        let used = ceil(manager.usedRect(for: container).height)
        return min(max(line, used), line * Self.maxLines)
    }

    override func layout() {
        super.layout()
        let inner = bounds.width - ChannelRowView.margin * 2
        attachButton.frame.origin = NSPoint(x: bounds.width - ChannelRowView.margin - attachButton.frame.width + 6, y: Self.pad - 2)
        label.frame = NSRect(x: ChannelRowView.margin - 2, y: Self.pad + 2, width: inner - (attachButton.isHidden ? 0 : attachButton.frame.width), height: 16)
        for (index, chip) in chips.enumerated() {
            let column = index % chipsPerRow, row = index / chipsPerRow
            chip.frame = NSRect(x: ChannelRowView.margin + CGFloat(column) * (chipSize + 8), y: Self.pad + Self.labelHeight + CGFloat(row) * Self.fileHeight, width: chipSize, height: Self.fileHeight - 8)
        }
        let field = NSRect(x: ChannelRowView.margin, y: Self.pad + Self.labelHeight + filesHeight, width: inner, height: textHeight + Self.fieldPad * 2)
        let side = QuietButton.micSide
        scroll.frame = field.insetBy(dx: 10, dy: Self.fieldPad)
        scroll.frame.size.width -= side
        // In the field at its right, level with the last line, so it stays by what you'd send as the box grows.
        mic.frame = NSRect(x: field.maxX - side - 4, y: field.maxY - Self.fieldPad - (textLine + side) / 2, width: side, height: side)
        textView.minSize = NSSize(width: scroll.frame.width, height: 0)
        textView.maxSize = NSSize(width: scroll.frame.width, height: .greatestFiniteMagnitude)
        alsoSend.sizeToFit()
        alsoSend.frame.origin = NSPoint(x: ChannelRowView.margin - 1 - QuietCheckbox.inset, y: field.maxY + 4)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        MessagesInk.line.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
        let field = NSRect(x: ChannelRowView.margin, y: Self.pad + Self.labelHeight + filesHeight, width: bounds.width - ChannelRowView.margin * 2, height: textHeight + Self.fieldPad * 2)
        MessagesInk.hover.setFill()
        NSBezierPath(roundedRect: field, xRadius: 9, yRadius: 9).fill()
    }

    func textDidChange(_ notification: Notification) {
        showWhereWordsGo()
        onResize?()
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            guard InputPanel.returnSends(NSApp.currentEvent?.modifierFlags ?? []) else { return false }
            send()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            if mic.isLit { onStopListening?() } else { onEscape?() }
            return true
        default:
            return false
        }
    }

    /// Sends this as if it had been typed and Return pressed.
    func send(_ text: String) {
        textView.string = text
        send()
    }

    var hasDraft: Bool { textView.string.contains { !$0.isWhitespace } || !attachments.isEmpty }

    /// Puts another place's or thread's draft in the box, with nothing to undo back into the one it replaced.
    func showDraft(_ text: String) {
        textView.string = text
        textView.undoManager?.removeAllActions()
        showWhereWordsGo()
        needsLayout = true
    }

    private func send() {
        let words = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let target, !words.isEmpty || !attachments.isEmpty, target.isReady, !isHeld else {
            NSSound.beep()
            return
        }
        textView.string = ""
        showWhereWordsGo()
        let files = takeAttachments()
        onResize?()
        onSend?(words, target, files)
    }
}

/// The box's text, which takes files or pictures dropped or pasted into it as attachments rather than as their paths.
final class ComposerTextView: PlaceholderTextView {
    var onAttach: (([Drop]) -> Bool)?

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        // A copied file is attached rather than its name pasted, but words copied with a picture, as from a web page,
        // paste as words.
        let hasFile = pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        if hasFile || pasteboard.string(forType: .string) == nil, onAttach?(Drop.all(pasteboard)) == true { return }
        super.paste(sender)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard Drop.all(sender.draggingPasteboard).contains(where: \.isFile) else { return super.draggingEntered(sender) }
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let drops = Drop.all(sender.draggingPasteboard)
        guard drops.contains(where: \.isFile) else { return super.performDragOperation(sender) }
        return onAttach?(drops) ?? false
    }
}

/// What's attached, over the box: a small picture or a file's mark, its name, and ✕ to take it off.
final class AttachmentChip: NSView {
    var onRemove: (() -> Void)?
    private let picture = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private let remove = QuietButton("✕", style: .text)

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        picture.imageScaling = .scaleProportionallyUpOrDown
        picture.wantsLayer = true
        picture.layer?.cornerRadius = 6
        picture.layer?.masksToBounds = true
        name.font = MessagesInk.font(ofSize: 13)
        name.lineBreakMode = .byTruncatingMiddle
        remove.onPress = { [weak self] in self?.onRemove?() }
        [picture, name, remove].forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func show(name: String, thumbnail: NSImage?) {
        self.name.stringValue = name
        self.name.textColor = MessagesInk.text
        picture.image = thumbnail ?? NSImage(systemSymbolName: "doc.fill", accessibilityDescription: nil)
        picture.contentTintColor = MessagesInk.soft
        setAccessibilityLabel(CatWords.attached(name))
        remove.setAccessibilityLabel(CatWords.remove(name))
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let side = bounds.height - 8
        picture.frame = NSRect(x: 4, y: 4, width: side, height: side)
        remove.setFrameOrigin(NSPoint(x: bounds.width - remove.frame.width - 2, y: (bounds.height - remove.frame.height) / 2))
        name.frame = NSRect(x: picture.frame.maxX + 8, y: (bounds.height - 18) / 2, width: remove.frame.minX - picture.frame.maxX - 12, height: 18)
    }

    override func draw(_ dirtyRect: NSRect) {
        MessagesInk.hover.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9).fill()
    }
}

/// A checkbox in Messages' colours. Like `QuietButton`, a click leaves the keyboard where it was, and Space ticks it
/// once Tab has reached it.
final class QuietCheckbox: NSView {
    private static let box: CGFloat = 14

    var title = "" { didSet { needsDisplay = true; setAccessibilityLabel(title) } }
    var isOn = false { didSet { if isOn != oldValue { needsDisplay = true; setAccessibilityValue(isOn) } } }
    var onChange: ((Bool) -> Void)?
    /// Its words' own font and colour, such as Settings', where they're the setting itself rather than a soft aside.
    var words: (font: NSFont, color: NSColor)? { didSet { needsDisplay = true } }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 160, height: 20))
        setAccessibilityElement(true)
        setAccessibilityRole(.checkBox)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { QuietFocus.allows(self) }
    override var canBecomeKeyView: Bool { QuietFocus.allows(self) && !isHiddenOrHasHiddenAncestor }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { false }

    private var label: NSAttributedString {
        NSAttributedString(string: title, attributes: [.font: words?.font ?? MessagesInk.font(ofSize: 12), .foregroundColor: words?.color ?? MessagesInk.soft])
    }

    /// Room inside it for the ring, which goes round the box and its words.
    static let inset: CGFloat = 4

    func sizeToFit() {
        setFrameSize(NSSize(width: Self.inset + Self.box + 8 + ceil(label.size().width) + 6, height: 20))
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSRect(x: Self.inset, y: (bounds.height - Self.box) / 2, width: Self.box, height: Self.box)
        let shape = NSBezierPath(roundedRect: box, xRadius: 3.5, yRadius: 3.5)
        if isOn {
            MessagesInk.accent.setFill()
            shape.fill()
            let tick = NSBezierPath()
            tick.move(to: NSPoint(x: box.minX + 3.5, y: box.midY))
            tick.line(to: NSPoint(x: box.minX + 6, y: box.maxY - 3.5))
            tick.line(to: NSPoint(x: box.maxX - 3, y: box.minY + 3.5))
            tick.lineWidth = 1.8
            ChannelSpeakerLook.readable(on: MessagesInk.theme?.accent ?? ChannelSpeakerLook.yours).setStroke()
            tick.stroke()
        } else {
            MessagesInk.line.setStroke()
            shape.lineWidth = 1.2
            shape.stroke()
        }
        let text = label
        text.draw(at: NSPoint(x: box.maxX + 7, y: (bounds.height - text.size().height) / 2))
        if QuietFocus.shows(self) { QuietFocus.ring(bounds, radius: 6) }
    }

    override func mouseDown(with event: NSEvent) {}

    override func becomeFirstResponder() -> Bool {
        QuietFocus.took(self)
        return true
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard QuietFocus.isSpace(event) else { return super.keyDown(with: event) }
        if !event.isARepeat { toggle() }
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        toggle()
    }

    override func accessibilityPerformPress() -> Bool {
        toggle()
        return true
    }

    func toggle() {
        isOn.toggle()
        onChange?(isOn)
    }
}
