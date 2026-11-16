import Foundation

/// Lets the main run loop go on until `condition` holds, for up to `seconds`. A set wait can run out while a busy runner
/// holds everything up, before the timer or animation it was waiting for gets its turn.
@MainActor
func runMainLoop(until condition: () -> Bool, seconds: TimeInterval = 5) {
    let deadline = Date().addingTimeInterval(seconds)
    while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
}
