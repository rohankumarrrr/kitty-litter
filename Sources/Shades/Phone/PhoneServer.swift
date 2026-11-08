import Foundation
import Network

/// A small HTTP server on 127.0.0.1, for Messages on your phone. Tailscale Serve is what puts it on your tailnet, with
/// a real certificate. Each request gets one answer and the connection closes, except a stream of events, which stays
/// open. It all runs on the main queue, since one phone makes very little traffic.
@MainActor
final class PhoneServer {
    struct Request {
        var method: String
        var path: String
        var query: [String: String]
        /// By lowercased name.
        var headers: [String: String]
        var body: Data
    }

    enum Response {
        case full(status: Int, type: String, body: Data)
        /// Stays open, and gets each event sent to the stream.
        case stream(PhoneStream)

        static func status(_ status: Int) -> Response {
            .full(status: status, type: "text/plain; charset=utf-8", body: Data())
        }

        static func json(_ value: some Encodable, status: Int = 200) -> Response {
            .full(status: status, type: "application/json", body: (try? JSONEncoder().encode(value)) ?? Data())
        }
    }

    private enum Parsed {
        case incomplete
        case bad
        case request(Request)
    }

    private static let biggestRequest = 64 * 1024
    /// A photo or file a phone sends ahead of its message, which is the only request this big.
    static let biggestFile = 12 * 1024 * 1024
    private static let fileRequest = Data("POST /file ".utf8)
    private static let mostConnections = 32
    /// Long enough for a slow phone, short enough that a half-sent request can't hold a connection.
    private static let requestSeconds: TimeInterval = 10
    /// A file takes longer to send, so its request gets longer.
    private static let fileSeconds: TimeInterval = 90

    var respond: (Request) -> Response = { _ in .status(404) }
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    /// Connections that have become a stream, which the request timeout leaves alone.
    private var streaming: Set<ObjectIdentifier> = []
    /// Connections sending a file, which get `fileSeconds` instead.
    private var sendingFiles: Set<ObjectIdentifier> = []
    private var starting: CheckedContinuation<UInt16, Error>?

    /// Listens on loopback only, and returns the port, which is a free one for 0.
    func start(port: UInt16) async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port) ?? .any)
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.accept(connection) }
        }
        return try await withCheckedThrowingContinuation { continuation in
            starting = continuation
            listener.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated {
                    guard let self, let starting = self.starting else { return }
                    switch state {
                    case .ready:
                        starting.resume(returning: listener.port?.rawValue ?? port)
                    case .failed(let error), .waiting(let error):
                        listener.cancel()
                        starting.resume(throwing: error)
                    case .cancelled:
                        starting.resume(throwing: CancellationError())
                    default:
                        return
                    }
                    self.starting = nil
                }
            }
            listener.start(queue: .main)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.values.forEach { $0.cancel() }
        connections = [:]
    }

    private func accept(_ connection: NWConnection) {
        guard connections.count < Self.mostConnections else { return connection.cancel() }
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                MainActor.assumeIsolated {
                    self?.connections[id] = nil
                    self?.streaming.remove(id)
                    self?.sendingFiles.remove(id)
                }
            default:
                break
            }
        }
        connection.start(queue: .main)
        read(connection, Data())
        giveUp(on: connection, after: Self.requestSeconds) { [weak self] in self?.sendingFiles.contains(id) != true }
    }

    private func giveUp(on connection: NWConnection, after seconds: TimeInterval, unless: @escaping () -> Bool = { true }) {
        let id = ObjectIdentifier(connection)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self, weak connection] in
            MainActor.assumeIsolated {
                guard let self, let connection, self.connections[id] != nil, !self.streaming.contains(id), unless() else { return }
                connection.cancel()
            }
        }
    }

    private func read(_ connection: NWConnection, _ buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                var buffer = buffer
                if let data { buffer.append(data) }
                let isFile = buffer.starts(with: Self.fileRequest)
                if isFile, self.sendingFiles.insert(ObjectIdentifier(connection)).inserted {
                    self.giveUp(on: connection, after: Self.fileSeconds)
                }
                guard buffer.count <= (isFile ? Self.biggestFile : Self.biggestRequest) else { return self.send(.status(413), on: connection) }
                switch Self.parse(buffer) {
                case .request(let request):
                    self.answer(request, on: connection)
                case .bad:
                    self.send(.status(400), on: connection)
                case .incomplete where isComplete || error != nil:
                    connection.cancel()
                case .incomplete:
                    self.read(connection, buffer)
                }
            }
        }
    }

    private func answer(_ request: Request, on connection: NWConnection) {
        switch respond(request) {
        case .stream(let stream):
            streaming.insert(ObjectIdentifier(connection))
            stream.attach(connection)
        case let response:
            send(response, on: connection)
        }
    }

    private func send(_ response: Response, on connection: NWConnection) {
        guard case .full(let status, let type, let body) = response else { return }
        var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\n"
        head += "Content-Type: \(type)\r\nContent-Length: \(body.count)\r\n"
        head += Self.commonHeaders + "Connection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }

    /// Nothing here is to be cached, framed, sniffed or followed back to where it came from.
    static let commonHeaders = """
        Cache-Control: no-store\r
        X-Content-Type-Options: nosniff\r
        Referrer-Policy: no-referrer\r
        X-Frame-Options: DENY\r
        Content-Security-Policy: default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' data:; manifest-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'\r

        """

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 409: return "Conflict"
        case 413: return "Payload Too Large"
        case 429: return "Too Many Requests"
        default: return "Error"
        }
    }

    private static func parse(_ buffer: Data) -> Parsed {
        guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else { return .incomplete }
        let lines = String(decoding: buffer[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let start = lines[0].split(separator: " ")
        guard start.count == 3, start[2].hasPrefix("HTTP/1.") else { return .bad }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return .bad }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        // Only a body of a stated length, which is all the page ever sends.
        guard headers["transfer-encoding"] == nil else { return .bad }
        let length = headers["content-length"].map { Int($0) } ?? 0
        guard let length, length >= 0 else { return .bad }
        let body = buffer[end.upperBound...]
        guard body.count >= length else { return .incomplete }
        guard let target = URLComponents(string: String(start[1])) else { return .bad }
        let query = (target.queryItems ?? []).reduce(into: [String: String]()) { $0[$1.name] = $1.value ?? "" }
        return .request(Request(method: String(start[0]), path: target.path, query: query, headers: headers, body: Data(body.prefix(length))))
    }
}

/// Server-sent events to one phone, for as long as it's looking. What's sent before the connection is ready waits.
@MainActor
final class PhoneStream {
    private static let pingSeconds: UInt64 = 25

    var onClose: (() -> Void)?
    private var connection: NWConnection?
    private var waiting: [Data] = []
    private var isClosed = false
    private var pings: Task<Void, Never>?

    fileprivate func attach(_ connection: NWConnection) {
        guard !isClosed else { return connection.cancel() }
        self.connection = connection
        let head = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\n" + PhoneServer.commonHeaders + "\r\n"
        connection.send(content: Data(head.utf8), completion: .idempotent)
        waiting.forEach(write)
        waiting = []
        // The phone only ever reads from here, so anything at all, or nothing more, means it's gone.
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] _, _, _, _ in
            MainActor.assumeIsolated { self?.close() }
        }
        // Keeps the proxy in between from giving up on a quiet stream, and finds out when the phone's gone.
        pings = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.pingSeconds * 1_000_000_000)
                self?.write(Data(": ping\n\n".utf8))
            }
        }
    }

    /// One event. JSON has no line breaks of its own, so it fits on one `data:` line.
    func send(_ json: Data) {
        guard !isClosed else { return }
        let event = Data("data: ".utf8) + json + Data("\n\n".utf8)
        if connection == nil { waiting.append(event) } else { write(event) }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        pings?.cancel()
        connection?.send(content: Data("0\r\n\r\n".utf8), completion: .contentProcessed { [connection] _ in connection?.cancel() })
        onClose?()
        onClose = nil
    }

    private func write(_ data: Data) {
        guard let connection, !isClosed else { return }
        let chunk = Data("\(String(data.count, radix: 16))\r\n".utf8) + data + Data("\r\n".utf8)
        connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
            guard error != nil else { return }
            MainActor.assumeIsolated { self?.close() }
        })
    }
}
