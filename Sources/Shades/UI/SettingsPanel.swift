import AppKit
import ShadesCore

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
    private static let fieldWidth: CGFloat = 230

    let panel: QuietPanel
    var onChange: ((Settings) -> Void)?
    var onDoNotDisturb: (() -> Void)?
    var onNotifications: ((ChannelID, ChannelNotifications) -> Void)?
    var onPairPhone: (() -> Void)?
    var openFolder: (URL) -> Void = { NSWorkspace.shared.open($0) }

    private(set) var page = Page.agents
    private(set) var form: SettingsForm?
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
                    row("Mode", note: "Full access never gets your screen. A thread that carries it runs in Auto.", popup(Self.modes, settings.frontierMode) { $0.frontierMode = $1 }, id: "Frontier mode"),
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
                    self?.build()
                }
            }
            let phone = toggle(Self.phoneTitle, settings.phone) { [weak self] on in
                self?.edit { $0.phone = on }
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
                    row("Replies while it works", note: "Steer joins its run, Queue waits for it. ⌘Return does the other.", segments(Self.followUps, settings.followUpBehavior) { $0.followUpBehavior = $1 }),
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
    private static let followUps: [(String, FollowUpBehavior)] = [("Steer", .steer), ("Queue", .queue)]

    private func build() {
        let focused = (panel.firstResponder as? NSView)?.accessibilityIdentifier() ?? ""
        endEditing()
        guard let form else { return }
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
        panel.initialFirstResponder = root
        panel.recalculateKeyViewLoop()
        func all(_ view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(all) }
        let again = focused.isEmpty ? nil : all(root).first { $0.accessibilityIdentifier() == focused && $0.acceptsFirstResponder }
        panel.makeFirstResponder(again ?? root)
    }

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

    private func place() {
        let size = panel.frame.size
        var origin = NSPoint(x: corner.x - size.width, y: corner.y - size.height)
        if let visible = (NSScreen.screens.first { $0.frame.contains(corner) } ?? NSScreen.main)?.visibleFrame {
            origin.x = max(origin.x, visible.minX + 8)
            origin.y = max(origin.y, visible.minY + 8)
        }
        panel.setFrameOrigin(origin)
    }

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

    private func stacked(_ title: String, note: String?, _ control: NSView, id: String? = nil) -> NSView {
        name(control, id ?? title)
        let line = NSStackView(views: [words(title, note, width: Self.contentWidth), control])
        line.orientation = .vertical
        line.alignment = .leading
        line.spacing = 10
        line.edgeInsets = NSEdgeInsets(top: 9, left: 0, bottom: 9, right: 0)
        return line
    }

    private func name(_ control: NSView, _ id: String) {
        control.setAccessibilityIdentifier(id)
        if !(control is QuietSwitch) { control.setAccessibilityLabel(id) }
    }

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
            // Outside the repo: an NSTextField cell's own measure of wrapped words can come up a line short.
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

    private func popup<T: Equatable>(_ choices: [(String, T)], _ selected: T, onPick: @escaping (inout Settings, T) -> Void) -> QuietButton {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (title, value) in choices {
            let item = NSMenuItem(title: title, action: #selector(Handler.fire), keyEquivalent: "")
            item.state = value == selected ? .on : .off
            item.target = handler { [weak self] in
                self?.edit { onPick(&$0, value) }
                self?.build()
            }
            menu.addItem(item)
        }
        let picked = menu.items.first { $0.state == .on } ?? menu.items[0]
        let button = menuButton(picked.title) { anchor in
            menu.popUp(positioning: picked, at: NSPoint(x: 0, y: anchor.bounds.height), in: anchor)
        }
        button.menu = menu
        return button
    }

    private func segments<T: Equatable>(_ choices: [(String, T)], _ selected: T, onPick: @escaping (inout Settings, T) -> Void) -> QuietSegments {
        let segments = QuietSegments(choices.map(\.0), selected: choices.firstIndex { $0.1 == selected } ?? 0)
        segments.onPick = { [weak self] index in
            self?.edit { onPick(&$0, choices[index].1) }
            self?.build()
        }
        segments.widthAnchor.constraint(equalToConstant: segments.frame.width).isActive = true
        segments.heightAnchor.constraint(equalToConstant: segments.frame.height).isActive = true
        return segments
    }

    private func toggle(_ title: String, _ on: Bool, onToggle: @escaping (Bool) -> Void) -> QuietSwitch {
        let toggle = QuietSwitch()
        toggle.title = title
        toggle.isOn = on
        toggle.onChange = onToggle
        toggle.widthAnchor.constraint(equalToConstant: toggle.frame.width).isActive = true
        toggle.heightAnchor.constraint(equalToConstant: toggle.frame.height).isActive = true
        return toggle
    }

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

    static func summary(_ notifications: ChannelNotifications, phone: Bool) -> String {
        if notifications.muted { return CatWords.muted }
        guard phone, notifications.phone != notifications.mac else { return CatWords.notifyLevel(notifications.mac) }
        return "Mac: \(CatWords.notifyLevel(notifications.mac)) · Phone: \(CatWords.notifyLevel(notifications.phone))"
    }

    private static func list(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

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
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.charactersIgnoringModifiers == "w" else {
            return super.performKeyEquivalent(with: event)
        }
        onCancel()
        return true
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { false }
    override func keyDown(with event: NSEvent) { interpretKeyEvents([event]) }
    // Outside the repo: once interpretKeyEvents reads Tab, nothing else in the responder chain moves to the next view.
    override func insertTab(_ sender: Any?) { window?.selectNextKeyView(sender) }
    override func insertBacktab(_ sender: Any?) { window?.selectPreviousKeyView(sender) }

    override func draw(_ dirtyRect: NSRect) {
        Opal.glass(NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: BalloonView.radius, yRadius: BalloonView.radius))
    }
}

private final class SettingsHairline: NSView {
    override func draw(_ dirtyRect: NSRect) {
        MessagesInk.line.setFill()
        bounds.fill()
    }
}
