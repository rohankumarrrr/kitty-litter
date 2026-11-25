import Foundation

public struct Transcript: Sendable, Equatable {
    public var raw: String
    public var cleaned: String
    public var audioSeconds: Double
    public var latencySeconds: Double

    public init(raw: String, cleaned: String, audioSeconds: Double, latencySeconds: Double) {
        self.raw = raw
        self.cleaned = cleaned
        self.audioSeconds = audioSeconds
        self.latencySeconds = latencySeconds
    }
}

public protocol VoiceEngine: AnyObject {
    func prepare() async throws
    func setVocabulary(_ words: [String])
    func begin() throws
    var partials: AsyncStream<String> { get }
    var levels: AsyncStream<Float> { get }
    func end() async throws -> Transcript
    func cancel()
}

public protocol TextInserting: AnyObject {
    func insert(_ text: String) async throws
    func replaceSelection(_ original: String, in bundleID: String?, with text: String) async -> Bool
}

public enum HoldKey: String, Codable, Sendable, CaseIterable {
    case fn, rightOption, rightCommand, rightControl, off
}

public protocol KeyHoldMonitoring: AnyObject {
    var onPress: ((HoldKey) -> Void)? { get set }
    var onRelease: ((HoldKey) -> Void)? { get set }
    func start(keys: [HoldKey]) throws
    func stop()
}
