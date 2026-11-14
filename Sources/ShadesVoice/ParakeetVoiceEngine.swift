import Foundation
import ShadesCore

/// Hold-to-talk: audio goes in, live text comes out, and on release you get clean text fast.
public final class ParakeetVoiceEngine: VoiceEngine {
    public struct Options {
        /// People let go as the last word ends, so the mic stays on until it's quiet, within these limits.
        public var tailMinimumSeconds: TimeInterval = 0.03
        public var tailMaximumSeconds: TimeInterval = 0.15
        /// How often live text updates while you talk.
        public var partialInterval: TimeInterval = 0.4
        /// No live text until there's this much to go on.
        public var firstPartialSeconds: TimeInterval = 0.5
        /// Download and load the cleanup model. Without it, the rules do what they can.
        public var useCleanupModel = true
        /// Shorter than this is an accidental tap, not speech.
        public var minimumSpeechSeconds: TimeInterval = 0.15
        /// The mic turns itself off after this, in case a release is somehow never heard.
        public var maximumTakeSeconds: TimeInterval = 300
        /// Quieter than this all the way through means nothing was said. Models imagine words in silence.
        public var silenceLevel: Float = 0.002

        public init() {}
    }

    /// How far first-time setup has got.
    public struct SetupProgress: Sendable {
        public enum Stage: String, Sendable {
            case speechModel, cleanupModel, ready
        }

        public var stage: Stage
        public var fraction: Double
    }

    /// What one take spent its time on, for checking the feel.
    public struct Timings: Sendable {
        public var tail: TimeInterval = 0
        public var waitForPartial: TimeInterval = 0
        public var recognition: TimeInterval = 0
        public var cleanup: TimeInterval = 0
        public var firstPartial: TimeInterval?
        public var partialCount = 0
        public var cleanupSource: CleanupPipeline.Source = .raw
        public var cleanupRejection: String?
    }

    public let partials: AsyncStream<String>
    public let levels: AsyncStream<Float>
    /// May be called on any thread.
    public var onSetupProgress: ((SetupProgress) -> Void)?
    public private(set) var lastTimings = Timings()
    public let source: AudioSource

    private let options: Options
    private let recognizer: SpeechRecognizing
    private let modelCleaner: ModelCleaner?
    private let cleanup: CleanupPipeline
    private let partialContinuation: AsyncStream<String>.Continuation
    private let levelContinuation: AsyncStream<Float>.Continuation

    private let lock = NSLock()
    private var isPrepared = false
    private var current: Take?
    /// The mic stays on briefly after a release, and a new take has to wait for it to close.
    private var isCapturing = false
    private var pendingVocabulary: [String]?
    private var vocabularyTask: Task<Void, Never>?
    private let captureQueue = DispatchQueue(label: "shades.voice.begin", qos: .userInteractive)

    public init(
        source: AudioSource = MicrophoneSource(),
        recognizer: SpeechRecognizing = ParakeetRecognizer(),
        options: Options = Options()
    ) {
        self.source = source
        self.recognizer = recognizer
        self.options = options
        let cleaner = options.useCleanupModel ? ModelCleaner() : nil
        modelCleaner = cleaner
        cleanup = CleanupPipeline(model: cleaner)
        (partials, partialContinuation) = AsyncStream.makeStream(of: String.self, bufferingPolicy: .bufferingNewest(1))
        (levels, levelContinuation) = AsyncStream.makeStream(of: Float.self, bufferingPolicy: .bufferingNewest(1))
    }

    deinit {
        partialContinuation.finish()
        levelContinuation.finish()
    }

    // MARK: - Setup

    /// Loads speech first, because that's all you need to start talking. The cleanup model
    /// comes next, and until it's ready the rules stand in.
    public func prepare() async throws {
        try source.prepare()
        try await recognizer.load { [weak self] fraction in
            self?.report(.speechModel, fraction)
        }
        markPrepared()
        if let modelCleaner, !modelCleaner.isLoaded {
            do {
                try await ModelStore.fetch(
                    from: S1Mini.url,
                    to: ModelCleaner.defaultURL,
                    byteCount: S1Mini.byteCount,
                    sha256: S1Mini.sha256,
                    progress: { [weak self] fraction in self?.report(.cleanupModel, fraction) }
                )
                try await modelCleaner.load()
            } catch {
                // Dictation still works, just with plainer cleanup.
            }
        }
        report(.ready, 1)
    }

    private func markPrepared() {
        lock.lock()
        isPrepared = true
        lock.unlock()
    }

    private func report(_ stage: SetupProgress.Stage, _ fraction: Double) {
        onSetupProgress?(SetupProgress(stage: stage, fraction: fraction))
    }

    public func setVocabulary(_ words: [String]) {
        _ = queueVocabulary(words)
    }

    /// The same, for when you need it in place before going on.
    public func applyVocabulary(_ words: [String]) async {
        await queueVocabulary(words).value
    }

    /// The recognizer loads its model on the first set and isn't safe to call twice at once,
    /// so sets go in one at a time and only the newest waiting set is applied.
    private func queueVocabulary(_ words: [String]) -> Task<Void, Never> {
        lock.withLock {
            pendingVocabulary = words
            if let vocabularyTask { return vocabularyTask }
            let task = Task { await drainVocabulary() }
            vocabularyTask = task
            return task
        }
    }

    private func drainVocabulary() async {
        while let words = nextVocabulary() {
            cleanup.setVocabulary(words)
            await recognizer.setVocabulary(words)
        }
    }

    private func nextVocabulary() -> [String]? {
        lock.withLock {
            guard let words = pendingVocabulary else {
                vocabularyTask = nil
                return nil
            }
            pendingVocabulary = nil
            return words
        }
    }

    // MARK: - One take

    public func begin() throws {
        let pressed = Date()
        lock.lock()
        defer { lock.unlock() }
        guard isPrepared else { throw VoiceError.notPrepared }
        guard current == nil, !isCapturing else { throw VoiceError.alreadyListening }
        if source is MicrophoneSource, MicrophoneSource.authorization != .granted {
            if MicrophoneSource.authorization == .notAsked {
                Task { _ = await MicrophoneSource.requestAccess() }
            }
            throw VoiceError.microphoneDenied
        }

        let take = Take(pressed: pressed)
        current = take
        isCapturing = true
        partialContinuation.yield("")
        modelCleaner?.wake()

        // Opening the mic can block for a moment, and the key's main thread shouldn't feel that.
        let source = self.source
        let limit = options.maximumTakeSeconds
        captureQueue.async { [weak self] in
            do {
                try source.start { samples in
                    take.append(samples)
                    self?.levelContinuation.yield(Self.level(of: samples))
                    if take.speechSeconds > limit, take.markLimitReached() {
                        self?.captureQueue.async { source.stop() }
                    }
                }
            } catch {
                take.fail(error)
            }
        }
        startPartials(for: take)
    }

    public func end() async throws -> Transcript {
        let released = Date()
        guard let take = takeCurrent() else { throw VoiceError.notListening }
        var timings = Timings()

        // Hear the rest of the last word, without waiting if it's already over.
        while Date().timeIntervalSince(released) < options.tailMaximumSeconds {
            let elapsed = Date().timeIntervalSince(released)
            if elapsed >= options.tailMinimumSeconds, take.recentPeak(seconds: 0.03) < Self.quietPeak { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        timings.tail = Date().timeIntervalSince(released)
        stopCapture()
        levelContinuation.yield(0)

        // The Neural Engine runs one thing at a time, so the last partial has to land first.
        let waitStart = Date()
        take.partialTask?.cancel()
        _ = await take.partialTask?.value
        timings.waitForPartial = Date().timeIntervalSince(waitStart)
        timings.firstPartial = take.firstPartialAt.map { $0.timeIntervalSince(take.pressed) }
        timings.partialCount = take.partialCount

        if let error = take.failure { throw error }

        let audio = take.audio()
        let seconds = take.speechSeconds
        // Half a second held with no audio at all means the mic never came alive.
        if seconds == 0, released.timeIntervalSince(take.pressed) > 0.5 { throw VoiceError.microphoneUnavailable }
        guard seconds >= options.minimumSpeechSeconds, take.loudest >= options.silenceLevel else {
            lastTimings = timings
            return Transcript(raw: "", cleaned: "", audioSeconds: seconds, latencySeconds: Date().timeIntervalSince(released))
        }

        let recognitionStart = Date()
        let raw = try await recognizer.finish(audio)
        timings.recognition = Date().timeIntervalSince(recognitionStart)

        let cleanupStart = Date()
        let outcome = await cleanup.clean(raw)
        timings.cleanup = Date().timeIntervalSince(cleanupStart)
        timings.cleanupSource = outcome.source
        timings.cleanupRejection = outcome.rejection
        lastTimings = timings

        return Transcript(
            raw: raw,
            cleaned: outcome.text,
            audioSeconds: seconds,
            latencySeconds: Date().timeIntervalSince(released)
        )
    }

    public func cancel() {
        guard let take = takeCurrent() else { return }
        stopCapture()
        take.partialTask?.cancel()
        levelContinuation.yield(0)
        partialContinuation.yield("")
    }

    private func takeCurrent() -> Take? {
        lock.lock()
        defer { lock.unlock() }
        let take = current
        current = nil
        return take
    }

    private func stopCapture() {
        let source = self.source
        // Queued behind `begin`'s start, so a very quick release can't leave the mic open.
        captureQueue.sync { source.stop() }
        lock.lock()
        isCapturing = false
        lock.unlock()
    }

    // MARK: - Live text

    private func startPartials(for take: Take) {
        let interval = options.partialInterval
        let first = options.firstPartialSeconds
        let recognizer = self.recognizer
        let continuation = partialContinuation
        take.partialTask = Task.detached(priority: .userInitiated) {
            var decodedUpTo = 0
            try? await Task.sleep(nanoseconds: UInt64(first * 1_000_000_000))
            while !Task.isCancelled {
                if take.sampleCount > decodedUpTo {
                    let window = take.partialWindow()
                    decodedUpTo = window.endsAt
                    if let text = try? await recognizer.draft(window.samples), !Task.isCancelled {
                        continuation.yield(take.addPartial(text, windowStart: window.startsAt, windowEnd: window.endsAt))
                    }
                }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    /// Below this peak the speaker has stopped, even with some room noise.
    static let quietPeak: Float = 0.01

    /// RMS on a perceptual scale, from about -60 dB to -15 dB.
    static func level(of samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let energy = samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(samples.count)
        let decibels = 10 * log10(max(energy, 1e-10))
        return min(1, max(0, (decibels + 60) / 45))
    }
}

/// The audio and live text of one press of the key.
private final class Take {
    let pressed: Date
    var partialTask: Task<Void, Never>?
    private(set) var firstPartialAt: Date?
    private(set) var partialCount = 0
    private(set) var failure: Error?

    private let lock = NSLock()
    private var samples: [Float] = []
    private var peak: Float = 0
    private var limitReached = false
    /// Live text past one window is the settled text so far plus a guess at the rest.
    private var settled = ""
    private var settledUpTo: Int

    /// The model's window is 15 seconds, and live text doesn't need more.
    private let partialWindowSamples = Int(14 * AudioFormat.sampleRate)
    /// Once this much is heard, that part stops changing and the window starts again after it.
    private let settleSamples = Int(12 * AudioFormat.sampleRate)

    init(pressed: Date) {
        self.pressed = pressed
        settledUpTo = 0
        samples.reserveCapacity(Int(30 * AudioFormat.sampleRate))
    }

    func append(_ new: [Float]) {
        var loudest: Float = 0
        for sample in new { loudest = max(loudest, abs(sample)) }
        lock.lock()
        samples.append(contentsOf: new)
        peak = max(peak, loudest)
        lock.unlock()
    }

    /// The loudest sample in the most recent stretch of audio.
    func recentPeak(seconds: Double) -> Float {
        lock.lock()
        defer { lock.unlock() }
        var peak: Float = 0
        for sample in samples.suffix(Int(seconds * AudioFormat.sampleRate)) { peak = max(peak, abs(sample)) }
        return peak
    }

    var loudest: Float {
        lock.lock()
        defer { lock.unlock() }
        return peak
    }

    /// True the first time it's called.
    func markLimitReached() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !limitReached else { return false }
        limitReached = true
        return true
    }

    func fail(_ error: Error) {
        lock.lock()
        failure = error
        lock.unlock()
    }

    var sampleCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return samples.count
    }

    var speechSeconds: Double {
        lock.lock()
        defer { lock.unlock() }
        return Double(samples.count) / AudioFormat.sampleRate
    }

    func audio() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }

    func partialWindow() -> (samples: [Float], startsAt: Int, endsAt: Int) {
        lock.lock()
        defer { lock.unlock() }
        let start = settledUpTo
        let end = min(samples.count, start + partialWindowSamples)
        return (Array(samples[start..<end]), start, end)
    }

    /// Returns the live text to show, moving the settled point forward once the window fills up.
    func addPartial(_ text: String, windowStart: Int, windowEnd: Int) -> String {
        lock.lock()
        defer { lock.unlock() }
        if firstPartialAt == nil { firstPartialAt = Date() }
        partialCount += 1
        let joined = settled.isEmpty ? text : settled + " " + text
        if windowEnd - windowStart >= settleSamples, windowStart == settledUpTo {
            settled = joined
            settledUpTo = windowEnd
        }
        return joined
    }
}
