import Foundation

/// Lets the benchmark drive the cleanup model directly, to compare ways of using it.
package final class CleanupModelProbe {
    let model: LlamaModel
    package struct Result { package var text: String; package var seconds: Double; package var promptTokens: Int; package var outputTokens: Int; package var drafted: Int; package var batches: Int }
    package init(path: String) throws { model = try LlamaModel(path: path) }
    package func warmS1() throws { try model.warm(prefix: S1Mini.prefix(structure: .prose)) }
    package func s1(_ transcript: String, draft: Int, structure: String = "prose") throws -> Result {
        let t0 = Date()
        let structure = S1Mini.Structure(rawValue: structure) ?? .prose
        let c = try model.complete(prompt: S1Mini.prompt(transcript: transcript, structure: structure), draftSource: transcript, draftLength: draft, maxTokens: S1Mini.maxTokens(forInputWords: transcript.split(separator: " ").count))
        return Result(text: c.text, seconds: Date().timeIntervalSince(t0), promptTokens: c.promptTokens, outputTokens: c.outputTokens, drafted: c.draftedTokens, batches: c.batches)
    }
    package func raw(prompt: String, source: String, draft: Int, max: Int) throws -> Result {
        let t0 = Date()
        let c = try model.complete(prompt: prompt, draftSource: source, draftLength: draft, maxTokens: max)
        return Result(text: c.text, seconds: Date().timeIntervalSince(t0), promptTokens: c.promptTokens, outputTokens: c.outputTokens, drafted: c.draftedTokens, batches: c.batches)
    }
    package func release() { model.release() }

    /// Runs the real first-use download into `folder`, for checking progress and the checksum.
    package static func downloadModel(to folder: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let target = folder.appendingPathComponent(S1Mini.fileName)
        try await ModelStore.fetch(from: S1Mini.url, to: target, byteCount: S1Mini.byteCount, sha256: S1Mini.sha256, progress: progress)
        return target
    }
}
