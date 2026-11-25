import Foundation

struct RelayLimit {
    static let notes = 3
    static let window: TimeInterval = 5 * 60

    private var sent: [Set<String>: [Date]] = [:]

    func allows(_ from: String, _ to: String, at now: Date) -> Bool {
        recent([from, to], at: now).count < Self.notes
    }

    mutating func record(_ from: String, _ to: String, at now: Date) {
        let pair: Set = [from, to]
        sent[pair] = recent(pair, at: now) + [now]
    }

    private func recent(_ pair: Set<String>, at now: Date) -> [Date] {
        (sent[pair] ?? []).filter { now.timeIntervalSince($0) < Self.window }
    }
}
