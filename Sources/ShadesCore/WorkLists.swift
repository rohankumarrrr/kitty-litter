import Foundation

/// Where work lists are kept.
public protocol WorkListStoring: AnyObject {
    /// The list, with anything new in `proposals/` merged in as proposed. Never fails: unreadable means empty.
    func load(for kitten: Kitten) -> WorkList
    /// Atomic. Throws rather than write through a symlink.
    func save(_ list: WorkList, for kitten: Kitten) throws
    func hasProblem(for kitten: Kitten) -> Bool
}

/// Lists in each kitten's own folder, so they stay out of this repo. A kitten can write anything in
/// its folder, so nothing here trusts what it finds.
///
///     worklist/items.json          Shades writes, the kitten reads.
///     worklist/items.broken.json   Set aside by Shades if items.json couldn't be read.
///     worklist/proposals/          The kitten writes, one plain text file per idea. Shades reads and removes.
public final class FileWorkLists: WorkListStoring {
    private struct FolderBlocked: Error {}

    private struct Paths {
        let folder: URL
        var items: URL { folder.appendingPathComponent("items.json") }
        var broken: URL { folder.appendingPathComponent("items.broken.json") }
        var proposals: URL { folder.appendingPathComponent("proposals") }

        init(_ kitten: Kitten) {
            folder = URL(fileURLWithPath: kitten.folder).appendingPathComponent("worklist")
        }
    }

    private static let listByteLimit = 1_024 * 1_024
    private static let proposalByteLimit = 64 * 1_024
    private static let proposalLength = 2_000
    private static let openProposalLimit = 20

    private let settle: TimeInterval
    private let files = FileManager.default

    /// - Parameter settle: How long a proposal file has to sit untouched, since it may be half written until then.
    public init(settle: TimeInterval = 5) {
        self.settle = settle
    }

    public func load(for kitten: Kitten) -> WorkList {
        let paths = Paths(kitten)
        guard !isBlocked(paths) else { return WorkList() }
        var list = read(paths)

        var consumed: [URL] = []
        var merged = false
        for file in settledProposals(paths) {
            guard let text = proposalText(at: file) else { continue }
            // Already there means a crash came between saving it and removing the file, or it was asked twice.
            if list.items.contains(where: { $0.text == text }) {
                consumed.append(file)
                continue
            }
            guard list.items.filter({ $0.state == .proposed }).count < Self.openProposalLimit else { break }
            list.put(WorkItem(text: text, state: .proposed, at: Date()))
            consumed.append(file)
            merged = true
        }
        if merged {
            do {
                try save(list, for: kitten)
            } catch {
                return list
            }
        }
        consumed.forEach { try? files.removeItem(at: $0) }
        return list
    }

    public func save(_ list: WorkList, for kitten: Kitten) throws {
        let paths = Paths(kitten)
        guard !isBlocked(paths) else { throw FolderBlocked() }
        try files.createDirectory(at: paths.proposals, withIntermediateDirectories: true)
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: paths.folder.path)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(list).write(to: paths.items, options: .atomic)
    }

    public func hasProblem(for kitten: Kitten) -> Bool {
        let paths = Paths(kitten)
        if isBlocked(paths) || kind(of: paths.broken) != nil { return true }
        if kind(of: paths.items) != nil, !files.isWritableFile(atPath: paths.items.path) { return true }
        let writesTo = kind(of: paths.folder) == nil ? kitten.folder : paths.folder.path
        return !files.isWritableFile(atPath: writesTo) || settledProposals(paths).contains { proposalText(at: $0) == nil }
    }

    // MARK: - Reading what a kitten left

    private func read(_ paths: Paths) -> WorkList {
        guard let kind = kind(of: paths.items) else { return WorkList() }
        if kind == .typeRegular, size(of: paths.items) <= Self.listByteLimit, let data = try? Data(contentsOf: paths.items) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let list = try? decoder.decode(WorkList.self, from: data) { return list }
        }
        try? files.removeItem(at: paths.broken)
        try? files.moveItem(at: paths.items, to: paths.broken)
        return WorkList()
    }

    /// Plain files that have had time to be finished, in a steady order. Links and the like don't count.
    private func settledProposals(_ paths: Paths) -> [URL] {
        guard kind(of: paths.proposals) == .typeDirectory else { return [] }
        let found = (try? files.contentsOfDirectory(at: paths.proposals, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        return found
            .filter { kind(of: $0) == .typeRegular && isSettled($0) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func proposalText(at file: URL) -> String? {
        guard size(of: file) <= Self.proposalByteLimit,
              let data = try? Data(contentsOf: file),
              let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else { return nil }
        return String(text.prefix(Self.proposalLength))
    }

    private func isSettled(_ file: URL) -> Bool {
        guard let changed = (try? files.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date else { return false }
        return Date().timeIntervalSince(changed) >= settle
    }

    /// A link or a file where a folder should be. A link could lead anywhere, so it's never followed.
    private func isBlocked(_ paths: Paths) -> Bool {
        [paths.folder, paths.proposals].contains { folder in
            kind(of: folder).map { $0 != .typeDirectory } ?? false
        }
    }

    /// What's really at this path, without following a link. `nil` if there's nothing.
    private func kind(of file: URL) -> FileAttributeType? {
        (try? files.attributesOfItem(atPath: file.path))?[.type] as? FileAttributeType
    }

    private func size(of file: URL) -> Int {
        ((try? files.attributesOfItem(atPath: file.path))?[.size] as? NSNumber)?.intValue ?? 0
    }
}

/// Lists that only last as long as the app. For the demo and tests.
public final class MemoryWorkLists: WorkListStoring {
    public var lists: [String: WorkList]
    public var saveError: Error?

    public init(lists: [String: WorkList] = [:]) {
        self.lists = lists
    }

    public func load(for kitten: Kitten) -> WorkList {
        lists[kitten.id] ?? WorkList()
    }

    public func save(_ list: WorkList, for kitten: Kitten) throws {
        if let saveError { throw saveError }
        lists[kitten.id] = list
    }

    public func hasProblem(for kitten: Kitten) -> Bool {
        saveError != nil
    }
}
