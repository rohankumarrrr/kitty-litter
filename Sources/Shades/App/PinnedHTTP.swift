import Foundation
import Network

struct PictureRequest: Equatable {
    let url: URL
    let address: [UInt8]
}

struct PictureResponse: Equatable {
    let status: Int
    let headers: [String: String]
    let body: Data

    init(status: Int, headers: [String: String], body: Data) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    init?(parsing raw: Data) {
        guard let end = raw.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        var lines = String(decoding: raw[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let statusLine = lines.removeFirst().split(separator: " ", maxSplits: 2)
        guard statusLine.count >= 2, statusLine[0].hasPrefix("HTTP/1."), let status = Int(statusLine[1]) else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if let earlier = headers[name], earlier != value, name == "content-length" || name == "transfer-encoding" { return nil }
            headers[name] = headers[name] ?? value
        }
        var body = Data(raw[end.upperBound...])
        if let encoding = headers["transfer-encoding"] {
            guard encoding.lowercased() == "chunked", let whole = Self.joined(chunks: body) else { return nil }
            body = whole
        } else if let length = headers["content-length"] {
            guard let count = Int(length), count >= 0, body.count >= count else { return nil }
            body = body.prefix(count)
        }
        self.init(status: status, headers: headers, body: body)
    }

    var mediaType: String? {
        headers["content-type"]?.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
    }

    private static func joined(chunks: Data) -> Data? {
        var whole = Data()
        var rest = chunks[...]
        while true {
            guard let lineEnd = rest.range(of: Data("\r\n".utf8)) else { return nil }
            let sizeText = String(decoding: rest[..<lineEnd.lowerBound], as: UTF8.self).split(separator: ";").first ?? ""
            guard let size = Int(sizeText.trimmingCharacters(in: .whitespaces), radix: 16), size >= 0 else { return nil }
            rest = rest[lineEnd.upperBound...]
            if size == 0 { return whole }
            guard rest.count >= size + 2, rest.dropFirst(size).prefix(2) == Data("\r\n".utf8) else { return nil }
            whole.append(rest.prefix(size))
            rest = rest.dropFirst(size + 2)
        }
    }
}

enum PinnedHTTP {
    static let headroom = 64 * 1024

    static func get(_ request: PictureRequest, biggest: Int, timeout: TimeInterval = 60) async -> PictureResponse? {
        guard let host = request.url.host, let message = message(for: request.url) else { return nil }
        let secure = request.url.scheme?.lowercased() == "https"
        guard let port = NWEndpoint.Port(rawValue: UInt16(request.url.port ?? (secure ? 443 : 80))),
              let address = endpoint(request.address)
        else { return nil }
        let parameters: NWParameters
        if secure {
            let tls = NWProtocolTLS.Options()
            sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, host)
            sec_protocol_options_add_tls_application_protocol(tls.securityProtocolOptions, "http/1.1")
            parameters = NWParameters(tls: tls)
        } else {
            parameters = .tcp
        }
        let connection = NWConnection(host: address, port: port, using: parameters)
        let exchange = Exchange(connection: connection, message: message, limit: biggest + headroom)
        return await exchange.run(timeout: timeout)
    }

    static func message(for url: URL) -> Data? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: true), let host = parts.host else { return nil }
        let path = parts.percentEncodedPath.isEmpty ? "/" : parts.percentEncodedPath
        let target = path + (parts.percentEncodedQuery.map { "?" + $0 } ?? "")
        let hostField = host + (parts.port.map { ":\($0)" } ?? "")
        guard !(target + hostField).contains(where: { $0.isNewline || $0 == " " }) else { return nil }
        return Data("""
        GET \(target) HTTP/1.1\r
        Host: \(hostField)\r
        User-Agent: Shades\r
        Accept: image/*\r
        Accept-Encoding: identity\r
        Connection: close\r
        \r

        """.utf8)
    }

    static func endpoint(_ address: [UInt8]) -> NWEndpoint.Host? {
        switch address.count {
        case 4: return IPv4Address(Data(address)).map(NWEndpoint.Host.ipv4)
        case 16: return IPv6Address(Data(address)).map(NWEndpoint.Host.ipv6)
        default: return nil
        }
    }

    private final class Exchange: @unchecked Sendable {
        private let connection: NWConnection
        private let message: Data
        private let limit: Int
        private let queue = DispatchQueue(label: "Shades.PinnedHTTP")
        private var received = Data()
        private var finish: ((PictureResponse?) -> Void)?

        init(connection: NWConnection, message: Data, limit: Int) {
            self.connection = connection
            self.message = message
            self.limit = limit
        }

        func run(timeout: TimeInterval) async -> PictureResponse? {
            await withCheckedContinuation { continuation in
                queue.async {
                    self.finish = { continuation.resume(returning: $0) }
                    self.connection.stateUpdateHandler = { [weak self] state in
                        switch state {
                        case .ready: self?.send()
                        case .failed, .cancelled, .waiting: self?.end(nil)
                        default: break
                        }
                    }
                    self.connection.start(queue: self.queue)
                    self.queue.asyncAfter(deadline: .now() + timeout) { [weak self] in self?.end(nil) }
                }
            }
        }

        private func send() {
            connection.send(content: message, completion: .contentProcessed { [weak self] error in
                if error != nil { self?.end(nil) } else { self?.receive() }
            })
        }

        private func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
                guard let self else { return }
                if let data { self.received.append(data) }
                if self.received.count > self.limit { return self.end(nil) }
                if isComplete || error != nil { return self.end(PictureResponse(parsing: self.received)) }
                self.receive()
            }
        }

        private func end(_ response: PictureResponse?) {
            guard let finish else { return }
            self.finish = nil
            connection.stateUpdateHandler = nil
            connection.cancel()
            finish(response)
        }
    }
}
