import AppKit
import ShadesCore

/// Every setting in one place, a page at a time, from the menu or from Messages. A change takes as you make it, so
/// there's nothing to save, and the file itself stays easy to edit by hand. Do Not Disturb, the theme and each channel's
/// notifications go through the same switch and menus they do everywhere else.
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

    static let width: CGFloat = 440
    private static let padding: CGFloat = 18
    private static let labelWidth: CGFloat = 110
    private static var controlWidth: CGFloat { width - padding * 2 - labelWidth - 8 }

    let panel = QuietPanel(allowsKey: true)
    var onChange: ((Settings) -> Void)?
    var onDoNotDisturb: (() -> Void)?
    var onTheme: ((NSView) -> Void)?
    var onNotifications: ((ChannelID, ChannelNotifications) -> Void)?
    var onPairPhone: (() -> Void)?

    private(set) var page = Page.agents
    private(set) var form: SettingsForm?
    /// Where its top right corner stays, whichever page is showing.
    private var corner = NSPoint.zero
    private var handlers: [Handler] = []
    private let notificationsMenu = NotificationsMenu()
    private let fontMenu = FontMenu()

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

    private func rows(for page: Page, _ form: SettingsForm) -> [NSView] {
        let settings = form.settings
        switch page {
        case .agents:
            return [
                row("Front door model", modelField(settings.quickModel) { $0.quickModel = Self.model($1, fallback: $0.quickModel) }),
                row("Front door mode", popup(Self.modes, settings.quickMode) { $0.quickMode = $1 }),
                row("Frontier model", modelField(settings.frontierModel) { $0.frontierModel = Self.model($1, fallback: $0.frontierModel) }),
                row("Frontier mode", popup(Self.modes, settings.frontierMode) { $0.frontierMode = $1 }),
                row("Summary model", modelField(settings.summaryModel) { $0.summaryModel = Self.model($1, fallback: $0.summaryModel) }),
            ]
        case .voice:
            return [
                row("Hold to talk", popup(Self.keys, settings.talkKey) { $0.talkKey = $1 }),
                row("Hold to dictate", popup(Self.keys, settings.dictateKey) { $0.dictateKey = $1 }),
                row("Extra words", field(settings.vocabulary.joined(separator: ", "), "Words I should know") { $0.vocabulary = Self.list($1) }),
            ]
        case .notifications:
            let quiet = checkbox(CatWords.doNotDisturb, settings.doNotDisturb) { [weak self] _ in self?.onDoNotDisturb?() }
            let finished = checkbox("Also when a session finishes", settings.notifyFinished) { [weak self] on in
                self?.edit { $0.notifyFinished = on }
            }
            var rows = [row(CatWords.notifications, quiet), row("", finished), heading(CatWords.channelsHeading)]
            // shortcut: a row a channel, so dozens of kittens would make it taller than the screen. Scroll them then.
            for channel in form.channels {
                let current = settings.notifications(for: channel.id.settingsKey)
                let summary = Self.summary(current, phone: settings.phone)
                let button = menuButton(summary) { [weak self] anchor in
                    self?.notificationsMenu.show(current, phone: settings.phone, under: anchor) { [weak self] picked in
                        self?.onNotifications?(channel.id, picked)
                    }
                }
                button.setAccessibilityLabel("\(channel.title): \(summary)")
                rows.append(row(channel.title, button))
            }
            return rows
        case .messages:
            let theme = menuButton(form.theme ?? CatWords.plainTheme) { [weak self] anchor in self?.onTheme?(anchor) }
            let font = menuButton(settings.messagesFont ?? MessagesInk.systemFaces[0].name) { [weak self] anchor in
                self?.fontMenu.show(current: settings.messagesFont, under: anchor) { [weak self] picked in
                    self?.edit { $0.messagesFont = picked }
                    // Its button says the font, and its own change doesn't make the page again by itself.
                    self?.build()
                }
            }
            let phone = checkbox("\(CatWords.appName) on my phone, over Tailscale", settings.phone) { [weak self] on in
                self?.edit { $0.phone = on }
            }
            var rows = [
                row(CatWords.themeButton, theme),
                row("Font", font),
                row("Text size", popup(Self.sizes, settings.textSize) { $0.textSize = $1 }),
                row("Open threads", popup(Self.opens, settings.openInMessages) { $0.openInMessages = $1 }),
                row("Phone", phone),
            ]
            if settings.phone {
                rows.append(row("", plainButton("Pair a phone...", style: .text) { [weak self] in self?.onPairPhone?() }))
            }
            return rows
        case .privacy:
            let apps = field(settings.privateApps.joined(separator: ", "), "Bundle IDs, comma separated", lines: 4) { $0.privateApps = Self.list($1) }
            return [
                row("Private apps", apps),
                row("", note("Nothing is captured while one of these apps is in front.")),
            ]
        }
    }

    private static let modes: [(String, RuntimeMode)] = RuntimeMode.allCases.map { (modeName($0), $0) }
    private static let keys: [(String, HoldKey)] = HoldKey.allCases.map { (keyName($0), $0) }
    private static let sizes: [(String, TextSize)] = [("Small", .small), ("Default", .standard), ("Large", .large), ("Larger", .larger)]
    private static let opens: [(String, Bool)] = [("In \(CatWords.appName) first", true), ("In T3", false)]

    // MARK: - Building

    private func build() {
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
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: Self.padding, left: Self.padding, bottom: Self.padding, right: Self.padding)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let tabs = NSSegmentedControl(labels: Page.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
        tabs.selectedSegment = page.rawValue
        tabs.segmentDistribution = .fillEqually
        tabs.setAccessibilityLabel("Settings")
        tabs.widthAnchor.constraint(equalToConstant: Self.width - Self.padding * 2).isActive = true
        bind(tabs) { [weak self, weak tabs] in
            guard let tabs, let page = Page(rawValue: tabs.selectedSegment) else { return }
            self?.select(page)
        }
        stack.addArrangedSubview(tabs)
        stack.setCustomSpacing(16, after: tabs)

        rows(for: page, form).forEach(stack.addArrangedSubview)

        let done = plainButton("Done", style: .filled) { [weak self] in self?.hide() }
        let reveal = plainButton("Open the file", style: .text) { NSWorkspace.shared.open(Settings.directory) }
        let buttons = NSStackView(views: [done, reveal])
        buttons.spacing = 6
        stack.addArrangedSubview(buttons)
        stack.setCustomSpacing(16, after: stack.arrangedSubviews[stack.arrangedSubviews.count - 2])

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
        panel.makeFirstResponder(root)
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

    private func row(_ title: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12)
        label.textColor = Ink.soft
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: Self.labelWidth).isActive = true
        if !title.isEmpty {
            // The demo finds a control by what its row is called.
            control.setAccessibilityIdentifier(title)
            if !(control is QuietButton) { control.setAccessibilityLabel(title) }
        }
        let line = NSStackView(views: [label, control])
        line.spacing = 8
        line.alignment = control is QuietButton ? .centerY : (control as? NSTextField)?.usesSingleLineMode == false ? .top : .firstBaseline
        return line
    }

    private func heading(_ text: String) -> NSView {
        let label = NSTextField(labelWithAttributedString: NSAttributedString(string: text.uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: Ink.soft,
            .kern: 0.5,
        ]))
        let line = NSStackView(views: [label])
        line.edgeInsets = NSEdgeInsets(top: 6, left: Self.labelWidth + 8, bottom: 0, right: 0)
        return line
    }

    private func note(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = Ink.soft
        label.widthAnchor.constraint(equalToConstant: Self.controlWidth).isActive = true
        return label
    }

    private func modelField(_ model: ModelChoice, onEnd: @escaping (inout Settings, String) -> Void) -> NSTextField {
        field("\(model.provider) / \(model.model) / \(model.effort)", "provider / model / effort", onEnd: onEnd)
    }

    /// Takes what's typed when you press Return or move on, and when Settings closes.
    private func field(_ value: String, _ placeholder: String, lines: Int = 1, onEnd: @escaping (inout Settings, String) -> Void) -> NSTextField {
        let field = NSTextField(string: value)
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 12)
        field.bezelStyle = .roundedBezel
        field.widthAnchor.constraint(equalToConstant: Self.controlWidth).isActive = true
        if lines > 1 {
            field.bezelStyle = .squareBezel
            field.usesSingleLineMode = false
            field.lineBreakMode = .byWordWrapping
            field.cell?.wraps = true
            field.cell?.isScrollable = false
            field.heightAnchor.constraint(equalToConstant: CGFloat(lines) * 16 + 6).isActive = true
        } else {
            field.usesSingleLineMode = true
            field.lineBreakMode = .byTruncatingTail
        }
        field.cell?.sendsActionOnEndEditing = true
        bind(field) { [weak self, weak field] in
            guard let text = field?.stringValue else { return }
            self?.edit { onEnd(&$0, text) }
        }
        return field
    }

    private func popup<T: Equatable>(_ choices: [(String, T)], _ selected: T, onPick: @escaping (inout Settings, T) -> Void) -> NSPopUpButton {
        let popup = NSPopUpButton()
        popup.font = .systemFont(ofSize: 12)
        choices.forEach { popup.addItem(withTitle: $0.0) }
        popup.selectItem(at: choices.firstIndex { $0.1 == selected } ?? 0)
        popup.widthAnchor.constraint(equalToConstant: 200).isActive = true
        bind(popup) { [weak self, weak popup] in
            guard let index = popup?.indexOfSelectedItem, choices.indices.contains(index) else { return }
            self?.edit { onPick(&$0, choices[index].1) }
        }
        return popup
    }

    private func checkbox(_ title: String, _ on: Bool, onToggle: @escaping (Bool) -> Void) -> NSButton {
        let box = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        box.font = .systemFont(ofSize: 12)
        box.state = on ? .on : .off
        bind(box) { [weak box] in onToggle(box?.state == .on) }
        return box
    }

    /// A button that opens a menu under itself, the way Theme and Notifications do in Messages.
    private func menuButton(_ title: String, onPress: @escaping (NSView) -> Void) -> QuietButton {
        let button = plainButton("\(title) ▾", style: .plain) {}
        button.setAccessibilityRole(.popUpButton)
        button.onPress = { [weak button] in
            guard let button else { return }
            onPress(button)
        }
        return button
    }

    private func plainButton(_ title: String, style: QuietButton.Style, onPress: @escaping () -> Void) -> QuietButton {
        let button = QuietButton(title, style: style, onPress: onPress)
        button.widthAnchor.constraint(equalToConstant: min(button.frame.width, Self.controlWidth)).isActive = true
        button.heightAnchor.constraint(equalToConstant: button.frame.height).isActive = true
        return button
    }

    private func bind(_ control: NSControl, run: @escaping () -> Void) {
        let handler = Handler(run)
        handlers.append(handler)
        control.target = handler
        control.action = #selector(Handler.fire)
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

    private static func keyName(_ key: HoldKey) -> String {
        switch key {
        case .fn: return "fn"
        case .rightOption: return "Right Option"
        case .rightCommand: return "Right Command"
        case .rightControl: return "Right Control"
        case .off: return "Off"
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
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
    /// Esc closes it, while no box has the keyboard too.
    override func keyDown(with event: NSEvent) { interpretKeyEvents([event]) }
    /// Tab still goes round the page from here, which nothing else in the chain does once a key is read this way.
    override func insertTab(_ sender: Any?) { window?.selectNextKeyView(sender) }
    override func insertBacktab(_ sender: Any?) { window?.selectPreviousKeyView(sender) }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: BalloonView.radius, yRadius: BalloonView.radius)
        Ink.paper.setFill()
        path.fill()
        Ink.line.setStroke()
        path.stroke()
    }
}
