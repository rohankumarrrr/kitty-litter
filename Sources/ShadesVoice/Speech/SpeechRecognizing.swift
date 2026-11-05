import Foundation

/// Turns audio into words. The batch model behind it takes a fixed window, so short clips cost the same as long ones.
public protocol SpeechRecognizing: AnyObject {
    func load(progress: @escaping @Sendable (Double) -> Void) async throws
    func setVocabulary(_ words: [String]) async
    /// Fast, for live text. No vocabulary pass.
    func draft(_ samples: [Float]) async throws -> String
    /// As accurate as it gets, for the final text.
    func finish(_ samples: [Float]) async throws -> String
}
