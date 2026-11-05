import Foundation
import ShadesVoice

extension Bench {
    /// Every clip played in real time through the real engine, the way the app uses it.
    static func pipeline(_ args: [String]) async throws {
        let quick = args.contains("--quick")
        let idlePause = args.contains("--idle")
        let voices = quick ? ["Samantha", "Daniel"] : Corpus.voices

        let source = FileAudioSource(samples: [], speed: 1)
        let engine = ParakeetVoiceEngine(source: source)
        let memoryBefore = Metrics.footprintMB()
        let t0 = Date()
        try await engine.prepare()
        print("Prepare, with models already downloaded: \(String(format: "%.1f", Date().timeIntervalSince(t0))) s")
        print("Memory after prepare: \(Int(Metrics.footprintMB())) MB (+\(Int(Metrics.footprintMB() - memoryBefore)) MB)")
        await engine.applyVocabulary(Corpus.vocabulary)

        var loaded = try loadClips(voices: voices)
        if let index = args.firstIndex(of: "--limit"), let limit = Int(args[index + 1]) {
            loaded = Array(loaded.shuffled().prefix(limit))
        }
        let finished = FinishSignal()
        source.onFinished = { finished.fire() }
        Task { for await _ in engine.partials {} }
        Task { for await _ in engine.levels {} }

        var raw = ErrorTally()
        var score = CleanScore()
        var total: [Double] = []
        var recognition: [Double] = []
        var cleanup: [Double] = []
        var wait: [Double] = []
        var firstPartial: [Double] = []
        var totalLong: [Double] = []
        var sources: [String: Int] = [:]
        var peak = Metrics.footprintMB()

        for (i, item) in loaded.enumerated() {
            source.samples = item.samples
            finished.reset()
            try engine.begin()
            await finished.wait()
            let transcript = try await engine.end()
            let timings = engine.lastTimings

            let scored = rawWords(item.clip.utterance, transcript.raw)
            raw.add(reference: scored.reference, hypothesis: scored.hypothesis)
            score.add(utterance: item.clip.utterance, raw: transcript.raw, cleaned: transcript.cleaned, milliseconds: nil)
            sources[timings.cleanupSource.rawValue, default: 0] += 1

            let ms = transcript.latencySeconds * 1000
            if item.seconds < 15 {
                total.append(ms)
                recognition.append(timings.recognition * 1000)
                cleanup.append(timings.cleanup * 1000)
                wait.append(timings.waitForPartial * 1000)
            } else {
                totalLong.append(ms)
            }
            if let first = timings.firstPartial { firstPartial.append(first * 1000) }
            peak = max(peak, Metrics.footprintMB())
            if idlePause, i % 10 == 9 { try await Task.sleep(nanoseconds: 30_000_000_000) }
        }

        func line(_ name: String, _ values: [Double]) -> String {
            "| \(name) | \(Int(Metrics.percentile(values, 50))) | \(Int(Metrics.percentile(values, 95))) | \(Int(values.max() ?? 0)) |"
        }
        print("\n\(loaded.count) clips across \(voices.count) voices, played in real time. Load \(loadAverage()).\n")
        print("| Release to final text, clips under 15 s | p50 ms | p95 ms | max ms |")
        print("|---|---:|---:|---:|")
        print(line("Total", total))
        print(line("Waiting for live text to finish", wait))
        print(line("Recognition with vocabulary", recognition))
        print(line("Cleanup", cleanup))
        if !totalLong.isEmpty { print(line("Total, clips 15 s and over", totalLong)) }
        print(line("First live text after pressing", firstPartial))
        print("\nRaw transcript WER: \(raw.percent) over \(raw.words) words. Peak memory: \(Int(peak)) MB.")
        print("Final text came from: \(sources.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))\n")
        print(cleanupHeader)
        print(score.row("Whole pipeline"))
        print("\nPer kind, words wrong after cleanup:")
        for kind in Utterance.Kind.allCases {
            if let tally = score.perKind[kind] { print("- \(kind.rawValue): \(tally.percent)") }
        }
        if args.contains("--verbose") { print(score.failures.joined(separator: "\n")) }
    }

    /// Whether a first press after sitting idle is slower. The GPU and Neural Engine can page out.
    static func idle(_ args: [String]) async throws {
        let source = FileAudioSource(samples: [], speed: 1)
        let engine = ParakeetVoiceEngine(source: source)
        try await engine.prepare()
        await engine.applyVocabulary(Corpus.vocabulary)
        let finished = FinishSignal()
        source.onFinished = { finished.fire() }
        Task { for await _ in engine.partials {} }
        Task { for await _ in engine.levels {} }
        let clips = try loadClips(voices: ["Samantha"]).filter { $0.seconds < 15 && $0.seconds > 2 }

        func take(_ item: Loaded) async throws -> (Double, Double, Double) {
            source.samples = item.samples
            finished.reset()
            try engine.begin()
            await finished.wait()
            let transcript = try await engine.end()
            let timings = engine.lastTimings
            return (transcript.latencySeconds * 1000, timings.recognition * 1000, timings.cleanup * 1000)
        }

        print("| Idle before the press | Release to text | Recognition | Cleanup | Next press, same |")
        print("|---:|---:|---:|---:|---:|")
        var next = 0
        let rows = args.compactMap(Int.init)
        for seconds in rows.isEmpty ? [0, 30, 120, 300, 600] : rows {
            if seconds > 0 { try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000) }
            let first = try await take(clips[next % clips.count])
            let second = try await take(clips[(next + 1) % clips.count])
            next += 2
            print("| \(seconds) s | \(Int(first.0)) ms | \(Int(first.1)) ms | \(Int(first.2)) ms | \(Int(second.0)) ms |")
        }
    }

    private static func loadAverage() -> String {
        var values = [Double](repeating: 0, count: 3)
        getloadavg(&values, 3)
        return String(format: "%.1f", values[0])
    }
}

/// Waits for a clip to finish playing.
final class FinishSignal {
    private let lock = NSLock()
    private var fired = false
    private var waiter: CheckedContinuation<Void, Never>?

    func reset() {
        lock.withLock { fired = false }
    }

    func fire() {
        lock.lock()
        fired = true
        let waiter = self.waiter
        self.waiter = nil
        lock.unlock()
        waiter?.resume()
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if fired {
                lock.unlock()
                continuation.resume()
            } else {
                waiter = continuation
                lock.unlock()
            }
        }
    }
}
