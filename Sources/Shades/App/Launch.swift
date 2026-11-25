import AppKit

@MainActor
enum Launch {
    static var began: DispatchTime?
    private(set) static var catOnScreen: Double?

    static var milliseconds: Double? {
        began.map { Double(DispatchTime.now().uptimeNanoseconds - $0.uptimeNanoseconds) / 1_000_000 }
    }

    static func putOnScreen(_ cat: CatController) -> CatController {
        cat.start()
        cat.panel.displayIfNeeded()
        CATransaction.flush()
        catOnScreen = milliseconds
        return cat
    }
}
