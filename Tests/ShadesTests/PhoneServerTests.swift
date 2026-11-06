import CryptoKit
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
    /// What Tailscale was asked, in order.
    private var tailscale: [String] = []
    private var serveTakes: UInt64 = 0
    /// What was sent to phones' push services, and what they answer.
    private var pushed: [URLRequest] = []
    private var pushAnswer = 201
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
                servePhone: { [unowned self] port in
                    try? await Task.sleep(nanoseconds: self.serveTakes)
                    self.tailscale.append("serve \(port)")
                    return "https://mac.example.ts.net:4797"
                },
                stopServingPhone: { [unowned self] in self.tailscale.append("off") },
                sendPush: { [unowned self] in
                    self.pushed.append($0)
                    return self.pushAnswer
                }
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

    private func call(_ method: String, _ path: String, json: String? = nil, key: String? = nil, headers: [String: String] = [:]) async throws -> HTTPURLResponse {
        try await send(method, path, json: json, key: key, headers: headers).response
    }

    private func send(_ method: String, _ path: String, json: String? = nil, key: String? = nil, headers: [String: String] = [:]) async throws -> (response: HTTPURLResponse, body: Data) {
        var request = URLRequest(url: URL(string: path, relativeTo: base)!)
        request.httpMethod = method
        if let json {
            request.httpBody = Data(json.utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let key { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let (body, response) = try await session.data(for: request)
        return (response as! HTTPURLResponse, body)
    }

    private func page(_ json: String, key: String?) async throws -> (status: Int, body: Data) {
        let (response, body) = try await send("POST", "/act", json: json, key: key, headers: ["X-Shades": "1"])
        return (response.statusCode, body)
    }

    private func pair() async throws -> String {
        let code = try XCTUnwrap(stage.pairings.last??.code)
        let (paired, body) = try await send("POST", "/pair", json: #"{"code":"\#(code)"}"#, headers: ["X-Shades": "1"])
        XCTAssertEqual(paired.statusCode, 200)
        return try XCTUnwrap((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["key"] as? String)
    }

    /// The first view a stream sends, and the task holding the stream open.
    private func watch(_ place: String, key: String) async throws -> (view: [String: Any], stream: Task<Void, Never>) {
        var request = URLRequest(url: URL(string: "/events?key=\(place.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)", relativeTo: base)!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
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
        let (status, _) = try await self.page(#"{"act":"send","key":"everyone","text":"ship it"}"#, key: "made-up")
        XCTAssertEqual(status, 401)
        XCTAssertEqual(backend.sent.count, 0)

        let unmarked = try await call("POST", "/pair", json: #"{"code":"ABCDEFGH"}"#)
        XCTAssertEqual(unmarked.statusCode, 400, "only the page's own requests, which another site can't make")
        let wrong = try await call("POST", "/pair", json: #"{"code":"ABCDEFGH"}"#, headers: ["X-Shades": "1"])
        XCTAssertEqual(wrong.statusCode, 403)

        let code = try XCTUnwrap(stage.pairings.last??.code)
        XCTAssertEqual(stage.pairings.last??.link, "https://mac.example.ts.net:4797/#pair=\(code)")
        let (paired, body) = try await send("POST", "/pair", json: #"{"code":"\#(code)"}"#, headers: ["X-Shades": "1"])
        XCTAssertEqual(paired.statusCode, 200)
        XCTAssertEqual(stage.pairings.last, .some(nil), "the code goes away once it's used")
        XCTAssertTrue(stage.bubbles.contains(.line(CatWords.phonePaired, threadID: nil)))
        let key = try XCTUnwrap((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["key"] as? String)
        XCTAssertFalse(keys.hashes.contains(key))
        let hello = try await call("GET", "/hello", key: key)
        XCTAssertEqual(hello.statusCode, 204)
    }

    func testTheKeyIsntACookieSoNoOtherPortOnTheMacsNameGetsIt() async throws {
        let code = try XCTUnwrap(stage.pairings.last??.code)
        let (paired, body) = try await send("POST", "/pair", json: #"{"code":"\#(code)"}"#, headers: ["X-Shades": "1"])
        XCTAssertNil(paired.value(forHTTPHeaderField: "Set-Cookie"), "a browser sends a cookie to every port on a name, whatever's serving there")
        let key = try XCTUnwrap((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["key"] as? String)
        let asCookie = try await call("GET", "/hello", headers: ["Cookie": "shades_phone=\(key)"])
        XCTAssertEqual(asCookie.statusCode, 401, "only the page's own header, which stays with its address and port, gets in")
    }

    func testWhatAPhoneSendsIsYourWordsAndNothingElse() async throws {
        let key = try await pair()
        let dm = PhonePlace.key(.channel(.direct(penny)))
        let (first, stream) = try await watch(dm, key: key)
        defer { stream.cancel() }
        XCTAssertEqual(first["title"] as? String, "Penny")
        XCTAssertEqual((first["box"] as? [String: Any])?["label"] as? String, "New topic with Penny")

        let (status, body) = try await page(#"{"act":"send","key":"\#(dm)","text":"How's December looking?"}"#, key: key)
        XCTAssertEqual(status, 200)
        let opens = try XCTUnwrap((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["open"] as? String)
        XCTAssertTrue(opens.hasPrefix("t:sent-"), "the phone follows the new topic into its thread")
        await until { backend.sent.contains { $0.mode == .start } }
        let started = try XCTUnwrap(backend.sent.first { $0.mode == .start })
        XCTAssertEqual(started.prompt.projectID, "project-penny")
        XCTAssertEqual(started.prompt.text, Prompts.forKitten(penny, words: "How's December looking?", snapshot: nil, screenshotPath: nil, screenLeftOut: false))
        XCTAssertTrue(started.prompt.attachments.isEmpty)
        XCTAssertFalse(log.all.contains("snapshot"), "nothing was captured")

        let (refused, _) = try await page(#"{"act":"send","key":"t:made-up@everyone","text":"ship it"}"#, key: key)
        XCTAssertEqual(refused, 409, "a thread Messages doesn't know isn't somewhere words can go")
        XCTAssertEqual(backend.sent.count, 1)
    }

    func testMovingAroundThePhoneKeepsWhatYouJustSent() async throws {
        let key = try await pair()
        let dm = PhonePlace.key(.channel(.direct(penny)))
        let (_, stream) = try await watch(dm, key: key)
        let (_, body) = try await page(#"{"act":"send","key":"\#(dm)","text":"How's December looking?"}"#, key: key)
        let opens = try XCTUnwrap((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["open"] as? String)
        stream.cancel()
        await until { controller.phone?.isWatched == false }

        let (topic, next) = try await watch(opens, key: key)
        defer { next.cancel() }
        let said = (topic["rows"] as? [[String: Any]])?.compactMap { $0["text"] as? String } ?? []
        XCTAssertTrue(said.contains("How's December looking?"), "each place is its own stream, and moving between them mustn't forget what you sent: \(said)")
    }

    func testAPhoneKeepsMessagesOpenAndClosingForgetsIt() async throws {
        let key = try await pair()
        controller.channelsPressed()
        let (_, stream) = try await watch("everyone", key: key)
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
        let key = try await pair()
        turnOff()
        XCTAssertNil(controller.phone)
        XCTAssertEqual(keys.hashes, [])
        await until { tailscale.last == "off" }
        XCTAssertEqual(tailscale, ["serve \(port)", "off"], "and the page comes off your tailnet")
        do {
            _ = try await call("GET", "/hello", key: key)
            XCTFail("the server should be gone")
        } catch {}
    }

    func testTurningItOffWhileTailscaleIsServingStillEndsWithItOff() async throws {
        turnOff()
        await until { tailscale.last == "off" }
        tailscale = []
        serveTakes = 300_000_000
        var settings = controller.settings
        settings.phone = true
        controller.apply(settings)
        await until { controller.phoneListening != nil }
        let port = try XCTUnwrap(controller.phoneListening)
        turnOff()
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertEqual(tailscale.last, "off", "the last thing Tailscale hears is what you last chose: \(tailscale) on \(port)")
        XCTAssertNil(controller.phoneAddress, "and nothing says it's still on")
    }

    func testTurningItOffAfterItCouldntStartStillTakesThePageOff() async throws {
        turnOff()
        await until { tailscale.last == "off" }
        var settings = controller.settings
        settings.phone = true
        controller.apply(settings)
        // As if it couldn't start this time, while the page from the last run is still on your tailnet.
        controller.phone?.stop()
        controller.phone = nil
        tailscale = []
        turnOff()
        await until { !tailscale.isEmpty }
        XCTAssertEqual(tailscale, ["off"])
    }

    // MARK: - Notifications

    private let phone = P256.KeyAgreement.PrivateKey()
    private let phoneAuth = Data(repeating: 9, count: 16)

    private func subscribe(key: String, endpoint: String = "https://web.push.apple.com/QGuW") async throws -> Int {
        let subscription = #"{"endpoint":"\#(endpoint)","p256dh":"\#(WebPush.string(phone.publicKey.x963Representation))","auth":"\#(WebPush.string(phoneAuth))"}"#
        return try await send("POST", "/push", json: subscription, key: key, headers: ["X-Shades": "1"]).response.statusCode
    }

    private func approvalNow() {
        let asking = AgentThread(
            id: "w", title: "Budget", projectTitle: "Penny", status: .waitingForApproval, model: "m", updatedAt: Date(),
            pendingApprovals: [ApprovalRequest(id: "r1", threadID: "w", threadTitle: "Budget", kind: .command, summary: "rm -rf build", createdAt: Date())],
            projectPath: penny.folder
        )
        controller.threadsChanged([asking])
    }

    func testANotificationSaysOnlyWhoAndWhatKind() async throws {
        let key = try await pair()
        let (asked, body) = try await send("GET", "/push", key: key)
        XCTAssertEqual(asked.statusCode, 200)
        let signing = try XCTUnwrap((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["key"] as? String)
        let subscribed = try await subscribe(key: key)
        XCTAssertEqual(subscribed, 204)

        approvalNow()
        await until { !pushed.isEmpty }
        let request = try XCTUnwrap(pushed.first)
        XCTAssertEqual(request.url?.absoluteString, "https://web.push.apple.com/QGuW")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Encoding"), "aes128gcm")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Authorization")?.hasSuffix(", k=\(signing)") == true, "signed with the key the phone subscribed with")
        let opened = try WebPush.decrypt(XCTUnwrap(request.httpBody), with: phone, auth: phoneAuth)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: opened) as? [String: String], ["title": "Penny needs an approval", "tag": "r1"], "and nothing they asked")
        XCTAssertFalse(String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self).contains("Penny"), "the push service only sees that Shades sent something")

        approvalNow()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(pushed.count, 1, "once, as on the Mac")
    }

    func testOnlyAPairedPhoneSubscribesAndOnlyToAPushService() async throws {
        let refused = try await subscribe(key: "made-up")
        XCTAssertEqual(refused, 401)
        let key = try await pair()
        let elsewhere = try await subscribe(key: key, endpoint: "https://127.0.0.1:4797/act")
        XCTAssertEqual(elsewhere, 400, "or a phone could have Shades send requests anywhere")
        XCTAssertEqual(keys.load(PhoneKeys.pushes), [])
    }

    func testAPhoneItsPushServiceSaysIsGoneStopsGettingThem() async throws {
        let key = try await pair()
        _ = try await subscribe(key: key)
        pushAnswer = 410
        approvalNow()
        await until { keys.load(PhoneKeys.pushes).isEmpty }
        XCTAssertEqual(keys.load(PhoneKeys.pushes), [])
    }

    func testTurningItOffStopsEveryPhonesNotifications() async throws {
        let key = try await pair()
        _ = try await subscribe(key: key)
        XCTAssertEqual(keys.load(PhoneKeys.pushes).count, 1)
        turnOff()
        XCTAssertEqual(keys.load(PhoneKeys.pushes), [])
        approvalNow()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(pushed, [])
    }

    func testTheSigningKeyLastsSoSubscriptionsKeepWorking() async throws {
        let key = try await pair()
        let first = try await send("GET", "/push", key: key).body
        let again = PhonePushes(keys: keys, send: { _ in nil }).publicKey
        XCTAssertEqual((try JSONSerialization.jsonObject(with: first) as? [String: Any])?["key"] as? String, again)
        XCTAssertEqual(keys.load(PhoneKeys.signing).count, 1)
    }

    func testTurningItOffAfterItCouldntStartStillForgetsEveryPhone() async throws {
        let key = try await pair()
        _ = try await subscribe(key: key)
        // As if it couldn't start this time, with a phone paired and subscribed in an earlier run.
        controller.phone?.stop()
        controller.phone = nil
        turnOff()
        XCTAssertEqual(keys.hashes, [])
        XCTAssertEqual(keys.load(PhoneKeys.pushes), [], "off means off, even if it never started")
        var settings = controller.settings
        settings.phone = true
        controller.apply(settings)
        approvalNow()
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(pushed, [], "a phone has to pair and turn its notifications on again")
    }

    private func turnOff() {
        var settings = controller.settings
        settings.phone = false
        controller.apply(settings)
    }

    /// Serve keeps forwarding after Shades stops, so whatever took its port would get what the phone sends. The page
    /// has to come off when Shades stops, however it stops, which is when the system closes Shades' end of the pipe.
    func testThePageComesOffYourTailnetWhenShadesStops() async throws {
        let (tool, lines) = try fakeTailscale()

        let serve = TailscaleServe(port: 4797, tool: tool)
        let address = try await serve.serve(to: 51000)
        XCTAssertEqual(address, "https://mac.example.ts.net:4797")
        XCTAssertEqual(lines(), ["serve --bg --https=4797 http://127.0.0.1:51000", "status --json"])

        try serve.helper?.pipe.fileHandleForWriting.close()
        for _ in 0..<300 where lines().count < 3 { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(lines().last, "serve --https=4797 off", "once Shades is gone, the page goes too")
    }

    func testTurningItOffStopsTheHelperFirstSoItCantTakeThePageOffLater() async throws {
        let (tool, lines) = try fakeTailscale()

        let serve = TailscaleServe(port: 4797, tool: tool)
        _ = try await serve.serve(to: 51000)
        let first = try XCTUnwrap(serve.helper)
        await serve.stop()
        _ = try await serve.serve(to: 52000)
        first.process.waitUntilExit()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(lines().suffix(3), ["serve --https=4797 off", "serve --bg --https=4797 http://127.0.0.1:52000", "status --json"], "turned on again, it stays on")
        try serve.helper?.pipe.fileHandleForWriting.close()
    }

    /// Stands in for the tailscale tool, and writes down what it's asked.
    private func fakeTailscale() throws -> (tool: String, said: () -> [String]) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("shades-tailscale-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let said = folder.appendingPathComponent("said")
        let tool = folder.appendingPathComponent("tailscale")
        try """
            #!/bin/sh
            echo "$*" >> '\(said.path)'
            [ "$1" = status ] && echo '{"Self":{"DNSName":"mac.example.ts.net."}}'
            exit 0
            """.write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        return (tool.path, { (try? String(contentsOf: said, encoding: .utf8))?.split(separator: "\n").map(String.init) ?? [] })
    }
}
