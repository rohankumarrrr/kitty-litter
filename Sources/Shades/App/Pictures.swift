import Foundation
import ShadesContext
import ShadesCore

enum PictureSource: Hashable {
    case sent(attachmentID: String)
    case workspace(threadID: String, path: String)
    case web(URL)

    private static let pictureTypes: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp"]

    init?(_ url: URL, inThread threadID: String) {
        if Markup.opens(url) {
            self = .web(url)
            return
        }
        guard url.scheme == nil || url.scheme?.lowercased() == "file", !threadID.isEmpty else { return nil }
        let path = url.path
        guard Self.pictureTypes.contains(URL(fileURLWithPath: path).pathExtension.lowercased()),
              !path.split(separator: "/").contains("..")
        else { return nil }
        self = .workspace(threadID: threadID, path: path)
    }

    var webAddress: URL? {
        if case .web(let url) = self { return url }
        return nil
    }
}

@MainActor
final class PictureShelf {
    nonisolated static let side: CGFloat = 480
    private static let kept = 300

    var onChange: (() -> Void)?
    private let fetch: (PictureSource) async -> Data?
    private var copies: [PictureSource: Data] = [:]
    private var order: [PictureSource] = []
    private var fetching: Set<PictureSource> = []
    private var failed: Set<PictureSource> = []
    private var inUse: Set<PictureSource> = []
    private var shown: Set<URL> = []

    init(fetch: @escaping (PictureSource) async -> Data?) {
        self.fetch = fetch
    }

    convenience init(backend: AgentBackend, web: @escaping @Sendable (URL) async -> Data? = { await WebPicture.fetch($0) }) {
        self.init { source in
            let data: Data?
            switch source {
            case .sent(let id): data = await backend.picture(attachmentID: id)
            case .workspace(let threadID, let path): data = await backend.picture(threadID: threadID, path: path)
            case .web(let url): data = await web(url)
            }
            guard let data else { return nil }
            return await Task.detached { Drop.thumbnail(of: data, side: PictureShelf.side) }.value
        }
    }

    func show(_ url: URL) {
        shown.insert(url)
        failed.remove(.web(url))
        want(.web(url))
    }

    func fill(_ book: inout ChannelBook) {
        var used: Set<PictureSource> = []
        book.eachMessage { message in
            used.formUnion(message.files.compactMap(\.source))
            guard message.files.contains(where: { $0.thumbnail == nil && $0.source != nil }) else { return }
            message.files = message.files.compactMap { file in
                guard file.thumbnail == nil, let source = file.source else { return file }
                var file = file
                if let copy = copies[source] {
                    file.thumbnail = copy
                } else if failed.contains(source) {
                    guard source.webAddress != nil else { return message.kind == .reply ? nil : file }
                    file.couldntShow = true
                } else if source.webAddress.map({ shown.contains($0) }) ?? true {
                    want(source)
                }
                return file
            }
        }
        inUse = used
        trim()
    }

    private func trim() {
        var index = 0
        while copies.count > Self.kept, index < order.count {
            if inUse.contains(order[index]) {
                index += 1
            } else {
                copies[order.remove(at: index)] = nil
            }
        }
    }

    private func want(_ source: PictureSource) {
        guard copies[source] == nil, !failed.contains(source), fetching.insert(source).inserted else { return }
        Task {
            let copy = await fetch(source)
            fetching.remove(source)
            if let copy {
                copies[source] = copy
                order.append(source)
                trim()
            } else {
                failed.insert(source)
            }
            onChange?()
        }
    }
}

enum WebPicture {
    static let biggest = 10 * 1024 * 1024
    static let redirectsFollowed = 5

    static func fetch(_ url: URL) async -> Data? {
        await fetch(
            url,
            resolve: { host in await Task.detached { addresses(of: host) }.value },
            get: { await PinnedHTTP.get($0, biggest: biggest) }
        )
    }

    static func fetch(
        _ url: URL,
        redirectsLeft: Int = redirectsFollowed,
        resolve: (String) async -> [[UInt8]]?,
        get: (PictureRequest) async -> PictureResponse?
    ) async -> Data? {
        guard let address = await checkedAddress(of: url, resolve: resolve),
              let response = await get(PictureRequest(url: url, address: address))
        else { return nil }
        if [301, 302, 303, 307, 308].contains(response.status) {
            guard redirectsLeft > 0, let location = response.headers["location"],
                  let next = URL(string: location, relativeTo: url)?.absoluteURL
            else { return nil }
            return await fetch(next, redirectsLeft: redirectsLeft - 1, resolve: resolve, get: get)
        }
        guard (200..<300).contains(response.status),
              let type = response.mediaType, type.hasPrefix("image/"), type != "image/svg+xml",
              response.body.count <= biggest
        else { return nil }
        return response.body
    }

    static func checkedAddress(of url: URL, resolve: (String) async -> [[UInt8]]?) async -> [UInt8]? {
        guard isPublic(url), let host = url.host, let addresses = await resolve(host), let first = addresses.first,
              addresses.allSatisfy(isPublic(address:))
        else { return nil }
        return first
    }

    static func isPublic(_ url: URL) -> Bool {
        guard Markup.opens(url), let host = url.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[].")) else { return false }
        if host == "localhost" || [".localhost", ".local", ".internal", ".home.arpa", ".ts.net", ".lan"].contains(where: host.hasSuffix) { return false }
        if !host.contains(".") { return false }
        let parts = host.split(separator: ".").compactMap { UInt8($0) }
        if parts.count == 4 { return isPublic(v4: parts) }
        return !host.contains(":") && host.rangeOfCharacter(from: CharacterSet.letters) != nil
    }

    private static func isPublic(v4 parts: [UInt8]) -> Bool {
        switch (parts[0], parts[1]) {
        case (0, _), (10, _), (127, _), (169, 254), (192, 168): return false
        case (172, 16...31), (100, 64...127), (224...255, _): return false
        default: return true
        }
    }

    static func isPublic(address: [UInt8]) -> Bool {
        if address.count == 4 { return isPublic(v4: address) }
        guard address.count == 16 else { return false }
        if address.allSatisfy({ $0 == 0 }) || address == Array(repeating: 0, count: 15) + [1] { return false }
        if address[0] == 0xfe && address[1] & 0xc0 == 0x80 { return false }
        if address[0] & 0xfe == 0xfc || address[0] == 0xff { return false }
        if address[0..<10].allSatisfy({ $0 == 0 }) { return address[10] == 0xff && address[11] == 0xff && isPublic(v4: Array(address[12...])) }
        return true
    }

    private static func addresses(of host: String) -> [[UInt8]]? {
        var hints = addrinfo()
        hints.ai_socktype = SOCK_STREAM
        var found: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &found) == 0, let found else { return nil }
        defer { freeaddrinfo(found) }
        var addresses: [[UInt8]] = []
        for entry in sequence(first: found, next: { $0.pointee.ai_next }) {
            guard let address = entry.pointee.ai_addr else { continue }
            switch Int32(address.pointee.sa_family) {
            case AF_INET:
                address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { addresses.append(withUnsafeBytes(of: $0.pointee.sin_addr) { Array($0) }) }
            case AF_INET6:
                address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { addresses.append(withUnsafeBytes(of: $0.pointee.sin6_addr) { Array($0) }) }
            default:
                addresses.append([])
            }
        }
        return addresses
    }
}
