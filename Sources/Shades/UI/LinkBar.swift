import AppKit

/// Where a link you pressed in Messages goes, over the box, written out in full. Nothing opens until you press Open, so
/// a link's words can't hide where it leads, and nothing in a message can open anything by itself.
final class LinkBar: QuietView {
    private static let pad: CGFloat = 12
    private static let titleHeight: CGFloat = 18
    private static let buttonGap: CGFloat = 8

    var onOpen: ((URL) -> Void)?
    var onCancel: (() -> Void)?
    private(set) var link: URL?
    let open = QuietButton(CatWords.openLink, style: .filled)
    let cancel = QuietButton("Cancel", style: .text)

    override init(frame: NSRect) {
        super.init(frame: frame)
        isHidden = true
        open.onPress = { [weak self] in
            guard let self, let link = self.link else { return }
            self.onOpen?(link)
        }
        cancel.onPress = { [weak self] in self?.onCancel?() }
        addSubview(open)
        addSubview(cancel)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(_ link: URL?) {
        self.link = link
        isHidden = link == nil
        setAccessibilityLabel(link.map { "\(CatWords.openLinkQuestion) \($0.absoluteString)" })
        needsLayout = true
        needsDisplay = true
    }

    private var address: NSAttributedString {
        let wrapping = NSMutableParagraphStyle()
        wrapping.lineBreakMode = .byCharWrapping
        return NSAttributedString(string: link?.absoluteString ?? "", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: MessagesInk.text,
            .paragraphStyle: wrapping,
        ])
    }

    private func addressHeight(width: CGFloat) -> CGFloat {
        ceil(address.boundingRect(with: NSSize(width: max(width - Self.pad * 2, 60), height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin]).height)
    }

    /// As tall as the whole address needs, however long it is.
    func height(for width: CGFloat) -> CGFloat {
        guard link != nil else { return 0 }
        return Self.pad + Self.titleHeight + addressHeight(width: width) + Self.buttonGap + open.frame.height + Self.pad
    }

    override func layout() {
        super.layout()
        let top = bounds.height - Self.pad - open.frame.height
        open.frame.origin = NSPoint(x: bounds.width - Self.pad - open.frame.width, y: top)
        cancel.frame.origin = NSPoint(x: open.frame.minX - 6 - cancel.frame.width, y: top)
    }

    override func draw(_ dirtyRect: NSRect) {
        MessagesInk.hover.setFill()
        bounds.fill()
        MessagesInk.line.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
        NSAttributedString(string: CatWords.openLinkQuestion, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: MessagesInk.soft,
        ]).draw(at: NSPoint(x: Self.pad, y: Self.pad))
        let width = bounds.width - Self.pad * 2
        address.draw(with: NSRect(x: Self.pad, y: Self.pad + Self.titleHeight, width: width, height: addressHeight(width: bounds.width)), options: [.usesLineFragmentOrigin])
    }
}
