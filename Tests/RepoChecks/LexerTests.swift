import XCTest

final class LexerTests: XCTestCase {
    func testSlashesInsideStringsRegexesAndInterpolationsAreNotComments() {
        let source = [
            #"let link = "https://example.com" // one"#,
            #"let nested = "a \(flag ? "//b" : "c") d" /* two */"#,
            ##"let raw = #"say "//" here"#"##,
            ##"let pattern = #/t3-thread://v2/[^/]+/#"##,
            #"let glob = "~/.claude/projects/**/*.jsonl""#,
            "/* three /* nested */ still three */",
        ].joined(separator: "\n")
        XCTAssertEqual(SwiftLexer(source).comments.map(\.text), ["// one", "/* two */", "/* three /* nested */ still three */"])
        XCTAssertEqual(SwiftLexer(source).comments.map(\.line), [1, 2, 6])
    }

    func testAShebangIsNotAComment() {
        XCTAssertEqual(SwiftLexer("#!/usr/bin/env swift\nprint(1)\n").comments, [])
    }

    func testCommentsInEmbeddedCodeAreFoundAtTheStartOfALine() {
        let source = [
            #"let page = """"#,
            "  <style>",
            "  /* css */",
            "  </style>",
            "  <!-- html -->",
            "  // script",
            #"  let url = "https://example.com";"#,
            #"  """"#,
        ].joined(separator: "\n")
        XCTAssertEqual(SwiftLexer(source).commentsInsideMultilineStrings.map(\.text), ["/* css */", "<!-- html -->", "// script"])
        XCTAssertEqual(SwiftLexer(source).commentsInsideMultilineStrings.map(\.line), [3, 5, 6])
        XCTAssertEqual(SwiftLexer(source).comments, [])
    }

    func testTakingCommentsOutLeavesTheCodeAndEveryLiteralExactlyAsItWas() {
        let before = "let a = 1 // one\n\n/// two\nlet b = \"  spaced  \"\n"
        let after = "let a = 1\nlet b = \"  spaced  \"\n"
        let changedLiteral = "let a = 1\nlet b = \" spaced \"\n"
        XCTAssertEqual(SwiftLexer(before).codeWithoutComments, SwiftLexer(after).codeWithoutComments)
        XCTAssertNotEqual(SwiftLexer(before).codeWithoutComments, SwiftLexer(changedLiteral).codeWithoutComments)
    }

    func testShellCommentsSkipQuotesCountsAndHeredocs() {
        let source = """
        #!/bin/zsh
        # one
        echo "# not" '# not' $# ${#name} a#b # two
        cat <<EOF
        # inside a heredoc
        EOF
        echo done
        """
        XCTAssertEqual(ShellLexer(source).comments.map(\.text), ["# one", "# two"])
        XCTAssertEqual(ShellLexer(source).comments.map(\.line), [2, 3])
    }

    func testMatchesSayTheirLineAndLookOnlyWhereTheyreAsked() throws {
        let source = [
            #"let a = "0x111111""#,
            "let b = 0x222222 /* 0x333333 */",
            ##"let c = "#444444""##,
        ].joined(separator: "\n")
        let hex = try NSRegularExpression(pattern: "0x[0-9a-f]{6}|#[0-9a-f]{6}")
        XCTAssertEqual(SwiftLexer(source).matches(of: hex, in: .code), [Match(line: 2, text: "0x222222")])
        XCTAssertEqual(SwiftLexer(source).matches(of: hex, in: .literal).map(\.line), [1, 3])
    }
}
