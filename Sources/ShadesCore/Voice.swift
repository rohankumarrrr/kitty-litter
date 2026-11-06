import Foundation

/// What was said, as heard and as tidied up.
public struct Transcript: Sendable, Equatable {
    public var raw: String
    public var cleaned: String
    public var audioSeconds: Double
    /// From letting go of the key to having the final text.
    public var latencySeconds: Double

    public init(raw: String, cleaned: String, audioSeconds: Double, latencySeconds: Double) {
        self.raw = raw
        self.cleaned = cleaned
        self.audioSeconds = audioSeconds
        self.latencySeconds = latencySeconds
    }
}

public protocol VoiceEngine: AnyObject {
    /// Loads the speech model so the first press is as fast as every other.
    func prepare() async throws
    /// Words the engine should expect, such as project names.
    func setVocabulary(_ words: [String])
    func begin() throws
    /// Live text while you're still talking.
    var partials: AsyncStream<String> { get }
    /// Microphone level from 0 to 1, for the cat to react to.
    var levels: AsyncStream<Float> { get }
    func end() async throws -> Transcript
    func cancel()
}

/// Puts text wherever the cursor is, in any app.
public protocol TextInserting: AnyObject {
    func insert(_ text: String) async throws
    /// Puts `text` in place of the selection, but only if the field in front, in the app with `bundleID`, still has
    /// exactly `original` selected and takes the change. `false` means nothing changed.
    func replaceSelection(_ original: String, in bundleID: String?, with text: String) async -> Bool
}

/// A key you hold down to talk.
public enum HoldKey: String, Codable, Sendable, CaseIterable {
    case fn, rightOption, rightCommand, rightControl, off
}

/// Notices hold keys anywhere in the system, without taking them from other apps.
public protocol KeyHoldMonitoring: AnyObject {
    var onPress: ((HoldKey) -> Void)? { get set }
    var onRelease: ((HoldKey) -> Void)? { get set }
    func start(keys: [HoldKey]) throws
    func stop()
}
