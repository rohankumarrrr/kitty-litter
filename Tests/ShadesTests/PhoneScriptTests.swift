@testable import Shades
import ShadesCore
import XCTest

@MainActor
final class PhoneScriptTests: XCTestCase {
    private let steve = Kitten(name: "Steve Pawsniak", role: "Professional", covers: "", folder: "/k/steve")
    private let noon = Date(timeIntervalSince1970: 1_000_000)
    private let gone = "That's changed since. Have another look."
    private let unreachable = "Can't reach your Mac. The Kitty Litter has to be running, and your Mac awake."

    private var threadKey: String { PhonePlace.key(.thread("a", in: .channel(.of(steve)))) }

    private func book() -> ChannelBook {
        ChannelBook.build(
            kittens: [steve],
            threads: [AgentThread(id: "a", title: "Work", projectTitle: steve.name, status: .completed, model: "m", updatedAt: noon, projectPath: steve.folder)],
            transcripts: ["a": [Exchange(id: "e1", asker: .you, askedAt: noon, ask: "How's it going?", reply: "Fine.", repliedAt: noon)]],
            isReading: false, unreadable: 0, cantReachT3: false
        )
    }

    private func view(_ key: String, in book: ChannelBook) -> String {
        String(decoding: (try? JSONEncoder().encode(PhoneView(PhonePlace(key, in: book), in: book, now: noon))) ?? Data(), as: UTF8.self)
    }

    private func mac(_ book: ChannelBook, refusing: @escaping () -> Bool = { false }, holding: @escaping () -> Bool = { false }, here: @escaping () -> Bool = { true }) -> (PhoneScript.Request) -> PhoneScript.Reply? {
        { [unowned self] request in
            guard here() else { return .unreachable }
            guard !holding() || request.path != "/act" else { return nil }
            switch request.path {
            case "/hello":
                return .status(request.headers["Authorization"] == "Bearer \(PhoneScript.pass)" ? 204 : 401)
            case "/events":
                return .stream(view(request.query["key"] ?? PhonePlace.home, in: book))
            case "/act":
                guard let ask = try? JSONDecoder().decode(PhoneAsk.self, from: Data(request.body.utf8)), !refusing(),
                      let done = ask.action(in: book, newTopic: { "topic-1" }) else { return .status(409) }
                return .json(done.opens.map { ["open": $0] } ?? [:])
            default:
                return nil
            }
        }
    }

    func testThePagesOwnScriptRunsAgainstAStandInMac() {
        let book = book()
        let phone = PhoneScript(at: threadKey)
        phone.mac = mac(book)
        phone.settle()
        XCTAssertEqual(phone.errors, [])
        XCTAssertEqual(phone.key, threadKey)
        XCTAssertEqual(phone.read("[...document.querySelectorAll('.msg .bubble')].map((node) => node.textContent)") as? [String], ["How's it going?", "Fine."])
        XCTAssertEqual(phone.requests.map(\.path), ["/hello", "/events", "/act"], "it says hello, looks, and marks the thread seen")
        XCTAssertEqual(phone.requests.last?.act, "seen")
    }

    func testOnlyWhatYouDoTakesAnErrorAway() throws {
        let book = book()
        var refusing = false
        var holding = false
        var here = true
        let phone = PhoneScript(at: threadKey)
        phone.mac = mac(book, refusing: { refusing }, holding: { holding }, here: { here })
        phone.settle()

        refusing = true
        phone.type("Ship it", into: "#words")
        phone.tap("#send")
        XCTAssertEqual(phone.text("banner"), gone)
        refusing = false
        holding = true
        let stream = try XCTUnwrap(phone.streams.last)
        phone.send(view(threadKey, in: book), on: stream)
        phone.settle()
        XCTAssertEqual(phone.text("banner"), gone, "what the Mac sends doesn't take it away")
        XCTAssertEqual(phone.pending.last?.act, "seen", "the page marks what came in seen by itself")
        holding = false
        phone.settle()
        XCTAssertEqual(phone.text("banner"), gone, "and that doesn't take it away either")

        here = false
        phone.end(stream)
        phone.settle()
        XCTAssertEqual(phone.text("banner"), unreachable)
        let writes = phone.read("document.getElementById('banner').textWrites") as? Int
        phone.advance(30)
        XCTAssertGreaterThan(phone.requests.filter { $0.path == "/hello" }.count, 3, "it keeps trying")
        XCTAssertEqual(phone.read("document.getElementById('banner').textWrites") as? Int, writes, "without saying it again each time, which VoiceOver would read out")

        here = true
        phone.advance(5)
        XCTAssertEqual(phone.text("banner"), "", "until the Mac answers")

        refusing = true
        phone.tap("#send")
        XCTAssertEqual(phone.text("banner"), gone)
        refusing = false
        phone.tap("#send")
        XCTAssertEqual(phone.text("banner"), "", "and what you do that works takes it away")
        XCTAssertEqual(phone.errors, [])
    }
}
