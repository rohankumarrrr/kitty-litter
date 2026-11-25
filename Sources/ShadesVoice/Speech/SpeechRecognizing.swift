import Foundation

public protocol SpeechRecognizing: AnyObject {
    func load(progress: @escaping @Sendable (Double) -> Void) async throws
    func setVocabulary(_ words: [String]) async
    func draft(_ samples: [Float]) async throws -> String
    func finish(_ samples: [Float]) async throws -> String
}
