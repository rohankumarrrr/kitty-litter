@testable import Shades
import ShadesCore
import XCTest

@MainActor
final class PhoneStreamModelTests: XCTestCase {
    static let depth = 5

    func testEveryOrderOfAStreamsEventsDeliversWhatYouSendOnceAndKeepsThePageLive() {
        let walk = walkEveryOrder(StreamWorld.self, upTo: Self.depth)
        XCTAssertNil(walk.counterexample, walk.counterexample ?? "")
        XCTAssertGreaterThan(walk.states, 700, "it explored too little to mean anything")
    }

    func testASendWhileTheMacHasLetGoReachesItOnceThePageLooksAgain() {
        var world = StreamWorld()
        for event: StreamWorld.Event in [.die, .notice, .letGo, .send, .answer(0)] {
            XCTAssertTrue(world.enabled(event), "\(event)")
            guard world.enabled(event) else { return }
            _ = world.apply(event)
            XCTAssertNil(world.broken())
        }
        XCTAssertEqual(world.delivered, [], "the Mac turned it away, since nobody was looking")
        XCTAssertEqual(world.phone.pending.map(\.path), ["/events"], "so the page looks again")
        for event: StreamWorld.Event in [.answer(0), .answer(0), .answer(0)] where world.enabled(event) { _ = world.apply(event) }
        XCTAssertEqual(world.delivered, [StreamWorld.words], "and sends it once it's looking")
        XCTAssertNil(world.finish())
        XCTAssertEqual(world.phone.text("banner"), "")
    }

    func testAStreamThatGoesDeadOnTheLockScreenIsReplaced() {
        var world = StreamWorld()
        _ = world.apply(.die)
        XCTAssertNil(world.finish())
        XCTAssertGreaterThan(world.phone.requests.filter { $0.path == "/events" }.count, 1, "the page started another")
    }
}

@MainActor
struct StreamWorld: PhoneModel {
    enum Event: Hashable {
        case send, answer(Int), die, notice, letGo, update, wait, away
    }

    static let events: [Event] = [.send, .answer(0), .answer(1), .answer(2), .die, .notice, .letGo, .update, .wait, .away]
    static let words = "Ship it"
    private static let steve = Kitten(name: "Steve Pawsniak", role: "Professional", covers: "", folder: "/k/steve")
    private static let noon = Date(timeIntervalSince1970: 1_000_000)
    private static let key = PhonePlace.key(.thread("a", in: .channel(.of(steve))))
    private static let book = ChannelBook.build(
        kittens: [steve],
        threads: [AgentThread(id: "a", title: "Work", projectTitle: steve.name, status: .completed, model: "m", updatedAt: noon, projectPath: steve.folder)],
        transcripts: ["a": [Exchange(id: "e1", asker: .you, askedAt: noon, ask: "How's it going?", reply: "Fine.", repliedAt: noon)]],
        isReading: false, unreadable: 0, cantReachT3: false
    )
    private static let view = String(decoding: (try? JSONEncoder().encode(PhoneView(PhonePlace(key, in: book), in: book, now: noon))) ?? Data(), as: UTF8.self)
    private static let gone = "That's changed since. Have another look."
    private static let grace: TimeInterval = 20

    let phone = PhoneScript(at: StreamWorld.key)
    private(set) var delivered: [String] = []
    private var holding = false
    private var macStreams: [Int: String] = [:]
    private var dead: Set<Int> = []
    private var closesHeard = 0
    private var sent = 0
    private var troubleSinceSend = false
    private var deaths = 0
    private var updates = 0
    private var waits = 0
    private var aways = 0

    init() {
        phone.settle()
        answerEverything()
    }

    private var live: [PhoneScript.Request] {
        phone.streams.filter { !dead.contains($0.id) }
    }

    func enabled(_ event: Event) -> Bool {
        switch event {
        case .send:
            return sent == 0 && phone.read("!document.getElementById('box').hidden && Boolean(view && view.box && view.box.ready)") as? Bool == true
        case .answer(let index):
            return index < phone.pending.count
        case .die:
            return deaths < 2 && !live.isEmpty
        case .notice:
            return macStreams.keys.contains { dead.contains($0) }
        case .letGo:
            return holding && macStreams.isEmpty
        case .update:
            return updates < 2 && live.contains { macStreams[$0.id] != nil }
        case .wait:
            return waits < 3 && phone.pending.isEmpty && phone.nextTimer != nil
        case .away:
            return aways < 1
        }
    }

    mutating func apply(_ event: Event) -> String {
        defer { heardCloses() }
        if sent > 0, [.die, .notice, .letGo].contains(event) { troubleSinceSend = true }
        switch event {
        case .send:
            sent += 1
            phone.type(Self.words, into: "#words")
            phone.tap("#send")
            return "you send \"\(Self.words)\""
        case .answer(let index):
            let request = phone.pending[index]
            let reply = reply(to: request)
            phone.answer(request, reply)
            phone.settle()
            return "the Mac answers \(Self.describe(request)) with \(Self.describe(reply))"
        case .die:
            deaths += 1
            if let stream = live.last { dead.insert(stream.id) }
            return "the connection under the page's stream goes dead, as on the lock screen or a new network"
        case .notice:
            if let id = macStreams.keys.first(where: { dead.contains($0) }) { close(id) }
            return "the Mac notices the dead connection and closes its end"
        case .letGo:
            phone.advance(Self.grace)
            holding = false
            return "\(Int(Self.grace)) seconds pass with no stream, and the Mac lets go of Messages"
        case .update:
            updates += 1
            for stream in live where macStreams[stream.id] != nil { phone.send(Self.view, on: stream) }
            phone.settle()
            return "something changes and the Mac sends it"
        case .wait:
            waits += 1
            let before = phone.clock
            ping()
            if let next = phone.nextTimer { phone.advance((next - before) / 1000) }
            return "\(Int((phone.clock - before) / 1000)) seconds pass"
        case .away:
            aways += 1
            phone.visible(false)
            phone.visible(true)
            return "you leave the page and come back"
        }
    }

    var fingerprint: String {
        let now = phone.clock
        let pending = phone.pending.map { "\($0.path) \($0.act ?? "") \(Int(now - $0.at))" }
        let streams = phone.streams.map { "\(dead.contains($0.id) ? "dead" : "live")\(macStreams[$0.id] == nil ? "" : " held")" }
        let macOnly = macStreams.keys.filter { id in !phone.streams.contains { $0.id == id } }.count
        let page = phone.read("""
            [() => key, () => $('banner').textContent, () => $('words').value, () => $('send').disabled, () => stream !== null, () => received !== null,
             () => waiting.length, ...[() => heard, () => began, () => shownAt].map((at) => () => Math.min(Date.now() - at(), 30001))]
              .map((part) => { try { return String(part()); } catch (error) { return '-'; } }).join(',')
            """) as? String ?? ""
        return [pending.joined(separator: ";"), streams.joined(separator: ";"), "\(macOnly) \(holding) \(delivered.count)",
                "\(sent) \(troubleSinceSend) \(deaths) \(updates) \(waits) \(aways)", page, phone.timers].joined(separator: "\n")
    }

    func broken() -> String? {
        if let error = phone.errors.first { return "the page threw \(error)" }
        if delivered.count > 1 { return "the Mac got what you sent \(delivered.count) times" }
        if phone.text("banner") == Self.gone { return "the page says it changed, though nothing had" }
        if phone.streams.count > 1 { return "the page reads \(phone.streams.count) streams at once" }
        return nil
    }

    mutating func finish() -> String? {
        let until = phone.clock + 60_000
        while true {
            for id in macStreams.keys where dead.contains(id) { close(id) }
            answerEverything()
            ping()
            guard let next = phone.nextTimer, next <= until else { break }
            phone.advance((next - phone.clock) / 1000)
            heardCloses()
        }
        if let problem = broken() { return problem }
        let left = phone.read("$('words').value") as? String ?? ""
        let keptForYou = delivered.isEmpty && troubleSinceSend && left == Self.words
        if sent > 0, !keptForYou {
            if delivered != [Self.words] { return "the Mac has \(delivered) of what you sent, though the network was fine from when you pressed send" }
            if !left.isEmpty { return "\"\(left)\" is still in the box" }
        }
        return listening()
    }

    private func listening() -> String? {
        if live.count != 1 || phone.read("stream === null") as? Bool == true { return "the page isn't listening on a live stream" }
        if !phone.text("banner").isEmpty { return "the page still says \"\(phone.text("banner"))\"" }
        return nil
    }

    private mutating func answerEverything() {
        while let request = phone.pending.first {
            phone.answer(request, reply(to: request))
            phone.settle()
            heardCloses()
        }
    }

    private mutating func reply(to request: PhoneScript.Request) -> PhoneScript.Reply {
        switch request.path {
        case "/hello":
            return .status(204)
        case "/events":
            let page = request.query["page"] ?? ""
            for (id, other) in macStreams where other == page { close(id) }
            holding = true
            macStreams[request.id] = page
            return .stream(Self.view)
        case "/act":
            guard holding else { return .status(503) }
            guard let ask = try? JSONDecoder().decode(PhoneAsk.self, from: Data(request.body.utf8)),
                  let done = ask.action(in: Self.book, newTopic: { "topic-1" }) else { return .status(409) }
            if ask.act == "send" { delivered.append(ask.text ?? "") }
            return .json(done.opens.map { ["open": $0] } ?? [:])
        default:
            return .status(404)
        }
    }

    private mutating func close(_ id: Int) {
        macStreams[id] = nil
        if !dead.contains(id), let stream = phone.streams.first(where: { $0.id == id }) {
            phone.end(stream)
            phone.settle()
        }
    }

    private mutating func heardCloses() {
        for id in phone.closedByPage.dropFirst(closesHeard) where !dead.contains(id) { macStreams[id] = nil }
        closesHeard = phone.closedByPage.count
    }

    private func ping() {
        for stream in live where macStreams[stream.id] != nil { phone.ping(stream) }
        phone.settle()
    }

    private static func describe(_ request: PhoneScript.Request) -> String {
        request.act.map { "the page's \($0)" } ?? "the page's \(request.path)"
    }

    private static func describe(_ reply: PhoneScript.Reply) -> String {
        switch reply {
        case .status(let status): return "\(status)"
        case .json: return "200"
        case .stream: return "a stream"
        case .unreachable: return "nothing"
        }
    }
}
