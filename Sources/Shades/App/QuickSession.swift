import Foundation

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
