import Foundation

/// Where the engine's audio comes from: the microphone in the app, a file in tests.
public protocol AudioSource: AnyObject {
    /// Does whatever can be done ahead of time. Must not open the microphone or ask for permission.
    func prepare() throws
    /// Starts delivering 16 kHz mono samples, on any thread.
    func start(_ onSamples: @escaping ([Float]) -> Void) throws
    func stop()
}

public enum AudioFormat {
    public static let sampleRate = 16_000.0
}
