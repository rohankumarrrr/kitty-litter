import Foundation
import ShadesCore

struct KittenMisses: Equatable {
    var kitten: String
    var count: Int
}

enum KittensCheck: Equatable {
    case found([KittenMisses])
    case stale(since: Date)
    case unreadable

    static let summaryFile = Kittens.defaultFolder.appendingPathComponent("clawde/outputs/check-kittens.json")
    static let staleAfter: TimeInterval = 26 * 3600
    static let largestSummary = 64 * 1024

    private struct Summary: Decodable {
        var checkedAt: Date
        var misses: [String: Int]
    }

    init(summary: Data?, kittens: [Kitten], now: Date) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let summary, let read = try? decoder.decode(Summary.self, from: summary) else {
            self = .unreadable
            return
        }
        guard now.timeIntervalSince(read.checkedAt) <= Self.staleAfter else {
            self = .stale(since: read.checkedAt)
            return
        }
        self = .found(kittens.compactMap { kitten in
            let count = read.misses[URL(fileURLWithPath: kitten.folder).lastPathComponent] ?? 0
            return count > 0 ? KittenMisses(kitten: kitten.name, count: count) : nil
        })
    }

    static func readSummary(at file: URL = summaryFile) -> Data? {
        let facts = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard facts?.isRegularFile == true, let size = facts?.fileSize, size <= largestSummary else { return nil }
        return try? Data(contentsOf: file)
    }
}
