import ShadesCore
@testable import ShadesVoice
import XCTest

/// Takes a while over each set of words, like the real one loading its model, and notes any overlap.
private final class SlowVocabularyRecognizer: SpeechRecognizing, @unchecked Sendable {
    private let lock = NSLock()
    private var running = 0
    private(set) var mostAtOnce = 0
    private(set) var applied: [[String]] = []

    func load(progress: @escaping @Sendable (Double) -> Void) async throws {}

    func setVocabulary(_ words: [String]) async {
        lock.withLock {
            running += 1
            mostAtOnce = max(mostAtOnce, running)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        lock.withLock {
            running -= 1
            applied.append(words)
        }
    }

    func draft(_ samples: [Float]) async throws -> String { "" }
    func finish(_ samples: [Float]) async throws -> String { "" }
}

final class VocabularyQueueTests: XCTestCase {
    func testManySetsAtOnceApplyOneAtATimeAndTheNewestWins() async {
        let recognizer = SlowVocabularyRecognizer()
        var options = ParakeetVoiceEngine.Options()
        options.useCleanupModel = false
        let engine = ParakeetVoiceEngine(source: FileAudioSource(samples: []), recognizer: recognizer, options: options)

        DispatchQueue.concurrentPerform(iterations: 50) { index in
            engine.setVocabulary(["Project \(index)"])
        }
        await engine.applyVocabulary(["Newest"])

        XCTAssertEqual(recognizer.mostAtOnce, 1)
        XCTAssertEqual(recognizer.applied.last, ["Newest"])
        XCTAssertLessThanOrEqual(recognizer.applied.count, 3, "sets that were replaced while waiting are skipped")
    }
}
