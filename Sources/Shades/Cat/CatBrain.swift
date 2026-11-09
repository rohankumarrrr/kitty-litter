import CoreGraphics

/// What the agents and the voice flows want the glint to show.
enum CatStatus: Equatable {
    case none, listening, thinking, attention
}

/// One drawing of the cat.
struct CatPose: Hashable {
    var frame: CatFrame
    var flip = false
    /// Art pixels off the ground, for hops.
    var lift = 0
    /// Which step of the floating z, while asleep.
    var z: Int?
    var glint: CatGlint = .plain
}

/// The cat's behaviour, following oneko: run at a choppy 10 ticks a second, then sit,
/// scratch, and eventually fall asleep. Positions are the bottom-left corner of the
/// cat in AppKit screen coordinates, so up is positive.
struct CatBrain {
    enum State: Equatable {
        case sit, sleep, run, celebrate, held
    }

    static let pettingWords = ["mrrp", "mrow", "...", "prrr"]

    // 15px a tick on the site at 3x, which is 20 at 4x.
    private static let speed: CGFloat = 20
    // A long way to go means running faster, so nothing is left waiting. Desktops are
    // far wider than a web column, so the speed starts climbing sooner than on the site.
    private static let reach: CGFloat = 200
    private static let scratchStart = 40
    private static let scratchEnd = 56
    private static let blinkEvery = 37
    private static let sleepAfter = 90
    /// How soon it curls up again under Do Not Disturb, once you're done with it.
    private static let dozeAfter = 10
    private static let celebrateTicks = 20
    /// Something that needs you blinks for five seconds, then holds, so it never flashes for hours.
    private static let attentionBlinks = 50

    private(set) var state: State = .sit
    private(set) var position: CGPoint
    private(set) var target: CGPoint
    private(set) var pose = CatPose(frame: .sit)
    private(set) var count = 0
    private(set) var idle = 0
    private(set) var agentsBusy = false
    private(set) var status: CatStatus = .none
    private(set) var doNotDisturb = false
    private var celebrating = 0
    private var celebrateOnArrival = false
    private var statusAt = 0
    var level: Float = 0
    /// Reduce Motion: it gets where it's going in one tick, and nothing else about it moves on its own.
    var still = false

    init(position: CGPoint) {
        self.position = position
        target = position
    }

    /// Moves one tick, returning whether the cat just got where it was going.
    @discardableResult
    mutating func tick() -> Bool {
        count += 1
        var arrived = false
        switch state {
        case .run:
            arrived = runStep()
        case .celebrate:
            celebrateStep()
        case .sit, .sleep, .held:
            break
        }
        if state == .sit || state == .sleep {
            idle += 1
            if state == .sit { sitStep() }
            if state == .sleep {
                let breath = cycle % 12 < 6
                pose = CatPose(frame: breath ? .sleep1 : .sleep2, z: (cycle / 6) % 4)
            }
        }
        return arrived
    }

    /// How many ticks can pass before anything changes, so the timer can sleep through them.
    func ticksUntilChange(limit: Int = 100) -> Int {
        if state == .held { return limit }
        if status == .listening { return 1 }
        var probe = self
        for ticks in 1...limit {
            if probe.tick() || probe.pose != pose || probe.position != position || probe.state != state {
                return ticks
            }
        }
        return limit
    }

    private mutating func runStep() -> Bool {
        let dx = target.x - position.x
        let dy = target.y - position.y
        let distance = (dx * dx + dy * dy).squareRoot()
        if still || distance <= Self.speed {
            position = target
            state = .sit
            idle = 0
            if celebrateOnArrival {
                celebrateOnArrival = false
                startCelebrating()
            }
            return true
        }
        let speed = Self.speed * max(1, distance / Self.reach)
        position.x += dx / distance * speed
        position.y += dy / distance * speed
        let first = count % 2 == 1
        if abs(dx) > abs(dy) * 1.1 {
            pose = CatPose(frame: first ? .run1 : .run2, flip: dx < 0, glint: glint)
        } else if dy > 0 {
            pose = CatPose(frame: first ? .up1 : .up2, glint: glint)
        } else {
            pose = CatPose(frame: first ? .down1 : .down2, glint: glint)
        }
        return false
    }

    private mutating func sitStep() {
        if staysUp {
            // Busy with you, so no scratching and no nodding off.
            if idle > Self.sleepAfter { idle = 0 }
            pose = CatPose(frame: blinking ? .blink : .sit, lift: hop, glint: glint)
            return
        }
        if idle > (doNotDisturb ? Self.dozeAfter : Self.sleepAfter) {
            if agentsBusy && !doNotDisturb {
                idle = 0
            } else {
                state = .sleep
                return
            }
        }
        if !still && idle > Self.scratchStart && idle < Self.scratchEnd {
            pose = CatPose(frame: count % 2 == 1 ? .scratch1 : .scratch2)
        } else {
            pose = CatPose(frame: blinking ? .blink : .sit)
        }
    }

    private mutating func celebrateStep() {
        celebrating -= 1
        if celebrating <= 0 {
            state = .sit
            idle = 0
            return
        }
        if still {
            pose = CatPose(frame: .bat1, glint: .party)
            return
        }
        let beat = celebrating % 4
        pose = CatPose(
            frame: beat < 2 ? .bat1 : .bat2,
            flip: celebrating <= Self.celebrateTicks / 2,
            lift: celebrating % 2,
            glint: .party
        )
    }

    /// Listening or thinking keeps it up. So does something needing you, unless Do Not Disturb says it can wait.
    private var staysUp: Bool {
        status != .none && !(doNotDisturb && status == .attention)
    }

    private var hop: Int {
        !still && status == .listening && level > 0.45 ? 1 : 0
    }

    private var blinking: Bool {
        !still && idle % Self.blinkEvery == 0
    }

    /// What the drawings that loop by themselves count by. A still cat stays on the first of each.
    private var cycle: Int {
        still ? 0 : count
    }

    private var glint: CatGlint {
        switch status {
        case .none: return .plain
        case .listening: return .listening(loudness: level < 0.15 ? 0 : level < 0.5 ? 1 : 2)
        case .thinking: return .thinking(bright: cycle % 8 < 4)
        case .attention: return .attention(bright: count - statusAt > Self.attentionBlinks || cycle % 6 < 3)
        }
    }

    // MARK: - Things that happen to the cat

    mutating func go(to point: CGPoint) {
        target = point
        state = .run
        idle = 0
        celebrating = 0
    }

    /// Being petted is the same as on the site: a word, and it sits up. Sleeping cats wake.
    mutating func pet(roll: Int) -> String {
        state = .sit
        idle = 0
        pose = CatPose(frame: .sit, glint: glint)
        return Self.pettingWords[abs(roll) % Self.pettingWords.count]
    }

    mutating func wake() {
        guard state == .sleep else { return }
        state = .sit
        idle = 0
        pose = CatPose(frame: .sit, glint: glint)
    }

    mutating func setStatus(_ status: CatStatus) {
        if status != self.status { statusAt = count }
        self.status = status
        if staysUp { wake() }
        if state == .sit { pose.glint = glint }
    }

    mutating func setAgentsBusy(_ busy: Bool) {
        agentsBusy = busy
        if busy && !doNotDisturb { wake() }
    }

    /// It curls up and sleeps through everything but you, and wakes when it's turned off.
    mutating func setDoNotDisturb(_ on: Bool) {
        doNotDisturb = on
        if !on {
            wake()
        } else if state == .sit, !staysUp {
            state = .sleep
        }
    }

    mutating func celebrate() {
        guard !doNotDisturb else { return }
        switch state {
        case .held:
            return
        case .run:
            // Not on the way anywhere: it gets there first.
            celebrateOnArrival = true
        case .sit, .sleep, .celebrate:
            startCelebrating()
        }
    }

    private mutating func startCelebrating() {
        state = .celebrate
        celebrating = Self.celebrateTicks
    }

    /// Picked up by the mouse. The legs dangle.
    mutating func pickUp() {
        state = .held
        pose = CatPose(frame: .down1, glint: glint)
    }

    mutating func move(to point: CGPoint) {
        position = point
        target = point
    }

    mutating func putDown(at point: CGPoint) {
        move(to: point)
        state = .sit
        idle = 0
        pose = CatPose(frame: .sit, glint: glint)
    }
}
