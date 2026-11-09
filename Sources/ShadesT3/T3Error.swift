import Foundation

public enum T3Error: LocalizedError, Equatable {
    case notRunning
    case commandLineToolMissing
    case signInFailed
    /// This T3 Code speaks a different protocol than the one The Kitty Litter was built against.
    case incompatibleServer(version: String?)
    case unauthorized
    case connectionLost
    case timedOut
    /// The server said no, with its own reason.
    case rejected(String)
    case attachmentNotSupported(name: String, reason: String)
    case keychain(status: Int32)

    public var errorDescription: String? {
        switch self {
        case .notRunning:
            return "I can't reach T3 Code. Open it and try again."
        case .commandLineToolMissing:
            return "I can't find T3 Code's command line tool. Open T3 Code once, then try again."
        case .signInFailed:
            return "I couldn't sign in to T3 Code. Quit and reopen it, then try again."
        case let .incompatibleServer(version):
            return "I can't work with \(version.map { "T3 Code \($0)" } ?? "this version of T3 Code") yet. Check for an update to The Kitty Litter."
        case .unauthorized:
            return "T3 Code didn't accept my sign-in. Try again in a moment."
        case .connectionLost:
            return "I lost the connection to T3 Code. Make sure it's open, then try again."
        case .timedOut:
            return "T3 Code took too long to answer. Try again in a moment."
        case let .rejected(reason):
            return reason
        case let .attachmentNotSupported(name, reason):
            return "Couldn't attach \(name): \(reason)"
        case let .keychain(status):
            return "Couldn't use the Keychain (\(status))."
        }
    }
}
