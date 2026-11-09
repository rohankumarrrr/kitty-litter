import Foundation
import ShadesContext
import ShadesCore

/// Where a picture on a message comes from. A reply is untrusted, so the only paths it can name are in the folder its
/// own thread works in, which T3 keeps them to, and a web address it names waits until you've seen it and pressed Show.
enum PictureSource: Hashable {
    /// A picture you sent, by T3's ID for the copy it keeps.
    case sent(attachmentID: String)
    /// A picture in the folder a thread works in, by its path there.
    case workspace(threadID: String, path: String)
    /// A picture on the web.
    case web(URL)

    private static let pictureTypes: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp"]

    /// What a reply's markdown points at, or `nil` for anything that isn't a picture in its thread's folder or on the web.
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

/// Small copies of the pictures on messages, fetched once and kept in memory only, never on disk, like the rest of
/// what Messages has read. What you sent and what a thread's folder holds come from T3. A web picture is fetched by
/// the Mac only once you've pressed Show on it, so a reply can't make Shades load an address you haven't seen.
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
    /// What the book last showed, which is never let go of, however many there are.
    private var inUse: Set<PictureSource> = []
    /// Web pictures you've pressed Show on.
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

    /// Fetches a web picture you pressed Show on, even one that didn't come last time.
    func show(_ url: URL) {
        shown.insert(url)
        failed.remove(.web(url))
        want(.web(url))
    }

    /// Puts each small copy there is on the book's messages, and fetches the rest. A reply's picture that couldn't be
    /// had comes off, since its description is still in its words.
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

    /// Lets go of the oldest copies past what it keeps, but never one still showing, or it would only fetch it again.
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

/// A picture on the web, fetched the way a picture should be and nothing more: from a public http or https address,
/// with no cookies, no cache and nothing saved, up to 10 MB, and only if it says it's a picture. Addresses on your
/// Mac, your network or your tailnet are refused, here and after a redirect, so a reply can't use Shades to reach them.
enum WebPicture {
    static let biggest = 10 * 1024 * 1024
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration, delegate: Redirects(), delegateQueue: nil)
    }()

    static func fetch(_ url: URL) async -> Data? {
        guard await reachesOnlyTheWeb(url) else { return nil }
        guard let (bytes, response) = try? await session.bytes(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let url = http.url, isPublic(url),
              let type = http.mimeType?.lowercased(), type.hasPrefix("image/"), type != "image/svg+xml",
              http.expectedContentLength <= biggest
        else { return nil }
        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count > biggest { return nil }
            }
        } catch {
            return nil
        }
        return data
    }

    /// Whether an address is on the open web, by its name or numbers, rather than this Mac, a local network or a tailnet.
    static func isPublic(_ url: URL) -> Bool {
        guard Markup.opens(url), let host = url.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[].")) else { return false }
        if host == "localhost" || [".localhost", ".local", ".internal", ".home.arpa", ".ts.net", ".lan"].contains(where: host.hasSuffix) { return false }
        if !host.contains(".") { return false }
        let parts = host.split(separator: ".").compactMap { UInt8($0) }
        if parts.count == 4 { return isPublic(v4: parts) }
        // Any address written in IPv6 numbers is refused, since a name is how a picture on the web is reached.
        return !host.contains(":") && host.rangeOfCharacter(from: CharacterSet.letters) != nil
    }

    /// The same, for every address its name leads to as well, since a name anyone can register can lead to this Mac.
    /// shortcut: the lookup happens again when it's fetched, so a name that changes in between still gets through,
    /// which only matters once you've seen the address and pressed Show.
    static func reachesOnlyTheWeb(_ url: URL) async -> Bool {
        guard isPublic(url), let host = url.host else { return false }
        return await Task.detached { addresses(of: host).map { !$0.isEmpty && $0.allSatisfy(isPublic(address:)) } ?? false }.value
    }

    private static func isPublic(v4 parts: [UInt8]) -> Bool {
        switch (parts[0], parts[1]) {
        case (0, _), (10, _), (127, _), (169, 254), (192, 168): return false
        case (172, 16...31), (100, 64...127), (224...255, _): return false
        default: return true
        }
    }

    /// An IPv6 address is public unless it's this Mac, unset, local to a link or a network, or an IPv4 one inside.
    static func isPublic(address: [UInt8]) -> Bool {
        if address.count == 4 { return isPublic(v4: address) }
        guard address.count == 16 else { return false }
        if address.allSatisfy({ $0 == 0 }) || address == Array(repeating: 0, count: 15) + [1] { return false }
        if address[0] == 0xfe && address[1] & 0xc0 == 0x80 { return false }
        if address[0] & 0xfe == 0xfc || address[0] == 0xff { return false }
        if address[0..<10].allSatisfy({ $0 == 0 }) { return address[10] == 0xff && address[11] == 0xff && isPublic(v4: Array(address[12...])) }
        return true
    }

    /// Every address a name leads to, or `nil` if it leads nowhere.
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

    private final class Redirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
            guard let url = request.url else { return nil }
            return await WebPicture.reachesOnlyTheWeb(url) ? request : nil
        }
    }
}
