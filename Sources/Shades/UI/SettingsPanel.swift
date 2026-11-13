import AppKit
import ShadesCore

/// Every setting in one place, a page at a time, from the menu or from Messages. A change takes as you make it, so
/// there's nothing to save, and the file itself stays easy to edit by hand. Do Not Disturb and each channel's
/// notifications go through the same switch and menus they do everywhere else. It's Opal's floating glass, laid out as
/// macOS's own Settings is, with underlined tabs, and every choice from a menu is the same quiet button.
@MainActor
final class SettingsPanel: NSObject, NSWindowDelegate {
    enum Page: Int, CaseIterable {
        case agents, voice, notifications, messages, privacy

        var title: String {
            switch self {
            case .agents: "Agents"
            case .voice: "Voice"
            case .notifications: CatWords.notifications
            case .messages: CatWords.appName
            case .privacy: "Privacy"
            }
        }
    }

    static let width: CGFloat = 480
    private static let padding: CGFloat = 24
    private static var contentWidth: CGFloat { width - padding * 2 }
    /// A box beside its setting's name.
    private static let fieldWidth: CGFloat = 230

    /// Its window, which tests give one that never reaches the screen.
    let panel: QuietPanel
    var onChange: ((Settings) -> Void)?
    var onDoNotDisturb: (() -> Void)?
    var onNotifications: ((ChannelID, ChannelNotifications) -> Void)?
    var onPairPhone: (() -> Void)?
    /// Where Open settings folder shows the folder. Tests stand in for Finder.
    var openFolder: (URL) -> Void = { NSWorkspace.shared.open($0) }

    private(set) var page = Page.agents
    private(set) var form: SettingsForm?
    /// Where its top right corner stays, whichever page is showing.
    private var corner = NSPoint.zero
    private var handlers: [Handler] = []
    private let notificationsMenu = NotificationsMenu()
    private let fontMenu = FontMenu()

    init(panel: QuietPanel? = nil) {
        let panel = panel ?? QuietPanel(allowsKey: true)
        self.panel = panel
        super.init()
    }

    func show(_ form: SettingsForm, near corner: NSPoint) {
        self.form = form
        self.corner = corner
        build()
        panel.makeKeyAndOrderFront(nil)
    }

    /// Shows a change made anywhere. Its own changes are already showing, so they don't build it again under your typing.
    func update(_ form: SettingsForm) {
        guard isVisible, form != self.form else { return }
        self.form = form
        build()
    }

    func select(_ page: Page) {
        self.page = page
        build()
    }

    var isVisible: Bool { panel.isVisible }

    func hide() {
        endEditing()
        panel.orderOut(nil)
    }

    /// A box you're typing in keeps what's typed.
    private func endEditing() {
        if panel.isVisible { panel.makeFirstResponder(nil) }
    }

    private func edit(_ change: (inout Settings) -> Void) {
        guard var form else { return }
        change(&form.settings)
        guard form != self.form else { return }
        self.form = form
        onChange?(form.settings)
    }

    // MARK: - Pages

    /// Settings that go together, under small capitals if they need them.
    private struct Group {
        var label: String?
        var rows: [NSView]
    }

    private func groups(for page: Page, _ form: SettingsForm) -> [Group] {
        let settings = form.settings
        switch page {
        case .agents:
            let quick = modelField(settings.quickModel) { $0.quickModel = Self.model($1, fallback: $0.quickModel) }
            let frontier = modelField(settings.frontierModel) { $0.frontierModel = Self.model($1, fallback: $0.frontierModel) }
            let summary = modelField(settings.summaryModel) { $0.summaryModel = Self.model($1, fallback: $0.summaryModel) }
            return [
                Group(label: "Front door", rows: [
                    stacked("Model", note: "Answers you, and passes real work on. It has to be a Claude model.", quick, id: "Front door model"),
                    row("Mode", popup(Self.modes, settings.quickMode) { $0.quickMode = $1 }, id: "Front door mode"),
                ]),
                Group(label: "Frontier", rows: [
                    stacked("Model", note: "Does the real work you hand off.", frontier, id: "Frontier model"),
                    row("Mode", popup(Self.modes, settings.frontierMode) { $0.frontierMode = $1 }, id: "Frontier mode"),
                ]),
                Group(label: "Summaries", rows: [
                    stacked("Model", note: "Sums up each session's report when it ends.", summary, id: "Summary model"),
                ]),
            ]
        case .voice:
            let talk = popup(Self.keys, settings.talkKey) { $0.talkKey = $1 }
            let dictate = popup(Self.keys, settings.dictateKey) { $0.dictateKey = $1 }
            let words = field(settings.vocabulary.joined(separator: ", "), "Words I should know") { $0.vocabulary = Self.list($1) }
            return [Group(rows: [
                row("Hold to talk", note: "Talk to me while you hold it.", talk),
                row("Hold to dictate", note: "Type by voice into any app while you hold it.", dictate),
                row("Extra words", note: "Names to listen for, separated by commas.", words),
            ])]
        case .notifications:
            let quiet = toggle(CatWords.doNotDisturb, settings.doNotDisturb) { [weak self] _ in self?.onDoNotDisturb?() }
            let finished = toggle(Self.finishedTitle, settings.notifyFinished) { [weak self] on in
                self?.edit { $0.notifyFinished = on }
            }
            // shortcut: a row a channel, so dozens of kittens would make it taller than the screen. Scroll them then.
            let channels = form.channels.map { channel in
                let current = settings.notifications(for: channel.id.settingsKey)
                let button = menuButton(Self.summary(current, phone: settings.phone)) { [weak self] anchor in
                    self?.notificationsMenu.show(current, phone: settings.phone, under: anchor) { [weak self] picked in
                        self?.onNotifications?(channel.id, picked)
                    }
                }
                return row(channel.title, button)
            }
            return [
                Group(rows: [
                    row(CatWords.doNotDisturb, note: "Nothing pops up until you turn it off. What came in waits in Activity.", quiet),
                    row(Self.finishedTitle, note: "Anything that needs you always notifies.", finished),
                ]),
                Group(label: CatWords.kittensHeading, rows: channels),
            ]
        case .messages:
            let font = menuButton(settings.messagesFont ?? MessagesInk.systemFaces[0].name) { [weak self] anchor in
                self?.fontMenu.show(current: settings.messagesFont, under: anchor) { [weak self] picked in
                    self?.edit { $0.messagesFont = picked }
                    // Its button says the font, and its own change doesn't make the page again by itself.
                    self?.build()
                }
            }
            let phone = toggle(Self.phoneTitle, settings.phone) { [weak self] on in
                self?.edit { $0.phone = on }
                // Pairing a phone comes and goes with it.
                self?.build()
            }
            var phoneRows = [row(Self.phoneTitle, note: "In your phone's browser, over Tailscale.", phone, id: "Phone")]
            if settings.phone {
                phoneRows.append(row("Pair a phone", note: "Scan a one-time code with its camera.", plainButton("Pair…", style: .plain) { [weak self] in self?.onPairPhone?() }))
            }
            return [
                Group(rows: [
                    row("Font", font),
                    row("Text size", segments(Self.sizes, settings.textSize) { $0.textSize = $1 }),
                    row("Open threads in", note: "Threads it doesn't follow open in T3.", segments(Self.opens, settings.openInMessages) { $0.openInMessages = $1 }),
                ]),
                Group(label: "Phone", rows: phoneRows),
            ]
        case .privacy:
            let apps = field(settings.privateApps.joined(separator: ", "), "Bundle IDs, comma separated", lines: 4) { $0.privateApps = Self.list($1) }
            return [Group(rows: [stacked("Private apps", note: "Nothing is captured while one of these apps is in front.", apps)])]
        }
    }

    private static let finishedTitle = "When a session finishes"
    private static let phoneTitle = "\(CatWords.appName) on my phone"
    private static let modes: [(String, RuntimeMode)] = RuntimeMode.allCases.map { (modeName($0), $0) }
    private static let keys: [(String, HoldKey)] = HoldKey.allCases.map { (CatWords.keyName($0), $0) }
    private static let sizes: [(String, TextSize)] = [("Small", .small), ("Default", .standard), ("Large", .large), ("Larger", .larger)]
    private static let opens: [(String, Bool)] = [(CatWords.appName, true), ("T3", false)]

    // MARK: - Building

    private func build() {
        // A control Tab reached still has the keyboard once its pick makes the page again.
        let focused = (panel.firstResponder as? NSView)?.accessibilityIdentifier() ?? ""
        // What's typed so far goes in before the page is made again from what's set.
        endEditing()
        guard let form else { return }
        // A control can build the page again from its own action, so the page it was on lives out this turn.
        let retired = (panel.contentView, handlers)
        DispatchQueue.main.async { withExtendedLifetime(retired) {} }
        handlers = []
        let root = SettingsRootView { [weak self] in self?.hide() }
        panel.contentView = root
        panel.delegate = self
        root.wantsLayer = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 14, left: Self.padding, bottom: 20, right: Self.padding)
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(tabs())
        stack.addArrangedSubview(hairline())
        for (index, group) in groups(for: page, form).enumerated() {
            let top: CGFloat = index == 0 ? 6 : 14
            if let label = group.label {
                let words = NSTextField(labelWithAttributedString: MessagesInk.label(label))
                stack.addArrangedSubview(words)
                stack.setCustomSpacing(top + 8, after: stack.arrangedSubviews[stack.arrangedSubviews.count - 2])
                stack.setCustomSpacing(0, after: words)
            } else if let last = stack.arrangedSubviews.last {
                stack.setCustomSpacing(top, after: last)
            }
            for (number, row) in group.rows.enumerated() {
                if number > 0 { stack.addArrangedSubview(hairline()) }
                stack.addArrangedSubview(row)
            }
        }

        // Done on the right, as macOS puts the button that finishes, and the folder on the left.
        let reveal = plainButton("Open settings folder", style: .text) { [weak self] in self?.openFolder(Settings.directory) }
        let done = plainButton("Done", style: .filled) { [weak self] in self?.hide() }
        let gap = NSView()
        gap.setContentHuggingPriority(.init(1), for: .horizontal)
        let buttons = NSStackView(views: [reveal, gap, done])
        buttons.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
        stack.addArrangedSubview(buttons)
        stack.setCustomSpacing(20, after: stack.arrangedSubviews[stack.arrangedSubviews.count - 2])

        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            root.widthAnchor.constraint(equalToConstant: Self.width),
        ])
        root.layoutSubtreeIfNeeded()
        panel.setContentSize(root.fittingSize)
        place()
        panel.invalidateShadow()
        // No box has the keyboard until you click into one, so a stray key can't type over a model.
        panel.initialFirstResponder = root
        panel.recalculateKeyViewLoop()
        func all(_ view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(all) }
        let again = focused.isEmpty ? nil : all(root).first { $0.accessibilityIdentifier() == focused && $0.acceptsFirstResponder }
        panel.makeFirstResponder(again ?? root)
    }

    /// Each page's name, underlined while it's open.
    private func tabs() -> NSView {
        let tabs = Page.allCases.map { page in
            let tab = SettingsTab(page.title)
            tab.isOpen = page == self.page
            tab.setAccessibilityIdentifier("tab \(page.title)")
            tab.onPress = { [weak self] in self?.select(page) }
            tab.widthAnchor.constraint(equalToConstant: tab.frame.width).isActive = true
            tab.heightAnchor.constraint(equalToConstant: tab.frame.height).isActive = true
            return tab
        }
        let row = NSStackView(views: tabs)
        row.spacing = 20
        row.setAccessibilityElement(true)
        row.setAccessibilityRole(.tabGroup)
        row.setAccessibilityLabel("Settings")
        return row
    }

    private func hairline() -> NSView {
        let line = SettingsHairline()
        line.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    /// Hangs from its corner, kept on the screen.
    private func place() {
        let size = panel.frame.size
        var origin = NSPoint(x: corner.x - size.width, y: corner.y - size.height)
        if let visible = (NSScreen.screens.first { $0.frame.contains(corner) } ?? NSScreen.main)?.visibleFrame {
            origin.x = max(origin.x, visible.minX + 8)
            origin.y = max(origin.y, visible.minY + 8)
        }
        panel.setFrameOrigin(origin)
    }

    /// One setting as macOS's own Settings lays it out: its name, and a line on what it does if it needs one, on the
    /// left, and its control on the right. `id` is what the demo and VoiceOver call it, where its name needs its group.
    private func row(_ title: String, note: String? = nil, _ control: NSView, id: String? = nil) -> NSView {
        name(control, id ?? title)
        let controlWidth = control.constraints.first { $0.firstAttribute == .width }?.constant ?? control.frame.width
        let words = self.words(title, note, width: Self.contentWidth - controlWidth - 16)
        let line = NSStackView(views: [words, control])
        line.alignment = .centerY
        line.spacing = 16
        line.distribution = .fill
        line.edgeInsets = NSEdgeInsets(top: 9, left: 0, bottom: 9, right: 0)
        words.setContentHuggingPriority(.init(1), for: .horizontal)
        line.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
        line.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        return line
    }

    /// A setting whose control needs the whole width, such as a long list, under its name.
    private func stacked(_ title: String, note: String?, _ control: NSView, id: String? = nil) -> NSView {
        name(control, id ?? title)
        let line = NSStackView(views: [words(title, note, width: Self.contentWidth), control])
        line.orientation = .vertical
        line.alignment = .leading
        line.spacing = 10
        line.edgeInsets = NSEdgeInsets(top: 9, left: 0, bottom: 9, right: 0)
        return line
    }

    /// The demo finds a control by what its row is called, and VoiceOver says it before what's picked. A switch says
    /// its own words.
    private func name(_ control: NSView, _ id: String) {
        control.setAccessibilityIdentifier(id)
        if !(control is QuietSwitch) { control.setAccessibilityLabel(id) }
    }

    /// A setting's name in the body's size and colour, with what it does under it in a quieter line.
    private func words(_ title: String, _ note: String?, width: CGFloat) -> NSView {
        let name = NSTextField(labelWithString: title)
        name.font = MessagesInk.font(ofSize: MessagesInk.body)
        name.textColor = MessagesInk.text
        name.lineBreakMode = .byTruncatingTail
        guard let note else { return name }
        let line = NSTextField(wrappingLabelWithString: note)
        line.font = MessagesInk.font(ofSize: MessagesInk.meta)
        line.textColor = MessagesInk.soft
        line.preferredMaxLayoutWidth = width
        let words = NSStackView(views: [name, line])
        words.orientation = .vertical
        words.alignment = .leading
        words.spacing = 2
        return words
    }

    private func modelField(_ model: ModelChoice, onEnd: @escaping (inout Settings, String) -> Void) -> NSTextField {
        field("\(model.provider) / \(model.model) / \(model.effort)", "provider / model / effort", wide: true, onEnd: onEnd)
    }

    /// Takes what's typed when you press Return or move on, and when Settings closes. A wide one takes the whole width
    /// under its name, and one of more than one line also grows to fit what's in it, with a line spare for the next, so
    /// nothing in it hides past its edge.
    private func field(_ value: String, _ placeholder: String, lines: Int = 1, wide: Bool = false, onEnd: @escaping (inout Settings, String) -> Void) -> NSTextField {
        let field = OpalField(value, placeholder: placeholder)
        let width = lines > 1 || wide ? Self.contentWidth : Self.fieldWidth
        let font = field.font ?? MessagesInk.font(ofSize: MessagesInk.body)
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
        if lines > 1 {
            field.usesSingleLineMode = false
            field.lineBreakMode = .byWordWrapping
            field.cell?.wraps = true
            field.cell?.isScrollable = false
            // Its words laid out as a text view does, which wraps a little sooner than the box draws them, where the
            // cell's own measure of itself can come up a line short.
            let edge = NSRect(x: 0, y: 0, width: width, height: 1000)
            let inside = field.cell?.drawingRect(forBounds: edge) ?? edge
            let words = NSTextStorage(attributedString: field.attributedStringValue)
            let layout = NSLayoutManager()
            let container = NSTextContainer(size: NSSize(width: inside.width, height: .greatestFiniteMagnitude))
            layout.addTextContainer(container)
            words.addLayoutManager(layout)
            layout.ensureLayout(for: container)
            let spare = layout.defaultLineHeight(for: font)
            let fits = ceil(layout.usedRect(for: container).height + spare) + edge.height - inside.height
            field.heightAnchor.constraint(equalToConstant: max(CGFloat(lines) * spare + edge.height - inside.height, fits)).isActive = true
        } else {
            field.usesSingleLineMode = true
            field.lineBreakMode = .byTruncatingTail
            field.cell?.isScrollable = true
            field.heightAnchor.constraint(equalToConstant: ceil(font.ascender - font.descender + font.leading) + 12).isActive = true
        }
        field.cell?.sendsActionOnEndEditing = true
        bind(field) { [weak self, weak field] in
            guard let text = field?.stringValue else { return }
            self?.edit { onEnd(&$0, text) }
        }
        return field
    }

    /// Choices with the one that's set ticked, opening over the button the way a pop-up's menu does.
    private func popup<T: Equatable>(_ choices: [(String, T)], _ selected: T, onPick: @escaping (inout Settings, T) -> Void) -> QuietButton {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (title, value) in choices {
            let item = NSMenuItem(title: title, action: #selector(Handler.fire), keyEquivalent: "")
            item.state = value == selected ? .on : .off
            item.target = handler { [weak self] in
                self?.edit { onPick(&$0, value) }
                // Its button says the choice, and its own change doesn't make the page again by itself.
                self?.build()
            }
            menu.addItem(item)
        }
        let picked = menu.items.first { $0.state == .on } ?? menu.items[0]
        let button = menuButton(picked.title) { anchor in
            menu.popUp(positioning: picked, at: NSPoint(x: 0, y: anchor.bounds.height), in: anchor)
        }
        // Where a right-click, VoiceOver's show menu and the demo find it too.
        button.menu = menu
        return button
    }

    /// A few close choices side by side, the way Opal picks one of a handful.
    private func segments<T: Equatable>(_ choices: [(String, T)], _ selected: T, onPick: @escaping (inout Settings, T) -> Void) -> QuietSegments {
        let segments = QuietSegments(choices.map(\.0), selected: choices.firstIndex { $0.1 == selected } ?? 0)
        segments.onPick = { [weak self] index in
            self?.edit { onPick(&$0, choices[index].1) }
            // A new text size reaches Settings' own words too.
            self?.build()
        }
        segments.widthAnchor.constraint(equalToConstant: segments.frame.width).isActive = true
        segments.heightAnchor.constraint(equalToConstant: segments.frame.height).isActive = true
        return segments
    }

    /// On or off, for a whole row.
    private func toggle(_ title: String, _ on: Bool, onToggle: @escaping (Bool) -> Void) -> QuietSwitch {
        let toggle = QuietSwitch()
        toggle.title = title
        toggle.isOn = on
        toggle.onChange = onToggle
        toggle.widthAnchor.constraint(equalToConstant: toggle.frame.width).isActive = true
        toggle.heightAnchor.constraint(equalToConstant: toggle.frame.height).isActive = true
        return toggle
    }

    /// A button that opens a menu, saying what's picked, with a pop-up's chevrons.
    private func menuButton(_ title: String, onPress: @escaping (NSView) -> Void) -> QuietButton {
        let button = QuietButton(title, style: .plain)
        button.showsChevrons = true
        button.widthAnchor.constraint(equalToConstant: min(button.frame.width, Self.contentWidth - 150)).isActive = true
        button.heightAnchor.constraint(equalToConstant: button.frame.height).isActive = true
        button.setAccessibilityRole(.popUpButton)
        button.setAccessibilityValue(title)
        button.onPress = { [weak button] in
            guard let button else { return }
            onPress(button)
        }
        return button
    }

    private func plainButton(_ title: String, style: QuietButton.Style, onPress: @escaping () -> Void) -> QuietButton {
        let button = QuietButton(title, style: style, onPress: onPress)
        button.widthAnchor.constraint(equalToConstant: min(button.frame.width, Self.contentWidth)).isActive = true
        button.heightAnchor.constraint(equalToConstant: button.frame.height).isActive = true
        return button
    }

    private func bind(_ control: NSControl, run: @escaping () -> Void) {
        control.target = handler(run)
        control.action = #selector(Handler.fire)
    }

    private func handler(_ run: @escaping () -> Void) -> Handler {
        let handler = Handler(run)
        handlers.append(handler)
        return handler
    }

    // MARK: - Words

    /// What a channel's button says it tells you. The phone only shows once it's on, and only where it differs.
    static func summary(_ notifications: ChannelNotifications, phone: Bool) -> String {
        if notifications.muted { return CatWords.muted }
        guard phone, notifications.phone != notifications.mac else { return CatWords.notifyLevel(notifications.mac) }
        return "Mac: \(CatWords.notifyLevel(notifications.mac)) · Phone: \(CatWords.notifyLevel(notifications.phone))"
    }

    private static func list(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// Reads "provider / model / effort". Anything else keeps what was there.
    nonisolated static func model(_ text: String, fallback: ModelChoice) -> ModelChoice {
        let parts = text.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty }) else { return fallback }
        return ModelChoice(provider: parts[0], model: parts[1], effort: parts[2])
    }

    private static func modeName(_ mode: RuntimeMode) -> String {
        switch mode {
        case .approvalRequired: return "Ask before everything"
        case .autoAcceptEdits: return "Accept edits"
        case .auto: return "Auto"
        case .fullAccess: return "Full access"
        }
    }
}

/// A control's action as a closure, kept for as long as the page it's on.
private final class Handler: NSObject {
    private let run: () -> Void

    init(_ run: @escaping () -> Void) {
        self.run = run
    }

    @objc func fire() { run() }
}

private final class SettingsRootView: NSView {
    private let onCancel: () -> Void

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func cancelOperation(_ sender: Any?) { onCancel() }
    /// ⌘W closes it, as it does any window on the Mac, from a box too. There's no menu of ours for it to come through.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.charactersIgnoringModifiers == "w" else {
            return super.performKeyEquivalent(with: event)
        }
        onCancel()
        return true
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
    /// It holds the keyboard as Settings opens, but shows no ring, so Tab goes round without stopping on it.
    override var canBecomeKeyView: Bool { false }
    /// Esc closes it, while no box has the keyboard too.
    override func keyDown(with event: NSEvent) { interpretKeyEvents([event]) }
    /// Tab still goes round the page from here, which nothing else in the chain does once a key is read this way.
    override func insertTab(_ sender: Any?) { window?.selectNextKeyView(sender) }
    override func insertBacktab(_ sender: Any?) { window?.selectPreviousKeyView(sender) }

    override func draw(_ dirtyRect: NSRect) {
        Opal.glass(NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: BalloonView.radius, yRadius: BalloonView.radius))
    }
}

/// A 1-point line between settings, in Opal's border.
private final class SettingsHairline: NSView {
    override func draw(_ dirtyRect: NSRect) {
        MessagesInk.line.setFill()
        bounds.fill()
    }
}
