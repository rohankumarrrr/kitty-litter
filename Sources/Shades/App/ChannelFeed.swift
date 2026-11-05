import Foundation
import ShadesCore

/// The one owner of what's been said. Words exist only while the Channels window is open, so
/// nothing is read in the background, and closing it forgets everything.
@MainActor
final class ChannelFeed {
    private static let newestReadPerKitten = 30
    private static let readsAtOnce = 4
    /// How many quiet gaps go by before it looks anyway. Nothing else would tell it that T3 has gone away.
    private static let quietGaps = 5

    private final class Session {
        var threads: [AgentThread]
        var transcripts: [String: [Exchange]] = [:]
        var readStamps: [String: Date] = [:]
        var isReading = true
        var unreadable = 0
        var cantReachT3 = false
        var isDirty = true
        var loop: Task<Void, Never>?
        var published: ChannelBook?

        init(threads: [AgentThread]) {
            self.threads = threads
        }

        /// A read still in flight can keep this object alive for a moment, so it can't keep the words too.
        func forget() {
            threads = []
            transcripts = [:]
            published = nil
        }
    }

    var onChange: ((ChannelBook) -> Void)?

    private let backend: AgentBackend
    private let kittens: () -> [Kitten]
    /// How long after one pass the next can start, so a burst of changes makes one read.
    private let gap: Duration
    /// `nil` means no words exist anywhere.
    private var session: Session?

    init(backend: AgentBackend, kittens: @escaping () -> [Kitten], gap: Duration = .seconds(3)) {
        self.backend = backend
        self.kittens = kittens
        self.gap = gap
    }

    var threadsHeld: Int { session?.transcripts.count ?? 0 }

    /// Returns at once, still reading. Opening what's already open changes nothing.
    func open(threads: [AgentThread]) -> ChannelBook {
        if let book = session?.published { return book }
        let session = Session(threads: threads)
        self.session = session
        let book = book(of: session)
        session.published = book
        startLoop(session)
        return book
    }

    func threadsChanged(_ threads: [AgentThread]) {
        guard let session else { return }
        // Until the first full list lands, this one is the best there is.
        if session.isReading {
            session.threads = threads
            publish(session)
        }
        session.isDirty = true
    }

    func close() {
        session?.loop?.cancel()
        session?.forget()
        session = nil
    }

    /// One loop per session, for as long as it's open. It holds off between passes, so a burst of changes makes one.
    private func startLoop(_ session: Session) {
        session.loop = Task { [weak self, gap] in
            var quiet = 0
            while self?.session === session {
                if session.isDirty || quiet >= Self.quietGaps {
                    session.isDirty = false
                    quiet = 0
                    await self?.pass(session)
                } else {
                    quiet += 1
                }
                try? await Task.sleep(for: gap)
            }
        }
    }

    private func pass(_ session: Session) async {
        let listed = await backend.allThreads()
        guard self.session === session else { return }
        guard let listed else {
            session.cantReachT3 = true
            session.isDirty = true
            publish(session)
            return
        }

        let kittens = kittens()
        let byOwner = Dictionary(grouping: listed) { KittenBoard.owner(of: $0, among: kittens)?.id }
        let owned = byOwner.filter { $0.key != nil }.values.flatMap { threads in
            threads.sorted { $0.updatedAt > $1.updatedAt }.prefix(Self.newestReadPerKitten)
        }
        let moved = owned.filter { session.readStamps[$0.id] != $0.updatedAt }
        let read = await read(moved)
        // A read landing after the window closed has nowhere to go, so it's dropped here.
        guard self.session === session else { return }

        let wanted = Set(owned.map(\.id))
        session.transcripts = session.transcripts.filter { wanted.contains($0.key) }
        session.readStamps = session.readStamps.filter { wanted.contains($0.key) }
        for thread in moved {
            guard let exchanges = read[thread.id] else { continue }
            session.transcripts[thread.id] = exchanges
            session.readStamps[thread.id] = thread.updatedAt
        }
        session.threads = listed
        session.isReading = false
        session.cantReachT3 = false
        session.unreadable = moved.count - read.count
        if session.unreadable > 0 { session.isDirty = true }
        publish(session)
    }

    private func read(_ threads: [AgentThread]) async -> [String: [Exchange]] {
        let backend = backend
        return await withTaskGroup(of: (String, [Exchange]?).self) { group in
            var waiting = threads.makeIterator()
            func readNext() {
                guard !Task.isCancelled, let id = waiting.next()?.id else { return }
                group.addTask { (id, await backend.exchanges(threadID: id)) }
            }
            for _ in 0..<Self.readsAtOnce { readNext() }

            var read: [String: [Exchange]] = [:]
            while let (id, exchanges) = await group.next() {
                read[id] = exchanges
                readNext()
            }
            return read
        }
    }

    private func publish(_ session: Session) {
        let book = book(of: session)
        guard book != session.published else { return }
        session.published = book
        onChange?(book)
    }

    private func book(of session: Session) -> ChannelBook {
        ChannelBook.build(
            kittens: kittens(),
            threads: session.threads,
            transcripts: session.transcripts,
            isReading: session.isReading,
            unreadable: session.unreadable,
            cantReachT3: session.cantReachT3
        )
    }
}
