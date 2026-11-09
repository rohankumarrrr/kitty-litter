@testable import ShadesT3
import XCTest

final class T3CredentialsTests: XCTestCase {
    func testMemoryStoreRoundTrip() {
        let store = MemoryCredentialStore()
        XCTAssertNil(store.load())
        store.save(T3Credential(sessionID: "s", token: "t"))
        XCTAssertEqual(store.load(), T3Credential(sessionID: "s", token: "t"))
        store.delete(sessionID: "other")
        XCTAssertNotNil(store.load())
        store.delete(sessionID: "s")
        XCTAssertNil(store.load())
    }

    /// Uses a throwaway entry, made and removed by the same binary, so it can't show a dialog.
    func testKeychainRoundTrip() throws {
        let store = KeychainCredentialStore(service: "dev.shades.t3-session.test.\(UUID().uuidString)")
        let credential = T3Credential(sessionID: "session-1", token: "not-a-real-token")
        do {
            XCTAssertNil(try store.load())
            try store.save(credential)
        } catch T3Error.keychain(let status) {
            throw XCTSkip("No usable login Keychain here (\(status))")
        }
        defer { try? store.delete(sessionID: credential.sessionID) }

        XCTAssertEqual(try store.load(), credential)
        XCTAssertNil(try store.newestUnreadableSessionID())

        try store.delete(sessionID: credential.sessionID)
        XCTAssertNil(try store.load())
        XCTAssertNoThrow(try store.delete(sessionID: credential.sessionID), "Deleting nothing is fine")
    }

    func testErrorsSpeakPlainly() {
        XCTAssertEqual(T3Error.notRunning.errorDescription, "I can't reach T3 Code. Open it and try again.")
        XCTAssertEqual(T3Error.incompatibleServer(version: "9.9.9").errorDescription, "I can't work with T3 Code 9.9.9 yet. Check for an update to The Kitty Litter.")
        XCTAssertEqual(T3Error.incompatibleServer(version: nil).errorDescription, "I can't work with this version of T3 Code yet. Check for an update to The Kitty Litter.")
        XCTAssertEqual(T3Error.signInFailed.errorDescription, "I couldn't sign in to T3 Code. Quit and reopen it, then try again.")
        XCTAssertEqual(T3Error.connectionLost.errorDescription, "I lost the connection to T3 Code. Make sure it's open, then try again.")
        XCTAssertEqual(T3Error.timedOut.errorDescription, "T3 Code took too long to answer. Try again in a moment.")
    }
}
