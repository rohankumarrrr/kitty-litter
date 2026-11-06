import CoreGraphics

/// Where a reply asked the cat to go.
public enum PointTarget: Equatable, Sendable {
    /// One of the snapshot's elements, counting from 1.
    case element(Int)
    /// A spot on the screenshot, as fractions of its width and height from the top left.
    case spot(x: Double, y: Double)
}

extension ScreenSnapshot {
    /// Whether there's anything to point with: elements to name, or a screenshot to point into.
    public var canPoint: Bool {
        !isPrivate && (!elements.isEmpty || screenshotArea != nil)
    }

    /// Only something about the size of a control or a short label is worth snapping to. A picture
    /// or a block of text would move the cat far from the spot it was given.
    static let snapLimit = CGSize(width: 240, height: 100)

    /// The part of the screen to run to, in AppKit global points, or `nil` if it can't tell.
    /// A spot snaps to the smallest element under it, since a guess from a picture is rarely exact.
    public func region(for target: PointTarget) -> CGRect? {
        switch target {
        case .element(let number):
            return elements.indices.contains(number - 1) ? elements[number - 1].frame : nil
        case .spot(let x, let y):
            guard let area = screenshotArea, (0...1).contains(x), (0...1).contains(y) else { return nil }
            let point = CGPoint(x: area.minX + x * area.width, y: area.maxY - y * area.height)
            let under = elements.map(\.frame)
                .filter { $0.contains(point) && $0.width <= Self.snapLimit.width && $0.height <= Self.snapLimit.height }
                .min { $0.width * $0.height < $1.width * $1.height }
            return under ?? CGRect(x: point.x - 12, y: point.y - 12, width: 24, height: 24)
        }
    }

    /// Where an element sits on the screenshot, in whole percentages across and down. `nil` if it isn't on it.
    public func spot(of element: ScreenElement) -> (x: Int, y: Int)? {
        let middle = CGPoint(x: element.frame.midX, y: element.frame.midY)
        guard let area = screenshotArea, area.contains(middle) else { return nil }
        let x = (middle.x - area.minX) / area.width * 100
        let y = (area.maxY - middle.y) / area.height * 100
        return (Int(x.rounded()), Int(y.rounded()))
    }
}
