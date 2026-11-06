@testable import Shades
import ShadesCore
import XCTest

/// The phone page for real: the server on a free loopback port, spoken to over HTTP the way the page does.
@MainActor
final class PhoneServerTests: XCTestCase {
    private var log: Log!
    private var stage: FakeStage!
    private var backend: FakeBackend!
    private var context: FakeContext!
    private var keys: MemoryPhoneKeys!
    private var stoppedServing: [UInt16] = []
    private var controller: AppController!
    private var port: UInt16 = 0
    private let penny = Kitten(name: "Penny", role: "Finance", covers: "their money", folder: "/k/penny")
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        return URLSession(configuration: configuration)
    }()

    override func setUp() async throws {
        log = Log()
        stage = FakeStage(log: log)
        backend = FakeBackend()
        context = FakeContext(log: log)
        keys = MemoryPhoneKeys()
        var settings = Settings()
        settings.phone = true
        controller = AppController(
            dependencies: AppDependencies(
                backend: backend,
                context: context,
                voice: FakeVoice(),
                inserter: FakeInserter(),
                keys: FakeKeys(),
                settings: settings,
                saveSettings: { _ in },
                kittens: { [unowned self] in [self.penny] },
                routerFolder: { "/shades/router" },
                phoneKeys: keys,
                servePhone: { "https://mac.example.ts.net:\($0)" },
                stopServingPhone: { [unowned self] in self.stoppedServing.append($0) }
            ),
            stage: stage
        )
        backend.projects[penny.folder] = "project-penny"
        controller.phoneGrace = 0.5
        controller.startPhone()
        await controller.phoneTask?.value
        await until { stage.pairings.last??.code != nil }
        port = try XCTUnwrap(controller.phoneListening)
    }

    override func tearDown() async throws {
        controller.stopPhone()
    }

    private var base: URL { URL(string: "http://127.0.0.1:\(port)")! }

    private func call(_ method: String, _ path: String, json: String? = nil, cookie: String? = nil, headers: [String: String] = [:]) async throws -> HTTPURLResponse {
        var request = URLRequest(url: URL(string: path, relativeTo: base)!)
        request.httpMethod = method
        if let json {
            request.httpBody = Data(json.utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let cookie { request.setValue("shades_phone=\(cookie)", forHTTPHeaderField: "Cookie") }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let (_, response) = try await session.data(for: request)
        return response as! HTTPURLResponse
    }

    private func page(_ json: String, cookie: String?) async throws -> (status: Int, body: Data) {
        var request = URLRequest(url: URL(string: "/act", relativeTo: base)!)
        request.httpMethod = "POST"
        request.httpBody = Data(json.utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "X-Shades")
        if let cookie { request.setValue("shades_phone=\(cookie)", forHTTPHeaderField: "Cookie") }
        let (body, response) = try await session.data(for: request)
        return ((response as! HTTPURLResponse).statusCode, body)
    }

    private func pair() async throws -> String {
        let code = try XCTUnwrap(stage.pairings.last??.code)
        let paired = try await call("POST", "/pair", json: #"{"code":"\#(code)"}"#, headers: ["X-Shades": "1"])
        XCTAssertEqual(paired.statusCode, 204)
        let cookie = try XCTUnwrap(paired.value(forHTTPHeaderField: "Set-Cookie"))
        return String(cookie.split(separator: ";")[0].dropFirst("shades_phone=".count))
    }

    /// The first view a stream sends, and the task holding the stream open.
    private func watch(_ key: String, cookie: String) async throws -> (view: [String: Any], stream: Task<Void, Never>) {
        var request = URLRequest(url: URL(string: "/events?key=\(key.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)", relativeTo: base)!)
        request.setValue("shades_phone=\(cookie)", forHTTPHeaderField: "Cookie")
        let (bytes, response) = try await session.bytes(for: request)
        XCTAssertEqual((response as! HTTPURLResponse).value(forHTTPHeaderField: "Content-Type"), "text/event-stream")
        var lines = bytes.lines.makeAsyncIterator()
        var first: [String: Any] = [:]
        while let line = try await lines.next() {
            guard line.hasPrefix("data: ") else { continue }
            first = try JSONSerialization.jsonObject(with: Data(line.dropFirst(6).utf8)) as! [String: Any]
            break
        }
        // Holding the iterator keeps the connection open until the task is cancelled.
        let stream = Task { [lines] in
            var lines = lines
            while (try? await lines.next()) != nil {}
            _ = lines
        }
        return (first, stream)
    }

    private func until(_ condition: () -> Bool) async {
        for _ in 0..<2000 where !condition() { try? await Task.sleep(nanoseconds: 2_000_000) }
    }

    func testOnlyAPairedPhoneGetsPastThePage() async throws {
        let page = try await call("GET", "/")
        XCTAssertEqual(page.statusCode, 200, "the page itself holds nothing")
        XCTAssertTrue(page.value(forHTTPHeaderField: "Content-Security-Policy")?.contains("script-src 'self'") == true)
        for path in ["/hello", "/events?key=everyone"] {
            let refused = try await call("GET", path, headers: ["Tailscale-User-Login": "someone@example.com"])
            XCTAssertEqual(refused.statusCode, 401, "\(path): Tailscale's header is easy to fake from this Mac, so it counts for nothing")
        }
        let (status, _) = try await self.page(#"{"act":"send","key":"everyone","text":"ship it"}"#, cookie: "made-up")
        XCTAssertEqual(status, 401)
        XCTAssertEqual(backend.sent.count, 0)

        let unmarked = try await call("POST", "/pair", json: #"{"code":"ABCDEFGH"}"#)
        XCTAssertEqual(unmarked.statusCode, 400, "only the page's own requests, which another site can't make")
        let wrong = try await call("POST", "/pair", json: #"{"code":"ABCDEFGH"}"#, headers: ["X-Shades": "1"])
        XCTAssertEqual(wrong.statusCode, 403)

        let code = try XCTUnwrap(stage.pairings.last??.code)
        XCTAssertEqual(stage.pairings.last??.link, "https://mac.example.ts.net:\(port)/#pair=\(code)")
        let paired = try await call("POST", "/pair", json: #"{"code":"\#(code)"}"#, headers: ["X-Shades": "1"])
        let cookie = try XCTUnwrap(paired.value(forHTTPHeaderField: "Set-Cookie"))
        for part in ["Secure", "HttpOnly", "SameSite=Strict"] { XCTAssertTrue(cookie.contains(part), cookie) }
        XCTAssertEqual(stage.pairings.last, .some(nil), "the code goes away once it's used")
        XCTAssertTrue(stage.bubbles.contains(.line(CatWords.phonePaired, threadID: nil)))
        let token = String(cookie.split(separator: ";")[0].dropFirst("shades_phone=".count))
        XCTAssertFalse(keys.hashes.contains(token))
        let hello = try await call("GET", "/hello", cookie: token)
        XCTAssertEqual(hello.statusCode, 204)
    }

    func testWhatAPhoneSendsIsYourWordsAndNothingElse() async throws {
        let cookie = try await pair()
        let dm = PhonePlace.key(.channel(.direct(penny)))
        let (first, stream) = try await watch(dm, cookie: cookie)
        defer { stream.cancel() }
        XCTAssertEqual(first["title"] as? String, "Penny")
        XCTAssertEqual((first["box"] as? [String: Any])?["label"] as? String, "New topic with Penny")

        let (status, body) = try await page(#"{"act":"send","key":"\#(dm)","text":"How's December looking?"}"#, cookie: cookie)
        XCTAssertEqual(status, 200)
        let opens = try XCTUnwrap((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["open"] as? String)
        XCTAssertTrue(opens.hasPrefix("t:sent-"), "the phone follows the new topic into its thread")
        await until { backend.sent.contains { $0.mode == .start } }
        let started = try XCTUnwrap(backend.sent.first { $0.mode == .start })
        XCTAssertEqual(started.prompt.projectID, "project-penny")
        XCTAssertEqual(started.prompt.text, Prompts.forKitten(penny, words: "How's December looking?", snapshot: nil, screenshotPath: nil, screenLeftOut: false))
        XCTAssertTrue(started.prompt.attachments.isEmpty)
        XCTAssertFalse(log.all.contains("snapshot"), "nothing was captured")

        let (refused, _) = try await page(#"{"act":"send","key":"t:made-up@everyone","text":"ship it"}"#, cookie: cookie)
        XCTAssertEqual(refused, 409, "a thread Messages doesn't know isn't somewhere words can go")
        XCTAssertEqual(backend.sent.count, 1)
    }

    func testMovingAroundThePhoneKeepsWhatYouJustSent() async throws {
        let cookie = try await pair()
        let dm = PhonePlace.key(.channel(.direct(penny)))
        let (_, stream) = try await watch(dm, cookie: cookie)
        let (_, body) = try await page(#"{"act":"send","key":"\#(dm)","text":"How's December looking?"}"#, cookie: cookie)
        let opens = try XCTUnwrap((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["open"] as? String)
        stream.cancel()
        await until { controller.phone?.isWatched == false }

        let (topic, next) = try await watch(opens, cookie: cookie)
        defer { next.cancel() }
        let said = (topic["rows"] as? [[String: Any]])?.compactMap { $0["text"] as? String } ?? []
        XCTAssertTrue(said.contains("How's December looking?"), "each place is its own stream, and moving between them mustn't forget what you sent: \(said)")
    }

    func testAPhoneKeepsMessagesOpenAndClosingForgetsIt() async throws {
        let cookie = try await pair()
        controller.channelsPressed()
        let (_, stream) = try await watch("everyone", cookie: cookie)
        stage.hideChannels()
        controller.channelsClosed()
        XCTAssertTrue(controller.channels.isOpen, "closing the window doesn't take Messages from the phone")
        let shown = stage.channelsUpdated.count
        controller.messagesAction(.startTopic("Hi from my phone", with: penny, id: "sent-phone"))
        XCTAssertEqual(stage.channelsUpdated.count, shown, "a closed window isn't shown anything, so it can't mark what it shows as seen")

        stream.cancel()
        await until { !controller.channels.isOpen }
        XCTAssertFalse(controller.channels.isOpen, "once the phone stops looking too, every word is forgotten")
    }

    func testTurningItOffForgetsEveryPhone() async throws {
        let cookie = try await pair()
        var settings = controller.settings
        settings.phone = false
        controller.apply(settings)
        XCTAssertNil(controller.phone)
        XCTAssertEqual(keys.hashes, [])
        await until { !stoppedServing.isEmpty }
        XCTAssertEqual(stoppedServing, [port], "and the page comes off your tailnet")
        do {
            _ = try await call("GET", "/hello", cookie: cookie)
            XCTFail("the server should be gone")
        } catch {}
    }
}
