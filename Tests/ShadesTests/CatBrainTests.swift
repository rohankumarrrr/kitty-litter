import CoreGraphics
@testable import Shades
import XCTest

final class CatBrainTests: XCTestCase {
    private func brain(at x: CGFloat = 0, _ y: CGFloat = 0) -> CatBrain {
        CatBrain(position: CGPoint(x: x, y: y))
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    func testSitsBlinksScratchesThenSleeps() {
        var cat = brain()
        var seen: [Int: CatFrame] = [:]
        for tick in 1...100 {
            cat.tick()
            seen[tick] = cat.pose.frame
        }
        XCTAssertEqual(seen[1], .sit)
        XCTAssertEqual(seen[37], .blink)
        XCTAssertEqual(seen[38], .sit)
        XCTAssertEqual(seen[40], .sit)
        XCTAssertTrue([.scratch1, .scratch2].contains(seen[41]!))
        XCTAssertTrue([.scratch1, .scratch2].contains(seen[55]!))
        XCTAssertEqual(seen[56], .sit)
        XCTAssertEqual(seen[74], .blink)
        XCTAssertEqual(seen[90], .sit)
        XCTAssertEqual(cat.state, .sleep)
        XCTAssertTrue([.sleep1, .sleep2].contains(seen[91]!))
    }

    func testCurlsUpUnderDoNotDisturbAndSleepsThroughEverythingButYou() {
        var cat = brain()
        cat.setDoNotDisturb(true)
        XCTAssertEqual(cat.state, .sleep)
        cat.setAgentsBusy(true)
        cat.setStatus(.attention)
        cat.celebrate()
        cat.tick()
        XCTAssertEqual(cat.state, .sleep)
        XCTAssertEqual(cat.pose.glint, .plain)

        cat.setStatus(.listening)
        XCTAssertEqual(cat.state, .sit, "you're talking to it")
        cat.setStatus(.none)
        for _ in 1...11 { cat.tick() }
        XCTAssertEqual(cat.state, .sleep, "and it curls up again soon after")

        cat.setDoNotDisturb(false)
        XCTAssertEqual(cat.state, .sit)
    }

    func testBreathesWhileAsleepWithAFloatingZ() {
        var cat = brain()
        for _ in 1...100 { cat.tick() }
        XCTAssertEqual(cat.state, .sleep)
        var frames = Set<CatFrame>()
        var zs = Set<Int>()
        for _ in 1...24 {
            cat.tick()
            frames.insert(cat.pose.frame)
            zs.insert(cat.pose.z ?? -1)
        }
        XCTAssertEqual(frames, [.sleep1, .sleep2])
        XCTAssertEqual(zs, [0, 1, 2, 3])
    }

    func testRunsThenSitsAtTheTarget() {
        var cat = brain()
        let target = CGPoint(x: 100, y: 0)
        cat.go(to: target)
        XCTAssertEqual(cat.state, .run)
        var arrived = false
        for _ in 1...20 where cat.tick() { arrived = true }
        XCTAssertTrue(arrived)
        XCTAssertEqual(cat.position, target)
        XCTAssertEqual(cat.state, .sit)
    }

    func testRunningSpeedScalesWithDistance() {
        var near = brain()
        near.go(to: CGPoint(x: 150, y: 0))
        near.tick()
        var far = brain()
        far.go(to: CGPoint(x: 2000, y: 0))
        far.tick()
        XCTAssertEqual(near.position.x, 20, accuracy: 0.01)
        XCTAssertGreaterThan(far.position.x, near.position.x * 5)
    }

    func testEvenAcrossALargeScreenTheWaitIsShort() {
        var cat = brain()
        cat.go(to: CGPoint(x: 5000, y: 3000))
        var ticks = 0
        while !cat.tick() { ticks += 1 }
        XCTAssertLessThan(ticks, 50, "under five seconds at 10 ticks a second")
    }

    func testPicksFramesByDirection() {
        var right = brain()
        right.go(to: CGPoint(x: 500, y: 0))
        right.tick()
        XCTAssertTrue([.run1, .run2].contains(right.pose.frame))
        XCTAssertFalse(right.pose.flip)

        var left = brain()
        left.go(to: CGPoint(x: -500, y: 0))
        left.tick()
        XCTAssertTrue([.run1, .run2].contains(left.pose.frame))
        XCTAssertTrue(left.pose.flip)

        // AppKit's y points up.
        var up = brain()
        up.go(to: CGPoint(x: 0, y: 500))
        up.tick()
        XCTAssertTrue([.up1, .up2].contains(up.pose.frame))

        var down = brain()
        down.go(to: CGPoint(x: 0, y: -500))
        down.tick()
        XCTAssertTrue([.down1, .down2].contains(down.pose.frame))
    }

    func testRunningAlternatesFramesEveryTick() {
        var cat = brain()
        cat.go(to: CGPoint(x: 800, y: 0))
        cat.tick()
        let first = cat.pose.frame
        cat.tick()
        XCTAssertNotEqual(cat.pose.frame, first)
    }

    func testAStillCatArrivesInOneTickAndItsGlintHolds() {
        var cat = brain()
        cat.still = true
        let target = CGPoint(x: 1800, y: 0)
        cat.go(to: target)
        XCTAssertTrue(cat.tick(), "nothing waits on a run across the screen")
        XCTAssertEqual(cat.position, target)
        XCTAssertEqual(cat.state, .sit)

        for status in [CatStatus.attention, .thinking] {
            cat.setStatus(status)
            var poses = Set<CatPose>()
            for _ in 1...300 {
                cat.tick()
                poses.insert(cat.pose)
            }
            XCTAssertEqual(poses.count, 1, "\(status) holds one drawing")
        }
        XCTAssertEqual(cat.pose, CatPose(frame: .sit, glint: .thinking(bright: true)))
    }

    func testNothingElseAboutAStillCatMovesOnItsOwn() {
        var cat = brain()
        cat.still = true
        var poses = Set<CatPose>()
        for _ in 1...200 {
            cat.tick()
            poses.insert(cat.pose)
        }
        XCTAssertEqual(cat.state, .sleep)
        XCTAssertEqual(poses, [CatPose(frame: .sit), CatPose(frame: .sleep1, z: 0)], "no blinking, scratching or breathing")

        cat.celebrate()
        poses = []
        for _ in 1...19 {
            cat.tick()
            poses.insert(cat.pose)
        }
        XCTAssertEqual(poses, [CatPose(frame: .bat1, glint: .party)])

        cat.setStatus(.listening)
        cat.level = 0.9
        cat.tick()
        XCTAssertEqual(cat.pose.lift, 0)
        XCTAssertEqual(cat.pose.glint, .listening(loudness: 2), "how loud you are still shows")
    }

    func testSomethingNeedingYouBlinksForFiveSecondsThenHolds() {
        var cat = brain()
        cat.setStatus(.attention)
        var first = Set<CatGlint>()
        for _ in 1...50 {
            cat.tick()
            first.insert(cat.pose.glint)
        }
        XCTAssertEqual(first, [.attention(bright: true), .attention(bright: false)])
        var after = Set<CatGlint>()
        for _ in 1...600 {
            cat.tick()
            after.insert(cat.pose.glint)
        }
        XCTAssertEqual(after, [.attention(bright: true)])
    }

    func testBeingPettedSaysAWordAndWakes() {
        var cat = brain()
        for _ in 1...100 { cat.tick() }
        XCTAssertEqual(cat.state, .sleep)
        for roll in 0..<4 {
            XCTAssertEqual(cat.pet(roll: roll), ["mrrp", "mrow", "...", "prrr"][roll])
        }
        XCTAssertEqual(cat.state, .sit)
        XCTAssertEqual(cat.pose.frame, .sit)
        XCTAssertEqual(cat.idle, 0)
    }

    func testStaysAwakeWhileAgentsWork() {
        var cat = brain()
        cat.setAgentsBusy(true)
        for _ in 1...500 { cat.tick() }
        XCTAssertEqual(cat.state, .sit)
    }

    func testWakesWhenAgentsStartAndSleepsAfterTheyStop() {
        var cat = brain()
        for _ in 1...100 { cat.tick() }
        XCTAssertEqual(cat.state, .sleep)
        cat.setAgentsBusy(true)
        XCTAssertEqual(cat.state, .sit)
        cat.setAgentsBusy(false)
        for _ in 1...100 { cat.tick() }
        XCTAssertEqual(cat.state, .sleep)
    }

    func testAStatusWakesItAndShowsInTheGlint() {
        var cat = brain()
        for _ in 1...100 { cat.tick() }
        cat.setStatus(.thinking)
        XCTAssertEqual(cat.state, .sit)
        var glints = Set<CatGlint>()
        for _ in 1...16 {
            cat.tick()
            glints.insert(cat.pose.glint)
        }
        XCTAssertEqual(glints, [.thinking(bright: true), .thinking(bright: false)])
    }

    func testStaysFocusedWhileBusyWithYou() {
        var cat = brain()
        cat.setStatus(.attention)
        for _ in 1...300 {
            cat.tick()
            XCTAssertTrue([.sit, .blink].contains(cat.pose.frame))
        }
        XCTAssertEqual(cat.state, .sit)
    }

    func testListeningReactsToLevels() {
        var cat = brain()
        cat.setStatus(.listening)
        cat.level = 0
        cat.tick()
        XCTAssertEqual(cat.pose.glint, .listening(loudness: 0))
        XCTAssertEqual(cat.pose.lift, 0)
        cat.level = 0.9
        cat.tick()
        XCTAssertEqual(cat.pose.glint, .listening(loudness: 2))
        XCTAssertEqual(cat.pose.lift, 1)
        cat.setStatus(.none)
        cat.tick()
        XCTAssertEqual(cat.pose.glint, .plain)
        XCTAssertEqual(cat.pose.lift, 0)
    }

    func testCelebratesBrieflyThenSits() {
        var cat = brain()
        cat.celebrate()
        XCTAssertEqual(cat.state, .celebrate)
        var frames = Set<CatFrame>()
        for _ in 1...19 {
            cat.tick()
            frames.insert(cat.pose.frame)
            XCTAssertEqual(cat.pose.glint, .party)
        }
        XCTAssertEqual(frames, [.bat1, .bat2])
        for _ in 1...3 { cat.tick() }
        XCTAssertEqual(cat.state, .sit)
    }

    func testCelebratingWaitsUntilItHasArrived() {
        var cat = brain()
        let home = CGPoint(x: 400, y: 0)
        cat.go(to: home)
        cat.tick()
        cat.celebrate()
        XCTAssertEqual(cat.state, .run)
        for _ in 1...40 where cat.state == .run { cat.tick() }
        XCTAssertEqual(cat.position, home)
        XCTAssertEqual(cat.state, .celebrate)
    }

    func testPickedUpDangles() {
        var cat = brain()
        cat.pickUp()
        XCTAssertEqual(cat.state, .held)
        XCTAssertEqual(cat.pose.frame, .down1)
        for _ in 1...200 { cat.tick() }
        XCTAssertEqual(cat.state, .held)
        cat.putDown(at: CGPoint(x: 5, y: 6))
        XCTAssertEqual(cat.state, .sit)
        XCTAssertEqual(cat.position, CGPoint(x: 5, y: 6))
    }

    /// The timer sleeps through ticks where nothing changes. That only works if nothing
    /// really does, so ticking in jumps has to look exactly like ticking one at a time.
    func testSkippedTicksLookTheSameAsEveryTick() {
        var cat = brain()
        var ticks = 0
        while ticks < 400 {
            let before = cat.pose
            let jump = cat.ticksUntilChange()
            XCTAssertGreaterThan(jump, 0)
            for step in 1...jump {
                cat.tick()
                ticks += 1
                if step < jump {
                    XCTAssertEqual(cat.pose, before, "nothing should change on a skipped tick")
                }
            }
        }
    }

    func testAnIdleCatHardlyEverNeedsToWake() {
        var cat = brain()
        var wakes = 0
        var ticks = 0
        // A minute awake and a minute asleep.
        while ticks < 1200 {
            let jump = cat.ticksUntilChange()
            for _ in 1...jump { cat.tick() }
            ticks += jump
            wakes += 1
        }
        XCTAssertLessThan(wakes, 250, "well under the 1200 wakes a plain 10 Hz timer would use")
        // Asleep, it's two wakes every 1.2 s.
        let jump = cat.ticksUntilChange()
        XCTAssertGreaterThanOrEqual(jump, 1)
        XCTAssertLessThanOrEqual(jump, 6)
    }
}
