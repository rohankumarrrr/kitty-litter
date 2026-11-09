import Foundation
import ShadesCore

/// The one owner of what's been said. What's been read stays in memory while the app runs, and never goes to disk,
/// since a copy in Shades' folder would let any kitten read every other kitten's threads. So Messages opens at once
/// and then reads only the threads that have moved since. It reads once soon after launch, then only while the window
/// or a phone is looking. Each kitten's channel and the cat's DM read their newest threads, older ones a page at a
/// time as you scroll back to them, and any older one Search finds in T3.
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
    /// How many of the threads T3 names for one search are read, and how many found that way stay read.
    private static let foundAtOnce = 8
    private static let foundKept = 30

    var onChange: ((ChannelBook) -> Void)?
    var waiting: () -> Waiting = { Waiting() }
    var isUnread: (AgentThread) -> Bool = { _ in false }
    /// The first message that's new to you in an unread thread, given its messages, oldest first.
    var firstNew: (AgentThread, [ChannelMessage]) -> String? = { _, _ in nil }
    /// Threads Messages started from #general, or passed your words to there, and when. They live in #general.
    var inGeneral: () -> [String: Date] = { [:] }
    /// Whether a thread is a conversation with the cat itself, which is any in the router's folder.
    var isWithShades: (AgentThread) -> Bool = { _ in false }
    /// Whether a thread is work the cat started for you outside Messages, which lives in its DM.
    var isCatsWork: (AgentThread) -> Bool = { _ in false }
    /// The cat's own work you chose to show on your phone, and whether Messages is on your phone at all.
    var onPhone: () -> Set<String> = { [] }
    var hasPhone: () -> Bool = { false }
    /// The turns of Messages' talk with the router that the cat answered in #general, by T3's ID for each.
    var answersInGeneral: () -> Set<String> = { [] }
    /// Replies also sent to their thread's channel by the ID of T3's copy of each, and to #general with the thread each
    /// is in.
    var alsoSent: () -> Set<String> = { [] }
    var alsoSentToGeneral: () -> [String: String] = { [:] }
    /// Your reactions, by the ID of each message T3 has.
    var reactions: () -> [String: [Reaction]] = { [:] }
    /// Hands over the replies also sent to a channel that T3 has now, so their IDs can be kept.
    var keepAlsoSent: ([String: ChannelBook.HeardAlsoSent]) -> Void = { _ in }
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
    /// Threads nothing could be read of last time, which aren't older than what's been read, just unread.
    private var couldntRead: Set<String> = []
    private var sent: [SentMessage] = []
    /// How many pages of older threads and posts you've scrolled back to in each channel, while the app runs.
    private var olderPages: [ChannelID: Int] = [:]
    private var loadingOlder: Set<ChannelID> = []
    /// Threads Search found in T3 that Messages hadn't read, latest last, which stay read while the app runs.
    private var found: [String] = []
    /// The words Search is asking T3 about now, and the asking.
    private var searching: (words: String, task: Task<Void, Never>)?
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

    /// A thread as T3 last listed it, title and all.
    func listed(_ id: String) -> AgentThread? {
        threads.first { $0.id == id }
    }

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

    /// Shows it at once, until T3 has it. A reply only shows in `channel` as well as its thread if it's `alsoSent`, as
    /// Slack's "Also send to #channel" does, and once T3 has it, it's kept by the ID of T3's copy. The same message sent
    /// again takes its old one's place.
    func sent(_ message: ChannelMessage, in channel: ChannelID, startsThread: Bool = false, alsoSent: Bool = false, isReply: Bool = false, target: MessageTarget? = nil) {
        sent.removeAll { $0.message.exchangeID == message.exchangeID }
        sent.append(SentMessage(channel: channel, message: message, startsThread: startsThread, alsoSent: alsoSent, isReply: isReply, target: target))
        sent = sent.suffix(Self.sentKept)
        isDirty = true
        publish()
    }

    /// What you sent went nowhere, and why, which shows under it.
    func failed(_ exchangeID: String, because reason: String) {
        guard let index = sent.firstIndex(where: { $0.message.exchangeID == exchangeID }) else { return }
        sent[index].message.failure = reason
        sent[index].message.isSending = false
        isDirty = true
        publish()
    }

    /// T3 has what you sent, for words whose own copy Messages can't count on reading back, such as a question the
    /// cat is still thinking about.
    func delivered(_ exchangeID: String) {
        guard let index = sent.firstIndex(where: { $0.message.exchangeID == exchangeID }), sent[index].message.isSending else { return }
        sent[index].message.isSending = false
        publish()
    }

    /// What you sent that went nowhere, to send again as it was, where it was going.
    func toTryAgain(_ exchangeID: String) -> SentMessage? {
        sent.first { $0.message.exchangeID == exchangeID && $0.message.canTryAgain && $0.target != nil }
    }

    /// What you sent is a turn T3 has now, so once that's read it shows instead.
    func heard(_ exchangeIDs: [String], as turn: String) {
        for index in sent.indices where exchangeIDs.contains(sent[index].message.exchangeID) {
            sent[index].heardAs = turn
            sent[index].message.isSending = false
        }
        isDirty = true
        publish()
    }

    /// What you sent now has a thread, or `nil` if it never got one. A new topic says it didn't start, and anything
    /// else stays where you said it.
    func started(_ exchangeID: String, in threadID: String?, title: String = "", alsoSent: Bool? = nil) {
        guard let index = sent.firstIndex(where: { $0.message.exchangeID == exchangeID }) else { return }
        sent[index].message.isSending = false
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

    /// Scrolled back past the top of a channel, it reads the next page of that channel's older threads, and shows as
    /// many more of its posts. One page at a time.
    func older(in channel: ChannelID) {
        guard !loadingOlder.contains(channel), published?.channel(channel)?.isCut == true else { return }
        olderPages[channel, default: 0] += 1
        loadingOlder.insert(channel)
        isDirty = true
        nap?.cancel()
        publish()
    }

    /// Asks T3 which threads have these words, and reads the ones Messages hasn't, so Search finds them too. Only the
    /// latest words count, and they're kept only until T3 answers.
    func find(_ words: String) {
        searching?.task.cancel()
        searching = nil
        guard !MessageSearch.words(in: words).isEmpty else { return publish() }
        let task = Task { [weak self, backend] in
            let named = await backend.threads(matching: words) ?? []
            guard let self, !Task.isCancelled else { return }
            let shows = self.shows(KittenBoard.Owners(self.kittens()))
            let new = Array(named.compactMap { id in self.threads.first { $0.id == id } }
                .filter { self.transcripts[$0.id] == nil && shows($0) }
                .prefix(Self.foundAtOnce))
            self.found = Array((self.found.filter { id in !new.contains { $0.id == id } } + new.map(\.id)).suffix(Self.foundKept))
            _ = await self.read(new) { thread, exchanges in
                if let exchanges { self.keep(exchanges, of: thread) }
            }
            guard !Task.isCancelled else { return }
            self.searching = nil
            self.publish()
        }
        searching = (words, task)
        publish()
    }

    /// Whether Messages shows a thread at all, as `ChannelBook.build` decides: a talk with the cat that isn't a test, a
    /// kitten's, or the cat's own work that lives in #general or its DM. Anything else can hold your screen.
    private func shows(_ owners: KittenBoard.Owners) -> (AgentThread) -> Bool {
        let inGeneral = inGeneral()
        return { [isWithShades, isCatsWork] thread in
            isWithShades(thread) ? !thread.isLiveTest : owners.of(thread) != nil || inGeneral[thread.id] != nil || isCatsWork(thread)
        }
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

    /// What's been said in a thread, oldest first, as Messages shows it now.
    func messages(in thread: String) -> [ChannelMessage] {
        published?.threads[thread]?.messages ?? []
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
        let mine = inGeneral()
        let shownInGeneral = Set(alsoSentToGeneral().values)
        // Everything that shows in #general is read, since only so many are kept, whoever's thread it is.
        let isGeneral = { (thread: AgentThread) in mine[thread.id] != nil || shownInGeneral.contains(thread.id) }
        let general = listed.filter { !isWithShades($0) && isGeneral($0) }
        let byOwner = Dictionary(grouping: listed.filter { !isWithShades($0) && !isGeneral($0) }) { owners.of($0)?.id }
        let loading = loadingOlder
        func newest(_ threads: [AgentThread], in channel: ChannelID) -> [AgentThread] {
            let pages = (olderPages[channel] ?? 0) + 1
            return Array(threads.sorted { $0.updatedAt > $1.updatedAt }.prefix(Self.newestReadPerKitten * pages))
        }
        let kittens: [AgentThread] = byOwner.flatMap { owner, threads in owner.map { newest(threads, in: .kitten($0)) } ?? [] }
        var owned: [AgentThread] = kittens + general
            + newest((byOwner[nil] ?? []).filter(isCatsWork), in: .shades)
            + newest(talks.filter { !$0.isLiveTest }, in: .shades)
        let reading = Set(owned.map(\.id))
        owned += listed.filter { found.contains($0.id) && !reading.contains($0.id) }
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
            if let exchanges { keep(exchanges, of: thread) }
            if Date().timeIntervalSince(lastShown) >= Self.showEvery {
                lastShown = Date()
                publish()
            }
        }
        // The live list can have stood in for it meanwhile, and this one has every thread.
        threads = listed
        unreadNew = []
        hasRead = true
        loadingOlder.subtract(loading)
        passes += 1
        unreadable = moved.count - read
        couldntRead = Set(moved.map(\.id)).subtracting(transcripts.keys)
        if unreadable > 0 { isDirty = true }
        publish()
    }

    /// A thread shows its newest replies, and always its first message, which is the one that started it.
    private func keep(_ exchanges: [Exchange], of thread: AgentThread) {
        transcripts[thread.id] = exchanges.count > ChannelBook.keptExchanges
            ? Array(exchanges.prefix(1) + exchanges.suffix(ChannelBook.keptExchanges - 1))
            : exchanges
        readStamps[thread.id] = thread.updatedAt
    }

    /// Whether a thread's words are part of what's on the screen.
    private func isOnScreen(_ owners: KittenBoard.Owners) -> (AgentThread) -> Bool {
        let isWithShades = isWithShades
        let isCatsWork = isCatsWork
        let open = lookingAt?.thread
        let inGeneral = inGeneral()
        let place: (AgentThread) -> Bool
        switch lookingAt?.place {
        case .channel(.shades)?:
            place = { isWithShades($0) || isCatsWork($0) }
        case .channel(.general)?:
            place = { inGeneral[$0.id] != nil || (!isWithShades($0) && owners.of($0) == nil && !isCatsWork($0)) }
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
        // With nobody looking there's no hurry, so reading ahead takes one at a time and leaves T3 room for the rest.
        let atOnce = isOpen ? Self.readsAtOnce : 1
        return await withTaskGroup(of: (AgentThread, [Exchange]?).self) { group in
            var waiting = threads.makeIterator()
            func readNext() {
                guard !Task.isCancelled, let thread = waiting.next() else { return }
                group.addTask { (thread, await backend.exchanges(threadID: thread.id)) }
            }
            for _ in 0..<atOnce { readNext() }

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
        if !book.alsoSentHeard.isEmpty { keepAlsoSent(book.alsoSentHeard) }
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
            firstNew: firstNew,
            inGeneral: inGeneral(),
            withShades: Set(threads.filter(isWithShades).map(\.id)),
            catsWork: Set(threads.filter(isCatsWork).map(\.id)),
            onPhone: onPhone(),
            hasPhone: hasPhone(),
            answersInGeneral: answersInGeneral(),
            alsoSent: alsoSent(),
            alsoSentToGeneral: Set(alsoSentToGeneral().keys),
            olderPages: olderPages,
            loadingOlder: loadingOlder,
            couldntRead: couldntRead,
            reactions: reactions(),
            searchingT3: searching?.words,
            said: { reply in
                let words = self.said[reply] ?? ChannelBook.said(reply)
                said[reply] = words
                return words
            }
        )
    }
}
