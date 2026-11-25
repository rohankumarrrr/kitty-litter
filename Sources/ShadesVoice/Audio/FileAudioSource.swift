import AVFoundation
import Foundation

public final class FileAudioSource: AudioSource {
    public var samples: [Float]
    public var speed: Double
    public var startDelay: TimeInterval
    public var onFinished: (() -> Void)?

    private let chunkSeconds = 0.02
    private let queue = DispatchQueue(label: "shades.voice.file-audio", qos: .userInteractive)
    private let lock = NSLock()
    private var generation = 0

    public init(samples: [Float] = [], speed: Double = 1, startDelay: TimeInterval = 0) {
        self.samples = samples
        self.speed = speed
        self.startDelay = startDelay
    }

    public convenience init(url: URL, speed: Double = 1, startDelay: TimeInterval = 0) throws {
        self.init(samples: try Self.load(url), speed: speed, startDelay: startDelay)
    }

    public func prepare() throws {}

    public func start(_ onSamples: @escaping ([Float]) -> Void) throws {
        lock.lock()
        generation += 1
        let current = generation
        lock.unlock()

        let chunk = Int(AudioFormat.sampleRate * chunkSeconds)
        let skip = Int(startDelay * AudioFormat.sampleRate)
        let samples = self.samples
        let speed = self.speed
        let interval = speed > 0 ? chunkSeconds / speed : 0
        let startDelay = speed > 0 ? self.startDelay / speed : 0

        queue.async { [weak self] in
            var position = min(skip, samples.count)
            var next = DispatchTime.now() + startDelay
            while position < samples.count {
                guard let self, self.isCurrent(current) else { return }
                if interval > 0 { Self.sleep(until: next) }
                let end = min(position + chunk, samples.count)
                onSamples(Array(samples[position..<end]))
                position = end
                next = next + interval
            }
            guard let self, self.isCurrent(current) else { return }
            self.onFinished?()
        }
    }

    public func stop() {
        lock.lock()
        generation += 1
        lock.unlock()
    }

    private func isCurrent(_ value: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == value
    }

    private static func sleep(until time: DispatchTime) {
        let now = DispatchTime.now()
        guard time > now else { return }
        usleep(UInt32((time.uptimeNanoseconds - now.uptimeNanoseconds) / 1_000))
    }

    public static func load(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else { return [] }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else { return [] }
        let frames = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
        if format.sampleRate == AudioFormat.sampleRate { return Array(frames) }
        return Resampler(from: format.sampleRate)?.convert(frames) ?? []
    }
}
