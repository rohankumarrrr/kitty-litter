import AppKit
import ShadesCore

/// The settings file, as a small form. The file itself stays easy to edit by hand.
@MainActor
final class SettingsPanel: NSObject, NSWindowDelegate {
    private static let width: CGFloat = 400
    private static let padding: CGFloat = 18
    private static let labelWidth: CGFloat = 96

    let panel = QuietPanel(allowsKey: true)
    private var fields: Form?
    private var onSave: ((Settings) -> Void)?
    private var current = Settings()

    private struct Form {
        var quickModel: NSTextField
        var summaryModel: NSTextField
        var frontierModel: NSTextField
        var quickMode: NSPopUpButton
        var frontierMode: NSPopUpButton
        var talkKey: NSPopUpButton
        var dictateKey: NSPopUpButton
        var privateApps: NSTextField
        var vocabulary: NSTextField
        var phone: NSButton
        var notifyFinished: NSButton
    }

    func show(_ settings: Settings, near corner: NSPoint, onSave: @escaping (Settings) -> Void) {
        current = settings
        self.onSave = onSave
        build(settings)
        let height = panel.frame.height
        panel.setFrameOrigin(NSPoint(x: corner.x - Self.width, y: corner.y - height))
        panel.makeKeyAndOrderFront(nil)
    }

    var isVisible: Bool { panel.isVisible }

    func hide() {
        panel.orderOut(nil)
    }

    private func build(_ settings: Settings) {
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

        func field(_ value: String, _ placeholder: String = "") -> NSTextField {
            let field = NSTextField(string: value)
            field.placeholderString = placeholder
            field.font = .systemFont(ofSize: 12)
            field.bezelStyle = .roundedBezel
            field.lineBreakMode = .byTruncatingTail
            field.usesSingleLineMode = true
            field.widthAnchor.constraint(equalToConstant: Self.width - Self.padding * 2 - Self.labelWidth - 8).isActive = true
            return field
        }
        func popup<T: RawRepresentable>(_ cases: [T], _ selected: T, title: (T) -> String) -> NSPopUpButton where T.RawValue == String {
            let popup = NSPopUpButton()
            popup.font = .systemFont(ofSize: 12)
            popup.controlSize = .regular
            for item in cases {
                popup.addItem(withTitle: title(item))
                popup.lastItem?.representedObject = item.rawValue
            }
            popup.selectItem(at: cases.firstIndex { $0.rawValue == selected.rawValue } ?? 0)
            popup.widthAnchor.constraint(equalToConstant: 190).isActive = true
            return popup
        }
        func row(_ title: String, _ control: NSView) -> NSView {
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 12)
            label.textColor = Ink.soft
            label.alignment = .right
            label.widthAnchor.constraint(equalToConstant: Self.labelWidth).isActive = true
            let line = NSStackView(views: [label, control])
            line.spacing = 8
            line.alignment = .firstBaseline
            return line
        }

        let form = Form(
            quickModel: field("\(settings.quickModel.provider) / \(settings.quickModel.model) / \(settings.quickModel.effort)"),
            summaryModel: field("\(settings.summaryModel.provider) / \(settings.summaryModel.model) / \(settings.summaryModel.effort)"),
            frontierModel: field("\(settings.frontierModel.provider) / \(settings.frontierModel.model) / \(settings.frontierModel.effort)"),
            quickMode: popup(RuntimeMode.allCases, settings.quickMode, title: Self.modeName),
            frontierMode: popup(RuntimeMode.allCases, settings.frontierMode, title: Self.modeName),
            talkKey: popup(HoldKey.allCases, settings.talkKey, title: Self.keyName),
            dictateKey: popup(HoldKey.allCases, settings.dictateKey, title: Self.keyName),
            privateApps: field(settings.privateApps.joined(separator: ", "), "Bundle IDs, comma separated"),
            vocabulary: field(settings.vocabulary.joined(separator: ", "), "Words I should know"),
            phone: NSButton(checkboxWithTitle: "Messages on my phone, over Tailscale", target: nil, action: nil),
            notifyFinished: NSButton(checkboxWithTitle: "Also when a session finishes", target: nil, action: nil)
        )
        form.phone.font = .systemFont(ofSize: 12)
        form.phone.state = settings.phone ? .on : .off
        form.notifyFinished.font = .systemFont(ofSize: 12)
        form.notifyFinished.state = settings.notifyFinished ? .on : .off
        fields = form

        for view in [
            row("Front door model", form.quickModel),
            row("Front door mode", form.quickMode),
            row("Frontier model", form.frontierModel),
            row("Frontier mode", form.frontierMode),
            row("Summary model", form.summaryModel),
            row("Hold to talk", form.talkKey),
            row("Hold to dictate", form.dictateKey),
            row("Private apps", form.privateApps),
            row("Extra words", form.vocabulary),
            row("Phone", form.phone),
            row("Notifications", form.notifyFinished),
        ] { stack.addArrangedSubview(view) }

        let save = QuietButton("Save", style: .filled) { [weak self] in self?.save() }
        let cancel = QuietButton("Cancel", style: .plain) { [weak self] in self?.hide() }
        let reveal = QuietButton("Open the file", style: .text) {
            NSWorkspace.shared.open(Settings.directory)
        }
        for button in [save, cancel, reveal] {
            button.widthAnchor.constraint(equalToConstant: button.frame.width).isActive = true
            button.heightAnchor.constraint(equalToConstant: button.frame.height).isActive = true
        }
        let buttons = NSStackView(views: [save, cancel, reveal])
        buttons.spacing = 6
        stack.addArrangedSubview(buttons)
        stack.setCustomSpacing(14, after: stack.arrangedSubviews[stack.arrangedSubviews.count - 2])

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
        panel.invalidateShadow()
    }

    private func save() {
        guard let form = fields else { return }
        var settings = current
        settings.quickModel = Self.model(form.quickModel.stringValue, fallback: current.quickModel)
        settings.frontierModel = Self.model(form.frontierModel.stringValue, fallback: current.frontierModel)
        settings.summaryModel = Self.model(form.summaryModel.stringValue, fallback: current.summaryModel)
        settings.quickMode = Self.selected(form.quickMode) ?? current.quickMode
        settings.frontierMode = Self.selected(form.frontierMode) ?? current.frontierMode
        settings.talkKey = Self.selected(form.talkKey) ?? current.talkKey
        settings.dictateKey = Self.selected(form.dictateKey) ?? current.dictateKey
        settings.privateApps = Self.list(form.privateApps.stringValue)
        settings.vocabulary = Self.list(form.vocabulary.stringValue)
        settings.phone = form.phone.state == .on
        settings.notifyFinished = form.notifyFinished.state == .on
        onSave?(settings)
        hide()
    }

    private static func selected<T: RawRepresentable>(_ popup: NSPopUpButton) -> T? where T.RawValue == String {
        (popup.selectedItem?.representedObject as? String).flatMap(T.init(rawValue:))
    }

    private static func list(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
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

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: BalloonView.radius, yRadius: BalloonView.radius)
        Ink.paper.setFill()
        path.fill()
        Ink.line.setStroke()
        path.stroke()
    }
}
