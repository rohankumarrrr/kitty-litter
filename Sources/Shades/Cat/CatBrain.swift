import CoreGraphics

enum CatStatus: Equatable {
    case none, listening, thinking, attention
}

struct CatPose: Hashable {
    var frame: CatFrame
    var flip = false
    var lift = 0
    var z: Int?
    var glint: CatGlint = .plain
}

struct CatBrain {
    enum State: Equatable {
        case sit, sleep, run, celebrate, held
    }

    static let pettingWords = ["mrrp", "mrow", "…", "prrr"]

    private static let speed: CGFloat = 20
    private static let reach: CGFloat = 200
    private static let scratchStart = 40
    private static let scratchEnd = 56
    private static let blinkEvery = 37
    private static let sleepAfter = 90
    private static let dozeAfter = 10
    private static let celebrateTicks = 20
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
    var still = false

    init(position: CGPoint) {
        self.position = position
        target = position
    }

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

    private var staysUp: Bool {
        status != .none && !(doNotDisturb && status == .attention)
    }

    private var hop: Int {
        !still && status == .listening && level > 0.45 ? 1 : 0
    }

    private var blinking: Bool {
        !still && idle % Self.blinkEvery == 0
    }

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

    mutating func go(to point: CGPoint) {
        target = point
        state = .run
        idle = 0
        celebrating = 0
    }

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
            celebrateOnArrival = true
        case .sit, .sleep, .celebrate:
            startCelebrating()
        }
    }

    private mutating func startCelebrating() {
        state = .celebrate
        celebrating = Self.celebrateTicks
    }

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
