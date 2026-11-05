import Accelerate
import Foundation
import llama

/// A language model loaded through llama.cpp and kept in memory. One call at a time.
///
/// Decoding is always greedy. Output that follows the input closely is drafted from the input and
/// checked in one batch, so cleanup, which mostly copies, runs several times faster with the same result.
final class LlamaModel {
    enum Failure: Error {
        case load, context, tokenize, decode, tooLong, timedOut
    }

    struct Completion {
        var text: String
        var promptTokens: Int
        var outputTokens: Int
        /// Tokens that came from a draft and passed the model's check.
        var draftedTokens: Int
        var batches: Int
    }

    private let model: OpaquePointer
    private let context: OpaquePointer
    private let vocab: OpaquePointer
    private var batch: llama_batch
    private let contextSize: Int32
    private let vocabSize: Int32
    /// The tokens in the context's memory, reused when the next prompt starts the same way.
    private var cached: [llama_token] = []
    private var prefixTokens: [llama_token] = []

    /// How many input tokens to try at once. More helps only until the first wrong guess.
    static let defaultDraftLength = 8

    init(path: String, contextSize: Int32 = 2048, threads: Int32 = 4) throws {
        Self.startBackend()

        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = -1
        guard let model = llama_model_load_from_file(path, modelParams) else { throw Failure.load }

        var contextParams = llama_context_default_params()
        contextParams.n_ctx = UInt32(contextSize)
        contextParams.n_batch = UInt32(contextSize)
        contextParams.n_ubatch = 512
        contextParams.n_threads = threads
        contextParams.n_threads_batch = threads
        contextParams.no_perf = true
        guard let context = llama_init_from_model(model, contextParams), let vocab = llama_model_get_vocab(model) else {
            llama_model_free(model)
            throw Failure.context
        }

        self.model = model
        self.context = context
        self.vocab = vocab
        self.contextSize = contextSize
        self.vocabSize = llama_vocab_n_tokens(vocab)
        self.batch = llama_batch_init(contextSize, 0, 1)
        Self.register(self)
    }

    deinit { release() }

    private var released = false

    /// llama.cpp's Metal backend aborts if a context is still alive at exit, so this has to run first.
    func release() {
        guard !released else { return }
        released = true
        Self.unregister(self)
        llama_batch_free(batch)
        llama_free(context)
        llama_model_free(model)
    }

    /// Runs the model on `prompt`, reusing whatever start of it is still in memory.
    ///
    /// - Parameters:
    ///   - draftSource: Text the output is likely to copy from.
    ///   - maxTokens: Stops here, for output that won't end on its own.
    ///   - deadline: Gives up with `Failure.timedOut` rather than holding up the caller.
    func complete(
        prompt: String,
        draftSource: String? = nil,
        draftLength: Int = LlamaModel.defaultDraftLength,
        maxTokens: Int,
        deadline: Date? = nil
    ) throws -> Completion {
        let promptTokens = try tokenize(prompt, special: true)
        let source = try draftSource.map { try tokenize($0, special: false) } ?? []
        guard promptTokens.count + maxTokens < Int(contextSize) else { throw Failure.tooLong }

        try feed(promptTokens)
        defer { forgetAfterPrefix() }

        var output: [llama_token] = []
        var drafted = 0
        var batches = 0
        var position = Int32(promptTokens.count)
        var next = bestToken(row: -1)
        var finished = false
        var cursor = 0

        while !finished, output.count < maxTokens {
            if llama_vocab_is_eog(vocab, next) { break }
            if let deadline, Date() >= deadline { throw Failure.timedOut }
            output.append(next)

            let draft = draftLength > 0 ? Self.draft(after: output, from: source, count: draftLength, cursor: &cursor) : []
            let tokens = [next] + draft
            fillBatch(tokens, startingAt: position) { _ in true }
            guard llama_decode(context, batch) == 0 else { throw Failure.decode }
            batches += 1

            // Row i predicts what follows tokens[i]. Drafted tokens stand only while they match.
            var row: Int32 = 0
            var kept = 1
            while true {
                let predicted = bestToken(row: row)
                if Int(row) < draft.count, draft[Int(row)] == predicted, !llama_vocab_is_eog(vocab, predicted) {
                    output.append(predicted)
                    drafted += 1
                    kept += 1
                    row += 1
                    if output.count >= maxTokens { finished = true; break }
                } else {
                    next = predicted
                    break
                }
            }
            position += Int32(kept)
            if kept < tokens.count {
                llama_memory_seq_rm(llama_get_memory(context), 0, position, -1)
            }
        }

        return Completion(
            text: detokenize(output),
            promptTokens: promptTokens.count,
            outputTokens: output.count,
            draftedTokens: drafted,
            batches: batches
        )
    }

    /// Fills the cache with `prefix`, so every call that starts with it can skip it.
    func warm(prefix: String) throws {
        cached = []
        llama_memory_clear(llama_get_memory(context), true)
        prefixTokens = try tokenize(prefix, special: true)
        try feed(prefixTokens)
    }

    /// Runs one token through the GPU. It sleeps after a few idle minutes, and this
    /// wakes it while you're still talking, so the cleanup itself doesn't pay for that.
    func wake() throws {
        guard !prefixTokens.isEmpty else { return }
        try feed(prefixTokens)
    }

    /// Forgets everything after the shared prefix, so what you said doesn't sit in the model's memory.
    private func forgetAfterPrefix() {
        llama_memory_seq_rm(llama_get_memory(context), 0, Int32(prefixTokens.count), -1)
        cached = prefixTokens
    }

    // MARK: - Decoding

    /// Puts `tokens` in the context's memory, keeping any start they share with what's already there.
    private func feed(_ tokens: [llama_token]) throws {
        var shared = 0
        while shared < cached.count, shared < tokens.count, cached[shared] == tokens[shared] { shared += 1 }
        // The last token always gets decoded again, for its logits.
        if shared == tokens.count { shared -= 1 }
        llama_memory_seq_rm(llama_get_memory(context), 0, Int32(shared), -1)

        var position = shared
        while position < tokens.count {
            let end = min(position + 512, tokens.count)
            let isLast = end == tokens.count
            let count = end - position
            fillBatch(Array(tokens[position..<end]), startingAt: Int32(position)) { isLast && $0 == count - 1 }
            guard llama_decode(context, batch) == 0 else {
                cached = []
                throw Failure.decode
            }
            position = end
        }
        cached = tokens
    }

    private func fillBatch(_ tokens: [llama_token], startingAt start: Int32, logits wanted: (Int) -> Bool) {
        batch.n_tokens = Int32(tokens.count)
        for (i, token) in tokens.enumerated() {
            batch.token[i] = token
            batch.pos[i] = start + Int32(i)
            batch.n_seq_id[i] = 1
            batch.seq_id[i]![0] = 0
            batch.logits[i] = wanted(i) ? 1 : 0
        }
    }

    private func bestToken(row: Int32) -> llama_token {
        guard let logits = llama_get_logits_ith(context, row) else { return llama_vocab_eos(vocab) }
        var best: Float = 0
        var index: vDSP_Length = 0
        vDSP_maxvi(logits, 1, &best, &index, vDSP_Length(vocabSize))
        return llama_token(index)
    }

    /// The input tokens that follow the longest recent stretch of output found in the input.
    /// `cursor` marks how far through the input the output has got, so repeated words don't send it backwards.
    static func draft(after output: [llama_token], from source: [llama_token], count: Int, cursor: inout Int) -> [llama_token] {
        guard !source.isEmpty, !output.isEmpty else { return [] }
        for length in stride(from: min(3, output.count), through: 1, by: -1) {
            let tail = Array(output.suffix(length))
            for start in [cursor, 0] {
                var i = start
                while i + length <= source.count {
                    if source[i] == tail[0], Array(source[i..<(i + length)]) == tail {
                        let from = i + length
                        let end = min(from + count, source.count)
                        guard from < end else { break }
                        cursor = from
                        return Array(source[from..<end])
                    }
                    i += 1
                }
            }
        }
        return []
    }

    // MARK: - Text

    private func tokenize(_ text: String, special: Bool) throws -> [llama_token] {
        let length = Int32(text.utf8.count)
        var tokens = [llama_token](repeating: 0, count: Int(length) + 8)
        let count = llama_tokenize(vocab, text, length, &tokens, Int32(tokens.count), false, special)
        guard count >= 0 else { throw Failure.tokenize }
        return Array(tokens.prefix(Int(count)))
    }

    private func detokenize(_ tokens: [llama_token]) -> String {
        // Bytes rather than strings, because one character can straddle two tokens.
        var bytes: [UInt8] = []
        var buffer = [CChar](repeating: 0, count: 128)
        for token in tokens {
            let written = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
            if written > 0 { bytes += buffer.prefix(Int(written)).map { UInt8(bitPattern: $0) } }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    // MARK: - Process-wide setup

    private static let lock = NSLock()
    private static var live: [Unmanaged<LlamaModel>] = []
    private static var started = false
    private static var exitHandlerInstalled = false

    private static func startBackend() {
        lock.lock()
        defer { lock.unlock() }
        guard !started else { return }
        started = true
        // llama.cpp narrates to stderr by default. Nothing it says belongs in a log next to dictated text.
        llama_log_set({ _, _, _ in }, nil)
        llama_backend_init()
    }

    /// Exit handlers run last-registered first, and loading a model registers some of llama.cpp's own.
    /// Ours has to go in after those, so models are freed while the Metal backend is still alive.
    private static func register(_ model: LlamaModel) {
        lock.lock()
        defer { lock.unlock() }
        live.append(Unmanaged.passUnretained(model))
        guard !exitHandlerInstalled else { return }
        exitHandlerInstalled = true
        atexit {
            LlamaModel.lock.lock()
            let models = LlamaModel.live
            LlamaModel.live = []
            LlamaModel.lock.unlock()
            for model in models { model.takeUnretainedValue().release() }
        }
    }

    private static func unregister(_ model: LlamaModel) {
        lock.lock()
        live.removeAll { $0.toOpaque() == Unmanaged.passUnretained(model).toOpaque() }
        lock.unlock()
    }
}
