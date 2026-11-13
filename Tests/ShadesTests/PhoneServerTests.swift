import Darwin
import AppKit
import CryptoKit
@testable import Shades
import ShadesContext
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
    /// How far ahead of the real time the controller's clock is.
    private var ahead: TimeInterval = 0
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
            stage: stage,
            now: { [unowned self] in Date().addingTimeInterval(self.ahead) }
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

    /// It used to close without a word, and it's open for ten minutes, so you may well have looked away.
    func testACodeThatRunsOutSaysSoAndHowToGetANewOne() async {
        stage.onPairing = { [unowned self] card in if card != nil { self.ahead = 601 } }
        controller.pairPhone()
        await until { self.stage.pairings.last == .some(nil) }
        XCTAssertEqual(stage.bubble, .line("That pairing code ran out after 10 minutes. Choose Pair Phone… from my menu for a new one.", threadID: nil))
    }

    /// Your face is yours, so unlike a cat it has no address of its own, and only comes in what a paired phone is sent.
    func testYourPictureGoesOnlyToAPairedPhone() async throws {
        MessagesInk.picture = DemoPicture.jpeg
        defer { MessagesInk.picture = nil }
        let picture = DemoPicture.jpeg.base64EncodedString()
        for path in ["/", "/app.js", "/app.css", "/manifest.json", "/sw.js", "/icon.png", "/picture.jpg", "/you", "/cat/light/sit/shades.png", "/events?key=general"] {
            let (_, body) = try await send("GET", path)
            XCTAssertFalse(String(decoding: body, as: UTF8.self).contains(picture), path)
        }
        let key = try await pair()
        let (view, stream) = try await watch("general", key: key)
        stream.cancel()
        XCTAssertEqual(view["you"] as? String, "data:image/jpeg;base64,\(picture)")
    }

    /// The page's words grow by as much as the window's for the text size picked on the Mac, from the next time it opens,
    /// and still when the page is turned off and on again.
    func testThePageTakesTheMacsTextSize() async throws {
        let style = { String(decoding: try await self.send("GET", "/app.css").body, as: UTF8.self) }
        let standard = try await style()
        XCTAssertFalse(standard.contains("--size:"), "at Standard, the phone's own")
        var settings = controller.settings
        settings.textSize = .larger
        controller.settingsEdited(settings)
        let larger = try await style()
        XCTAssertTrue(larger.contains("--size: calc(100% * 17 / 13)"))
        turnOff()
        settings = controller.settings
        settings.phone = true
        controller.apply(settings)
        await controller.phoneTask?.value
        port = try XCTUnwrap(controller.phoneListening)
        let again = try await style()
        XCTAssertTrue(again.contains("--size: calc(100% * 17 / 13)"))
    }

    func testOnlyAPairedPhoneGetsPastThePage() async throws {
        let page = try await call("GET", "/")
        XCTAssertEqual(page.statusCode, 200, "the page itself holds nothing")
        XCTAssertTrue(page.value(forHTTPHeaderField: "Content-Security-Policy")?.contains("script-src 'self'") == true)
        for path in ["/hello", "/events?key=general"] {
            let refused = try await call("GET", path, headers: ["Tailscale-User-Login": "someone@example.com"])
            XCTAssertEqual(refused.statusCode, 401, "\(path): Tailscale's header is easy to fake from this Mac, so it counts for nothing")
        }
        let (status, _) = try await self.page(#"{"act":"send","key":"general","text":"ship it"}"#, key: "made-up")
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

    func testACatsAddressIsTheWindowsArtInThatColourAndSaysNothingElse() async throws {
        // An image can't send the key, so like the icon it's served without one.
        let (drawn, png) = try await send("GET", "/cat/dark/sit/7458e8.png")
        XCTAssertEqual(drawn.statusCode, 200)
        XCTAssertEqual(drawn.value(forHTTPHeaderField: "Content-Type"), "image/png")
        XCTAssertEqual(drawn.value(forHTTPHeaderField: "Cache-Control"), "no-store", "under the same rules as the page's other files")
        XCTAssertEqual(drawn.value(forHTTPHeaderField: "X-Content-Type-Options"), "nosniff")
        XCTAssertTrue(drawn.value(forHTTPHeaderField: "Content-Security-Policy")?.contains("img-src 'self'") == true)
        XCTAssertNil(drawn.value(forHTTPHeaderField: "Set-Cookie"))

        let image = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertEqual([image.pixelsWide, image.pixelsHigh], [96, 96], "each art pixel six pixels square, for a 2x or 3x phone")
        let art = CatRenderer.pixels(for: CatPose(frame: .sit), theme: .dark, jacket: 0x7458e8)
        XCTAssertEqual(image.colorSpace, .sRGB)
        var jacket = 0
        for y in 0..<16 {
            for x in 0..<16 {
                let i = (y * 16 + x) * 4
                var pixel = [Int](repeating: 0, count: 4)
                image.getPixel(&pixel, atX: x * 6 + 3, y: y * 6 + 3)
                XCTAssertEqual(pixel[3], Int(art[i + 3]), "(\(x), \(y))")
                guard pixel[3] == 255 else { continue }
                XCTAssertEqual(Array(pixel.prefix(3)), [Int(art[i]), Int(art[i + 1]), Int(art[i + 2])], "the window's own art at (\(x), \(y))")
                if Array(pixel.prefix(3)) == [0x74, 0x58, 0xe8] { jacket += 1 }
            }
        }
        XCTAssertGreaterThan(jacket, 0, "in that jacket")
        var chunks: [String] = []
        var at = 8
        while at + 8 <= png.count {
            let length = png[at..<at + 4].reduce(0) { $0 << 8 | Int($1) }
            chunks.append(String(decoding: png[at + 4..<at + 8], as: UTF8.self))
            at += 12 + length
        }
        XCTAssertEqual(chunks.first, "IHDR")
        XCTAssertTrue(Set(chunks).isDisjoint(with: ["tEXt", "iTXt", "zTXt", "tIME"]), "no words or times in it: \(chunks)")

        // Any colour gets a cat, so an address can't tell anyone which colours your kittens wear, or that you have any.
        let (stranger, _) = try await send("GET", "/cat/light/alert/123456.png")
        XCTAssertEqual(stranger.statusCode, 200)
        let (own, _) = try await send("GET", "/cat/light/sleep/shades.png")
        XCTAssertEqual(own.statusCode, 200, "and the cat its own")
        let key = try await pair()
        let (_, paired) = try await send("GET", "/cat/dark/sit/7458e8.png", key: key)
        XCTAssertEqual(paired, png, "and it's the same picture whether you're paired or not")

        for path in [
            "/cat/dark/sit/7458E8.png", "/cat/dark/sit/7458e8ff.png", "/cat/dark/sit/7458e.png", "/cat/dark/sit/7458e8.svg",
            "/cat/dim/sit/7458e8.png", "/cat/dark/dance/7458e8.png", "/cat/dark/sit/penny.png", "/cat/dark/sit/7458e8.png/more",
            "/cat/dark/7458e8.png", "/cat/", "/cat/dark/sit/%2E%2E.png",
        ] {
            let (refused, body) = try await send("GET", path)
            XCTAssertEqual(refused.statusCode, 404, path)
            XCTAssertTrue(body.isEmpty, path)
        }
        let posted = try await call("POST", "/cat/dark/sit/7458e8.png", json: "{}", headers: ["X-Shades": "1"])
        XCTAssertNotEqual(posted.statusCode, 200)
    }

    /// What review found: anyone who can reach the page could fill the Mac's memory by asking for colours, and tell which
    /// cats a phone had just loaded by how fast they came back.
    func testACatsAddressKeepsNothingSoStrangersCantFillMemoryOrTellWhatAPhoneLoaded() {
        let link = PhoneLink(keys: MemoryPhoneKeys(), grace: 0, hold: { nil }, release: {}, act: { _ in }, sendPush: { _ in nil }, now: { Date() })
        func get(_ path: String) -> (status: Int, seconds: TimeInterval) {
            let started = DispatchTime.now().uptimeNanoseconds
            let response = link.respond(to: PhoneServer.Request(method: "GET", path: path, query: [:], headers: [:], body: Data()))
            let seconds = Double(DispatchTime.now().uptimeNanoseconds - started) / 1e9
            guard case .full(let status, _, _) = response else { return (-1, seconds) }
            return (status, seconds)
        }
        func median(_ times: [TimeInterval]) -> TimeInterval { times.sorted()[times.count / 2] }
        let loaded = (0..<21).map { "/cat/light/work/\(String(format: "%06x", 0x100000 + $0)).png" }
        loaded.forEach { _ = get($0) }
        let again = median(loaded.map { get($0).seconds })
        let fresh = median((0..<21).map { get("/cat/light/work/\(String(format: "%06x", 0x200000 + $0)).png").seconds })
        XCTAssertGreaterThan(again, fresh / 2, "a cat a phone just loaded comes back no faster than one it didn't")

        let before = footprint()
        // Each request drains its own autorelease pool, as the server's run loop does between requests.
        for n in 0..<20_000 { autoreleasepool { XCTAssertEqual(get("/cat/dark/sit/\(String(format: "%06x", 0x300000 + n)).png").status, 200) } }
        XCTAssertLessThan(footprint() - before, 4 << 20, "asking for colours doesn't fill memory")
    }

    private func footprint() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
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
        let dm = PhonePlace.key(.channel(.of(penny)))
        let (first, stream) = try await watch(dm, key: key)
        defer { stream.cancel() }
        XCTAssertEqual(first["title"] as? String, "#penny")
        XCTAssertEqual((first["box"] as? [String: Any])?["label"] as? String, "Starts a new thread with Penny")

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

        let (refused, _) = try await page(#"{"act":"send","key":"t:made-up@general","text":"ship it"}"#, key: key)
        XCTAssertEqual(refused, 409, "a thread Messages doesn't know isn't somewhere words can go")
        XCTAssertEqual(backend.sent.count, 1)
    }

    /// A phone's photo goes up first, to a paired phone's own request, then with its words to a new thread.
    func testAPhotoFromAPhoneGoesWithItsWordsOnly() async throws {
        let key = try await pair()
        let dm = PhonePlace.key(.channel(.of(penny)))
        let (first, stream) = try await watch(dm, key: key)
        defer { stream.cancel() }
        XCTAssertEqual((first["box"] as? [String: Any])?["files"] as? Bool, true)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let photo = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))

        func upload(_ body: Data, key: String?, headers: [String: String] = ["X-Shades": "1"]) async throws -> (status: Int, id: String?) {
            var request = URLRequest(url: URL(string: "/file", relativeTo: base)!)
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("image/png", forHTTPHeaderField: "Content-Type")
            request.setValue("receipt%20photo.png", forHTTPHeaderField: "X-Name")
            if let key { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
            for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
            let (data, response) = try await session.data(for: request)
            return ((response as! HTTPURLResponse).statusCode, (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["id"] as? String)
        }
        let stranger = try await upload(photo, key: "made-up")
        XCTAssertEqual(stranger.status, 401, "only a paired phone")
        let unmarked = try await upload(photo, key: key, headers: [:])
        XCTAssertEqual(unmarked.status, 400, "only the page's own request")
        let tooBig = try await upload(Data(count: PhoneServer.biggestFile + 1), key: key)
        XCTAssertEqual(tooBig.status, 413)
        let kept = try await upload(photo, key: key)
        XCTAssertEqual(kept.status, 200)
        let id = try XCTUnwrap(kept.id)

        let (made, _) = try await page(#"{"act":"send","key":"\#(dm)","text":"Can I expense this?","files":["made-up"]}"#, key: key)
        XCTAssertEqual(made, 409, "only a file this phone sent")
        let (status, _) = try await page(#"{"act":"send","key":"\#(dm)","text":"Can I expense this?","files":["\#(id)"]}"#, key: key)
        XCTAssertEqual(status, 200)
        await until { backend.sent.contains { $0.mode == .start } }
        let started = try XCTUnwrap(backend.sent.first { $0.mode == .start })
        XCTAssertEqual(started.prompt.projectID, "project-penny")
        XCTAssertTrue(started.prompt.text.hasPrefix("Can I expense this?"))
        XCTAssertEqual(Prompts.droppedNames(in: started.prompt.text).first, "receipt photo.png")
        XCTAssertEqual(started.prompt.attachments.count, 1)
        XCTAssertFalse(log.all.contains("snapshot"), "nothing was captured")
        let (again, _) = try await page(#"{"act":"send","key":"\#(dm)","text":"And again","files":["\#(id)"]}"#, key: key)
        XCTAssertEqual(again, 409, "a file goes once")

        // Taking one off and adding another used to push out one still attached, so none could go.
        var ids: [String] = []
        for _ in 0..<Drop.mostAtOnce {
            let uploaded = try await upload(photo, key: key)
            ids.append(try XCTUnwrap(uploaded.id))
        }
        let (dropped, _) = try await page(#"{"act":"unattach","id":"\#(ids.removeLast())"}"#, key: key)
        XCTAssertEqual(dropped, 204)
        let replacement = try await upload(photo, key: key)
        ids.append(try XCTUnwrap(replacement.id))
        let list = ids.map { "\"\($0)\"" }.joined(separator: ",")
        let (ten, _) = try await page(#"{"act":"send","key":"\#(dm)","text":"Ten","files":[\#(list)]}"#, key: key)
        XCTAssertEqual(ten, 200, "ten attached, ten sent")
    }

    func testMovingAroundThePhoneKeepsWhatYouJustSent() async throws {
        let key = try await pair()
        let dm = PhonePlace.key(.channel(.of(penny)))
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

    func testAPhoneKeepsMessagesOpenUntilItStopsLookingToo() async throws {
        let key = try await pair()
        controller.channelsPressed()
        let (_, stream) = try await watch("general", key: key)
        stage.hideChannels()
        controller.channelsClosed()
        XCTAssertTrue(controller.channels.isOpen, "closing the window doesn't take Messages from the phone")
        let shown = stage.channelsUpdated.count
        controller.messagesAction(.startTopic("Hi from my phone", with: penny, id: "sent-phone"))
        XCTAssertEqual(stage.channelsUpdated.count, shown, "a closed window isn't shown anything, so it can't mark what it shows as seen")

        stream.cancel()
        await until { !controller.channels.isOpen }
        XCTAssertFalse(controller.channels.isOpen, "once the phone stops looking too, nothing reads until someone looks again")
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
        backend.listed = [asking]
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
        let page = PhonePlace.key(.thread("w", in: .channel(.of(penny))))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: opened) as? [String: String], ["title": "Penny needs an approval", "tag": "r1", "key": page], "and nothing they asked")
        XCTAssertFalse(String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self).contains("Penny"), "the push service only sees that Shades sent something")

        approvalNow()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(pushed.count, 1, "once, as on the Mac")
    }

    /// The cat's own work opens Activity on your phone, unless you've chosen to show it there, when it opens the thread.
    func testANotificationAboutTheCatsOwnWorkOpensItOnlyOnceItsSwitchIsOn() async throws {
        let key = try await pair()
        _ = try await subscribe(key: key)
        func asking(_ id: String) -> AgentThread {
            AgentThread(
                id: id, title: "Fix: it", projectTitle: nil, status: .waitingForApproval, model: "m", updatedAt: Date(),
                pendingApprovals: [ApprovalRequest(id: "r-\(id)", threadID: id, threadTitle: "Fix: it", kind: .command, summary: "ls", createdAt: Date())]
            )
        }
        func opened(_ index: Int) throws -> String? {
            let body = try WebPush.decrypt(XCTUnwrap(pushed[index].httpBody), with: phone, auth: phoneAuth)
            return (try JSONSerialization.jsonObject(with: body) as? [String: String])?["key"]
        }
        backend.listed = [asking("off")]
        controller.threadsChanged([asking("off")])
        await until { pushed.count == 1 }
        XCTAssertEqual(try opened(0), PhonePlace.key(.activity))

        controller.threadsChanged([asking("off"), AgentThread(id: "on", title: "Fix: it", projectTitle: nil, status: .running, model: "m", updatedAt: Date())])
        controller.showOnPhonePressed("on")
        backend.listed = [asking("off"), asking("on")]
        controller.threadsChanged([asking("off"), asking("on")])
        await until { pushed.count == 2 }
        XCTAssertEqual(try opened(1), PhonePlace.key(.thread("on", in: .channel(.shades))))
    }

    func testSearchOnAPhoneNeedsItsKeyThePagesOwnRequestAndAPhoneLooking() async throws {
        let key = try await pair()
        let budget = AgentThread(id: "w", title: "Budget", projectTitle: "Penny", status: .completed, model: "m", updatedAt: Date(), projectPath: penny.folder)
        backend.listed = [budget]
        backend.said["w"] = [Exchange(id: "turn", asker: .you, askedAt: Date(), ask: "Check the budget for December", reply: "Groceries went over.", repliedAt: Date())]
        controller.threadsChanged([budget])
        func search(key: String?, headers: [String: String] = ["X-Shades": "1"]) async throws -> (status: Int, found: [[String: Any]]) {
            let (response, body) = try await send("POST", "/search", json: #"{"words":"groceries"}"#, key: key, headers: headers)
            let found = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["found"] as? [[String: Any]]
            return (response.statusCode, found ?? [])
        }
        let stranger = try await search(key: "made-up")
        XCTAssertEqual(stranger.status, 401)
        let elsewhere = try await search(key: key, headers: [:])
        XCTAssertEqual(elsewhere.status, 400, "only the page's own requests, which another site can't make")
        let unlooked = try await search(key: key)
        XCTAssertEqual(unlooked.status, 409, "Messages is only open while a phone is looking")

        let (_, stream) = try await watch(PhonePlace.key(.channel(.of(penny))), key: key)
        defer { stream.cancel() }
        var found: [[String: Any]] = []
        for _ in 0..<200 where found.isEmpty {
            found = try await search(key: key).found
            if found.isEmpty { try? await Task.sleep(nanoseconds: 20_000_000) }
        }
        XCTAssertEqual(found.first?["open"] as? String, PhonePlace.key(.thread("w", in: .channel(.of(penny)))))
        XCTAssertEqual(found.first?["id"] as? String, "turn:reply")
        XCTAssertEqual(found.first?["text"] as? String, "Groceries went over.")
        XCTAssertEqual(found.first?["marks"] as? [[Int]], [[0, 9]])
    }

    func testTappingANotificationOpensItsThreadEvenBeforeMessagesHasReadIt() async throws {
        let key = try await pair()
        _ = try await subscribe(key: key)
        backend.said["w"] = [Exchange(id: "turn", asker: .you, askedAt: Date(), ask: "Check the budget", reply: "On it.", repliedAt: Date())]
        approvalNow()
        await until { !pushed.isEmpty }
        let opened = try WebPush.decrypt(XCTUnwrap(pushed.first?.httpBody), with: phone, auth: phoneAuth)
        let page = try XCTUnwrap((try JSONSerialization.jsonObject(with: opened) as? [String: String])?["key"])
        XCTAssertEqual(page, PhonePlace.key(.thread("w", in: .channel(.of(penny)))))

        var request = URLRequest(url: URL(string: "/events?key=\(page.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)", relativeTo: base)!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (bytes, _) = try await session.bytes(for: request)
        var shown: [String] = []
        let stream = Task { @MainActor in
            for try await line in bytes.lines where line.hasPrefix("data: ") {
                let view = try JSONSerialization.jsonObject(with: Data(line.dropFirst(6).utf8)) as? [String: Any]
                shown.append(view?["key"] as? String ?? "")
            }
        }
        defer { stream.cancel() }
        await until { shown.last == page }
        XCTAssertEqual(shown.first, PhonePlace.key(.channel(.of(penny))), "Messages hadn't read it, so it showed where it lives")
        XCTAssertEqual(shown.last, page, "and opened it once it had")
    }

    func testTappingANotificationForAThreadYouRepliedToBeforeMessagesReadItStillOpensIt() async throws {
        let key = try await pair()
        _ = try await subscribe(key: key)
        backend.said["w"] = [Exchange(id: "turn", asker: .you, askedAt: Date(), ask: "Check the budget", reply: "On it.", repliedAt: Date())]
        approvalNow()
        // Sent from Messages before it had read the thread, so the thread is known without anything leading to it.
        controller.messagesAction(.send("Use last month's numbers", to: .thread(id: "w", title: "Budget"), shownIn: .of(penny)))
        await until { !pushed.isEmpty }
        let opened = try WebPush.decrypt(XCTUnwrap(pushed.first?.httpBody), with: phone, auth: phoneAuth)
        let page = try XCTUnwrap((try JSONSerialization.jsonObject(with: opened) as? [String: String])?["key"])

        var request = URLRequest(url: URL(string: "/events?key=\(page.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)", relativeTo: base)!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (bytes, _) = try await session.bytes(for: request)
        var shown: [String] = []
        let stream = Task { @MainActor in
            for try await line in bytes.lines where line.hasPrefix("data: ") {
                let view = try JSONSerialization.jsonObject(with: Data(line.dropFirst(6).utf8)) as? [String: Any]
                shown.append(view?["key"] as? String ?? "")
            }
        }
        defer { stream.cancel() }
        await until { shown.last == page }
        XCTAssertEqual(shown.last, page, "the tap ends on the thread once it's read: \(shown)")
    }

    func testDoNotDisturbHoldsPushesAndDoesntSendThemLate() async throws {
        let key = try await pair()
        _ = try await subscribe(key: key)
        controller.doNotDisturbPressed()
        approvalNow()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(pushed, [])
        controller.doNotDisturbPressed()
        approvalNow()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(pushed, [], "the catch-up covers it")
    }

    func testAChannelSaysWhatPushesForItselfWhateverTheMacIsSetTo() async throws {
        let key = try await pair()
        _ = try await subscribe(key: key)
        controller.messagesAction(.notifications(.of(penny), ChannelNotifications(mac: .everything, phone: .nothing)))
        approvalNow()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(pushed, [])

        controller.threadsChanged([])
        controller.messagesAction(.notifications(.of(penny), ChannelNotifications(mac: .nothing, phone: .needsYou)))
        let asking = AgentThread(
            id: "w2", title: "Taxes", projectTitle: "Penny", status: .waitingForApproval, model: "m", updatedAt: Date(),
            pendingApprovals: [ApprovalRequest(id: "r2", threadID: "w2", threadTitle: "Taxes", kind: .command, summary: "ls", createdAt: Date())],
            projectPath: penny.folder
        )
        controller.threadsChanged([asking])
        await until { !pushed.isEmpty }
        let opened = try WebPush.decrypt(XCTUnwrap(pushed.first?.httpBody), with: phone, auth: phoneAuth)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: opened) as? [String: String])?["tag"], "r2")
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
