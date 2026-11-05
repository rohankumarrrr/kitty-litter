import Foundation

/// Runs a blocking system call on a thread of its own and stops waiting when time is up,
/// because an app that has hung can hold these calls for seconds.
func blocking<T>(within seconds: TimeInterval, _ work: @escaping () -> T?) async -> T? {
    await withCheckedContinuation { continuation in
        let answer = FirstAnswer(continuation)
        DispatchQueue.global(qos: .userInitiated).async { answer.give(work()) }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + seconds) { answer.give(nil) }
    }
}

/// The same for async work, which may never finish if the system service behind it stalls.
func waiting<T>(within seconds: TimeInterval, _ work: @escaping () async -> T?) async -> T? {
    await withCheckedContinuation { continuation in
        let answer = FirstAnswer(continuation)
        Task.detached(priority: .userInitiated) { answer.give(await work()) }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + seconds) { answer.give(nil) }
    }
}

private final class FirstAnswer<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?

    init(_ continuation: CheckedContinuation<T?, Never>) {
        self.continuation = continuation
    }

    func give(_ value: T?) {
        lock.lock()
        let waiting = continuation
        continuation = nil
        lock.unlock()
        waiting?.resume(returning: value)
    }
}
