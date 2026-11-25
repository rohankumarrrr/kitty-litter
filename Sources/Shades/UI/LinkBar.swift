import AppKit

final class LinkBar: QuietView {
    private static let pad: CGFloat = 14
    private static let inset = NSSize(width: ChannelRowView.margin, height: 4)
    private static var titleHeight: CGFloat { MessagesInk.meta + 7 }
    private static let buttonGap: CGFloat = 8

    var onOpen: ((URL) -> Void)?
    var onShowPicture: ((URL) -> Void)?
    var onCancel: (() -> Void)?
    private(set) var link: URL?
    private(set) var isPicture = false
    let open = QuietButton(CatWords.openLink, style: .filled)
    let cancel = QuietButton("Cancel", style: .text)

    override init(frame: NSRect) {
        super.init(frame: frame)
        isHidden = true
        open.onPress = { [weak self] in
            guard let self, let link = self.link else { return }
            if self.isPicture { self.onShowPicture?(link) } else { self.onOpen?(link) }
        }
        cancel.onPress = { [weak self] in self?.onCancel?() }
        addSubview(open)
        addSubview(cancel)
        clipsToBounds = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(_ link: URL?, picture: Bool = false) {
        self.link = link
        isPicture = picture
        open.retitle(picture ? CatWords.showPicture : CatWords.openLink)
        isHidden = link == nil
        setAccessibilityLabel(link.map { "\(title) \($0.absoluteString)" })
        needsLayout = true
        needsDisplay = true
    }

    var title: String { isPicture ? CatWords.showPicture(from: link?.host ?? "") : CatWords.openLink(to: link?.host ?? "") }

    private var address: NSAttributedString {
        let wrapping = NSMutableParagraphStyle()
        wrapping.lineBreakMode = .byCharWrapping
        return NSAttributedString(string: link?.absoluteString ?? "", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: MessagesInk.body - 1, weight: .regular),
            .foregroundColor: MessagesInk.text,
            .paragraphStyle: wrapping,
        ])
    }

    private func addressHeight(width: CGFloat) -> CGFloat {
        ceil(address.boundingRect(with: NSSize(width: max(width - (Self.pad + Self.inset.width) * 2, 60), height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin]).height)
    }

    func height(for width: CGFloat) -> CGFloat {
        guard link != nil else { return 0 }
        return Self.inset.height * 2 + Self.pad + Self.titleHeight + addressHeight(width: width) + Self.buttonGap + open.frame.height + Self.pad
    }

    // Outside the repo: insetting a rect past empty gives CGRect.null, whose origin is at infinity.
    private var glass: NSRect {
        NSRect(x: Self.inset.width, y: Self.inset.height, width: max(bounds.width - Self.inset.width * 2, 0), height: max(bounds.height - Self.inset.height * 2, 0))
    }

    override func layout() {
        super.layout()
        let glass = glass
        let top = glass.maxY - Self.pad - open.frame.height + 4
        open.frame.origin = NSPoint(x: glass.maxX - Self.pad - open.frame.width + 4, y: top)
        cancel.frame.origin = NSPoint(x: open.frame.minX - 6 - cancel.frame.width, y: top)
    }

    override func draw(_ dirtyRect: NSRect) {
        let glass = glass
        Opal.glass(NSBezierPath(roundedRect: glass.insetBy(dx: 0.5, dy: 0.5), xRadius: Opal.Corner.popover, yRadius: Opal.Corner.popover))
        let words = glass.insetBy(dx: Self.pad, dy: Self.pad)
        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingMiddle
        NSAttributedString(string: title, attributes: [
            .font: MessagesInk.font(ofSize: MessagesInk.meta, weight: .semibold),
            .foregroundColor: MessagesInk.soft,
            .paragraphStyle: truncating,
        ]).draw(in: NSRect(x: words.minX, y: words.minY, width: words.width, height: Self.titleHeight))
        let top = words.minY + Self.titleHeight
        let room = max(open.frame.minY - Self.buttonGap - top, 0)
        address.draw(with: NSRect(x: words.minX, y: top, width: words.width, height: min(addressHeight(width: bounds.width), room)), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}
