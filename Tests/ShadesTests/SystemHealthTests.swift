import AppKit
@testable import Shades
import XCTest

@MainActor
final class SystemHealthTests: XCTestCase {
    func testCheckingTheSignatureLeavesTheMainThreadFree() async {
        var answered: UInt64?
        DispatchQueue.main.async { answered = DispatchTime.now().uptimeNanoseconds }
        let start = DispatchTime.now().uptimeNanoseconds
        _ = await SystemHealth.signature()
        let end = DispatchTime.now().uptimeNanoseconds
        let waited = (answered ?? end) - start
        XCTAssertLessThan(waited, (end - start) / 2, "the main thread waited \(waited / 1_000_000) ms of the \((end - start) / 1_000_000) ms macOS took to check the signature")
    }
}
