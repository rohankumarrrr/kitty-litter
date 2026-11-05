import Foundation
import ShadesCore

extension AppController {
    func startLook(_ options: CaptureOptions) -> Task<Capture, Never> {
        let context = self.context
        return Task {
            let result = await firstOf(seconds: Self.captureTimeout) { () -> Capture in
                do {
                    return Capture(snapshot: try await context.snapshot(options), error: nil)
                } catch {
                    return Capture(snapshot: nil, error: error)
                }
            }
            return result ?? Capture(snapshot: nil, error: nil)
        }
    }
}

/// Runs `work`, giving up after a while. It keeps going in the background if it's late.
func firstOf<T: Sendable>(seconds: TimeInterval, _ work: @escaping @Sendable () async -> T) async -> T? {
    await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
        let gate = OnceGate()
        Task {
            let value = await work()
            if gate.claim() { continuation.resume(returning: value) }
        }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if gate.claim() { continuation.resume(returning: nil) }
        }
    }
}

private final class OnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}
