import Foundation
import ShadesCore

/// Decides what a stream of key changes means. Pure logic, so every case can be tested without a keyboard.
///
/// A press fires as soon as the key goes down, because the microphone has to open right away. If it turns
/// out to be a tap or part of a shortcut, the press is called off with `.cancel`, so nothing gets typed.
struct HoldGesture {
    enum Output: Equatable {
        case press(HoldKey)
        case release(HoldKey)
        case cancel(HoldKey)
    }

    /// Letting go faster than this is a tap, not talking.
    var tapThreshold: TimeInterval = 0.15
    /// Another key this soon after pressing means a shortcut such as Option-E, not talking.
    /// Later than this you're mid-sentence, and a stray key shouldn't lose what you said.
    var chordWindow: TimeInterval = 1.0

    private var active: (key: HoldKey, since: TimeInterval)?
    /// A key that went down as part of something else, whose release should do nothing.
    private var ignored: Set<HoldKey> = []
    /// Called off already, and waiting for the key to come up.
    private var calledOff = false

    var activeKey: HoldKey? { active?.key }

    /// A hold key changed. `otherModifiers` says whether any other modifier is being held.
    mutating func keyChanged(_ key: HoldKey, isDown: Bool, otherModifiers: Bool, at time: TimeInterval) -> Output? {
        if isDown {
            if let current = active {
                if key == current.key { return nil }
                // A second hold key is a chord too.
                ignored.insert(key)
                return otherKeyPressed(at: time)
            }
            // Already holding Shift or Command means a shortcut is under way.
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

    /// A key, another modifier or a mouse button went down during a hold.
    mutating func otherKeyPressed(at time: TimeInterval) -> Output? {
        guard let current = active, !calledOff, time - current.since < chordWindow else { return nil }
        calledOff = true
        return .cancel(current.key)
    }

    /// Escape always means stop, however long you've been holding.
    mutating func escapePressed() -> Output? {
        guard let current = active, !calledOff else { return nil }
        calledOff = true
        return .cancel(current.key)
    }

    /// The key is known to be up though its release never arrived, as when Secure Keyboard Entry
    /// hides events from us. It ends the take as normal, so what was said still lands.
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
