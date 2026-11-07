import Foundation
import ShadesCore

/// The one owner of what's been said. What's been read stays in memory while the app runs, and never goes to disk,
/// since a copy in Shades' folder would let any kitten read every other kitten's threads. So Messages opens at once
/// and then reads only the threads that have moved since. It reads once soon after launch, then only while the window
/// or a phone is looking.
@MainActor
final class ChannelFeed {
    private static let newestReadPerKitten = 30
    private static let readsAtOnce = 4
    /// How many quiet gaps go by before it looks anyway. Nothing else would tell it that T3 has gone away.
    private static let quietGaps = 5
    /// How long reads that land close together wait to be shown as one change.
    private static let showEvery: TimeInterval = 0.15
    /// What you've sent that T3 hasn't echoed yet, such as the cat's own answers in #general, which T3 never has, and
    /// replies you also sent to a channel.
    private static let sentKept = 100

    var onChange: ((ChannelBook) -> Void)?
    var waiting: () -> Waiting = { Waiting() }
    var isUnread: (AgentThread) -> Bool = { _ in false }
    /// Threads Messages started from #general, or passed your words to there, and when. They live in #general.
    var inGeneral: () -> [String: Date] = { [:] }
    /// Whether a thread is a conversation with the cat itself, which is any in the router's folder.
    var isWithShades: (AgentThread) -> Bool = { _ in false }
    /// What's on the screen, whose threads are read before the rest.
    var lookingAt: ChannelSelection?

    private let backend: AgentBackend
    private let kittens: () -> [Kitten]
    /// How long after one pass the next can start, so a burst of changes makes one read.
    private let gap: Duration

    private var threads: [AgentThread] = []
    private var transcripts: [String: [Exchange]] = [:]
    private var readStamps: [String: Date] = [:]
    /// Listed threads this pass hasn't read yet and nothing was ever read of, kept back so they don't look cut short.
    private var unreadNew: Set<String> = []
    private var sent: [SentMessage] = []
    private var hasRead = false
    private var unreadable = 0
    private var cantReachT3 = false
    private var isDirty = true
    private var wantsWarm = false
    private var quiet = 0
    private var loop: Task<Void, Never>?
    /// The wait between passes, which opening cuts short.
    private var nap: Task<Void, Never>?
    private var published: ChannelBook?
    /// What each of the cat's replies came to, since working that out is slow and a reply doesn't change.
    private var said: [String: String?] = [:]

    /// Whether the window or a phone is looking.
    private(set) var isOpen = false
    /// How many passes over T3 have finished.
    private(set) var passes = 0

    init(backend: AgentBackend, kittens: @escaping () -> [Kitten], gap: Duration = .seconds(3)) {
        self.backend = backend
        self.kittens = kittens
        self.gap = gap
    }

    var threadsHeld: Int { transcripts.count }

    /// Returns at once with whatever's known, and catches up on what moved while nobody was looking.
    func open(threads: [AgentThread]) -> ChannelBook {
        if isOpen, let published { return published }
        if !isOpen {
            isOpen = true
            isDirty = true
            if !hasRead { self.threads = threads }
            nap?.cancel()
            run()
        }
        // What's waiting can have changed while nobody was looking.
        let book = book()
        published = book
        return book
    }

    /// Reads everything once, before anyone's looked, so the first time Messages opens is as quick as the rest.
    func warm(threads: [AgentThread]) {
        guard !hasRead, !isOpen else { return }
        self.threads = threads
        wantsWarm = true
        run()
    }

    /// Nobody's looking, so it stops reading. What's been read stays.
    func close() {
        isOpen = false
    }

    func threadsChanged(_ threads: [AgentThread]) {
        // Until the first full list lands, this one is the best there is.
        if !hasRead, isOpen {
            self.threads = threads
            publish()
        }
        isDirty = true
    }

    /// Shows a change to what's waiting or what's been read, with no need to read anything again.
    func refresh() {
        if isOpen { publish() }
    }

    /// Shows it at once, until T3 has it. A reply that's `alsoSent` shows in `channel` as well as its thread, from
    /// memory only, as Slack's "Also send to #channel" does.
    func sent(_ message: ChannelMessage, in channel: ChannelID, startsThread: Bool = false, alsoSent: Bool = false) {
        sent.append(SentMessage(channel: channel, message: message, startsThread: startsThread, alsoSent: alsoSent))
        sent = sent.suffix(Self.sentKept)
        isDirty = true
        publish()
    }

    /// What you sent now has a thread, or `nil` if it never got one. A new topic says it didn't start, and anything
    /// else stays where you said it.
    func started(_ exchangeID: String, in threadID: String?, title: String = "", alsoSent: Bool? = nil) {
        guard let index = sent.firstIndex(where: { $0.message.exchangeID == exchangeID }) else { return }
        if let threadID {
            sent[index].message.threadID = threadID
            sent[index].message.threadTitle = title
            if let alsoSent { sent[index].alsoSent = alsoSent }
        } else if sent[index].startsThread {
            sent[index].message.failure = CatWords.didntStart
        }
        isDirty = true
        publish()
    }

    /// The threads behind what you're looking at whose latest words are on the screen as they are now, so they can
    /// count as read. A channel only shows each thread's parent, so there that has to be all it's said, or its latest
    /// reply has to be sent to the channel too. A thread's pane shows every reply.
    func threads(in selection: ChannelSelection) -> [AgentThread] {
        guard let book = published else { return [] }
        var shown: Set<String> = []
        if let open = selection.thread, book.threads[open] != nil { shown.insert(open) }
        var quiet: (AgentThread) -> Bool = { _ in false }
        if let id = selection.channelID, let channel = book.channel(id) {
            // A thread that's said nothing has nothing left to see, so the channel it would be in counts for it.
            let owners = KittenBoard.Owners(kittens())
            let inGeneral = inGeneral()
            quiet = { thread in
                guard book.threads[thread.id] == nil, self.transcripts[thread.id] != nil else { return false }
                let owner = owners.of(thread)
                switch id {
                case .kitten(let kitten): return owner?.id == kitten && inGeneral[thread.id] == nil
                case .general: return inGeneral[thread.id] != nil
                case .shades: return false
                }
            }
            for post in channel.posts {
                switch post {
                case .thread(let thread):
                    if book.threads[thread]?.replies.isEmpty == true { shown.insert(thread) }
                case .alsoSent(let message, let thread):
                    if book.threads[thread]?.latest.id == message.id { shown.insert(thread) }
                case .message:
                    break
                }
            }
        }
        return threads.filter { readStamps[$0.id] == $0.updatedAt && !isWithShades($0) && (shown.contains($0.id) || quiet($0)) }
    }

    /// One loop at a time, so there's only ever one pass. It holds off between passes, so a burst of changes makes one.
    private func run() {
        guard loop == nil else { return }
        loop = Task { [weak self, gap] in
            while await self?.step() == true {
                let nap = Task { _ = try? await Task.sleep(for: gap) }
                self?.nap = nap
                await nap.value
            }
        }
    }

    /// One turn of the loop. `false` once nobody's looking, which ends it.
    private func step() async -> Bool {
        if wantsWarm || isOpen && (isDirty || quiet >= Self.quietGaps) {
            wantsWarm = false
            isDirty = false
            quiet = 0
            await pass()
        }
        quiet += 1
        guard isOpen else {
            loop = nil
            return false
        }
        return true
    }

    private func pass() async {
        guard let listed = await backend.allThreads() else {
            cantReachT3 = true
            isDirty = true
            publish()
            return
        }

        let owners = KittenBoard.Owners(kittens())
        let talks = listed.filter(isWithShades)
        let byOwner = Dictionary(grouping: listed.filter { !isWithShades($0) }) { owners.of($0)?.id }
        let mine = inGeneral()
        let owned = byOwner.filter { $0.key != nil }.values.flatMap { threads in
            threads.sorted { $0.updatedAt > $1.updatedAt }.prefix(Self.newestReadPerKitten)
        } + (byOwner[nil] ?? []).filter { mine[$0.id] != nil }
            + talks.filter { !$0.isLiveTest }.sorted { $0.updatedAt > $1.updatedAt }.prefix(Self.newestReadPerKitten)
        let onScreen = isOnScreen(owners)
        // What you're looking at first, then the newest, so the top of each conversation fills in first.
        let moved = owned
            .filter { readStamps[$0.id] != $0.updatedAt }
            .sorted { (onScreen($0) ? 0 : 1, $1.updatedAt) < (onScreen($1) ? 0 : 1, $0.updatedAt) }

        let wanted = Set(owned.map(\.id))
        transcripts = transcripts.filter { wanted.contains($0.key) }
        readStamps = readStamps.filter { wanted.contains($0.key) }
        threads = listed
        unreadNew = Set(moved.map(\.id)).subtracting(transcripts.keys)
        cantReachT3 = false

        var lastShown = Date()
        let read = await read(moved) { thread, exchanges in
            unreadNew.remove(thread.id)
            if let exchanges {
                // A thread shows its newest replies, and always its first message, which is the one that started it.
                transcripts[thread.id] = exchanges.count > ChannelBook.keptExchanges
                    ? Array(exchanges.prefix(1) + exchanges.suffix(ChannelBook.keptExchanges - 1))
                    : exchanges
                readStamps[thread.id] = thread.updatedAt
            }
            if Date().timeIntervalSince(lastShown) >= Self.showEvery {
                lastShown = Date()
                publish()
            }
        }
        // The live list can have stood in for it meanwhile, and this one has every thread.
        threads = listed
        unreadNew = []
        hasRead = true
        passes += 1
        unreadable = moved.count - read
        if unreadable > 0 { isDirty = true }
        publish()
    }

    /// Whether a thread's words are part of what's on the screen.
    private func isOnScreen(_ owners: KittenBoard.Owners) -> (AgentThread) -> Bool {
        let isWithShades = isWithShades
        let open = lookingAt?.thread
        let inGeneral = inGeneral()
        let place: (AgentThread) -> Bool
        switch lookingAt?.place {
        case .channel(.shades)?:
            place = isWithShades
        case .channel(.general)?:
            place = { inGeneral[$0.id] != nil || (!isWithShades($0) && owners.of($0) == nil) }
        case .channel(.kitten(let kitten))?:
            place = { thread in owners.of(thread)?.id == kitten }
        case .threads?:
            place = { !isWithShades($0) }
        case .activity?, nil:
            place = { _ in false }
        }
        return { $0.id == open || place($0) }
    }

    /// Hands each read over as it lands, in the order asked, and returns how many could be read.
    private func read(_ threads: [AgentThread], landed: (AgentThread, [Exchange]?) -> Void) async -> Int {
        let backend = backend
        return await withTaskGroup(of: (AgentThread, [Exchange]?).self) { group in
            var waiting = threads.makeIterator()
            func readNext() {
                guard !Task.isCancelled, let thread = waiting.next() else { return }
                group.addTask { (thread, await backend.exchanges(threadID: thread.id)) }
            }
            for _ in 0..<Self.readsAtOnce { readNext() }

            var read = 0
            while let (thread, exchanges) = await group.next() {
                if exchanges != nil { read += 1 }
                landed(thread, exchanges)
                readNext()
            }
            return read
        }
    }

    private func publish() {
        let book = book()
        guard book != published else { return }
        published = book
        onChange?(book)
    }

    private func book() -> ChannelBook {
        // Only what this build asks about is kept, so replies that have gone don't stay in memory.
        var said: [String: String?] = [:]
        defer { self.said = said }
        return ChannelBook.build(
            kittens: kittens(),
            threads: unreadNew.isEmpty ? threads : threads.filter { !unreadNew.contains($0.id) },
            transcripts: transcripts,
            isReading: !hasRead,
            unreadable: unreadable,
            cantReachT3: cantReachT3,
            waiting: waiting(),
            sent: sent,
            isUnread: isUnread,
            inGeneral: inGeneral(),
            withShades: Set(threads.filter(isWithShades).map(\.id)),
            said: { reply in
                let words = self.said[reply] ?? ChannelBook.said(reply)
                said[reply] = words
                return words
            }
        )
    }
}
