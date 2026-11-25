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

        public enum Verdict: Sendable {
            case answeredByYou, unanswered, neither
        }

        public var verdict: Verdict {
            switch self {
            case .replied, .done, .ignored, .allowed, .denied: .answeredByYou
            case .superseded, .reportDidntAsk, .settled, .pullRequestMerged, .pullRequestClosed: .unanswered
            case .withdrawn, .alreadyMade, .turnWithoutYou, .archived: .neither
            }
        }
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
    public var text: String?
    public var updates: Int?

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
            enteredAt: date,
            text: entry.text
        ))
        if visits.count > Self.kept { visits.removeFirst(visits.count - Self.kept) }
    }

    mutating func left(_ row: String, _ exit: WaitingVisit.Exit, at date: Date) {
        guard let index = visits.lastIndex(where: { $0.row == row && $0.isOpen }) else { return }
        visits[index].exit = exit
        visits[index].leftAt = date
    }

    mutating func updated(_ row: String, to text: String) {
        guard let index = visits.lastIndex(where: { $0.row == row && $0.isOpen }) else { return }
        visits[index].text = text
        visits[index].updates = (visits[index].updates ?? 0) + 1
    }

    mutating func renamed(_ row: String, to newRow: String) {
        guard let index = visits.lastIndex(where: { $0.row == row && $0.isOpen }) else { return }
        visits[index].row = newRow
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
        let verdicts = visits.filter { ($0.leftAt ?? .distantPast) >= date }.compactMap { $0.exit?.verdict }
        let judged = verdicts.filter { $0 != .neither }
        return (judged.count, judged.filter { $0 == .unanswered }.count)
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
