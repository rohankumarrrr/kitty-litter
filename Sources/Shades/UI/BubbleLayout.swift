import CoreGraphics

enum BubbleLayout {
    struct Placement: Equatable {
        var frame: CGRect
        var tailX: CGFloat
        var below: Bool
    }

    static let gap: CGFloat = 2
    static let margin: CGFloat = 8
    static let tailHeight: CGFloat = 8
    private static let tailInset: CGFloat = 30

    static func place(size: CGSize, over anchor: CGRect, in visible: CGRect) -> Placement {
        let center = anchor.midX
        var x = center < visible.midX ? center - tailInset : center - size.width + tailInset
        x = min(max(x, visible.minX + margin), max(visible.minX + margin, visible.maxX - margin - size.width))

        let above = anchor.maxY + gap
        var y = above
        var below = false
        if above + size.height > visible.maxY - margin {
            let under = anchor.minY - gap - size.height
            if under >= visible.minY + margin {
                y = under
                below = true
            } else {
                y = max(visible.minY + margin, visible.maxY - margin - size.height)
            }
        }

        let tailX = min(max(center - x, tailInset), max(tailInset, size.width - tailInset))
        return Placement(frame: CGRect(x: x, y: y, width: size.width, height: size.height), tailX: tailX, below: below)
    }
}

enum ScreenBounds {
    static func perch(on region: CGRect, size: CGSize, screens: [CGRect]) -> CGPoint {
        let above = CGPoint(x: region.midX - size.width / 2, y: region.maxY - 3)
        guard clamp(above, size: size, to: screens).y < above.y else { return above }
        return CGPoint(x: above.x, y: region.minY - size.height + 3)
    }

    static func clamp(_ origin: CGPoint, size: CGSize, to screens: [CGRect]) -> CGPoint {
        guard !screens.isEmpty else { return origin }
        let rect = CGRect(origin: origin, size: size)
        if screens.contains(where: { $0.contains(rect) }) { return origin }

        var best = origin
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for screen in screens {
            let x = min(max(origin.x, screen.minX), max(screen.minX, screen.maxX - size.width))
            let y = min(max(origin.y, screen.minY), max(screen.minY, screen.maxY - size.height))
            let distance = hypot(x - origin.x, y - origin.y)
            if distance < bestDistance {
                best = CGPoint(x: x, y: y)
                bestDistance = distance
            }
        }
        return best
    }
}
