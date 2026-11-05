import Foundation

public enum VoiceError: LocalizedError {
    case notPrepared
    case alreadyListening
    case notListening
    case microphoneDenied
    case microphoneUnavailable
    case passwordField
    case accessibilityNeeded
    case inputMonitoringNeeded
    case downloadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notPrepared: return "Still getting my ears on. Give me a moment."
        case .alreadyListening: return "I'm already listening."
        case .notListening: return "I wasn't listening."
        case .microphoneDenied: return "I need the microphone. You can turn it on in System Settings, under Privacy & Security."
        case .microphoneUnavailable: return "I can't find a microphone."
        case .passwordField: return "That's a password field, so I won't type there."
        case .accessibilityNeeded: return "To type for you, I need Accessibility access in System Settings, under Privacy & Security."
        case .inputMonitoringNeeded: return "To hear your hold key, I need Input Monitoring in System Settings, under Privacy & Security."
        case .downloadFailed(let what): return "Couldn't download \(what). Check your connection and try again."
        }
    }
}
