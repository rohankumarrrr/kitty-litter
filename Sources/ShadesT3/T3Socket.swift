import Foundation

/// One WebSocket to the server, speaking Effect RPC. It stays connected on its own: when T3 restarts
/// it keeps trying, then sends every open subscription again.
actor T3Socket {
    /// What a subscription does with each chunk. Chunks are handled one at a time, in order.
    typealias ChunkHandler = @Sendable (Data) async -> Void

    private struct Subscription {
        let method: String
        /// Asked again on every reconnect, so a stream can pick up where it left off.
        let payload: @Sendable () -> Data
        let onChunk: ChunkHandler
        let onEnd: @Sendable (Error?) -> Void
        let onConnectionChange: (@Sendable (Bool) -> Void)?
        /// A failed stream is tried again instead of ending.
        let retriesOnFailure: Bool
        var requestID: String?
    }

    private static let callTimeout: Duration = .seconds(30)
    private static let pingInterval: Duration = .seconds(10)
    private static let silenceLimit: TimeInterval = 25
    private static let maxFrameBytes = 64 * 1024 * 1024

    private let requestProvider: @Sendable (Bool) async throws -> URLRequest
    private let session: URLSession

    private var runner: Task<Void, Never>?
    private var retryDelay: Task<Void, Never>?
    private var isShutDown = false
    private var socket: URLSessionWebSocketTask?
    private var lastFrameAt = Date()
    private var lastFailure: Error?
    private var nextRequestID = 0
    private var calls: [String: CheckedContinuation<Data, Error>] = [:]
    private var subscriptions: [UUID: Subscription] = [:]
    private var subscriptionByRequest: [String: UUID] = [:]
    private var openWaiters: [CheckedContinuation<Void, Error>] = []

    init(requestProvider: @escaping @Sendable (Bool) async throws -> URLRequest) {
        self.requestProvider = requestProvider
        session = URLSession(configuration: .ephemeral)
    }

    // MARK: Using the connection

    /// Returns once connected, or throws why not. Keeps trying in the background either way.
    func connect() async throws {
        if socket != nil { return }
        if isShutDown { throw T3Error.connectionLost }
        startRunning()
        // Someone's waiting, so try again now instead of at the next retry.
        retryDelay?.cancel()
        try await withCheckedThrowingContinuation { openWaiters.append($0) }
    }

    func call<Result: Decodable>(_ method: String, _ payload: some Encodable, as type: Result.Type = Result.self) async throws -> Result {
        try await connect()
        guard let socket else { throw T3Error.connectionLost }

        let id = makeRequestID()
        let timeout = Task { [weak self] in
            try await Task.sleep(for: Self.callTimeout)
            await self?.expireCall(id)
        }
        defer { timeout.cancel() }

        let frame: Data = try await withCheckedThrowingContinuation { continuation in
            calls[id] = continuation
            send(T3Wire.request(id: id, method: method, payload: T3Wire.encode(payload)), on: socket)
        }

        // The frame holds this request's result, so decode it away from the actor.
        return try await Task.detached {
            // An answer this client can't read means the server's format has changed.
            guard let frames = try? T3Wire.frames(T3Wire.ExitFrame<Result>.self, in: frame),
                  let exit = frames.first(where: { $0.requestId == id })?.exit
            else { throw T3Error.incompatibleServer(version: nil) }
            if exit.isSuccess, let value = exit.value { return value }
            if exit.isProtocolMismatch || exit.isSuccess { throw T3Error.incompatibleServer(version: nil) }
            throw T3Error.rejected(exit.failureMessage)
        }.value
    }

    @discardableResult
    func subscribe(
        _ method: String,
        retriesOnFailure: Bool = false,
        payload: @escaping @Sendable () -> Data,
        onConnectionChange: (@Sendable (Bool) -> Void)? = nil,
        onEnd: @escaping @Sendable (Error?) -> Void,
        onChunk: @escaping ChunkHandler
    ) -> UUID {
        let id = UUID()
        subscriptions[id] = Subscription(
            method: method,
            payload: payload,
            onChunk: onChunk,
            onEnd: onEnd,
            onConnectionChange: onConnectionChange,
            retriesOnFailure: retriesOnFailure
        )
        startRunning()
        if socket != nil { open(subscription: id) }
        return id
    }

    func unsubscribe(_ id: UUID) {
        guard let subscription = subscriptions.removeValue(forKey: id), let requestID = subscription.requestID else { return }
        subscriptionByRequest[requestID] = nil
        if let socket { send(T3Wire.interrupt(requestID: requestID), on: socket) }
    }

    /// Stops for good.
    func shutdown() {
        isShutDown = true
        runner?.cancel()
        retryDelay?.cancel()
        runner = nil
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        failCalls(T3Error.connectionLost)
        for waiter in openWaiters { waiter.resume(throwing: T3Error.connectionLost) }
        openWaiters = []
        let ended = subscriptions.values
        subscriptions = [:]
        subscriptionByRequest = [:]
        for subscription in ended { subscription.onEnd(nil) }
        session.invalidateAndCancel()
    }

    // MARK: Staying connected

    private func startRunning() {
        guard runner == nil, !isShutDown else { return }
        runner = Task { [weak self] in await self?.run() }
    }

    private func run() async {
        var delay = 0.2
        var forceNewSession = false

        while !Task.isCancelled {
            do {
                let socket = try await open(forceNewSession: forceNewSession)
                forceNewSession = false
                delay = 0.2
                didOpen(socket)
                let keepAlive = Task { [weak self] in await self?.keepAlive(socket) }
                defer { keepAlive.cancel() }
                try await pump(socket)
            } catch T3Error.unauthorized {
                // The session was revoked or expired, so the next try signs in again.
                forceNewSession = true
                didFail(T3Error.unauthorized)
            } catch {
                didFail(error)
            }

            didClose()
            if Task.isCancelled { return }
            await waitBeforeRetrying(delay)
            delay = min(delay * 2, 5)
        }
    }

    private func waitBeforeRetrying(_ delay: Double) async {
        let wait = Task<Void, Never> { try? await Task.sleep(for: .seconds(delay)) }
        retryDelay = wait
        await wait.value
        retryDelay = nil
    }

    private func open(forceNewSession: Bool) async throws -> URLSessionWebSocketTask {
        let request = try await requestProvider(forceNewSession)
        let socket = session.webSocketTask(with: request)
        socket.maximumMessageSize = Self.maxFrameBytes
        socket.resume()

        // URLSession only shows how the handshake went on the first exchange.
        do {
            try await socket.send(.data(T3Wire.ping))
            _ = try await socket.receive()
            return socket
        } catch {
            let status = (socket.response as? HTTPURLResponse)?.statusCode
            socket.cancel()
            switch status {
            case 401: throw T3Error.unauthorized
            case 426: throw T3Error.incompatibleServer(version: nil)
            default: throw T3Error.notRunning
            }
        }
    }

    private func didOpen(_ socket: URLSessionWebSocketTask) {
        self.socket = socket
        lastFailure = nil
        lastFrameAt = Date()
        for waiter in openWaiters { waiter.resume() }
        openWaiters = []
        for id in subscriptions.keys {
            subscriptions[id]?.onConnectionChange?(true)
            open(subscription: id)
        }
    }

    private func didFail(_ error: Error) {
        lastFailure = error
        // Anyone waiting hears why right away, and the loop keeps trying without them.
        for waiter in openWaiters { waiter.resume(throwing: error) }
        openWaiters = []
    }

    private func didClose() {
        socket = nil
        failCalls(T3Error.connectionLost)
        subscriptionByRequest = [:]
        for id in subscriptions.keys {
            subscriptions[id]?.requestID = nil
            subscriptions[id]?.onConnectionChange?(false)
        }
    }

    private func keepAlive(_ socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.pingInterval)
            if Task.isCancelled { return }
            if Date().timeIntervalSince(lastFrameAt) > Self.silenceLimit {
                socket.cancel()
                return
            }
            send(T3Wire.ping, on: socket)
        }
    }

    // MARK: Frames

    private nonisolated func pump(_ socket: URLSessionWebSocketTask) async throws {
        while true {
            let data: Data
            switch try await socket.receive() {
            case let .data(frame): data = frame
            case let .string(text): data = Data(text.utf8)
            @unknown default: continue
            }

            guard let headers = try? T3Wire.frames(T3Wire.FrameHeader.self, in: data) else { continue }
            for header in headers {
                guard let handler = await route(header, data) else { continue }
                await handler(data)
                if header.isChunk, let requestID = header.requestId {
                    await acknowledge(requestID, on: socket)
                }
            }
        }
    }

    /// Answers now and returns any slower work, to run off the actor.
    private func route(_ header: T3Wire.FrameHeader, _ data: Data) -> ChunkHandler? {
        lastFrameAt = Date()
        guard let requestID = header.requestId else { return nil }

        if header.isChunk {
            return subscriptionByRequest[requestID].flatMap { subscriptions[$0]?.onChunk }
        }
        guard header.isExit else { return nil }

        if let call = calls.removeValue(forKey: requestID) {
            call.resume(returning: data)
        } else if let id = subscriptionByRequest.removeValue(forKey: requestID) {
            subscriptions[id]?.requestID = nil
            return { [weak self] frame in await self?.streamEnded(id, frame: frame, requestID: requestID) }
        }
        return nil
    }

    private func streamEnded(_ id: UUID, frame: Data, requestID: String) {
        guard let subscription = subscriptions[id] else { return }
        let exit = (try? T3Wire.frames(T3Wire.ExitFrame<T3Wire.Ignored>.self, in: frame))?
            .first { $0.requestId == requestID }?.exit

        // A stream the server let go of, without anything failing, just needs asking for again.
        if exit?.isInterruptOnly == true || (subscription.retriesOnFailure && exit?.isSuccess != true) {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                await self?.reopen(id)
            }
            return
        }
        subscriptions[id] = nil
        subscription.onEnd(exit?.isSuccess == false ? T3Error.rejected(exit?.failureMessage ?? "") : nil)
    }

    private func reopen(_ id: UUID) {
        if socket != nil, subscriptions[id]?.requestID == nil { open(subscription: id) }
    }

    private func open(subscription id: UUID) {
        guard let socket, let subscription = subscriptions[id], subscription.requestID == nil else { return }
        let requestID = makeRequestID()
        subscriptions[id]?.requestID = requestID
        subscriptionByRequest[requestID] = id
        send(T3Wire.request(id: requestID, method: subscription.method, payload: subscription.payload()), on: socket)
    }

    private func acknowledge(_ requestID: String, on socket: URLSessionWebSocketTask) {
        // The server sends nothing more on a stream until the last chunk is acknowledged.
        send(T3Wire.ack(requestID: requestID), on: socket)
    }

    private func send(_ frame: Data, on socket: URLSessionWebSocketTask) {
        socket.send(.data(frame)) { _ in
            // A failed send means a closed socket, and the receive loop deals with that.
        }
    }

    private func makeRequestID() -> String {
        nextRequestID += 1
        return String(nextRequestID)
    }

    private func expireCall(_ id: String) {
        calls.removeValue(forKey: id)?.resume(throwing: T3Error.timedOut)
    }

    private func failCalls(_ error: Error) {
        let waiting = calls.values
        calls = [:]
        for call in waiting { call.resume(throwing: error) }
    }
}
