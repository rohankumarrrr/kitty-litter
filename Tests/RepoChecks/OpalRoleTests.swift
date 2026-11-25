import XCTest

final class OpalRoleTests: XCTestCase {
    static let designSystem: Set<String> = [
        "Sources/Shades/UI/Opal.swift",
        "Sources/Shades/UI/OpalLight.swift",
        "Sources/Shades/UI/MessagesInk.swift",
    ]

    static let ownLooksInCode = [
        #"\b0x[0-9a-fA-F]{6}\b"#,
        #"NSColor\((srgbRed|red|white|calibratedRed|calibratedWhite|deviceRed|deviceWhite|displayP3Red|hue|cgColor):"#,
        #"NSColor\.(?!clear\b)[a-z]\w*"#,
        #"\bofSize: *[0-9]+(\.[0-9]+)? *[,)]"#,
    ]

    static let ownLooksInText = #"#[0-9a-fA-F]{3,8}\b"#

    static let ownLooksLeft: [String: Int] = [
        "Sources/Shades/Cat/CatArt.swift": 18,
        "Sources/Shades/Demo/Demo.swift": 4,
        "Sources/Shades/Demo/DemoPhone.swift": 3,
        "Sources/Shades/Demo/DemoPicture.swift": 2,
        "Sources/Shades/Demo/DemoRecorder.swift": 16,
        "Sources/Shades/Demo/OpalSheet.swift": 7,
        "Sources/Shades/Phone/PhonePage.swift": 9,
    ]

    func testEverythingDrawnTakesItsColoursAndSizesFromOpal() throws {
        let inCode = try NSRegularExpression(pattern: Self.ownLooksInCode.joined(separator: "|"))
        let inText = try NSRegularExpression(pattern: Self.ownLooksInText)
        var found: [String: [Match]] = [:]
        for file in try Repo.files(under: ["Sources/Shades", "Sources/ShadesContext"], endingIn: [".swift"])
        where !Self.designSystem.contains(file) {
            let lexed = SwiftLexer(try Repo.read(file))
            found[file] = (lexed.matches(of: inCode, in: .code) + lexed.matches(of: inText, in: .literal)).sorted { $0.line < $1.line }
        }
        Allowance(name: "OpalRoleTests.ownLooksLeft", left: Self.ownLooksLeft).check(found) { file, count, allowed in
            """
            \(file) draws with a colour or a text size of its own \(count) times, where \(allowed) are allowed. Opal is \
            the app's only look: use a role from MessagesInk, such as `MessagesInk.text` or `MessagesInk.meta`, or a \
            token from Opal.swift, and a `var(--role)` on the phone page. A new colour goes in docs/design.md, \
            Opal.swift and DesignTests first.
            """
        }
    }
}
