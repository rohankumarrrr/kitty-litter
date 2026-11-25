import Foundation
import Network

@MainActor
final class PhoneServer {
    struct Request {
        var method: String
        var path: String
        var query: [String: String]
        var headers: [String: String]
        var body: Data

        var takesGzip: Bool {
            headers["accept-encoding"]?.split(separator: ",").contains { coding in
                let parts = coding.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                return parts.first == "gzip" && !parts.dropFirst().contains { $0.hasPrefix("q=") && Double($0.dropFirst(2)) == 0 }
            } == true
        }
    }

    enum Response {
        case full(status: Int, type: String, body: Data)
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
    static let biggestFile = 12 * 1024 * 1024
    private static let fileRequest = Data("POST /file ".utf8)
    private static let mostConnections = 32
    private static let requestSeconds: TimeInterval = 10
    private static let fileSeconds: TimeInterval = 90

    var respond: (Request) -> Response = { _ in .status(404) }
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var streaming: Set<ObjectIdentifier> = []
    private var sendingFiles: Set<ObjectIdentifier> = []
    private var starting: CheckedContinuation<UInt16, Error>?

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
            stream.attach(connection, gzip: request.takesGzip)
        case let response:
            send(response, on: connection, gzip: request.takesGzip)
        }
    }

    private func send(_ response: Response, on connection: NWConnection, gzip: Bool = false) {
        guard case .full(let status, let type, var body) = response else { return }
        var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\n"
        if gzip, body.count > 1024, type.hasPrefix("text/") {
            body = Gzip.whole(body)
            head += "Content-Encoding: gzip\r\n"
        }
        head += "Content-Type: \(type)\r\nContent-Length: \(body.count)\r\n"
        head += Self.commonHeaders + "Connection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }

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
        case 503: return "Service Unavailable"
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

@MainActor
final class PhoneStream {
    private static let pingSeconds: UInt64 = 10

    var onClose: (() -> Void)?
    private var connection: NWConnection?
    private var gzip: Gzip?
    private var waiting: [[Data]] = []
    private var isClosed = false
    private var pings: Task<Void, Never>?
    private var nudge: Task<Void, Never>?

    fileprivate func attach(_ connection: NWConnection, gzip: Bool) {
        guard !isClosed else { return connection.cancel() }
        self.connection = connection
        self.gzip = gzip ? Gzip() : nil
        let packed = gzip ? "Content-Encoding: gzip\r\n" : ""
        let head = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n\(packed)Transfer-Encoding: chunked\r\n" + PhoneServer.commonHeaders + "\r\n"
        connection.send(content: Data(head.utf8), completion: .idempotent)
        waiting.forEach(write)
        waiting = []
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] _, _, _, _ in
            MainActor.assumeIsolated { self?.close() }
        }
        pings = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.pingSeconds * 1_000_000_000)
                self?.ping()
            }
        }
    }

    func send(_ parts: [Data]) {
        guard !isClosed, !parts.isEmpty else { return }
        var event = parts
        event[0] = Data("data: ".utf8) + event[0]
        event[event.count - 1] += Data("\n\n".utf8)
        if connection == nil { waiting.append(event) } else { write(event) }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        pings?.cancel()
        nudge?.cancel()
        let last = gzip.map { Self.chunk($0.finished()) } ?? Data()
        connection?.send(content: last + Data("0\r\n\r\n".utf8), completion: .contentProcessed { [connection] _ in connection?.cancel() })
        onClose?()
        onClose = nil
    }

    private func write(_ parts: [Data]) {
        write(gzip.map { $0.packed(parts) } ?? parts.reduce(Data(), +))
        // Outside the repo: WebKit can hold back the end of a long gzipped event until more of the stream comes.
        guard gzip != nil else { return }
        nudge?.cancel()
        nudge = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.ping()
        }
    }

    private func ping() {
        let ping = Data(": ping\n\n".utf8)
        write(gzip.map { $0.flushed(ping) } ?? ping)
    }

    private func write(_ bytes: Data) {
        guard let connection, !isClosed else { return }
        let chunk = Self.chunk(bytes)
        connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
            guard error != nil else { return }
            MainActor.assumeIsolated { self?.close() }
        })
    }

    private static func chunk(_ data: Data) -> Data {
        Data("\(String(data.count, radix: 16))\r\n".utf8) + data + Data("\r\n".utf8)
    }
}
