import CryptoKit
@testable import Shades
import XCTest

@MainActor
final class PhoneKeychainTests: XCTestCase {
    // Outside the repo: the Keychain shares items between builds only with a Team ID, and deleting another build's item waits on a dialog.
    final class Keychain: PhoneKeychain {
        var build: String
        var readsOtherBuilds = true
        private var stored: [(account: String, data: Data, build: String)]
        private(set) var added: [String] = []
        private(set) var prompts: [String] = []

        init(build: String, items: [(String, [String], String)]) {
            self.build = build
            stored = items.map { ($0.0, Data($0.1.joined(separator: "\n").utf8), $0.2) }
        }

        func items() -> [(account: String, data: Data?)] {
            stored.reversed().map { ($0.account, readsOtherBuilds || $0.build == build ? $0.data : nil) }
        }

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
    private var saved: String { #"{"auth":"\#(subscription.auth)","p256dh":"\#(subscription.p256dh)","endpoint":"\#(subscription.endpoint)"}"# }

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

    func testAPairingThisBuildCantReadMeansPairingAgain() {
        let keychain = Keychain(build: "new", items: [("paired.a", ["hash"], "old")])
        keychain.readsOtherBuilds = false
        let door = PhoneDoor(keys: KeychainPhoneKeys(keychain: keychain))
        XCTAssertFalse(door.hasPhones)
        XCTAssertTrue(door.needsPairingAgain)
        XCTAssertEqual(keychain.prompts, [], "found out without a dialog")

        keychain.readsOtherBuilds = true
        XCTAssertFalse(PhoneDoor(keys: KeychainPhoneKeys(keychain: keychain)).needsPairingAgain, "a pairing it can read still counts")
        XCTAssertFalse(PhoneDoor(keys: KeychainPhoneKeys(keychain: Keychain(build: "new", items: []))).needsPairingAgain, "never paired isn't pairing again")
    }

    func testPairingAgainInThisRunPutsItRight() {
        let keychain = Keychain(build: "new", items: [("paired.a", ["hash"], "old")])
        keychain.readsOtherBuilds = false
        let door = PhoneDoor(keys: KeychainPhoneKeys(keychain: keychain))
        let pairing = door.openPairing(now: Date())
        XCTAssertNotNil(door.pair(pairing.code, now: Date()))
        XCTAssertFalse(door.needsPairingAgain)
    }
}
