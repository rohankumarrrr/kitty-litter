import AppKit
import CoreImage

/// What pairing a phone shows: where to go, and the one-time code. `address` is `nil` when Tailscale couldn't say.
struct PhonePairingCard: Equatable {
    var address: String?
    var code: String

    /// What the picture holds, so scanning it opens the page and pairs in one go.
    var link: String? { address.map { "\($0)/#pair=\(code)" } }
}

/// The code a phone pairs with. Whoever has it can speak as you from the phone, so this window is left out of every
/// capture, Shades' own and every other app's, like Messages, and the code is never written anywhere else.
@MainActor
final class PairingPanel {
    private static let width: CGFloat = 320
    private static let padding: CGFloat = 24
    private static let pictureSide: CGFloat = 200

    /// Its window, which tests give one that never reaches the screen.
    let panel: QuietPanel
    var onClose: (() -> Void)?

    init(panel: QuietPanel? = nil) {
        let panel = panel ?? QuietPanel(allowsKey: false)
        self.panel = panel
        panel.sharingType = .none
    }

    var isVisible: Bool { panel.isVisible }

    func show(_ card: PhonePairingCard, centeredIn visible: NSRect) {
        let root = PairingRootView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: Self.padding, left: Self.padding, bottom: Self.padding, right: Self.padding)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: CatWords.pairTitle)
        title.font = MessagesInk.font(ofSize: MessagesInk.toolbarTitle, weight: .semibold)
        title.textColor = MessagesInk.strong
        stack.addArrangedSubview(title)

        if let link = card.link, let picture = Self.picture(of: link) {
            let image = NSImageView(image: picture)
            image.imageScaling = .scaleNone
            image.setAccessibilityLabel(CatWords.pairPicture)
            image.wantsLayer = true
            image.layer?.backgroundColor = NSColor.white.cgColor
            image.layer?.cornerRadius = Opal.Corner.control
            image.widthAnchor.constraint(equalToConstant: Self.pictureSide + 16).isActive = true
            image.heightAnchor.constraint(equalToConstant: Self.pictureSide + 16).isActive = true
            stack.addArrangedSubview(image)
        }

        // A figure, light and tabular, spaced out a little so it's easy to read off and type.
        let figure = MessagesInk.font(ofSize: 32 + MessagesInk.title - 14, weight: .light, tabular: true)
        let code = NSTextField(labelWithAttributedString: NSAttributedString(string: card.code, attributes: [
            .font: figure, .foregroundColor: MessagesInk.strong, .kern: 2,
        ]))
        code.setAccessibilityLabel(card.code.map(String.init).joined(separator: " "))
        stack.addArrangedSubview(code)
        stack.setCustomSpacing(8, after: code)

        let words = NSTextField(wrappingLabelWithString: CatWords.pairHow(card.address))
        words.font = MessagesInk.font(ofSize: MessagesInk.body)
        words.textColor = MessagesInk.soft
        words.alignment = .center
        words.preferredMaxLayoutWidth = Self.width - Self.padding * 2
        stack.addArrangedSubview(words)
        stack.setCustomSpacing(Self.padding, after: words)

        let cancel = QuietButton(CatWords.pairCancel, style: .plain) { [weak self] in self?.close() }
        cancel.widthAnchor.constraint(equalToConstant: cancel.frame.width).isActive = true
        cancel.heightAnchor.constraint(equalToConstant: cancel.frame.height).isActive = true
        stack.addArrangedSubview(cancel)

        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            root.widthAnchor.constraint(equalToConstant: Self.width),
        ])
        panel.contentView = root
        root.layoutSubtreeIfNeeded()
        let size = root.fittingSize
        panel.setContentSize(size)
        panel.setFrameOrigin(NSPoint(x: (visible.midX - size.width / 2).rounded(), y: (visible.midY - size.height / 2).rounded()))
        panel.invalidateShadow()
        panel.orderFrontRegardless()
    }

    /// Cancel and Esc: the code stops working once it's gone.
    func close() {
        hide()
        onClose?()
    }

    func hide() {
        panel.orderOut(nil)
        panel.contentView = nil
    }

    /// Black on white whatever the theme, since that's what a camera reads best, at a whole number of points a square.
    static func picture(of text: String) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let code = filter.outputImage else { return nil }
        let scale = (pictureSide / code.extent.width).rounded(.down)
        let representation = NSCIImageRep(ciImage: code.transformed(by: CGAffineTransform(scaleX: scale, y: scale)))
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}

private final class PairingRootView: NSView {
    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Opal.glass(NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: BalloonView.radius, yRadius: BalloonView.radius))
    }
}
