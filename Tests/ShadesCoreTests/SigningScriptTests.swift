import Foundation
import XCTest

/// Runs the signing choices scripts/bundle.sh and scripts/install.sh make, on output shaped like macOS's own.
final class SigningScriptTests: XCTestCase {
    private var script: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/signing.sh")
    }

    private func run(_ function: String, _ arguments: String...) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-f", "-c", #"set -euo pipefail; source "$1"; shift; "$@""#, "zsh", script.path, function] + arguments
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines))
    }

    // MARK: Which certificate bundle.sh signs with

    private static let selfSigned = #"  1) 3333333333333333333333333333333333333333 "Shades Dev""#
    private static let development = #"  2) 1111111111111111111111111111111111111111 "Apple Development: Jane Appleseed (AB12CD34EF)""#
    private static let developerID = #"  3) 2222222222222222222222222222222222222222 "Developer ID Application: Jane Appleseed (TEAM111111)""#

    private func identities(_ lines: String...) -> String {
        (lines + ["     \(lines.count) valid identities found"]).joined(separator: "\n")
    }

    func testAnAppleDevelopmentCertificateWinsOverShadesDev() throws {
        let picked = try run("signing_identity", identities(Self.selfSigned, Self.development))
        XCTAssertEqual(picked.output, "1111111111111111111111111111111111111111")
    }

    func testADeveloperIDCertificateWinsOverShadesDevToo() throws {
        let picked = try run("signing_identity", identities(Self.selfSigned, Self.developerID))
        XCTAssertEqual(picked.output, "2222222222222222222222222222222222222222")
    }

    func testShadesDevIsLeftForAnyoneWithoutATeam() throws {
        let picked = try run("signing_identity", identities(Self.selfSigned))
        XCTAssertEqual(picked.output, "3333333333333333333333333333333333333333")
    }

    func testNoCertificateMeansAdHoc() throws {
        let picked = try run("signing_identity", "     0 valid identities found")
        XCTAssertEqual(picked.status, 0)
        XCTAssertEqual(picked.output, "")
    }

    // MARK: What install.sh lets replace the installed copy

    private func signed(by authority: String, team: String) -> String {
        """
        Executable=/Applications/Shades.app/Contents/MacOS/Shades
        Identifier=me.rohan-is.shades
        Format=app bundle with Mach-O thin (arm64)
        CodeDirectory v=20400 size=56907 flags=0x0(none) hashes=1772+3 location=embedded
        Signature size=4790
        Authority=\(authority)
        Info.plist entries=13
        TeamIdentifier=\(team)
        Sealed Resources version=2 rules=13 files=4
        """
    }

    private var teamA: String { signed(by: "Apple Development: Jane Appleseed (AB12CD34EF)", team: "TEAM111111") }
    private var teamB: String { signed(by: "Apple Development: Jane Appleseed (ZY98XW76VU)", team: "TEAM222222") }
    private var shadesDev: String { signed(by: "Shades Dev", team: "not set") }
    private let adHoc = """
        Executable=/Applications/Shades.app/Contents/MacOS/Shades
        Identifier=me.rohan-is.shades
        Format=app bundle with Mach-O thin (arm64)
        CodeDirectory v=20400 size=56907 flags=0x2(adhoc) hashes=1772+3 location=embedded
        Signature=adhoc
        Info.plist entries=13
        TeamIdentifier=not set
        """

    func testTheSameTeamReplacesItsOwnBuild() throws {
        XCTAssertEqual(try run("may_replace", teamA, teamA).status, 0)
    }

    func testAnotherTeamIsRefused() throws {
        let refused = try run("may_replace", teamB, teamA)
        XCTAssertEqual(refused.status, 1)
        XCTAssertTrue(refused.output.contains("--change-team"))
        XCTAssertFalse(refused.output.contains("TEAM"), "the message doesn't print anyone's Team ID")
    }

    func testABuildWithoutATeamCantReplaceOneWithATeam() throws {
        XCTAssertEqual(try run("may_replace", shadesDev, teamA).status, 1)
    }

    func testChangingTeamIsAllowedWhenAskedFor() throws {
        XCTAssertEqual(try run("may_replace", teamB, teamA, "--change-team").status, 0)
        XCTAssertEqual(try run("may_replace", shadesDev, teamA, "--change-team").status, 0)
    }

    func testTheFirstMoveOntoATeamNeedsNoFlag() throws {
        XCTAssertEqual(try run("may_replace", teamA, shadesDev).status, 0, "from Shades Dev")
        XCTAssertEqual(try run("may_replace", teamA, adHoc).status, 0, "from ad hoc")
        XCTAssertEqual(try run("may_replace", teamA, "").status, 0, "onto a Mac without the app")
    }

    func testShadesDevStillReplacesShadesDev() throws {
        XCTAssertEqual(try run("may_replace", shadesDev, shadesDev).status, 0)
    }

    func testAdHocIsStillRefused() throws {
        let refused = try run("may_replace", adHoc, shadesDev)
        XCTAssertEqual(refused.status, 1)
        XCTAssertTrue(refused.output.contains("--ad-hoc"))
        XCTAssertEqual(try run("may_replace", adHoc, "").status, 1, "even with nothing installed")
        XCTAssertEqual(try run("may_replace", adHoc, shadesDev, "--ad-hoc").status, 0)
    }

    func testAdHocOverATeamTakesBothFlags() throws {
        XCTAssertEqual(try run("may_replace", adHoc, teamA, "--ad-hoc").status, 1)
        XCTAssertEqual(try run("may_replace", adHoc, teamA, "--change-team").status, 1)
        XCTAssertEqual(try run("may_replace", adHoc, teamA, "--ad-hoc", "--change-team").status, 0)
    }
}
