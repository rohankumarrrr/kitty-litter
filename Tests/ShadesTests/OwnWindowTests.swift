@testable import Shades
import XCTest

/// Which window a marked spot is on, from the windows a click there reaches, front to back: 1 is The Kitty Litter, 2
/// the region picker's overlay, which a click still reaches just after it's gone, 3 the cat, and 9 another app's.
@MainActor
final class OwnWindowTests: XCTestCase {
    private let counting: Set<Int> = [1]
    /// Ours that don't count, or gone.
    private let passedOver: Set<Int> = [2, 3]

    private func decide(_ stack: [Int]) -> Bool {
        AppStage.isOwnWindow(counting: counting, isPassedOver: passedOver.contains) { below in
            let next = below == 0 ? stack.first : stack.firstIndex(of: below).flatMap { stack.indices.contains($0 + 1) ? stack[$0 + 1] : nil }
            return next ?? 0
        }
    }

    func testTheKittyLitterInFrontCounts() {
        XCTAssertTrue(decide([1, 9]))
    }

    func testThePickersOverlayOnTheWayOutIsLookedPast() {
        XCTAssertTrue(decide([2, 1, 9]), "a fix marked on The Kitty Litter, checked as soon as the picker lets go")
        XCTAssertFalse(decide([2, 9, 1]))
    }

    func testTheCatIsLookedPastToWhatsUnderIt() {
        XCTAssertFalse(decide([3, 9]), "a box whose middle lands on the cat means what's under it")
        XCTAssertTrue(decide([3, 1]))
    }

    func testAnotherAppInFrontOfOursDoesntCount() {
        XCTAssertFalse(decide([9, 1]))
        XCTAssertFalse(decide([]))
    }

    func testAWindowServerThatRepeatsItselfStillGetsAnAnswer() {
        XCTAssertFalse(AppStage.isOwnWindow(counting: [], isPassedOver: { _ in true }) { _ in 2 })
    }
}
