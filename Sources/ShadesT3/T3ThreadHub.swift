import Foundation
import ShadesCore

/// Holds the live thread list and everyone watching it. There's one shell subscription however many watchers.
actor T3ThreadHub {
    private let socket: T3Socket
    private var list: T3ThreadList
    private var watchers: [UUID: AsyncStream<[AgentThread]>.Continuation] = [:]
    private var isStarted = false
    private var subscription: UUID?
    private var published: [AgentThread]?
    private var summaries: [String: String] = [:]
    private var questions: [String: T3ThreadList.QuestionWords] = [:]
    private var fetching: Set<String> = []
    private var loadWaiters: [CheckedContinuation<Void, Never>] = []

    init(socket: T3Socket, scratchRoot: String) {
        self.socket = socket
        list = T3ThreadList(scratchRoot: scratchRoot)
    }

    func start() async {
        guard !isStarted else { return }
        isStarted = true
        let payload = T3Wire.encode(T3Wire.SubscribeShell())
        subscription = await socket.subscribe(
            T3Wire.Method.subscribeShell,
            retriesOnFailure: true,
            payload: { payload },
            onEnd: { _ in }
        ) { [weak self] frame in
            let items = (try? T3Wire.frames(T3Wire.ChunkFrame<T3Wire.ShellItem>.self, in: frame))?
                .flatMap(\.items) ?? []
            await self?.apply(items)
        }
    }

    func stop() async {
        if let subscription { await socket.unsubscribe(subscription) }
        subscription = nil
        for watcher in watchers.values { watcher.finish() }
        watchers = [:]
        for waiter in loadWaiters { waiter.resume() }
        loadWaiters = []
    }

    func add(_ watcher: AsyncStream<[AgentThread]>.Continuation, id: UUID) {
        watchers[id] = watcher
        if let published { watcher.yield(published) }
    }

    func remove(id: UUID) {
        watchers[id] = nil
    }

    func runtimeMode(of threadID: String) -> String? {
        list.runtimeMode(of: threadID)
    }

    /// Waits for the first snapshot, so the caller sees real projects rather than an empty list.
    func projects() async -> [T3Project] {
        if !list.isLoaded {
            await withCheckedContinuation { loadWaiters.append($0) }
        }
        return list.projects
    }

    private func apply(_ items: [T3Wire.ShellItem]) {
        guard !items.isEmpty else { return }
        for item in items { list.apply(item) }
        if list.isLoaded {
            for waiter in loadWaiters { waiter.resume() }
            loadWaiters = []
        }
        fetchMissingSummaries()
        fetchMissingQuestions()
        publish()
    }

    private func publish() {
        guard list.isLoaded else { return }
        let threads = list.agentThreads(summaries: summaries, questions: questions)
        guard threads != published else { return }
        published = threads
        for watcher in watchers.values { watcher.yield(threads) }
    }

    // MARK: Approval words

    /// The shell only says an approval exists. Its words live on a turn item, one quick call away.
    private func fetchMissingSummaries() {
        let pendingApprovals = list.pendingApprovals
        let pendingIDs = Set(pendingApprovals.map(\.requestID))
        summaries = summaries.filter { pendingIDs.contains($0.key) }

        for pending in pendingApprovals where summaries[pending.requestID] == nil && !fetching.contains(pending.requestID) {
            fetching.insert(pending.requestID)
            Task { [weak self] in
                guard let self else { return }
                let summary = await self.loadSummary(pending)
                await self.didLoad(summary, for: pending.requestID)
            }
        }
    }

    private func loadSummary(_ pending: T3ThreadList.PendingApproval) async -> String {
        let item = await requestItem(requestID: pending.requestID, threadID: pending.threadID)
        var related: T3Wire.TurnItem?
        if let ref = item?.nativeItemRef {
            related = await turnItem(id: T3Wire.providerItemID(ref), threadID: pending.threadID)
        }
        return T3Wire.approvalSummary(kind: pending.kind, item: item, related: related)
    }

    private func requestItem(requestID: String, threadID: String) async -> T3Wire.TurnItem? {
        let id = T3Wire.approvalItemID(requestID: requestID)
        if let item = await turnItem(id: id, threadID: threadID) { return item }

        // That ID is T3's convention rather than a promise, so fall back to reading the thread.
        let projection: T3Wire.Projection? = try? await socket.call(
            T3Wire.Method.getThreadProjection,
            T3Wire.GetThreadProjection(threadId: threadID)
        )
        return projection?.turnItems.lazy.compactMap(\.value).first { $0.requestId == requestID }
    }

    private func turnItem(id: String, threadID: String) async -> T3Wire.TurnItem? {
        let request = T3Wire.GetTurnItem(threadId: threadID, itemId: id)
        let result: T3Wire.TurnItemResult? = try? await socket.call(T3Wire.Method.getTurnItem, request)
        return result?.item
    }

    private func didLoad(_ summary: String, for requestID: String) {
        fetching.remove(requestID)
        summaries[requestID] = summary
        publish()
    }

    // MARK: Question words

    /// A question's words live on a turn item too. Words that can't be read still count, so you hear about it.
    private func fetchMissingQuestions() {
        let pendingQuestions = list.pendingQuestions
        let pendingIDs = Set(pendingQuestions.map(\.requestID))
        questions = questions.filter { pendingIDs.contains($0.key) }

        for pending in pendingQuestions where questions[pending.requestID] == nil && !fetching.contains(pending.requestID) {
            fetching.insert(pending.requestID)
            Task { [weak self] in
                guard let self else { return }
                let item = await self.requestItem(requestID: pending.requestID, threadID: pending.threadID)
                let first = item?.questions?.first
                let words = T3ThreadList.QuestionWords(
                    text: first?.question ?? "",
                    options: first?.options?.map(\.label) ?? [],
                    moreCount: max(0, (item?.questions?.count ?? 0) - 1)
                )
                await self.didLoad(words, for: pending.requestID)
            }
        }
    }

    private func didLoad(_ words: T3ThreadList.QuestionWords, for requestID: String) {
        fetching.remove(requestID)
        questions[requestID] = words
        publish()
    }
}
