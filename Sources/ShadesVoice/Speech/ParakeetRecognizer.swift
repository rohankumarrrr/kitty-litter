import CoreML
import FluidAudio
import Foundation

public final class ParakeetRecognizer: SpeechRecognizing {
    public enum Model: String, CaseIterable, Sendable {
        case ultra, v3, v2

        var version: AsrModelVersion {
            switch self {
            case .ultra: return .ultra
            case .v3: return .v3
            case .v2: return .v2
            }
        }
    }

    public struct VocabularySettings: Sendable {
        public var boost: Float
        public var minimumSimilarity: Float

        public init(boost: Float = 1.5, minimumSimilarity: Float = 0.6) {
            self.boost = boost
            self.minimumSimilarity = minimumSimilarity
        }
    }

    public var vocabularySettings = VocabularySettings()
    public private(set) var lastVocabularyChanges: [String] = []

    private let model: Model
    private var manager: AsrManager?
    private var decoderLayers = 2
    private var ctcModels: CtcModels?
    private let boosterLock = NSLock()
    private var booster: VocabularyBoostingSession?

    private let minimumSamples = 16_000

    public init(model: Model = .ultra) {
        self.model = model
    }

    public func load(progress: @escaping @Sendable (Double) -> Void) async throws {
        guard manager == nil else { return }
        let models = try await AsrModels.downloadAndLoad(version: model.version) { update in
            progress(update.fractionCompleted)
        }
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        decoderLayers = await manager.decoderLayerCount
        self.manager = manager
        _ = try await transcribe([Float](repeating: 0, count: minimumSamples))
    }

    public func setVocabulary(_ words: [String]) async {
        let terms = words.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !terms.isEmpty else {
            setBooster(nil)
            return
        }
        do {
            if ctcModels == nil {
                ctcModels = try await CtcModels.downloadAndLoad(variant: .ctc110m)
            }
            guard let ctcModels else { return }
            let vocabulary = CustomVocabularyContext(terms: terms.map { CustomVocabularyTerm(text: $0) })
            setBooster(try await VocabularyBoostingSession(
                vocabulary: vocabulary,
                ctcModels: ctcModels,
                config: VocabularyRescorer.Config(spotterRescueEnabled: false),
                thresholds: .init(cbw: vocabularySettings.boost, minSimilarity: vocabularySettings.minimumSimilarity)
            ))
        } catch {
            setBooster(nil)
        }
    }

    public func draft(_ samples: [Float]) async throws -> String {
        try await transcribe(samples).text
    }

    public func finish(_ samples: [Float]) async throws -> String {
        let result = try await transcribe(samples)
        guard let booster = boosterLock.withLock({ booster }), let timings = result.tokenTimings, !timings.isEmpty else { return result.text }
        guard booster.hasCTCRescoringCandidates(text: result.text, tokenTimings: timings) else { return result.text }
        guard let rescored = await booster.rescore(text: result.text, tokenTimings: timings, audioSamples: samples) else {
            return result.text
        }
        lastVocabularyChanges = rescored.replacements.filter(\.shouldReplace).map {
            "\($0.originalWord) (\($0.originalScore)) -> \($0.replacementWord ?? "") (\($0.replacementScore ?? 0))"
        }
        let replacements = rescored.replacements.compactMap { item -> (heard: String, term: String)? in
            guard item.shouldReplace, let term = item.replacementWord else { return nil }
            return (item.originalWord, term)
        }
        if replacements.allSatisfy({ VocabularyGate.allows(heard: $0.heard, term: $0.term) }) { return rescored.text }
        return VocabularyGate.apply(replacements: replacements, to: result.text)
    }

    private func setBooster(_ value: VocabularyBoostingSession?) {
        boosterLock.withLock { booster = value }
    }

    private func transcribe(_ samples: [Float]) async throws -> ASRResult {
        guard let manager else { throw VoiceError.notPrepared }
        var padded = samples
        if padded.count < minimumSamples {
            padded += [Float](repeating: 0, count: minimumSamples - padded.count)
        }
        var state = TdtDecoderState.make(decoderLayers: decoderLayers)
        return try await manager.transcribe(padded, decoderState: &state)
    }
}
