import Foundation

@MainActor
enum Launch {
    static var began: DispatchTime?

    static var milliseconds: Double? {
        began.map { Double(DispatchTime.now().uptimeNanoseconds - $0.uptimeNanoseconds) / 1_000_000 }
    }
}
