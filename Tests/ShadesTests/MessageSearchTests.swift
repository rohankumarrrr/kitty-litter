import AppKit
@testable import Shades
import ShadesCore
import XCTest

/// ⌘F and the phone's Search, over a book worked out the way Messages works it out.
@MainActor
final class MessageSearchTests: XCTestCase {
    private let steve = Kitten(name: "Steve", role: "Professional", covers: "", folder: "/k/steve")
    private let at = Date(timeIntervalSince1970: 1_000_000)

    private func thread(_ id: String, title: String = "Work", project: String = "/k/steve") -> AgentThread {
        AgentThread(id: id, title: title, projectTitle: "Steve", status: .completed, model: "m", updatedAt: at, projectPath: project)
    }

    private func book(_ said: [String: [Exchange]], talks: [String] = [], sent: [SentMessage] = []) -> ChannelBook {
        ChannelBook.build(
            kittens: [steve],
            threads: said.keys.sorted().map { talks.contains($0) ? thread($0, title: "Question", project: "/shades/router") : thread($0) },
            transcripts: said,
            isReading: false, unreadable: 0, cantReachT3: false,
            sent: sent,
            withShades: Set(talks)
        )
    }

    private func exchange(_ id: String, ask: String, reply: String, minutes: TimeInterval) -> Exchange {
        Exchange(id: id, asker: .you, askedAt: at.addingTimeInterval(minutes * 60), ask: ask, reply: reply, repliedAt: at.addingTimeInterval(minutes * 60 + 1))
    }

    func testItFindsTheWordsAMessageShowsNotTheMarkdownTheyWereWrittenIn() throws {
        let reply = "I'd use **Silkscreen**. See [the billing page](https://example.com/billing), and https://github.com/example/kittens/pull/31 is merged."
        let book = book(["a": [exchange("e1", ask: "Which font?", reply: reply, minutes: 0)]])

        let found = try XCTUnwrap(MessageSearch.find("silkscreen", in: book, limit: 8).found.first)
        XCTAssertEqual(found.message.id, "e1:reply")
        XCTAssertFalse(found.snippet.contains("*"), "it shows the words as Messages draws them")
        let marked = (found.snippet as NSString).substring(with: try XCTUnwrap(found.marks.first))
        XCTAssertEqual(marked, "Silkscreen")
        XCTAssertEqual(MessageSearch.find("billing page", in: book, limit: 8).found.count, 1)
        XCTAssertEqual(MessageSearch.find("kittens #31", in: book, limit: 8).found.count, 1, "a pull request's chip is found by what it says")

        XCTAssertTrue(MessageSearch.find("**Silkscreen**", in: book, limit: 8).found.isEmpty, "not the markdown")
        XCTAssertTrue(MessageSearch.find("example.com", in: book, limit: 8).found.isEmpty, "nor where a link with words of its own goes")
        XCTAssertTrue(MessageSearch.find("pull/31", in: book, limit: 8).found.isEmpty)
    }

    func testEveryWordHasToBeThereInAnyCaseAndTheNewestComeFirst() {
        let book = book([
            "a": [exchange("old", ask: "Is the café open?", reply: "Yes, till six.", minutes: 0)],
            "b": [exchange("new", ask: "Did the cafe menu change?", reply: "Only the prices.", minutes: 10)],
        ])
        XCTAssertEqual(MessageSearch.find("CAFE", in: book, limit: 8).found.map(\.message.id), ["new:ask", "old:ask"], "accents and case don't matter")
        XCTAssertEqual(MessageSearch.find("cafe menu", in: book, limit: 8).found.map(\.message.id), ["new:ask"], "every word")
        XCTAssertEqual(MessageSearch.find("menu cafe", in: book, limit: 8).found.map(\.message.id), ["new:ask"], "in any order")

        let one = MessageSearch.find("cafe", in: book, limit: 1)
        XCTAssertEqual(one.found.map(\.message.id), ["new:ask"])
        XCTAssertTrue(one.more, "it says when there are more than it shows")
        XCTAssertFalse(MessageSearch.find("cafe", in: book, limit: 2).more)
        XCTAssertTrue(MessageSearch.find("c", in: book, limit: 8).found.isEmpty, "one letter isn't a search yet")
    }

    func testAThreadsMessageOpensInItsThreadAndALooseOneInItsChannel() throws {
        let loose = ChannelMessage(exchangeID: "sent-1", kind: .ask, speaker: .you, text: "Remind me about the invoice", at: at, threadID: "", threadTitle: "")
        let book = book(["a": [exchange("e1", ask: "Tidy the invoice template", reply: "Done.", minutes: 0)]], sent: [SentMessage(channel: .general, message: loose)])
        let found = MessageSearch.find("invoice", in: book, limit: 8).found
        XCTAssertEqual(found.map(\.message.id), ["sent-1:ask", "e1:ask"])
        XCTAssertEqual(found.map(\.selection), [.channel(.general), .thread("a", in: .channel(.of(steve)))])
    }

    func testALongSnippetStartsNearTheWordsAndSaysWhereItsCut() throws {
        let filler = Array(repeating: "Nothing else on the page changed.", count: 8).joined(separator: " ")
        let book = book(["a": [exchange("e1", ask: "How did it go?", reply: "\(filler) The coupon box moved. \(filler)", minutes: 0)]])
        let found = try XCTUnwrap(MessageSearch.find("coupon", in: book, limit: 8).found.first)
        XCTAssertTrue(found.snippet.hasPrefix("…") && found.snippet.hasSuffix("…"))
        XCTAssertLessThan(found.snippet.count, 150)
        XCTAssertTrue(found.snippet.contains("The coupon box moved."))
    }

    func testAPhoneOnlyFindsWhatItCanOpenAndNeverTheCatsDM() throws {
        let book = book([
            "a": [exchange("e1", ask: "Which plan is cheapest?", reply: "Starter.", minutes: 0)],
            "r": [exchange("e2", ask: "Which plan is cheapest here?", reply: "Pro, on this page.", minutes: 5)],
        ], talks: ["r"])
        XCTAssertEqual(MessageSearch.find("cheapest", in: book, limit: 8).found.map(\.message.id), ["e2:ask", "e1:ask"], "the window shows the DM")

        let phone = PhoneFound("cheapest", in: book, now: at)
        XCTAssertEqual(phone.found.map(\.id), ["e1:ask"], "what you asked the cat can be about your screen, so it stays on the Mac")
        let hit = try XCTUnwrap(phone.found.first)
        XCTAssertEqual(hit.open, PhonePlace.key(.thread("a", in: .channel(.of(steve)))))
        XCTAssertEqual(PhonePlace(hit.open, in: book).selection, .thread("a", in: .channel(.of(steve))), "it opens where the phone can go")
        XCTAssertEqual(hit.marks, [[14, 8]], "where \"cheapest\" is, as a page counts")
        XCTAssertEqual(hit.name, CatWords.you)
    }
}
