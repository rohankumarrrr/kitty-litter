import AppKit
import ShadesContext
import ShadesCore

@MainActor
final class PhoneLink {
    static let port: UInt16 = 4797

    private final class Watcher {
        let stream: PhoneStream
        let page: String?
        var key: String
        var shown: PhoneView?
        var opening: Bool
        var newFrom: [String: String] = [:]

        init(stream: PhoneStream, page: String?, key: String) {
            self.stream = stream
            self.page = page
            self.key = key
            opening = PhonePlace.thread(in: key) != nil
        }
    }

    let door: PhoneDoor
    let pushes: PhonePushes
    var onPaired: (() -> Void)?
    var textSize = TextSize.standard
    var t3: String?
    var readPriorities: ([Kitten]) -> Priorities = { _ in Priorities() }
    var takesFiles: (MessageTarget) -> Bool = { $0.takesFiles }
    private var priorities = Priorities()
    private var prioritiesRead: Date?
    private let server = PhoneServer()
    private let hold: () -> ChannelBook?
    private let release: () -> Void
    private let act: (MessagesAction) -> Void
    private let now: () -> Date
    private let grace: TimeInterval
    private var watchers: [Watcher] = []
    private var book: ChannelBook?
    private var letting: Task<Void, Never>?
    private var files: [String: (file: Drop, at: Date)] = [:]
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

    var isHolding: Bool { book != nil }


    func publish(_ book: ChannelBook) {
        guard self.book != nil else { return }
        self.book = book
        plainWords.readAhead(book)
        watchers.forEach { show(book, to: $0) }
    }

    private func show(_ book: ChannelBook, to watcher: Watcher) {
        let place = PhonePlace(watcher.key, in: book)
        watcher.newFrom.merge(book.newFrom) { _, now in now }
        let view = PhoneView(place, in: book, now: now(), newFrom: watcher.newFrom, t3: t3, priorities: priorities(for: book), takesFiles: takesFiles)
        if place.selection?.thread != nil { watcher.opening = false }
        if !watcher.opening { watcher.key = view.key }
        guard view != watcher.shown else { return }
        let parts = view.since(watcher.shown).parts()
        guard !parts.isEmpty else { return }
        watcher.shown = view
        watcher.stream.send(parts)
    }

    private func priorities(for book: ChannelBook) -> Priorities {
        if prioritiesRead.map({ now().timeIntervalSince($0) >= 60 }) ?? true {
            priorities = readPriorities(book.statuses.map(\.kitten).filter { !$0.planned })
            prioritiesRead = now()
        }
        return priorities
    }

    func respond(to request: PhoneServer.Request) -> PhoneServer.Response {
        switch (request.method, request.path) {
        case ("GET", "/"):
            return .full(status: 200, type: "text/html; charset=utf-8", body: Data(PhonePage.html.utf8))
        case ("GET", "/app.js"):
            return .full(status: 200, type: "text/javascript; charset=utf-8", body: Data(PhonePage.script.utf8))
        case ("GET", "/app.css"):
            return .full(status: 200, type: "text/css; charset=utf-8", body: Data((PhonePage.style + PhonePage.colors + PhonePage.size(textSize)).utf8))
        case ("GET", "/manifest.json"):
            return .full(status: 200, type: "application/manifest+json", body: Data(PhonePage.manifest.utf8))
        case ("GET", "/sw.js"):
            return .full(status: 200, type: "text/javascript; charset=utf-8", body: Data(PhonePage.worker.utf8))
        case ("GET", "/icon.png"):
            return .full(status: 200, type: "image/png", body: Self.icon)
        // Outside the repo: a browser's image request can't carry the key's header.
        case ("GET", let path) where path.hasPrefix("/cat/"):
            return cat(at: path)
        case ("GET", "/hello"):
            return door.admits(request) ? .status(204) : .status(401)
        case ("POST", "/pair"):
            return pair(request)
        case ("GET", "/events"):
            return door.admits(request) ? watch(request.query["key"] ?? PhonePlace.home, page: request.query["page"]) : .status(401)
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

    // Outside the repo: another site's page can't send this header or a JSON body without a CORS preflight, which this server never allows.
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

    private func watch(_ key: String, page: String?) -> PhoneServer.Response {
        if let page { watchers.filter { $0.page == page }.forEach { $0.stream.close() } }
        let stream = PhoneStream()
        let watcher = Watcher(stream: stream, page: page, key: key)
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

    private func forget() {
        guard book != nil else { return }
        book = nil
        plainWords = PlainWords()
        priorities = Priorities()
        prioritiesRead = nil
        release()
    }

    private func subscribe(_ request: PhoneServer.Request) -> PhoneServer.Response {
        guard Self.isFromPage(request), let subscription = try? JSONDecoder().decode(WebPush.Subscription.self, from: request.body) else { return .status(400) }
        return pushes.subscribe(subscription) ? .status(204) : .status(400)
    }

    private func cat(at path: String) -> PhoneServer.Response {
        guard let drawn = PhoneCat.png(at: path) else { return .status(404) }
        return .full(status: 200, type: "image/png", body: drawn)
    }

    static let icon = AppIcon.phone

    private struct Opened: Encodable {
        var open: String?
    }

    private func perform(_ request: PhoneServer.Request) -> PhoneServer.Response {
        guard Self.isFromPage(request), let ask = try? JSONDecoder().decode(PhoneAsk.self, from: request.body) else { return .status(400) }
        if ask.act == "unattach" {
            if let id = ask.id { files[id] = nil }
            return .status(204)
        }
        guard let book else { return .status(503) }
        guard let (action, opens) = ask.action(in: book, newTopic: { "sent-\(UUID().uuidString)" }, file: { [files] in files[$0]?.file }) else { return .status(409) }
        for id in ask.files ?? [] { files[id] = nil }
        act(action)
        return .json(Opened(open: opens))
    }

    private struct Search: Decodable {
        var words: String
    }

    private func search(_ request: PhoneServer.Request) -> PhoneServer.Response {
        guard Self.isFromPage(request), let search = try? JSONDecoder().decode(Search.self, from: request.body) else { return .status(400) }
        guard let book else { return .status(503) }
        return .json(PhoneFound(search.words, in: book, now: now(), reading: plainWords))
    }

    private struct Kept: Encodable {
        var id: String
    }

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
