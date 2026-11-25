import Foundation

@MainActor
@discardableResult
public func runMainLoop(until condition: () -> Bool, seconds: TimeInterval = 5) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    return condition()
}

@discardableResult
public func until(
    isolation: isolated (any Actor)? = #isolation,
    seconds: TimeInterval = 5,
    _ condition: () async throws -> Bool
) async rethrows -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if try await condition() { return true }
        try? await Task.sleep(nanoseconds: 2_000_000)
    }
    return try await condition()
}
