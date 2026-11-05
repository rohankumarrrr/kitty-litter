import Foundation

/// Cleans text with a small on-device model made for exactly this: S1-mini by Superwhisper.
public final class ModelCleaner: TextCleaning {
    public struct Timing: Sendable {
        public var seconds: Double
        public var outputTokens: Int
        public var draftedTokens: Int
    }

    /// Past this the rules take over, so a stuck model can't hold up your text. Long takes get longer.
    public var timeLimit: TimeInterval = 1
    public var timeLimitPerWord: TimeInterval = 0.012
    public private(set) var lastTiming: Timing?

    private let queue = DispatchQueue(label: "shades.voice.cleanup", qos: .userInteractive)
    private var model: LlamaModel?
    private var lastUsed = Date()
    private let wakeAfterIdle: TimeInterval = 20

    public static var defaultURL: URL { ModelStore.folder.appendingPathComponent(S1Mini.fileName) }

    public init() {}

    public var isLoaded: Bool { queue.sync { model != nil } }

    public func load(from url: URL = ModelCleaner.defaultURL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    let model = try LlamaModel(path: url.path)
                    try model.warm(prefix: S1Mini.prefix(structure: .prose))
                    // The first real run sets up the GPU pipelines, and nobody should have to wait for that.
                    let warmUp = "Okay, um, so this is just a warm up, no, actually a test of the model."
                    for _ in 0..<2 {
                        _ = try model.complete(prompt: S1Mini.prompt(transcript: warmUp, structure: .prose), draftSource: warmUp, maxTokens: 32)
                    }
                    self.model = model
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Gets the GPU ready ahead of time. Only worth it after sitting idle, so most calls do nothing.
    public func wake() {
        queue.async {
            guard Date().timeIntervalSince(self.lastUsed) > self.wakeAfterIdle else { return }
            try? self.model?.wake()
            self.lastUsed = Date()
        }
    }

    public func unload() {
        queue.async {
            self.model?.release()
            self.model = nil
        }
    }

    public func clean(_ raw: String) async -> String? {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.run(raw))
            }
        }
    }

    private func run(_ raw: String) -> String? {
        guard let model else { return nil }
        let start = Date()
        lastUsed = start
        let deadline = start.addingTimeInterval(timeLimit + timeLimitPerWord * Double(raw.split(separator: " ").count))
        var pieces: [String] = []
        var outputTokens = 0
        var drafted = 0
        do {
            for chunk in Self.chunks(of: raw) {
                let words = chunk.split(whereSeparator: \.isWhitespace).count
                let completion = try model.complete(
                    prompt: S1Mini.prompt(transcript: chunk, structure: .prose),
                    draftSource: chunk,
                    maxTokens: S1Mini.maxTokens(forInputWords: words),
                    deadline: deadline
                )
                pieces.append(Self.tidy(completion.text))
                outputTokens += completion.outputTokens
                drafted += completion.draftedTokens
            }
        } catch {
            return nil
        }
        lastTiming = Timing(seconds: Date().timeIntervalSince(start), outputTokens: outputTokens, draftedTokens: drafted)
        return pieces.filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func tidy(_ text: String) -> String {
        var result = text
        if let end = result.range(of: "</think>") { result = String(result[end.upperBound...]) }
        for token in ["<|im_start|>", "<|im_end|>", "<|endoftext|>", "<think>"] {
            result = result.replacingOccurrences(of: token, with: "")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The model is built for dictation-length input, so long takes go through a sentence group at a time.
    static func chunks(of text: String, maxWords: Int = 350) -> [String] {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard words.count > maxWords else { return [text] }
        var chunks: [String] = []
        var current: [Substring] = []
        for word in words {
            current.append(word)
            let endsSentence = word.last.map { ".?!".contains($0) } ?? false
            if current.count >= maxWords || (endsSentence && current.count >= maxWords - 60) {
                chunks.append(current.joined(separator: " "))
                current = []
            }
        }
        if !current.isEmpty { chunks.append(current.joined(separator: " ")) }
        return chunks
    }
}
