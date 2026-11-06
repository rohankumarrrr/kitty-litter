import AppKit
import Foundation
import ShadesCore

/// Runs agents through the T3 Code app on this Mac. See docs/t3-integration.md.
public final class T3Backend: AgentBackend, @unchecked Sendable {
    /// How long a turn's stream waits for T3 to come back before giving up.
    private static let outageLimit: Duration = .seconds(30)

    private let auth: T3Auth
    private let socket: T3Socket
    private let hub: T3ThreadHub
    private let home: URL
    private let uploads: URLSession
    private let scratchRoot: String
    private let lock = NSLock()
    private var scratchProjectID: String?
    /// What `exchanges(threadID:)` names senders from, as of the last `allThreads()`.
    private var catalog = T3ThreadList()

    /// T3 Code's data folder: `$T3CODE_HOME`, then `~/.t3`.
    public static var defaultHome: URL { T3Auth.defaultHome }

    /// - Parameters:
    ///   - home: T3 Code's data folder. Defaults to `$T3CODE_HOME`, then `~/.t3`.
    ///   - credentials: Where the sign-in is kept.
    ///   - label: The name this client goes by in T3's list of connections.
    ///   - sessionTTL: How long each sign-in lasts, as `t3 auth session issue` takes it.
    ///   - renewBefore: Signs in again once this little is left, so a session never runs out mid-task.
    public init(
        home: URL? = nil,
        credentials: T3CredentialStoring = KeychainCredentialStore(),
        label: String = "Shades",
        sessionTTL: String = "30d",
        renewBefore: TimeInterval = 7 * 24 * 60 * 60
    ) {
        let home = home ?? T3Auth.defaultHome
        let auth = T3Auth(home: home, store: credentials, label: label, ttl: sessionTTL, renewBefore: renewBefore)
        let socket = T3Socket { forceNewSession in
            try await auth.socketRequest(forceNewSession: forceNewSession)
        }
        self.home = home
        self.auth = auth
        self.socket = socket
        let scratchRoot = home.appendingPathComponent("scratch", isDirectory: true).standardizedFileURL.path
        self.scratchRoot = scratchRoot
        hub = T3ThreadHub(socket: socket, scratchRoot: scratchRoot)
        uploads = URLSession(configuration: .ephemeral)
    }

    // MARK: AgentBackend

    public func connect() async throws {
        try await socket.connect()
        await hub.start()
    }

    public func start(_ prompt: AgentPrompt) -> AsyncThrowingStream<AgentReplyEvent, Error> {
        stream { [self] continuation in
            try await connect()
            let attachments = try await upload(prompt.attachments)
            let threadID = Self.newID()
            let messageID = Self.newID()
            let title = Self.title(for: prompt)
            let launch = T3Wire.LaunchThread(
                commandId: Self.newID(),
                threadId: threadID,
                projectId: try await projectID(for: prompt),
                title: title,
                generateTitle: prompt.title == nil,
                modelSelection: T3Wire.ModelSelection(prompt.model),
                runtimeMode: prompt.runtimeMode.rawValue,
                initialMessage: .init(messageId: messageID, text: prompt.text, attachments: attachments)
            )

            let result: T3Wire.LaunchResult
            do {
                result = try await socket.call(T3Wire.Method.launchThread, launch)
            } catch {
                // The folder can be deleted between launches, so ask for it again next time.
                if prompt.projectID == nil { lock.withLock { scratchProjectID = nil } }
                throw error
            }
            continuation.yield(.started(threadID: threadID))

            let runID = result.projection.runs.lazy.compactMap(\.value).first { $0.userMessageId == messageID }?.id
            let tracker = TurnProgress(T3TurnTracker(threadID: threadID, messageID: messageID, threadTitle: title, runID: runID))
            await follow(threadID: threadID, afterSequence: result.sequence, tracker: tracker, continuation: continuation)
        }
    }

    public func followUp(threadID: String, _ prompt: AgentPrompt) -> AsyncThrowingStream<AgentReplyEvent, Error> {
        stream { [self] continuation in
            try await connect()
            let attachments = try await upload(prompt.attachments)
            try await setRuntimeMode(prompt.runtimeMode, on: threadID)
            continuation.yield(.started(threadID: threadID))
            await send(
                prompt.text,
                attachments: attachments,
                model: T3Wire.ModelSelection(prompt.model),
                title: prompt.title ?? "",
                to: threadID,
                continuation: continuation
            )
        }
    }

    public func forward(threadID: String, text: String, attachments: [AgentAttachment]) -> AsyncThrowingStream<AgentReplyEvent, Error> {
        stream { [self] continuation in
            try await connect()
            let uploaded = try await upload(attachments)
            continuation.yield(.started(threadID: threadID))
            await send(text, attachments: uploaded, model: nil, title: "", to: threadID, continuation: continuation)
        }
    }

    private func send(
        _ text: String,
        attachments: [T3Wire.ImageAttachment],
        model: T3Wire.ModelSelection?,
        title: String,
        to threadID: String,
        continuation: AsyncThrowingStream<AgentReplyEvent, Error>.Continuation
    ) async {
        let messageID = Self.newID()
        let message = T3Wire.DispatchMessage(
            commandId: Self.newID(),
            threadId: threadID,
            messageId: messageID,
            text: text,
            attachments: attachments,
            modelSelection: model
        )
        let tracker = TurnProgress(T3TurnTracker(threadID: threadID, messageID: messageID, threadTitle: title))

        // Listen first: the snapshot this asks for and the events after it can't miss the new run.
        // Nothing waits for that snapshot, so sending the message isn't held up.
        await follow(threadID: threadID, afterSequence: nil, tracker: tracker, continuation: continuation) { [socket] in
            let _: T3Wire.DispatchResult = try await socket.call(T3Wire.Method.dispatchCommand, message)
        }
    }

    public func watchThreads() -> AsyncStream<[AgentThread]> {
        AsyncStream { continuation in
            let id = UUID()
            let hub = self.hub
            continuation.onTermination = { _ in
                Task { await hub.remove(id: id) }
            }
            Task { [self] in
                await hub.add(continuation, id: id)
                // If T3 isn't up yet this list simply starts when it is: the socket keeps trying.
                await hub.start()
                try? await socket.connect()
            }
        }
    }

    public func respond(to request: ApprovalRequest, with decision: ApprovalDecision) async throws {
        let command = T3Wire.RespondToRequest(
            commandId: Self.newID(),
            threadId: request.threadID,
            requestId: request.id,
            decision: decision.rawValue
        )
        let _: T3Wire.DispatchResult = try await socket.call(T3Wire.Method.dispatchCommand, command)
    }

    public func answer(_ question: AgentQuestion, with answers: [String]) async throws {
        guard let form = question.form, let answers = T3Wire.answers(answers, to: form) else { throw T3Error.rejected("That question can't be answered from here.") }
        let command = T3Wire.RespondToRequest(
            commandId: Self.newID(),
            threadId: question.threadID,
            requestId: question.id,
            answers: answers
        )
        let _: T3Wire.DispatchResult = try await socket.call(T3Wire.Method.dispatchCommand, command)
    }

    public func projectID(atPath path: String) async -> String? {
        let wanted = URL(fileURLWithPath: path).standardizedFileURL.path
        return (try? await projects())?.first { URL(fileURLWithPath: $0.path).standardizedFileURL.path == wanted }?.id
    }

    public func addProject(atPath path: String, title: String) async throws -> String {
        try await connect()
        let command = T3Wire.CreateProject(commandId: Self.newID(), projectId: Self.newID(), title: title, workspaceRoot: path)
        let project: T3Wire.Project = try await socket.call(T3Wire.Method.mutateProject, command)
        return project.id
    }

    public func archive(threadID: String) async throws {
        let command = T3Wire.ArchiveThread(commandId: Self.newID(), threadId: threadID)
        let _: T3Wire.DispatchResult = try await socket.call(T3Wire.Method.dispatchCommand, command)
    }

    public func settle(threadID: String) async throws {
        let command = T3Wire.SettleThread(commandId: Self.newID(), threadId: threadID)
        let _: T3Wire.DispatchResult = try await socket.call(T3Wire.Method.dispatchCommand, command)
    }

    public func report(threadID: String, run: String?) async throws -> String? {
        let projection: T3Wire.Projection = try await socket.call(
            T3Wire.Method.getThreadProjection,
            T3Wire.GetThreadProjection(threadId: threadID)
        )
        return T3Wire.finalReport(in: projection.turnItems.compactMap(\.value), run: run)
    }

    public func allThreads() async -> [AgentThread]? {
        let scratchRoot = scratchRoot
        let list = await firstSnapshot(
            T3Wire.Method.subscribeShell,
            payload: T3Wire.encode(T3Wire.SubscribeShell.everything),
            of: T3Wire.ShellItem.self
        ) { items -> T3ThreadList? in
            var list = T3ThreadList(scratchRoot: scratchRoot)
            for item in items { list.apply(item) }
            return list.isLoaded ? list : nil
        }
        guard let list else { return nil }
        lock.withLock { catalog = list }
        return list.threadsWithoutWords
    }

    /// Reads the whole thread, because `getThreadProjection` only answers with its latest 75 or so
    /// rows, which leaves out what a long thread was asked.
    /// shortcut: a thread over `T3Socket`'s 64 MB frame limit would drop the connection, and the largest seen is 15 MB. Check its `itemCount` first if they get near that.
    public func exchanges(threadID: String) async -> [Exchange]? {
        if !lock.withLock({ catalog.isLoaded }) { _ = await allThreads() }
        let projection = await firstSnapshot(
            T3Wire.Method.subscribeThread,
            payload: T3Wire.encode(T3Wire.SubscribeThread.whole(threadID: threadID)),
            of: T3Wire.ThreadItem.self
        ) { items -> T3Wire.Projection? in
            for case let .snapshot(projection, _) in items { return projection }
            return nil
        }
        guard let projection else { return nil }
        let known = lock.withLock { catalog }
        return T3Transcript.exchanges(
            in: projection.turnItems.compactMap(\.value),
            runs: projection.runs.compactMap(\.value),
            sender: known.listedThreadID(of:)
        )
    }

    /// Subscribes just long enough for a stream's first snapshot. `nil` if the connection drops or it takes too long.
    private func firstSnapshot<Snapshot, Item: Decodable>(
        _ method: String,
        payload: Data,
        of item: Item.Type,
        reading snapshot: @escaping @Sendable ([Item]) -> Snapshot?
    ) async -> Snapshot? {
        guard (try? await socket.connect()) != nil else { return nil }
        let found = AsyncStream<Snapshot?>.makeStream()
        let giveUp = OutageTimer(limit: Self.outageLimit) { found.continuation.yield(nil) }
        giveUp.start()
        defer { giveUp.cancel() }

        let subscription = await socket.subscribe(
            method,
            payload: { payload },
            onConnectionChange: { isOpen in
                if !isOpen { found.continuation.yield(nil) }
            },
            onEnd: { _ in found.continuation.yield(nil) },
            onChunk: { frame in
                let items = (try? T3Wire.frames(T3Wire.ChunkFrame<Item>.self, in: frame))?.flatMap(\.items) ?? []
                if let value = snapshot(items) { found.continuation.yield(value) }
            }
        )

        // Going away cancels this, which ends the wait.
        var first: Snapshot?
        for await next in found.stream {
            first = next
            break
        }
        await socket.unsubscribe(subscription)
        return first
    }

    public func origin(of threadID: String) async -> ThreadOrigin? {
        guard let projection: T3Wire.Projection = try? await socket.call(
            T3Wire.Method.getThreadProjection,
            T3Wire.GetThreadProjection(threadId: threadID)
        ) else { return nil }
        let path = await hub.projects().first { $0.id == projection.thread.projectId }?.path
        return ThreadOrigin(title: projection.thread.title, projectPath: path, startedBy: projection.startedBy)
    }

    public func open(threadID: String) {
        Task { [self] in
            guard let environmentID = await environmentID(),
                  let url = T3Wire.threadLink(environmentID: environmentID, threadID: threadID)
            else { return }
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Beyond the contract

    /// Your T3 projects, for binding a thread to one.
    public func projects() async throws -> [T3Project] {
        try await connect()
        return await hub.projects()
    }

    /// Closes the connection. A backend can't be used again after this.
    public func disconnect() async {
        await hub.stop()
        await socket.shutdown()
    }

    /// Ends this sign-in on the server and forgets it. The next `connect()` signs in again.
    public func signOut() async {
        await auth.signOut()
    }

    // MARK: Streaming a turn

    private func stream(
        _ body: @escaping @Sendable (AsyncThrowingStream<AgentReplyEvent, Error>.Continuation) async throws -> Void
    ) -> AsyncThrowingStream<AgentReplyEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await body(continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Passes the thread's events through the tracker until the turn ends or the listener goes away.
    private func follow(
        threadID: String,
        afterSequence: Int?,
        tracker: TurnProgress,
        continuation: AsyncThrowingStream<AgentReplyEvent, Error>.Continuation,
        sending: (@Sendable () async throws -> Void)? = nil
    ) async {
        let outcome = AsyncStream<Result<Void, Error>>.makeStream()
        let outage = OutageTimer(limit: Self.outageLimit) {
            outcome.continuation.yield(.failure(T3Error.connectionLost))
        }
        tracker.noteSequence(afterSequence)

        let subscription = await socket.subscribe(
            T3Wire.Method.subscribeThread,
            payload: {
                T3Wire.encode(T3Wire.SubscribeThread(threadId: threadID, afterSequence: tracker.lastSequence))
            },
            onConnectionChange: { isOpen in
                if isOpen { outage.cancel() } else { outage.start() }
            },
            onEnd: { error in
                outcome.continuation.yield(error.map { .failure($0) } ?? .failure(T3Error.connectionLost))
            },
            onChunk: { frame in
                let items = (try? T3Wire.frames(T3Wire.ChunkFrame<T3Wire.ThreadItem>.self, in: frame))?
                    .flatMap(\.items) ?? []
                for item in items {
                    for event in tracker.apply(item) { continuation.yield(event) }
                }
                if tracker.isFinished { outcome.continuation.yield(.success(())) }
            }
        )

        let sender = Task {
            do {
                try await sending?()
            } catch {
                outcome.continuation.yield(.failure(error))
            }
        }

        // The listener going away cancels this, which ends the wait.
        var result: Result<Void, Error> = .success(())
        for await next in outcome.stream {
            result = next
            break
        }
        sender.cancel()
        outage.cancel()
        await socket.unsubscribe(subscription)

        switch result {
        case .success: continuation.finish()
        case let .failure(error): continuation.finish(throwing: error)
        }
    }

    // MARK: Attachments

    private func upload(_ attachments: [AgentAttachment]) async throws -> [T3Wire.ImageAttachment] {
        if attachments.isEmpty { return [] }
        for attachment in attachments {
            guard T3Wire.imageTypes.contains(attachment.mimeType.lowercased()) else {
                throw T3Error.attachmentNotSupported(name: attachment.name, reason: "only images can be attached.")
            }
            guard attachment.data.count <= T3Wire.maxImageBytes else {
                throw T3Error.attachmentNotSupported(name: attachment.name, reason: "images can be up to 10 MB.")
            }
            guard !attachment.data.isEmpty else {
                throw T3Error.attachmentNotSupported(name: attachment.name, reason: "the file is empty.")
            }
        }

        let origin = try await auth.currentOrigin()
        return try await withThrowingTaskGroup(of: (Int, T3Wire.ImageAttachment).self) { group in
            for (index, attachment) in attachments.enumerated() {
                group.addTask { (index, try await self.upload(attachment, to: origin)) }
            }
            var uploaded: [(Int, T3Wire.ImageAttachment)] = []
            for try await result in group { uploaded.append(result) }
            return uploaded.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func upload(_ attachment: AgentAttachment, to origin: URL) async throws -> T3Wire.ImageAttachment {
        let ticket: T3Wire.UploadTicket = try await socket.call(
            T3Wire.Method.createUploadURL,
            T3Wire.CreateUploadURL(name: attachment.name, mimeType: attachment.mimeType.lowercased(), sizeBytes: attachment.data.count)
        )
        guard let url = URL(string: ticket.relativeUrl, relativeTo: origin) else { throw T3Error.connectionLost }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(attachment.mimeType.lowercased(), forHTTPHeaderField: "Content-Type")
        let (_, response) = try await uploads.upload(for: request, from: attachment.data)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
            throw T3Error.attachmentNotSupported(name: attachment.name, reason: "T3 Code wouldn't take the upload.")
        }
        return T3Wire.ImageAttachment(
            id: ticket.attachmentId,
            name: attachment.name,
            mimeType: attachment.mimeType.lowercased(),
            sizeBytes: attachment.data.count
        )
    }

    // MARK: Small things

    /// Only when it really changes: this can end a provider session, and the next turn then pays to start one.
    private func setRuntimeMode(_ mode: RuntimeMode, on threadID: String) async throws {
        var current = await hub.runtimeMode(of: threadID)
        if current == nil {
            // The list leaves out threads settled long ago.
            let projection: T3Wire.Projection = try await socket.call(
                T3Wire.Method.getThreadProjection,
                T3Wire.GetThreadProjection(threadId: threadID)
            )
            current = projection.thread.runtimeMode
        }
        guard current != mode.rawValue else { return }
        let change = T3Wire.SetRuntimeMode(commandId: Self.newID(), threadId: threadID, runtimeMode: mode.rawValue)
        let _: T3Wire.DispatchResult = try await socket.call(T3Wire.Method.dispatchCommand, change)
    }

    private func projectID(for prompt: AgentPrompt) async throws -> String {
        if let projectID = prompt.projectID { return projectID }
        if let known = lock.withLock({ scratchProjectID }) { return known }
        let scratch: T3Wire.ScratchProject = try await socket.call(T3Wire.Method.ensureScratch, T3Wire.Empty())
        lock.withLock { scratchProjectID = scratch.projectId }
        return scratch.projectId
    }

    private func environmentID() async -> String? {
        if let known = await auth.environmentID { return known }
        let file = home.appendingPathComponent("userdata/environment-id")
        return (try? String(contentsOf: file, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func newID() -> String { UUID().uuidString.lowercased() }

    /// T3 needs a title up front. Without one it gets the first line, and T3 writes a better one.
    private static func title(for prompt: AgentPrompt) -> String {
        if let title = prompt.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty { return title }
        let firstLine = prompt.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "New thread" : String(trimmed.prefix(60))
    }
}

/// The tracker and resume point for one turn. Chunks arrive one at a time; reconnects read the sequence.
private final class TurnProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var tracker: T3TurnTracker
    private var sequence: Int?

    init(_ tracker: T3TurnTracker) {
        self.tracker = tracker
    }

    var lastSequence: Int? { lock.withLock { sequence } }
    var isFinished: Bool { lock.withLock { tracker.isFinished } }

    func noteSequence(_ sequence: Int?) {
        lock.withLock { self.sequence = sequence }
    }

    func apply(_ item: T3Wire.ThreadItem) -> [AgentReplyEvent] {
        lock.withLock {
            switch item {
            case let .snapshot(_, next), let .event(_, next): sequence = next
            case .other: break
            }
            return tracker.apply(item)
        }
    }
}

/// Runs its action if the connection stays down too long.
private final class OutageTimer: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private let limit: Duration
    private let action: @Sendable () -> Void

    init(limit: Duration, action: @escaping @Sendable () -> Void) {
        self.limit = limit
        self.action = action
    }

    func start() {
        let limit = limit
        let action = action
        lock.withLock {
            guard task == nil else { return }
            task = Task {
                try? await Task.sleep(for: limit)
                if !Task.isCancelled { action() }
            }
        }
    }

    func cancel() {
        lock.withLock {
            task?.cancel()
            task = nil
        }
    }
}
