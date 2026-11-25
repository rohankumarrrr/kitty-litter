import Foundation
import ShadesCore

struct HoldGesture {
    enum Output: Equatable {
        case press(HoldKey)
        case release(HoldKey)
        case cancel(HoldKey)
    }

    var tapThreshold: TimeInterval = 0.15
    var chordWindow: TimeInterval = 1.0

    private var active: (key: HoldKey, since: TimeInterval)?
    private var ignored: Set<HoldKey> = []
    private var calledOff = false

    var activeKey: HoldKey? { active?.key }

    mutating func keyChanged(_ key: HoldKey, isDown: Bool, otherModifiers: Bool, at time: TimeInterval) -> Output? {
        if isDown {
            if let current = active {
                if key == current.key { return nil }
                ignored.insert(key)
                return otherKeyPressed(at: time)
            }
            if otherModifiers {
                ignored.insert(key)
                return nil
            }
            active = (key, time)
            calledOff = false
            return .press(key)
        }

        if ignored.remove(key) != nil { return nil }
        guard let current = active, current.key == key else { return nil }
        active = nil
        if calledOff {
            calledOff = false
            return nil
        }
        return time - current.since < tapThreshold ? .cancel(key) : .release(key)
    }

    mutating func otherKeyPressed(at time: TimeInterval) -> Output? {
        guard let current = active, !calledOff, time - current.since < chordWindow else { return nil }
        calledOff = true
        return .cancel(current.key)
    }

    mutating func escapePressed() -> Output? {
        guard let current = active, !calledOff else { return nil }
        calledOff = true
        return .cancel(current.key)
    }

    mutating func releaseWasMissed() -> Output? {
        guard let current = active else { return nil }
        active = nil
        if calledOff {
            calledOff = false
            return nil
        }
        return .release(current.key)
    }

    mutating func reset() {
        active = nil
        ignored = []
        calledOff = false
    }
}
