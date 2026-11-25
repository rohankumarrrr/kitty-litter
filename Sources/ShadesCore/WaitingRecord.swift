import Foundation

public struct WaitingVisit: Codable, Equatable, Sendable {
    public enum Starter: String, Codable, Sendable {
        case you, passedOn, agent, unknown
    }

    public enum Source: String, Codable, Sendable {
        case sorter, failedRun, requestCard, answerToYou
    }

    public enum Exit: String, Codable, Sendable, CaseIterable {
        case replied, done, ignored, allowed, denied
        case superseded, withdrawn, alreadyMade, reportDidntAsk, turnWithoutYou, settled, archived, pullRequestMerged, pullRequestClosed

        public var tookYou: Bool { [.replied, .done, .ignored, .allowed, .denied].contains(self) }
    }

    public var row: String
    public var threadID: String
    public var threadTitle: String
    public var startedBy: Starter
    public var held: Bool
    public var source: Source
    public var enteredAt: Date
    public var leftAt: Date?
    public var exit: Exit?

    public var isOpen: Bool { exit == nil }
}

public struct WaitingRecord: Codable, Equatable, Sendable {
    public static let kept = 500
    public static let fileName = "waiting-on-you.json"

    public private(set) var visits: [WaitingVisit] = []

    public init() {}

    mutating func entered(_ entry: InboxEntry, startedBy: WaitingVisit.Starter, held: Bool, source: WaitingVisit.Source, at date: Date) {
        visits.append(WaitingVisit(
            row: entry.id,
            threadID: entry.threadID,
            threadTitle: entry.threadTitle,
            startedBy: startedBy,
            held: held,
            source: source,
            enteredAt: date
        ))
        if visits.count > Self.kept { visits.removeFirst(visits.count - Self.kept) }
    }

    mutating func left(_ row: String, _ exit: WaitingVisit.Exit, at date: Date) {
        guard let index = visits.lastIndex(where: { $0.row == row && $0.isOpen }) else { return }
        visits[index].exit = exit
        visits[index].leftAt = date
    }

    mutating func cameBack(_ row: String) {
        guard let index = visits.lastIndex(where: { $0.row == row }), visits[index].exit == .replied else { return }
        visits[index].exit = nil
        visits[index].leftAt = nil
    }

    func lastVisit(of row: String) -> WaitingVisit? {
        visits.last { $0.row == row }
    }

    public func leftSince(_ date: Date) -> (all: Int, withoutYou: Int) {
        let left = visits.filter { ($0.leftAt ?? .distantPast) >= date }
        return (left.count, left.filter { $0.exit?.tookYou == false }.count)
    }

    public static func load(beside inboxFile: URL) -> WaitingRecord {
        let file = inboxFile.deletingLastPathComponent().appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: file) else { return WaitingRecord() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(WaitingRecord.self, from: data)) ?? WaitingRecord()
    }

    public func save(beside inboxFile: URL) throws {
        let file = inboxFile.deletingLastPathComponent().appendingPathComponent(Self.fileName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try PrivateFile.write(try encoder.encode(self), to: file)
    }
}
