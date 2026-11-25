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
    case notSetUp

    static let owner = "clawde"
    static let summaryFile = Kittens.defaultFolder.appendingPathComponent("\(owner)/outputs/check-kittens.json")
    static let staleAfter: TimeInterval = 26 * 3600
    static let largestSummary = 64 * 1024

    private struct Summary: Decodable {
        var checkedAt: Date
        var misses: [String: Int]
    }

    init(summary: Data?, kittens: [Kitten], now: Date) {
        let folders = kittens.map { URL(fileURLWithPath: $0.folder).lastPathComponent }
        guard folders.contains(Self.owner) else {
            self = .notSetUp
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let summary, let read = try? decoder.decode(Summary.self, from: summary) else {
            self = .unreadable
            return
        }
        let age = now.timeIntervalSince(read.checkedAt)
        guard age >= -Self.staleAfter else {
            self = .unreadable
            return
        }
        guard age <= Self.staleAfter else {
            self = .stale(since: read.checkedAt)
            return
        }
        self = .found(zip(kittens, folders).compactMap { kitten, folder in
            let count = read.misses[folder] ?? 0
            return count > 0 ? KittenMisses(kitten: kitten.name, count: count) : nil
        })
    }

    static func readSummary(at file: URL = summaryFile) -> Data? {
        let descriptor = open(file.path, O_RDONLY | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var facts = stat()
        guard fstat(descriptor, &facts) == 0, facts.st_mode & S_IFMT == S_IFREG,
              let data = try? handle.read(upToCount: largestSummary + 1), data.count <= largestSummary
        else { return nil }
        return data
    }
}
