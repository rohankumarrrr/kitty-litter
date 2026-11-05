import AVFoundation
import Foundation

/// The real microphone. It's only open between `start` and `stop`, so the orange dot means you're talking.
public final class MicrophoneSource: AudioSource {
    public enum Authorization {
        case granted, denied, notAsked
    }

    public static var authorization: Authorization {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .notDetermined: return .notAsked
        default: return .denied
        }
    }

    /// Shows the system prompt the first time.
    public static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    /// A specific microphone, or `nil` to follow the system's default.
    public var preferredDeviceUID: String?
    /// Skips Core Audio's input unit and uses AVAudioEngine, mostly for comparing the two.
    public var useEngineOnly = false
    /// How long the last `start` took from the call to the first audio, once that's known.
    public var lastStartLatency: TimeInterval? { latencyLock.withLock { startLatency } }
    /// What ended up running, for diagnostics.
    public private(set) var lastBackend = ""

    /// If the fast path shows no sign of life by now, the fallback takes over.
    /// A Bluetooth mic you chose yourself really can take seconds to wake.
    private let noAudioTimeout: TimeInterval = 0.5
    private let noAudioTimeoutBluetooth: TimeInterval = 3

    private let latencyLock = NSLock()
    private var startLatency: TimeInterval?
    private let lock = NSLock()
    private var capture: HALCapture?
    private var engine: AVAudioEngine?
    private var isRunning = false
    private var generation = 0
    private var halBroken = false
    private var watching = false

    public init() {}

    public func prepare() throws {
        // Setting up the unit can count as using the mic, so it waits until that's allowed.
        guard Self.authorization == .granted, !useEngineOnly else { return }
        rebuildCapture()
        guard !watching else { return }
        watching = true
        AudioDevices.watchChanges { [weak self] in self?.rebuildCapture() }
    }

    private func rebuildCapture() {
        lock.lock()
        defer { lock.unlock() }
        guard !isRunning else { return }
        capture = makeCapture()
    }

    private func makeCapture() -> HALCapture? {
        guard !halBroken, let device = AudioDevices.preferred(uid: preferredDeviceUID) else { return nil }
        return try? HALCapture(device: device)
    }

    public func start(_ onSamples: @escaping ([Float]) -> Void) throws {
        let began = DispatchTime.now()
        lock.lock()
        defer { lock.unlock() }
        isRunning = true
        generation += 1
        latencyLock.withLock { startLatency = nil }

        var firstAudio = true
        let wrapped: ([Float]) -> Void = { [weak self] samples in
            if firstAudio {
                firstAudio = false
                let nanos = DispatchTime.now().uptimeNanoseconds - began.uptimeNanoseconds
                self?.latencyLock.withLock { self?.startLatency = Double(nanos) / 1e9 }
            }
            onSamples(samples)
        }

        if !useEngineOnly, !halBroken {
            do {
                try startCapture(wrapped)
                watchForSilence(generation: generation, wrapped)
                return
            } catch {
                capture = nil
            }
        }
        try startEngine(wrapped)
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        isRunning = false
        generation += 1
        capture?.stop()
        stopEngine()
    }

    private func startCapture(_ onSamples: @escaping ([Float]) -> Void) throws {
        let device = AudioDevices.preferred(uid: preferredDeviceUID)
        if capture == nil || capture?.device.id != device?.id || (device.flatMap { AudioDevices.sampleRate(of: $0.id) } != capture?.sampleRate) {
            capture = makeCapture()
        }
        guard let capture else { throw HALCapture.Failure.noUnit }
        lastBackend = "hal"
        try capture.start(onSamples)
    }

    /// A unit can start and then deliver nothing. Better to lose half a second than the whole take.
    private func watchForSilence(generation: Int, _ onSamples: @escaping ([Float]) -> Void) {
        let timeout = capture?.device.isBluetooth == true ? noAudioTimeoutBluetooth : noAudioTimeout
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            defer { self.lock.unlock() }
            guard self.isRunning, self.generation == generation, self.lastStartLatency == nil else { return }
            self.capture?.stop()
            self.capture = nil
            self.halBroken = true
            try? self.startEngine(onSamples)
        }
    }

    private func startEngine(_ onSamples: @escaping ([Float]) -> Void) throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        if let device = AudioDevices.preferred(uid: preferredDeviceUID), let unit = input.audioUnit {
            var id = device.id
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        }

        // Choosing a device doesn't update the node's other side, and a tap on mismatched rates raises an
        // exception nothing can catch. So the rates get lined up by hand, and checked.
        let hardware = input.inputFormat(forBus: 0)
        if let unit = input.audioUnit, hardware.sampleRate > 0, input.outputFormat(forBus: 0).sampleRate != hardware.sampleRate {
            var client = input.outputFormat(forBus: 0).streamDescription.pointee
            client.mSampleRate = hardware.sampleRate
            AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &client, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.sampleRate == hardware.sampleRate, format.channelCount > 0,
              let resampler = Resampler(from: format.sampleRate)
        else { throw VoiceError.microphoneUnavailable }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            let out = resampler.convert(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            if !out.isEmpty { onSamples(out) }
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
        lastBackend = "engine"
    }

    private func stopEngine() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
    }
}
