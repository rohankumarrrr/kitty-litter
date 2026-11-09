import AppKit
import ShadesContext
import ShadesCore

/// Messages on your phone: the page, a stream of what one place in Messages shows, and what you do there, which goes
/// through the same `messagesAction` as the window. Only a paired phone gets past the page itself.
@MainActor
final class PhoneLink {
    /// Where the page is on your tailnet, beside T3's own. On loopback it's a free port, whichever Shades has this time.
    static let port: UInt16 = 4797

    private final class Watcher {
        let stream: PhoneStream
        var key: String
        var shown: PhoneView?
        /// A notification can open a thread Messages hasn't read yet, so a stream asks for the thread it opened with
        /// until it shows.
        var opening: Bool
        /// Where each thread's New line was when this page opened, so it stays put once it's all been seen.
        var newFrom: [String: String] = [:]

        init(stream: PhoneStream, key: String) {
            self.stream = stream
            self.key = key
            opening = PhonePlace.thread(in: key) != nil
        }
    }

    let door: PhoneDoor
    let pushes: PhonePushes
    var onPaired: (() -> Void)?
    /// Messages' colours, which the page takes the next time it opens.
    var theme: ColorTheme?
    private let server = PhoneServer()
    /// Holds Messages open, and returns what it shows.
    private let hold: () -> ChannelBook?
    /// Lets it go once nobody's looking.
    private let release: () -> Void
    private let act: (MessagesAction) -> Void
    private let now: () -> Date
    /// How long Messages stays open after the last phone stops looking. Each place on the page is a stream of its
    /// own, so moving from one to the next would otherwise close it in between, and forget what you'd just sent.
    private let grace: TimeInterval
    private var watchers: [Watcher] = []
    private var book: ChannelBook?
    private var letting: Task<Void, Never>?
    /// Photos and files a phone sent ahead of its message, by the ID it was given, in memory only and briefly.
    private var files: [String: (file: Drop, at: Date)] = [:]
    /// What Search has read of messages' words, while a phone is looking.
    private var plainWords = PlainWords()
    private static let filesKept = Drop.mostAtOnce
    private static let fileMinutes: TimeInterval = 10

    init(
        keys: PhoneKeyStoring,
        grace: TimeInterval,
        hold: @escaping () -> ChannelBook?,
        release: @escaping () -> Void,
        act: @escaping (MessagesAction) -> Void,
        sendPush: @escaping (URLRequest) async -> Int?,
        now: @escaping () -> Date
    ) {
        door = PhoneDoor(keys: keys)
        pushes = PhonePushes(keys: keys, send: sendPush)
        self.grace = grace
        self.hold = hold
        self.release = release
        self.act = act
        self.now = now
        server.respond = { [weak self] in self?.respond(to: $0) ?? .status(404) }
    }

    /// Returns the port it's listening on.
    func start(port: UInt16) async throws -> UInt16 {
        try await server.start(port: port)
    }

    func stop() {
        files = [:]
        server.stop()
        watchers.forEach { $0.stream.close() }
        letting?.cancel()
        forget()
    }

    var isWatched: Bool { !watchers.isEmpty }

    /// Whether a phone is holding Messages open, because it's looking or has only just stopped.
    var isHolding: Bool { book != nil }


    /// Messages changed, so each phone gets what its place shows now, if that's different.
    func publish(_ book: ChannelBook) {
        guard self.book != nil else { return }
        self.book = book
        plainWords.readAhead(book)
        watchers.forEach { show(book, to: $0) }
    }

    private func show(_ book: ChannelBook, to watcher: Watcher) {
        let place = PhonePlace(watcher.key, in: book)
        watcher.newFrom.merge(book.newFrom) { _, now in now }
        let view = PhoneView(place, in: book, now: now(), newFrom: watcher.newFrom)
        if place.selection?.thread != nil { watcher.opening = false }
        if !watcher.opening { watcher.key = view.key }
        guard view != watcher.shown, let json = try? JSONEncoder().encode(view) else { return }
        watcher.shown = view
        watcher.stream.send(json)
    }

    func respond(to request: PhoneServer.Request) -> PhoneServer.Response {
        switch (request.method, request.path) {
        case ("GET", "/"):
            return .full(status: 200, type: "text/html; charset=utf-8", body: Data(PhonePage.html.utf8))
        case ("GET", "/app.js"):
            return .full(status: 200, type: "text/javascript; charset=utf-8", body: Data(PhonePage.script.utf8))
        case ("GET", "/app.css"):
            return .full(status: 200, type: "text/css; charset=utf-8", body: Data((PhonePage.style + PhonePage.colors(theme)).utf8))
        // What a phone needs to keep the page on its Home Screen, and to show notifications while it's closed.
        case ("GET", "/manifest.json"):
            return .full(status: 200, type: "application/manifest+json", body: Data(PhonePage.manifest.utf8))
        case ("GET", "/sw.js"):
            return .full(status: 200, type: "text/javascript; charset=utf-8", body: Data(PhonePage.worker.utf8))
        case ("GET", "/icon.png"):
            return .full(status: 200, type: "image/png", body: Self.icon)
        // Like the icon, an image can't carry the key, so these are only ever the art for the colour asked for.
        case ("GET", let path) where path.hasPrefix("/cat/"):
            return cat(at: path)
        case ("GET", "/hello"):
            return door.admits(request) ? .status(204) : .status(401)
        case ("POST", "/pair"):
            return pair(request)
        case ("GET", "/events"):
            return door.admits(request) ? watch(request.query["key"] ?? PhonePlace.home) : .status(401)
        case ("POST", "/act"):
            return door.admits(request) ? perform(request) : .status(401)
        case ("POST", "/file"):
            return door.admits(request) ? keep(request) : .status(401)
        case ("POST", "/search"):
            return door.admits(request) ? search(request) : .status(401)
        case ("GET", "/push"):
            return door.admits(request) ? .json(["key": pushes.publicKey]) : .status(401)
        case ("POST", "/push"):
            return door.admits(request) ? subscribe(request) : .status(401)
        case (_, "/"), (_, "/hello"), (_, "/pair"), (_, "/events"), (_, "/act"), (_, "/file"), (_, "/push"), (_, "/search"):
            return .status(405)
        default:
            return .status(404)
        }
    }

    /// Only the page sends this header, and another site's page can't without asking first, which nothing here allows.
    /// That keeps another site from using up a pairing code by guessing.
    private static func isFromPage(_ request: PhoneServer.Request) -> Bool {
        request.headers["x-shades"] == "1" && request.headers["content-type"]?.hasPrefix("application/json") == true
    }

    private struct Code: Decodable {
        var code: String
    }

    private struct Paired: Encodable {
        var key: String
    }

    private func pair(_ request: PhoneServer.Request) -> PhoneServer.Response {
        guard Self.isFromPage(request), let code = try? JSONDecoder().decode(Code.self, from: request.body) else { return .status(400) }
        guard let key = door.pair(code.code, now: now()) else { return .status(403) }
        onPaired?()
        return .json(Paired(key: key))
    }

    private func watch(_ key: String) -> PhoneServer.Response {
        let stream = PhoneStream()
        let watcher = Watcher(stream: stream, key: key)
        letting?.cancel()
        letting = nil
        book = hold()
        if let book { plainWords.readAhead(book) }
        watchers.append(watcher)
        stream.onClose = { [weak self, weak watcher] in
            guard let self else { return }
            self.watchers.removeAll { $0 === watcher }
            guard self.watchers.isEmpty else { return }
            self.letting = Task { [weak self, grace] in
                try? await Task.sleep(nanoseconds: UInt64(grace * 1_000_000_000))
                guard !Task.isCancelled, let self, self.watchers.isEmpty else { return }
                self.forget()
            }
        }
        if let book { show(book, to: watcher) }
        return .stream(stream)
    }

    /// As when the window closes, nothing that was said is kept once nobody's looking.
    private func forget() {
        guard book != nil else { return }
        book = nil
        plainWords = PlainWords()
        release()
    }

    private func subscribe(_ request: PhoneServer.Request) -> PhoneServer.Response {
        guard Self.isFromPage(request), let subscription = try? JSONDecoder().decode(WebPush.Subscription.self, from: request.body) else { return .status(400) }
        return pushes.subscribe(subscription) ? .status(204) : .status(400)
    }

    /// Drawn fresh every time and kept nowhere. Anyone who can reach the page can ask for any colour, so a cache would
    /// grow with what strangers ask for, and answer faster for the cats a phone just loaded, which would give them away.
    private func cat(at path: String) -> PhoneServer.Response {
        guard let drawn = PhoneCat.png(at: path) else { return .status(404) }
        return .full(status: 200, type: "image/png", body: drawn)
    }

    /// The app's own icon, at the size a Home Screen wants.
    private static let icon: Data = {
        let side = 180
        let image = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return Data() }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:]) ?? Data()
    }()

    private struct Opened: Encodable {
        var open: String?
    }

    private func perform(_ request: PhoneServer.Request) -> PhoneServer.Response {
        guard Self.isFromPage(request), let ask = try? JSONDecoder().decode(PhoneAsk.self, from: request.body) else { return .status(400) }
        // A photo or file taken off before sending goes now, so it can't push out one still attached.
        if ask.act == "unattach" {
            if let id = ask.id { files[id] = nil }
            return .status(204)
        }
        // Messages is only open while a phone is looking, and what's done is checked against what it shows.
        guard let book, let (action, opens) = ask.action(in: book, newTopic: { "sent-\(UUID().uuidString)" }, file: { [files] in files[$0]?.file }) else { return .status(409) }
        for id in ask.files ?? [] { files[id] = nil }
        act(action)
        return .json(Opened(open: opens))
    }

    private struct Search: Decodable {
        var words: String
    }

    /// Search over what Messages has read, kept to what a phone can open. As with `/act`, Messages is only open while
    /// a phone is looking, and nothing it was asked or found is kept.
    private func search(_ request: PhoneServer.Request) -> PhoneServer.Response {
        guard Self.isFromPage(request), let search = try? JSONDecoder().decode(Search.self, from: request.body) else { return .status(400) }
        guard let book else { return .status(409) }
        return .json(PhoneFound(search.words, in: book, now: now(), reading: plainWords))
    }

    private struct Kept: Encodable {
        var id: String
    }

    /// A photo or file, sent ahead so the message itself stays small. Only the page sends the header, as with `/act`.
    private func keep(_ request: PhoneServer.Request) -> PhoneServer.Response {
        guard request.headers["x-shades"] == "1", !request.body.isEmpty else { return .status(400) }
        let named = request.headers["x-name"]?.removingPercentEncoding?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = named.isEmpty ? CatWords.aFile : String(named.prefix(120))
        files = files.filter { now().timeIntervalSince($0.value.at) < Self.fileMinutes * 60 }
        while files.count >= Self.filesKept, let oldest = files.min(by: { $0.value.at < $1.value.at })?.key { files[oldest] = nil }
        let id = UUID().uuidString
        files[id] = (.bytes(request.body, name: name), now())
        return .json(Kept(id: id))
    }
}
