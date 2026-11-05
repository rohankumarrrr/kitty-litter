import Foundation

/// Keeps using the same quick thread for follow-ups, which saves about 1.5 s a question,
/// and starts fresh once the conversation has clearly gone quiet.
struct QuickSession {
    static let lifetime: TimeInterval = 10 * 60

    private var threadID: String?
    private var lastUsed = Date.distantPast

    func thread(at now: Date) -> String? {
        now.timeIntervalSince(lastUsed) < Self.lifetime ? threadID : nil
    }

    mutating func use(_ threadID: String, at now: Date) {
        self.threadID = threadID
        lastUsed = now
    }

    mutating func reset() {
        threadID = nil
        lastUsed = .distantPast
    }
}
