import Foundation

public enum T3Error: LocalizedError, Equatable {
    case notRunning
    case commandLineToolMissing
    case signInFailed
    /// This T3 Code speaks a different protocol than the one Shades was built against.
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
            return "T3 Code isn't running. Open it and try again."
        case .commandLineToolMissing:
            return "Couldn't find T3 Code's command line tool. Open T3 Code once, then try again."
        case .signInFailed:
            return "Couldn't sign in to T3 Code."
        case let .incompatibleServer(version):
            return "The Kitty Litter doesn't work with \(version.map { "T3 Code \($0)" } ?? "this version of T3 Code") yet. Check for an update to The Kitty Litter."
        case .unauthorized:
            return "T3 Code didn't accept the saved sign-in."
        case .connectionLost:
            return "Lost the connection to T3 Code."
        case .timedOut:
            return "T3 Code took too long to answer."
        case let .rejected(reason):
            return reason
        case let .attachmentNotSupported(name, reason):
            return "Couldn't attach \(name): \(reason)"
        case let .keychain(status):
            return "Couldn't use the Keychain (\(status))."
        }
    }
}
