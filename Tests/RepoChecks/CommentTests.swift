import XCTest

final class CommentTests: XCTestCase {
    static let outsideNote = "Outside the repo: "
    static let allowedOpenings = ["// ", "/* ", "# "].map { $0 + outsideNote }

    func testNothingInTheCodeIsAComment() throws {
        for file in try Repo.files(under: ["Sources", "Tests", "scripts", "Package.swift"], endingIn: [".swift", ".sh"]) {
            for comment in try Self.comments(in: file) where !Self.allowed(comment, in: file) {
                XCTFail("""
                \(file):\(comment.line) has a comment: \(comment.text.prefix(80))
                Say it in a name, a type, a test or the commit message instead. Only a note on how something \
                outside this repo behaves, which the code can't change, stays, as one line starting \
                "// \(Self.outsideNote)".
                """)
            }
        }
    }

    static func comments(in file: String) throws -> [SourceComment] {
        let source = try Repo.read(file)
        if file.hasSuffix(".sh") { return ShellLexer(source).comments }
        let lexed = SwiftLexer(source)
        return lexed.comments + lexed.commentsInsideMultilineStrings
    }

    static func allowed(_ comment: SourceComment, in file: String) -> Bool {
        if file == "Package.swift", comment.line == 1, comment.text.hasPrefix("// swift-tools-version:") { return true }
        return allowedOpenings.contains { comment.text.hasPrefix($0) }
    }
}
