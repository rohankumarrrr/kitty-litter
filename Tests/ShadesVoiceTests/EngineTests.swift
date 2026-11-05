import ShadesCore
@testable import ShadesVoice
import XCTest

/// Answers with canned text, so the engine's flow can be tested without any model.
private final class FakeRecognizer: SpeechRecognizing {
    var finalText = "Um, let's meet at three, no, actually four."
    var partialText = "let's meet"
    var finishDelay: TimeInterval = 0
    private(set) var loaded = false
    private(set) var draftedSampleCounts: [Int] = []
    private(set) var finishedSampleCount: Int?
    private(set) var vocabulary: [String] = []

    func load(progress: @escaping @Sendable (Double) -> Void) async throws {
        progress(0.5)
        progress(1)
        loaded = true
    }

    func setVocabulary(_ words: [String]) async { vocabulary = words }

    func draft(_ samples: [Float]) async throws -> String {
        draftedSampleCounts.append(samples.count)
        return partialText
    }

    func finish(_ samples: [Float]) async throws -> String {
        finishedSampleCount = samples.count
        if finishDelay > 0 { try await Task.sleep(nanoseconds: UInt64(finishDelay * 1e9)) }
        return finalText
    }
}

/// Counts starts and stops, and never touches a microphone.
private final class FakeSource: AudioSource {
    var isOpen = false
    var starts = 0
    var stops = 0
    var failure: Error?
    private var deliver: (([Float]) -> Void)?

    func prepare() throws {}

    func start(_ onSamples: @escaping ([Float]) -> Void) throws {
        if let failure { throw failure }
        starts += 1
        isOpen = true
        deliver = onSamples
    }

    func stop() {
        stops += 1
        isOpen = false
        deliver = nil
    }

    func send(seconds: Double, value: Float = 0.1) {
        deliver?([Float](repeating: value, count: Int(seconds * AudioFormat.sampleRate)))
    }
}

final class EngineTests: XCTestCase {
    private var options: ParakeetVoiceEngine.Options {
        var options = ParakeetVoiceEngine.Options()
        options.useCleanupModel = false
        options.tailMinimumSeconds = 0
        options.tailMaximumSeconds = 0
        options.partialInterval = 0.02
        options.firstPartialSeconds = 0.1
        return options
    }

    private func makeEngine(_ recognizer: FakeRecognizer = FakeRecognizer()) async throws -> (ParakeetVoiceEngine, FakeSource, FakeRecognizer) {
        let source = FakeSource()
        let engine = ParakeetVoiceEngine(source: source, recognizer: recognizer, options: options)
        try await engine.prepare()
        return (engine, source, recognizer)
    }

    private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func testBeginBeforePrepareThrows() {
        let engine = ParakeetVoiceEngine(source: FakeSource(), recognizer: FakeRecognizer(), options: options)
        XCTAssertThrowsError(try engine.begin())
    }

    func testAWholeTake() async throws {
        let (engine, source, recognizer) = try await makeEngine()
        try engine.begin()
        await waitUntil { source.isOpen }
        source.send(seconds: 1)
        let transcript = try await engine.end()
        XCTAssertEqual(transcript.raw, "Um, let's meet at three, no, actually four.")
        XCTAssertEqual(transcript.cleaned, "Let's meet at four.")
        XCTAssertEqual(transcript.audioSeconds, 1, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(transcript.latencySeconds, 0)
        XCTAssertFalse(source.isOpen, "the mic has to be off once the key is up")
        XCTAssertEqual(recognizer.finishedSampleCount, Int(AudioFormat.sampleRate))
    }

    func testTheMicIsOffUntilPressedAndAfterEveryTake() async throws {
        let (engine, source, _) = try await makeEngine()
        XCTAssertFalse(source.isOpen)
        XCTAssertEqual(source.starts, 0)
        for _ in 0..<3 {
            try engine.begin()
            await waitUntil { source.isOpen }
            source.send(seconds: 0.5)
            _ = try await engine.end()
            XCTAssertFalse(source.isOpen)
        }
        XCTAssertEqual(source.starts, 3)
    }

    func testBeginTwiceThrows() async throws {
        let (engine, _, _) = try await makeEngine()
        try engine.begin()
        XCTAssertThrowsError(try engine.begin())
        engine.cancel()
    }

    func testEndWithoutBeginThrows() async throws {
        let (engine, _, _) = try await makeEngine()
        do {
            _ = try await engine.end()
            XCTFail("should have thrown")
        } catch {
            XCTAssertNotNil(error as? VoiceError)
        }
    }

    func testCancelClosesTheMicAndAllowsAnotherTake() async throws {
        let (engine, source, recognizer) = try await makeEngine()
        try engine.begin()
        await waitUntil { source.isOpen }
        source.send(seconds: 1)
        engine.cancel()
        await waitUntil { !source.isOpen }
        XCTAssertFalse(source.isOpen)
        XCTAssertNil(recognizer.finishedSampleCount)
        try engine.begin()
        await waitUntil { source.isOpen }
        source.send(seconds: 0.5)
        let transcript = try await engine.end()
        XCTAssertEqual(transcript.cleaned, "Let's meet at four.")
    }

    func testAPressDuringTheTailCantStealTheMic() async throws {
        var options = self.options
        options.tailMinimumSeconds = 0.05
        options.tailMaximumSeconds = 0.1
        let source = FakeSource()
        let recognizer = FakeRecognizer()
        let engine = ParakeetVoiceEngine(source: source, recognizer: recognizer, options: options)
        try await engine.prepare()
        try engine.begin()
        await waitUntil { source.isOpen }
        source.send(seconds: 0.5)

        async let first = engine.end()
        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertThrowsError(try engine.begin())
        _ = try await first

        // Once the mic has closed, the next press works.
        try engine.begin()
        await waitUntil { source.isOpen }
        source.send(seconds: 0.5)
        let second = try await engine.end()
        XCTAssertEqual(second.cleaned, "Let's meet at four.")
    }

    func testAMicThatNeverDeliversSaysSo() async throws {
        let (engine, source, _) = try await makeEngine()
        try engine.begin()
        await waitUntil { source.isOpen }
        try await Task.sleep(nanoseconds: 550_000_000)
        do {
            _ = try await engine.end()
            XCTFail("should have thrown")
        } catch {
            XCTAssertNotNil(error as? VoiceError)
        }
    }

    func testATapGivesNothing() async throws {
        let (engine, source, recognizer) = try await makeEngine()
        try engine.begin()
        await waitUntil { source.isOpen }
        source.send(seconds: 0.05)
        let transcript = try await engine.end()
        XCTAssertEqual(transcript.raw, "")
        XCTAssertEqual(transcript.cleaned, "")
        XCTAssertNil(recognizer.finishedSampleCount)
    }

    func testPartialsArriveWhileTalking() async throws {
        let (engine, source, recognizer) = try await makeEngine()
        try engine.begin()
        await waitUntil { source.isOpen }
        source.send(seconds: 0.5)
        var received: [String] = []
        var iterator = engine.partials.makeAsyncIterator()
        while received.last != "let's meet", let next = await iterator.next() {
            received.append(next)
        }
        XCTAssertEqual(received.last, "let's meet")
        XCTAssertFalse(recognizer.draftedSampleCounts.isEmpty)
        _ = try await engine.end()
    }

    func testPartialsStopAfterRelease() async throws {
        let (engine, source, recognizer) = try await makeEngine()
        try engine.begin()
        await waitUntil { source.isOpen }
        source.send(seconds: 0.5)
        await waitUntil { !recognizer.draftedSampleCounts.isEmpty }
        _ = try await engine.end()
        let count = recognizer.draftedSampleCounts.count
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(recognizer.draftedSampleCounts.count, count)
    }

    func testPartialWindowsNeverExceedTheModelsWindow() async throws {
        let (engine, source, recognizer) = try await makeEngine()
        try engine.begin()
        await waitUntil { source.isOpen }
        source.send(seconds: 40)
        await waitUntil { recognizer.draftedSampleCounts.count >= 2 }
        _ = try await engine.end()
        XCTAssertLessThanOrEqual(recognizer.draftedSampleCounts.max() ?? 0, Int(15 * AudioFormat.sampleRate))
    }

    func testAFailedMicComesOutOfEnd() async throws {
        let (engine, source, _) = try await makeEngine()
        source.failure = VoiceError.microphoneUnavailable
        try engine.begin()
        await waitUntil { engine.lastTimings.partialCount == 0 }
        try await Task.sleep(nanoseconds: 20_000_000)
        do {
            _ = try await engine.end()
            XCTFail("should have thrown")
        } catch {
            XCTAssertNotNil(error as? VoiceError)
        }
    }

    func testVocabularyReachesRecognizerAndSpelling() async throws {
        let recognizer = FakeRecognizer()
        recognizer.finalText = "Push it to git hub."
        let (engine, source, _) = try await makeEngine(recognizer)
        await engine.applyVocabulary(["GitHub"])
        XCTAssertEqual(recognizer.vocabulary, ["GitHub"])
        try engine.begin()
        await waitUntil { source.isOpen }
        source.send(seconds: 0.5)
        let transcript = try await engine.end()
        XCTAssertEqual(transcript.cleaned, "Push it to GitHub.")
    }

    func testTheTailWaitsForTheLastWordToEnd() async throws {
        var options = self.options
        options.tailMinimumSeconds = 0.01
        options.tailMaximumSeconds = 0.3
        let source = FakeSource()
        let engine = ParakeetVoiceEngine(source: source, recognizer: FakeRecognizer(), options: options)
        try await engine.prepare()

        // Still talking at release: stays open until the maximum.
        try engine.begin()
        await waitUntil { source.isOpen }
        source.send(seconds: 0.5, value: 0.2)
        var transcript = try await engine.end()
        XCTAssertGreaterThanOrEqual(engine.lastTimings.tail, 0.28)

        // Already quiet: closes straight away.
        try engine.begin()
        await waitUntil { source.isOpen }
        source.send(seconds: 0.5, value: 0.2)
        source.send(seconds: 0.2, value: 0.001)
        transcript = try await engine.end()
        XCTAssertLessThan(engine.lastTimings.tail, 0.15)
        XCTAssertEqual(transcript.cleaned, "Let's meet at four.")
    }

    func testNothingButSilenceGivesNothing() async throws {
        let (engine, source, recognizer) = try await makeEngine()
        try engine.begin()
        await waitUntil { source.isOpen }
        source.send(seconds: 1, value: 0.0005)
        let transcript = try await engine.end()
        XCTAssertEqual(transcript.cleaned, "")
        XCTAssertNil(recognizer.finishedSampleCount)
    }

    func testLevelIsScaled() {
        XCTAssertEqual(ParakeetVoiceEngine.level(of: []), 0)
        XCTAssertEqual(ParakeetVoiceEngine.level(of: [Float](repeating: 0, count: 160)), 0)
        XCTAssertEqual(ParakeetVoiceEngine.level(of: [Float](repeating: 1, count: 160)), 1)
        let middle = ParakeetVoiceEngine.level(of: [Float](repeating: 0.03, count: 160))
        XCTAssertGreaterThan(middle, 0.2)
        XCTAssertLessThan(middle, 0.9)
    }

    func testSetupProgressReachesReady() async throws {
        let engine = ParakeetVoiceEngine(source: FakeSource(), recognizer: FakeRecognizer(), options: options)
        final class Box { var stages: [ParakeetVoiceEngine.SetupProgress.Stage] = [] }
        let box = Box()
        engine.onSetupProgress = { box.stages.append($0.stage) }
        try await engine.prepare()
        XCTAssertEqual(box.stages.last, .ready)
        XCTAssertTrue(box.stages.contains(.speechModel))
    }
}

final class ModelStoreTests: XCTestCase {
    func testDigestMatchesAKnownValue() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("hello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try ModelStore.digest(of: url), "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }

    func testAFileOfTheRightSizeIsNotDownloadedAgain() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("model.bin")
        try Data(repeating: 1, count: 10).write(to: file)
        // An address that can't work, so this would fail if it tried.
        let unreachable = URL(string: "http://127.0.0.1:9/none")!
        try await ModelStore.fetch(from: unreachable, to: file, byteCount: 10, sha256: "unused", progress: { _ in })
    }
}

final class AudioTests: XCTestCase {
    func testResamplerDownsamplesTo16k() throws {
        let resampler = try XCTUnwrap(Resampler(from: 48_000))
        var input = [Float](repeating: 0, count: 48_000)
        for i in input.indices { input[i] = sin(2 * .pi * 440 * Float(i) / 48_000) * 0.5 }
        var output: [Float] = []
        // In device-sized pieces, as the mic delivers it.
        var position = 0
        while position < input.count {
            let end = min(position + 512, input.count)
            output += input[position..<end].withUnsafeBufferPointer { resampler.convert($0) }
            position = end
        }
        XCTAssertEqual(Double(output.count), 16_000, accuracy: 400)
        let peak = output.map(abs).max() ?? 0
        XCTAssertEqual(peak, 0.5, accuracy: 0.1)
    }

    func testResamplerRejectsNonsense() {
        XCTAssertNil(Resampler(from: 0))
    }

    func testFileSourceSkipsWhatTheMicWouldHaveMissed() throws {
        let samples = (0..<16_000).map { Float($0) }
        let source = FileAudioSource(samples: samples, speed: 0, startDelay: 0.5)
        let done = expectation(description: "finished")
        var received: [Float] = []
        source.onFinished = { done.fulfill() }
        try source.start { received += $0 }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(received.count, 8_000)
        XCTAssertEqual(received.first, 8_000)
    }

    func testFileSourceStops() throws {
        let source = FileAudioSource(samples: [Float](repeating: 0, count: 160_000), speed: 1)
        var count = 0
        let lock = NSLock()
        try source.start { samples in
            lock.withLock { count += samples.count }
        }
        Thread.sleep(forTimeInterval: 0.1)
        source.stop()
        let atStop = lock.withLock { count }
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertLessThanOrEqual(lock.withLock { count }, atStop + 640)
        XCTAssertLessThan(atStop, 160_000)
    }

    func testDraftFollowsTheInput() {
        var cursor = 0
        // After [1, 2], the input says 3, 4 come next.
        XCTAssertEqual(LlamaModel.draft(after: [1, 2], from: [1, 2, 3, 4, 5], count: 2, cursor: &cursor), [3, 4])
        XCTAssertEqual(cursor, 2)
        // A repeated word doesn't send it back to the start.
        XCTAssertEqual(LlamaModel.draft(after: [9, 1], from: [1, 2, 3, 1, 4], count: 1, cursor: &cursor), [4])
        // Nothing to go on.
        var fresh = 0
        XCTAssertEqual(LlamaModel.draft(after: [7], from: [1, 2, 3], count: 2, cursor: &fresh), [])
        XCTAssertEqual(LlamaModel.draft(after: [], from: [1, 2, 3], count: 2, cursor: &fresh), [])
    }

    func testLongTranscriptsAreChunked() {
        let short = "one two three"
        XCTAssertEqual(ModelCleaner.chunks(of: short), [short])
        let long = (0..<1000).map { "w\($0)." }.joined(separator: " ")
        let chunks = ModelCleaner.chunks(of: long, maxWords: 100)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertEqual(chunks.joined(separator: " "), long)
    }
}
