import Foundation
import ShadesCore

@MainActor
final class ChannelFeed {
    private static let newestReadPerKitten = 30
    private static let readsAtOnce = 4
    private static let quietGaps = 5
    private static let showEvery: TimeInterval = 0.15
    private static let sentKept = 100
    private static let foundAtOnce = 8
    private static let foundKept = 30

    var onChange: ((ChannelBook) -> Void)?
    var waiting: () -> Waiting = { Waiting() }
    var isUnread: (AgentThread) -> Bool = { _ in false }
    var firstNew: (AgentThread, [ChannelMessage]) -> String? = { _, _ in nil }
    var messagesThreads: () -> [String: Date] = { [:] }
    var isWithShades: (AgentThread) -> Bool = { _ in false }
    var isCatsWork: (AgentThread) -> Bool = { _ in false }
    var onPhone: () -> Set<String> = { [] }
    var hasPhone: () -> Bool = { false }
    var alsoSent: () -> Set<String> = { [] }
    var reactions: () -> [String: [Reaction]] = { [:] }
    var keepAlsoSent: ([String: ChannelBook.HeardAlsoSent]) -> Void = { _ in }
    var lookingAt: ChannelSelection?

    private let backend: AgentBackend
    private let kittens: () -> [Kitten]
    private let gap: Duration

    private var threads: [AgentThread] = []
    private var transcripts: [String: [Exchange]] = [:]
    private var readStamps: [String: Date] = [:]
    private var unreadNew: Set<String> = []
    private var couldntRead: Set<String> = []
    private var sent: [SentMessage] = []
    private var passedOn: [String: String] = [:]
    private var olderPages: [ChannelID: Int] = [:]
    private var loadingOlder: Set<ChannelID> = []
    private var found: [String] = []
    private var searching: (words: String, task: Task<Void, Never>)?
    private var hasRead = false
    private var unreadable = 0
    private var cantReachT3 = false
    private var isDirty = true
    private var wantsWarm = false
    private var quiet = 0
    private var loop: Task<Void, Never>?
    private var nap: Task<Void, Never>?
    private var published: ChannelBook?
    private var said: [String: String?] = [:]

    private(set) var isOpen = false
    private(set) var passes = 0

    let pictures: PictureShelf

    init(backend: AgentBackend, kittens: @escaping () -> [Kitten], gap: Duration = .seconds(3), web: @escaping @Sendable (URL) async -> Data? = { await WebPicture.fetch($0) }) {
        self.backend = backend
        self.kittens = kittens
        self.gap = gap
        pictures = PictureShelf(backend: backend, web: web)
        pictures.onChange = { [weak self] in self?.refresh() }
    }

    var threadsHeld: Int { transcripts.count }

    func listed(_ id: String) -> AgentThread? {
        threads.first { $0.id == id }
    }

    func open(threads: [AgentThread]) -> ChannelBook {
        if isOpen, let published { return published }
        if !isOpen {
            isOpen = true
            isDirty = true
            if !hasRead { self.threads = threads }
            nap?.cancel()
            run()
        }
        let book = book()
        published = book
        return book
    }

    func warm(threads: [AgentThread]) {
        guard !hasRead, !isOpen else { return }
        self.threads = threads
        wantsWarm = true
        run()
    }

    func close() {
        isOpen = false
    }

    func threadsChanged(_ threads: [AgentThread]) {
        if !hasRead, isOpen {
            self.threads = threads
            publish()
        }
        isDirty = true
    }

    func refresh() {
        if isOpen { publish() }
    }

    func sent(_ message: ChannelMessage, in channel: ChannelID, startsThread: Bool = false, alsoSent: Bool = false, isReply: Bool = false, target: MessageTarget? = nil) {
        sent.removeAll { $0.message.exchangeID == message.exchangeID }
        sent.append(SentMessage(channel: channel, message: message, startsThread: startsThread, alsoSent: alsoSent, isReply: isReply, target: target))
        sent = sent.suffix(Self.sentKept)
        isDirty = true
        publish()
    }

    func failed(_ exchangeID: String, because reason: String) {
        guard let index = sent.firstIndex(where: { $0.message.exchangeID == exchangeID }) else { return }
        sent[index].message.failure = reason
        sent[index].message.isSending = false
        isDirty = true
        publish()
    }

    func delivered(_ exchangeID: String) {
        guard let index = sent.firstIndex(where: { $0.message.exchangeID == exchangeID }), sent[index].message.isSending else { return }
        sent[index].message.isSending = false
        publish()
    }

    func passedOn(_ talk: String, to thread: String) {
        passedOn[talk] = thread
        isDirty = true
        publish()
    }

    func toTryAgain(_ exchangeID: String) -> SentMessage? {
        sent.first { $0.message.exchangeID == exchangeID && $0.message.canTryAgain && $0.target != nil }
    }

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

    func older(in channel: ChannelID) {
        guard !loadingOlder.contains(channel), published?.channel(channel)?.isCut == true else { return }
        olderPages[channel, default: 0] += 1
        loadingOlder.insert(channel)
        isDirty = true
        nap?.cancel()
        publish()
    }

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

    private func shows(_ owners: KittenBoard.Owners) -> (AgentThread) -> Bool {
        let mine = messagesThreads()
        return { [isWithShades, isCatsWork] thread in
            isWithShades(thread) ? !thread.isLiveTest : owners.of(thread) != nil || mine[thread.id] != nil || isCatsWork(thread)
        }
    }

    func threads(in selection: ChannelSelection) -> [AgentThread] {
        guard let book = published else { return [] }
        var shown: Set<String> = []
        if let open = selection.thread, book.threads[open] != nil { shown.insert(open) }
        var quiet: (AgentThread) -> Bool = { _ in false }
        if let id = selection.channelID, let channel = book.channel(id) {
            let owners = KittenBoard.Owners(kittens())
            quiet = { thread in
                guard book.threads[thread.id] == nil, self.transcripts[thread.id] != nil else { return false }
                switch id {
                case .kitten(let kitten): return owners.of(thread)?.id == kitten
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

    func messages(in thread: String) -> [ChannelMessage] {
        published?.threads[thread]?.messages ?? []
    }

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
        let mine = messagesThreads()
        let byOwner = Dictionary(grouping: listed.filter { !isWithShades($0) }) { owners.of($0)?.id }
        let loading = loadingOlder
        func newest(_ threads: [AgentThread], in channel: ChannelID) -> [AgentThread] {
            let pages = (olderPages[channel] ?? 0) + 1
            return Array(threads.sorted { $0.updatedAt > $1.updatedAt }.prefix(Self.newestReadPerKitten * pages))
        }
        let kittens: [AgentThread] = byOwner.flatMap { owner, threads in owner.map { newest(threads, in: .kitten($0)) } ?? [] }
        var owned: [AgentThread] = kittens
            + newest((byOwner[nil] ?? []).filter { isCatsWork($0) || mine[$0.id] != nil }, in: .shades)
            + newest(talks.filter { !$0.isLiveTest }, in: .shades)
        let reading = Set(owned.map(\.id))
        owned += listed.filter { found.contains($0.id) && !reading.contains($0.id) }
        let onScreen = isOnScreen(owners)
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

    private func keep(_ exchanges: [Exchange], of thread: AgentThread) {
        transcripts[thread.id] = exchanges.count > ChannelBook.keptExchanges
            ? Array(exchanges.prefix(1) + exchanges.suffix(ChannelBook.keptExchanges - 1))
            : exchanges
        readStamps[thread.id] = thread.updatedAt
    }

    private func isOnScreen(_ owners: KittenBoard.Owners) -> (AgentThread) -> Bool {
        let isWithShades = isWithShades
        let isCatsWork = isCatsWork
        let open = lookingAt?.thread
        let mine = messagesThreads()
        let place: (AgentThread) -> Bool
        switch lookingAt?.place {
        case .channel(.shades)?:
            place = { isWithShades($0) || owners.of($0) == nil && (isCatsWork($0) || mine[$0.id] != nil) }
        case .channel(.kitten(let kitten))?:
            place = { thread in owners.of(thread)?.id == kitten }
        case .threads?:
            place = { !isWithShades($0) }
        case .activity?, nil:
            place = { _ in false }
        }
        return { $0.id == open || place($0) }
    }

    private func read(_ threads: [AgentThread], landed: (AgentThread, [Exchange]?) -> Void) async -> Int {
        let backend = backend
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
        var said: [String: String?] = [:]
        defer { self.said = said }
        var book = ChannelBook.build(
            kittens: kittens(),
            threads: unreadNew.isEmpty ? threads : threads.filter { !unreadNew.contains($0.id) },
            transcripts: transcripts,
            isReading: !hasRead,
            unreadable: unreadable,
            cantReachT3: cantReachT3,
            waiting: waiting(),
            sent: sent,
            passedOn: passedOn,
            isUnread: isUnread,
            firstNew: firstNew,
            messagesThreads: messagesThreads(),
            withShades: Set(threads.filter(isWithShades).map(\.id)),
            catsWork: Set(threads.filter(isCatsWork).map(\.id)),
            onPhone: onPhone(),
            hasPhone: hasPhone(),
            alsoSent: alsoSent(),
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
        pictures.fill(&book)
        return book
    }
}
