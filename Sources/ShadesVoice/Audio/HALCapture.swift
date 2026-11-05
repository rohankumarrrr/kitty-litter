import AudioToolbox
import CoreAudio
import Foundation
import os

/// Reads the microphone through Core Audio's own input unit. It has far less to set up at start
/// than AVAudioEngine, and the unit can be made ready ahead of time without opening the mic.
final class HALCapture {
    enum Failure: Error {
        case noUnit, setup(OSStatus), start(OSStatus)
    }

    private(set) var device: AudioDevices.Device
    let sampleRate: Double
    private var unit: AudioUnit?
    private let ring: CaptureRing
    private var scratch: UnsafeMutablePointer<Float>
    private let scratchFrames: Int
    private var consumer: Thread?
    private let wake = DispatchSemaphore(value: 0)
    private var onSamples: (([Float]) -> Void)?
    private let stateLock = NSLock()
    private var running = false
    /// Which start the drain thread belongs to, so a slow old thread can't pick up a new take's audio.
    private var session = 0

    init(device: AudioDevices.Device) throws {
        self.device = device
        scratchFrames = 8192
        scratch = .allocate(capacity: scratchFrames)
        ring = CaptureRing(capacity: 96_000 * 2)

        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &description) else { throw Failure.noUnit }
        var created: AudioUnit?
        let status = AudioComponentInstanceNew(component, &created)
        guard status == noErr, let unit = created else { throw Failure.setup(status) }
        self.unit = unit

        var on: UInt32 = 1
        var off: UInt32 = 0
        let flagSize = UInt32(MemoryLayout<UInt32>.size)
        try Self.check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &on, flagSize))
        try Self.check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &off, flagSize))

        var id = device.id
        try Self.check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size)))

        var hardware = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try Self.check(AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &hardware, &size))
        guard hardware.mSampleRate > 0 else { throw Failure.setup(-1) }
        sampleRate = hardware.mSampleRate

        // The unit won't change the sample rate on the way in, so that's done on our side.
        var client = AudioStreamBasicDescription(
            mSampleRate: hardware.mSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        try Self.check(AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &client, size))

        var callback = AURenderCallbackStruct(
            inputProc: { context, flags, timestamp, bus, frames, _ -> OSStatus in
                let capture = Unmanaged<HALCapture>.fromOpaque(context).takeUnretainedValue()
                return capture.render(flags: flags, timestamp: timestamp, bus: bus, frames: frames)
            },
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        try Self.check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)))
        try Self.check(AudioUnitInitialize(unit))
    }

    deinit {
        stop()
        if let unit {
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
        }
        scratch.deallocate()
    }

    private static func check(_ status: OSStatus) throws {
        guard status == noErr else { throw Failure.setup(status) }
    }

    func start(_ onSamples: @escaping ([Float]) -> Void) throws {
        guard let unit else { throw Failure.noUnit }
        self.onSamples = onSamples
        ring.reset()
        let current = stateLock.withLock {
            running = true
            session += 1
            return session
        }

        let thread = Thread { [weak self] in self?.drain(session: current) }
        thread.qualityOfService = .userInteractive
        thread.name = "shades.voice.capture"
        consumer = thread
        thread.start()

        let status = AudioOutputUnitStart(unit)
        guard status == noErr else {
            stop()
            throw Failure.start(status)
        }
    }

    func stop() {
        let wasRunning = stateLock.withLock {
            defer { running = false }
            return running
        }
        guard wasRunning else { return }
        if let unit { AudioOutputUnitStop(unit) }
        wake.signal()
        consumer = nil
        onSamples = nil
    }

    /// Runs on the audio thread, so it copies and leaves.
    private func render(
        flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timestamp: UnsafePointer<AudioTimeStamp>,
        bus: UInt32,
        frames: UInt32
    ) -> OSStatus {
        guard let unit, Int(frames) <= scratchFrames else { return noErr }
        var list = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: frames * 4, mData: scratch)
        )
        let status = AudioUnitRender(unit, flags, timestamp, bus, frames, &list)
        guard status == noErr else { return status }
        ring.write(scratch, count: Int(frames))
        wake.signal()
        return noErr
    }

    private func drain(session current: Int) {
        guard let resampler = Resampler(from: sampleRate), let callback = onSamples else { return }
        let block = UnsafeMutablePointer<Float>.allocate(capacity: 8192)
        defer { block.deallocate() }
        while stateLock.withLock({ running && session == current }) {
            wake.wait()
            while true {
                let count = ring.read(block, capacity: 8192)
                guard count > 0 else { break }
                let out = resampler.convert(UnsafeBufferPointer(start: block, count: count))
                if !out.isEmpty { callback(out) }
            }
        }
    }
}

/// A fixed buffer between the audio thread and everyone else.
private final class CaptureRing {
    private let storage: UnsafeMutablePointer<Float>
    private let capacity: Int
    private let lock: UnsafeMutablePointer<os_unfair_lock>
    private var head = 0
    private var count = 0

    init(capacity: Int) {
        self.capacity = capacity
        storage = .allocate(capacity: capacity)
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
    }

    deinit {
        storage.deallocate()
        lock.deallocate()
    }

    func reset() {
        os_unfair_lock_lock(lock)
        head = 0
        count = 0
        os_unfair_lock_unlock(lock)
    }

    func write(_ source: UnsafePointer<Float>, count frames: Int) {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        // If nobody's draining, the oldest audio goes.
        let writable = min(frames, capacity)
        for i in 0..<writable {
            storage[(head + count + i) % capacity] = source[i]
        }
        count += writable
        if count > capacity {
            head = (head + count - capacity) % capacity
            count = capacity
        }
    }

    func read(_ target: UnsafeMutablePointer<Float>, capacity wanted: Int) -> Int {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        let taken = min(wanted, count)
        for i in 0..<taken {
            target[i] = storage[(head + i) % capacity]
        }
        head = (head + taken) % capacity
        count -= taken
        return taken
    }
}
