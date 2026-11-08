import AppKit
@testable import Shades
import ShadesCore
import XCTest

@MainActor
final class MarkupTests: XCTestCase {
    private let pullURL = "https://github.com/example/kittens/pull/31"

    private var formatted: String {
        """
        Merged: \(pullURL)

        - one
        - two with `code`
          1. nested

        > quoted

        | Name | State |
        | --- | --- |
        | a \\| b | *open* |

        ```swift
        let x = 1

        print(x)
        ```

        ---
        """
    }

    func testBlocksComeThroughAsWritten() {
        let markup = Markup(formatted)
        XCTAssertEqual(markup.blocks.map(\.kind), [.paragraph, .item, .item, .item, .quote, .table, .code, .rule])
        XCTAssertEqual(markup.blocks[1].marker, "•")
        XCTAssertEqual(markup.blocks[2].spans?.map(\.text), ["two with ", "code"])
        XCTAssertEqual(markup.blocks[2].spans?.last?.code, true)
        XCTAssertEqual(markup.blocks[3].marker, "1.")
        XCTAssertEqual(markup.blocks[3].depth, 2)
        XCTAssertEqual(markup.blocks[5].rows?.map { $0.map { $0.map(\.text).joined() } }, [["Name", "State"], ["a | b", "open"]])
        XCTAssertEqual(markup.blocks[6].code, "let x = 1\n\nprint(x)", "without the newline that ends it")
    }

    func testALineBreakStaysOne() {
        XCTAssertEqual(Markup("Fixed.\nIt's in review.").blocks.first?.spans?.map(\.text).joined(), "Fixed.\nIt's in review.")
    }

    func testOnlyWebAddressesAreLinks() {
        let markup = Markup("[a](https://example.com/a) [b](http://example.com/b) [c](javascript:alert(1)) [d](file:///etc/hosts) [e](shortcuts://run-shortcut?name=x) [f](t3code://threads/x) <mailto:a@example.com>")
        let spans = markup.blocks.flatMap { $0.spans ?? [] }
        XCTAssertEqual(spans.compactMap(\.link).map(\.absoluteString), ["https://example.com/a", "http://example.com/b"])
        for words in ["c", "d", "e", "f"] {
            XCTAssertTrue(spans.contains { $0.text == words && $0.link == nil }, "\(words) is only words")
        }
    }

    func testAPictureIsOnlyItsWords() {
        let spans = Markup("![the chart](https://example.com/chart.png?secret=1)").blocks.flatMap { $0.spans ?? [] }
        XCTAssertEqual(spans.map(\.text), ["the chart"])
        XCTAssertNil(spans.first?.link, "nothing loads it, and nothing links to it")
    }

    func testAPullRequestLinkIsAChipWithTheStateT3Has() throws {
        let known = try XCTUnwrap(Markup(formatted, pulls: ["example/kittens#31": "merged"]).blocks.first?.spans?.last)
        XCTAssertEqual(known.text, "kittens #31", "a bare address reads as the pull request")
        XCTAssertEqual(known.pull, Markup.Pull(state: "merged"))
        XCTAssertEqual(known.link?.absoluteString, pullURL)

        let unknown = try XCTUnwrap(Markup(formatted).blocks.first?.spans?.last)
        XCTAssertEqual(unknown.pull, Markup.Pull(state: nil), "still a chip, with no state, since nothing goes looking")

        let labelled = try XCTUnwrap(Markup("See [the fix](\(pullURL)).").blocks.first?.spans?.first { $0.link != nil })
        XCTAssertEqual(labelled.text, "the fix", "words someone chose stay theirs")
        XCTAssertNil(Markup("[x](https://example.com/o/r/pull/31)").blocks.first?.spans?.first?.pull, "only GitHub's")
    }

    func testABookKnowsEachPullRequestsState() {
        let thread = AgentThread(id: "t", title: "Work", projectTitle: "Steve", status: .completed, model: "m", updatedAt: Date(), pullRequest: ThreadPullRequest(number: 31, state: "open", url: "https://github.com/Example/Kittens/pull/31"))
        let book = ChannelBook.build(kittens: [], threads: [thread], transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false)
        XCTAssertEqual(book.pulls, ["example/kittens#31": "open"])
    }

    func testFormattedWordsLayOutAndCanBeCut() {
        let block = ChannelTextBlock(ChannelMarkdown.attributed(formatted, pulls: ["example/kittens#31": "merged"]))
        let full = block.fit(width: 400)
        XCTAssertFalse(block.isCut)
        XCTAssertEqual(block.width, 400, "code and tables take the whole width")
        XCTAssertEqual(block.codeBlocks.map(\.code), ["let x = 1\n\nprint(x)"])
        let cut = block.fit(width: 400, maxLines: 4)
        XCTAssertTrue(block.isCut)
        XCTAssertLessThan(cut, full)
    }

    func testFormattedWordsLayOutAtAnyWidth() {
        for width in stride(from: CGFloat(60), through: 400, by: 10) {
            let block = ChannelTextBlock(ChannelMarkdown.attributed(formatted))
            XCTAssertGreaterThan(block.fit(width: width, maxLines: 12), 0, "\(width)")
            XCTAssertGreaterThan(block.fit(width: width), 0, "\(width)")
        }
    }

    func testTheMacDrawsBlocksChipsAndLinks() throws {
        let text = ChannelMarkdown.attributed(formatted, pulls: ["example/kittens#31": "merged"])
        XCTAssertTrue(text.string.hasPrefix("Merged: \u{00A0}kittens\u{00A0}#31\u{00A0}·\u{00A0}merged\u{00A0}\n•\tone\n•\ttwo with code\n1.\tnested"), text.string)
        let chip = (text.string as NSString).range(of: "kittens")
        XCTAssertEqual((text.attribute(.link, at: chip.location, effectiveRange: nil) as? URL)?.absoluteString, pullURL)
        XCTAssertEqual(text.attribute(.channelChip, at: chip.location, effectiveRange: nil) as? NSColor, ChannelMarkdown.chipColor("merged"))
        let code = (text.string as NSString).range(of: "print(x)")
        XCTAssertEqual((text.attribute(.channelCode, at: code.location, effectiveRange: nil) as? ChannelCode)?.text, "let x = 1\n\nprint(x)")
        let font = try XCTUnwrap(text.attribute(.font, at: code.location, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(font.isFixedPitch)
    }
}
