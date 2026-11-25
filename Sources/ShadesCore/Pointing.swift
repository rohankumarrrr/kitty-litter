import CoreGraphics

public enum PointTarget: Equatable, Sendable {
    case element(Int)
    case spot(x: Double, y: Double)
}

extension ScreenSnapshot {
    public var canPoint: Bool {
        !isPrivate && (!elements.isEmpty || screenshotArea != nil)
    }

    static let snapLimit = CGSize(width: 240, height: 100)

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

    public func spot(of element: ScreenElement) -> (x: Int, y: Int)? {
        let middle = CGPoint(x: element.frame.midX, y: element.frame.midY)
        guard let area = screenshotArea, area.contains(middle) else { return nil }
        let x = (middle.x - area.minX) / area.width * 100
        let y = (area.maxY - middle.y) / area.height * 100
        return (Int(x.rounded()), Int(y.rounded()))
    }
}
