import Foundation

public protocol AudioSource: AnyObject {
    func prepare() throws
    func start(_ onSamples: @escaping ([Float]) -> Void) throws
    func stop()
}

public enum AudioFormat {
    public static let sampleRate = 16_000.0
}
