@testable import Shades
import ShadesCore
import XCTest

@MainActor
final class PhonePairingModelTests: XCTestCase {
    static let depth = 4

    func testEveryOrderOfCodesKeysAndAnswersKeepsAPhonePairedOnlyWhileTheMacTakesItsKey() {
        let walk = walkEveryOrder(PairingWorld.self, upTo: Self.depth)
        XCTAssertNil(walk.counterexample, walk.counterexample ?? "")
        XCTAssertGreaterThan(walk.states, 1_800, "it explored too little to mean anything")
    }

    func testACodeScannedIntoThePageAlreadyOpenPairsItAfterOneThatDidntWork() {
        var world = PairingWorld()
        for event: PairingWorld.Event in [.scanOld, .settle, .show, .scanShowing, .settle] {
            XCTAssertTrue(world.enabled(event), "\(event)")
            _ = world.apply(event)
            XCTAssertNil(world.broken(), "\(event)")
        }
        XCTAssertTrue(world.phone.isHidden("pair"), "it's paired")
        XCTAssertNil(world.finish())
    }

    func testAnOldPairingLinkLeavesAPairedPhonePaired() {
        var world = PairingWorld()
        for event: PairingWorld.Event in [.typeShowing, .settle, .scanOld, .settle] {
            XCTAssertTrue(world.enabled(event), "\(event)")
            _ = world.apply(event)
            XCTAssertNil(world.broken(), "\(event)")
        }
        XCTAssertEqual(world.phone.text("banner"), "That code didn't work, but this phone is still paired.")
        XCTAssertNil(world.finish())
    }
}

@MainActor
struct PairingWorld: PhoneModel {
    enum Event: Hashable {
        case show, scanShowing, scanOld, openShowing, typeShowing, typeWrong, forget, answer(Int), drop, settle, wait
    }

    static let events: [Event] = [.show, .scanShowing, .scanOld, .openShowing, .typeShowing, .typeWrong, .forget, .answer(0), .answer(1), .drop, .settle, .wait]
    private static let noon = Date(timeIntervalSince1970: 1_000_000)
    private static let steve = Kitten(name: "Steve Pawsniak", role: "Professional", covers: "", folder: "/k/steve")
    private static let book = ChannelBook.build(kittens: [steve], threads: [], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false)
    private static let wrong = "WXYZ-2345"
    private static let used = "HJKM-NPQR"

    private(set) var phone = PhoneScript(at: PhonePlace.home, stored: [:])
    private let keys = MemoryPhoneKeys()
    private var link: PhoneLink
    private var codes: [PhoneDoor.Pairing] = []
    private var handed: [String] = []
    private var sentToPair: [String] = []
    private var used: [Event: Int] = [:]
    private var keyBeforeStep: String?

    init() {
        link = Self.mac(keys)
        codes.append(link.door.openPairing(now: Self.noon))
        phone.settle()
    }

    private static func mac(_ keys: MemoryPhoneKeys) -> PhoneLink {
        PhoneLink(keys: keys, grace: 0, hold: { PairingWorld.book }, release: {}, act: { _ in }, sendPush: { _ in nil }, now: { PairingWorld.noon })
    }

    private var showing: PhoneDoor.Pairing? { link.door.pairing }
    private var old: String? { codes.last { $0 != showing }?.shown ?? (codes.count > 1 ? nil : Self.used) }
    private var asking: Bool { phone.read("!document.getElementById('pair').hidden") as? Bool == true }
    private var storedKey: String? { phone.stored["shades.key"] }

    private func admits(_ key: String?) -> Bool {
        guard let key else { return false }
        return link.door.admits(PhoneServer.Request(method: "GET", path: "/hello", query: [:], headers: ["authorization": "Bearer \(key)"], body: Data()))
    }

    private func count(_ event: Event) -> Int { used[event, default: 0] }

    func enabled(_ event: Event) -> Bool {
        switch event {
        case .show: return count(.show) < 1
        case .scanShowing: return showing != nil && count(.scanShowing) < 1
        case .scanOld: return old != nil && count(.scanOld) < 1
        case .openShowing: return showing != nil && count(.openShowing) < 1
        case .typeShowing: return showing != nil && asking && count(.typeShowing) < 1
        case .typeWrong: return asking && count(.typeWrong) < 1
        case .forget: return count(.forget) < 1
        case .answer(let index): return index < phone.pending.count
        case .drop: return !phone.pending.isEmpty && count(.drop) < 1
        case .settle: return !phone.pending.isEmpty
        case .wait: return phone.pending.isEmpty && phone.nextTimer != nil && count(.wait) < 1
        }
    }

    mutating func apply(_ event: Event) -> String {
        used[event, default: 0] += 1
        keyBeforeStep = storedKey
        defer { notePairs() }
        switch event {
        case .show:
            codes.append(link.door.openPairing(now: Self.noon))
            return "the Mac shows a new code"
        case .scanShowing:
            let code = showing!.shown
            handed.append(code)
            phone.scan(code)
            return "you scan the code showing into the page that's open"
        case .scanOld:
            let code = old!
            handed.append(code)
            phone.scan(code)
            return "you scan an old code into the page that's open"
        case .openShowing:
            let code = showing!.shown
            handed.append(code)
            notePairs()
            phone = PhoneScript(at: PhonePlace.home, hash: "#pair=\(code)", stored: phone.stored)
            phone.settle()
            return "you open the code showing as a new page"
        case .typeShowing:
            let code = showing!.shown
            handed.append(code)
            phone.run("document.getElementById('code').value = ''")
            phone.type(code, into: "#code")
            phone.tap("#pairform button", "Pair")
            return "you type the code showing and press Pair"
        case .typeWrong:
            phone.run("document.getElementById('code').value = ''")
            phone.type(Self.wrong, into: "#code")
            phone.tap("#pairform button", "Pair")
            return "you type a wrong code and press Pair"
        case .forget:
            keys.saved = [:]
            for stream in phone.streams { phone.end(stream) }
            link = Self.mac(keys)
            phone.settle()
            return "the Mac restarts as a build that can't read its pairing, so it forgets this phone"
        case .answer(let index):
            let request = phone.pending[index]
            let reply = reply(to: request)
            phone.answer(request, reply)
            phone.settle()
            return "the Mac answers the page's \(request.path) with \(Self.describe(reply))"
        case .drop:
            let request = phone.pending[0]
            phone.answer(request, .unreachable)
            phone.settle()
            return "the page's \(request.path) doesn't get through"
        case .settle:
            answerEverything()
            return "the Mac answers everything waiting, in order"
        case .wait:
            let before = phone.clock
            if let next = phone.nextTimer { phone.advance((next - before) / 1000) }
            return "\(Int((phone.clock - before) / 1000)) seconds pass"
        }
    }

    var fingerprint: String {
        let pending = phone.pending.map { "\($0.path) \(label($0.json["code"] as? String))" }
        let page = phone.read("""
            [location.hash.includes('pair='), $('pair').hidden, $('pairnote').textContent, $('banner').textContent, $('top').hidden, $('rows').hidden,
             $('found').hidden, $('found').childElementCount, key, pass === null ? 'none' : 'some', stream !== null].join(',')
            """) as? String ?? ""
        let key = storedKey.map { admits($0) ? "admitted" : "refused" } ?? "none"
        let door = "\(label(showing?.shown)) \(codes.count) \(keys.hashes.count)"
        return [pending.joined(separator: ";"), page, key, door, handed.map(label).joined(separator: ","),
                Self.events.map { "\(count($0))" }.joined(separator: ","), phone.timers].joined(separator: "\n")
    }

    func broken() -> String? {
        if let error = phone.errors.first { return "the page threw \(error)" }
        if admits(keyBeforeStep), !admits(storedKey) { return "the page lost a key the Mac takes" }
        if asking, let shown = phone.read("['top', 'head', 'rows', 'box', 'search', 'found'].filter((id) => !$(id).hidden)") as? [String], !shown.isEmpty {
            return "the page asks for a code with \(shown) still showing"
        }
        if phone.read("location.hash.includes('pair=')") as? Bool == true, phone.pending.isEmpty, phone.timersDue == 0 {
            return "the code stays in the page's address"
        }
        return nil
    }

    mutating func finish() -> String? {
        let keptBefore = admits(storedKey)
        for _ in 0..<20 {
            answerEverything()
            guard let next = phone.nextTimer, next <= phone.clock + 30_000 else { break }
            phone.advance((next - phone.clock) / 1000)
        }
        if let problem = broken() { return problem }
        if keptBefore, !admits(storedKey) { return "the page lost a key the Mac takes" }
        for code in handed where !sentToPair.contains(code) { return "you gave the page \(label(code)), and it never sent it to the Mac" }
        if admits(storedKey) {
            if asking { return "the page asks for a code with a key the Mac takes" }
            if phone.isHidden("rows") { return "the page doesn't show the places with a key the Mac takes" }
            if !phone.text("banner").isEmpty, phone.text("banner") != "That code didn't work, but this phone is still paired." { return "the page says \"\(phone.text("banner"))\"" }
        } else {
            if storedKey != nil { return "the page keeps a key the Mac refuses" }
            if !asking { return "the page shows the places with no key the Mac takes" }
        }
        return nil
    }

    private mutating func answerEverything() {
        while let request = phone.pending.first {
            phone.answer(request, reply(to: request))
            phone.settle()
            notePairs()
        }
    }

    private mutating func notePairs() {
        for request in phone.requests where request.path == "/pair" {
            if let code = request.json["code"] as? String, !sentToPair.contains(code) { sentToPair.append(code) }
        }
    }

    private func reply(to request: PhoneScript.Request) -> PhoneScript.Reply {
        let headers = Dictionary(request.headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
        let answer = link.respond(to: PhoneServer.Request(method: request.method, path: request.path, query: request.query, headers: headers, body: Data(request.body.utf8)))
        switch answer {
        case .stream:
            let view = PhoneView(PhonePlace(request.query["key"] ?? PhonePlace.home, in: Self.book), in: Self.book, now: Self.noon)
            return .stream(String(decoding: (try? JSONEncoder().encode(view)) ?? Data(), as: UTF8.self))
        case .full(let status, _, let body):
            guard status == 200, let json = try? JSONSerialization.jsonObject(with: body) else { return .status(status) }
            return .json(json)
        }
    }

    private func label(_ code: String?) -> String {
        guard let code else { return "nothing" }
        if code == Self.wrong { return "a wrong code" }
        if code == Self.used { return "a code from before" }
        guard let index = codes.firstIndex(where: { $0.shown == code }) else { return "a code" }
        return code == showing?.shown ? "code \(index + 1), showing" : "code \(index + 1), used or replaced"
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
