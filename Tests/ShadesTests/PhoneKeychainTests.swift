import CryptoKit
@testable import Shades
import XCTest

/// The phone keys over what earlier builds left in the Keychain, with the Keychain stood in for, so nothing here
/// touches it.
@MainActor
final class PhoneKeychainTests: XCTestCase {
    /// The login Keychain as builds signed with one certificate see it: each reads what any of them saved, newest first,
    /// but deleting one another build saved shows a dialog and waits on it, on the main thread, which `prompts` counts.
    final class Keychain: PhoneKeychain {
        var build: String
        private var stored: [(account: String, data: Data, build: String)]
        private(set) var added: [String] = []
        private(set) var prompts: [String] = []

        init(build: String, items: [(String, [String], String)]) {
            self.build = build
            stored = items.map { ($0.0, Data($0.1.joined(separator: "\n").utf8), $0.2) }
        }

        func items() -> [(account: String, data: Data?)] { stored.reversed().map { ($0.account, $0.data) } }

        func add(account: String, data: Data, label: String) -> Bool {
            stored.append((account, data, build))
            added.append(account)
            return true
        }

        func delete(account: String) {
            if stored.contains(where: { $0.account == account && $0.build != build }) { prompts.append(account) }
            stored.removeAll { $0.account == account }
        }
    }

    private let subscription = WebPush.Subscription(endpoint: "https://web.push.apple.com/a-phone", p256dh: WebPush.string(P256.KeyAgreement.PrivateKey().publicKey.x963Representation), auth: WebPush.string(Data(repeating: 7, count: 16)))
    private var saved: String { String(decoding: try! JSONEncoder().encode(subscription), as: UTF8.self) }

    /// A paired phone coming back posts its subscription again, which replaced the last build's item on the main thread,
    /// and that waited on a Keychain dialog, which held the whole app.
    func testAPhoneComingBackAfterAnInstallTouchesNothing() {
        let keychain = Keychain(build: "fixed", items: [("pushes", [saved], "32d9263"), ("paired", ["hash"], "32d9263")])
        let pushes = PhonePushes(keys: KeychainPhoneKeys(keychain: keychain)) { _ in 201 }
        XCTAssertTrue(pushes.subscribe(subscription))
        XCTAssertTrue(PhoneDoor(keys: KeychainPhoneKeys(keychain: keychain)).hasPhones, "the last build's pairing still counts")
        XCTAssertEqual(keychain.added, [], "nothing changed, so nothing's saved")
        XCTAssertEqual(keychain.prompts, [])
    }

    func testAChangeIsAnItemOfItsOwnAndOnlyThisRunsOwnGoes() {
        let keychain = Keychain(build: "fixed", items: [("paired", ["one"], "32d9263")])
        let keys = KeychainPhoneKeys(keychain: keychain)
        keys.save(PhoneKeys.paired, ["one", "two"])
        XCTAssertEqual(keys.load(PhoneKeys.paired), ["one", "two"])
        keys.save(PhoneKeys.paired, [])
        XCTAssertEqual(keys.load(PhoneKeys.paired), [], "unpairing every phone still reads as none")
        XCTAssertEqual(keychain.added.count, 2)
        XCTAssertEqual(keychain.prompts, [], "the last build's item stays behind")
        XCTAssertFalse(keychain.items().contains { $0.account == keychain.added[0] }, "the first one this run saved went")
    }
}
