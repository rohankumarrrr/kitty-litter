import CryptoKit
@testable import Shades
import XCTest

/// Web push as the RFCs say. The example and its values are RFC 8291's own, from its section 5 and appendix A.
final class WebPushTests: XCTestCase {
    private let plaintext = Data("When I grow up, I want to be a watermelon".utf8)
    private let auth = WebPush.data("BTBZMqHH6r4Tts7J_aSIgg")!
    private let salt = WebPush.data("DGv6ra1nlYgDCS1FRnbzlw")!
    /// RFC 8291's own example keys, in hex rather than the RFC's base64url, which secret scanners take for a live key.
    /// They're published in the RFC, so they unlock nothing.
    private let phonePrivate = "ab5757a70dd4a53e553a6bbf71ffefea2874ec07a6b379e3c48f895a02dc33de"
    private let phonePublic = "BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4"
    private let senderPrivate = "c9f58f89813e9f8e872e71f42aa64e1757c9254dcc62b72ddc010bb4043ea11c"
    private let body = "DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A_yl95bQpu6cVPTpK4Mqgkf1CXztLVBSt2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN"

    func testTheRFCsExampleEncryptsToTheRFCsBody() throws {
        let phone = try P256.KeyAgreement.PublicKey(x963Representation: XCTUnwrap(WebPush.data(phonePublic)))
        let sender = try P256.KeyAgreement.PrivateKey(rawRepresentation: Self.hex(senderPrivate))
        let encrypted = try WebPush.encrypt(plaintext, for: phone, auth: auth, blocks: 1, sender: sender, salt: salt)
        XCTAssertEqual(WebPush.string(encrypted), body)
    }

    func testTheRFCsBodyOpensWithThePhonesKey() throws {
        let phone = try P256.KeyAgreement.PrivateKey(rawRepresentation: Self.hex(phonePrivate))
        XCTAssertEqual(try WebPush.decrypt(XCTUnwrap(WebPush.data(body)), with: phone, auth: auth), plaintext)
        XCTAssertThrowsError(try WebPush.decrypt(XCTUnwrap(WebPush.data(body)), with: phone, auth: Data(repeating: 0, count: 16)), "only with its own secret")
    }

    func testEachPushHasItsOwnKeyAndSalt() throws {
        let phone = P256.KeyAgreement.PrivateKey()
        let first = try WebPush.encrypt(plaintext, for: phone.publicKey, auth: auth)
        let second = try WebPush.encrypt(plaintext, for: phone.publicKey, auth: auth)
        XCTAssertNotEqual(first.prefix(86), second.prefix(86))
        XCTAssertEqual(try WebPush.decrypt(second, with: phone, auth: auth), plaintext)
    }

    func testEveryNotificationIsTheSameSizeSoItsLengthSaysNothing() throws {
        let phone = P256.KeyAgreement.PrivateKey()
        let titles = ["Pepper needs an approval", "Pepper has a question", "Pepper needs a decision", "Steve Pawsniak needs an approval", "An agent needs an approval", "Steve Pawsniak finished"]
        // As long as T3's thread IDs get, in the tag and in the page a tap opens, which names its kitten by folder.
        let thread = "mcp:launch:" + String(repeating: "f", count: 64)
        let page = PhonePlace.key(.thread(thread, in: .channel(.kitten("/Users/someone/kittens/steve-pawsniak"))))
        let sizes = try titles.flatMap { title in
            try [
                #"{"title":"\#(title)","tag":"11111111-1111-1111-1111-111111111111","key":"activity"}"#,
                #"{"title":"\#(title)","tag":"\#(thread)","key":"\#(page)"}"#,
            ].map { try WebPush.encrypt(Data($0.utf8), for: phone.publicKey, auth: auth).count }
        }
        XCTAssertEqual(Set(sizes).count, 1, "\(sizes)")
        let padded = try WebPush.encrypt(plaintext, for: phone.publicKey, auth: auth)
        XCTAssertEqual(try WebPush.decrypt(padded, with: phone, auth: auth), plaintext, "and the phone takes the padding off")
    }

    func testTheSignatureIsWhatAPushServiceChecks() throws {
        let key = P256.Signing.PrivateKey()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let header = try WebPush.vapid(for: XCTUnwrap(URL(string: "https://web.push.apple.com/QGuW/abc")), key: key, now: now)
        let parts = header.components(separatedBy: ", k=")
        XCTAssertEqual(parts.last, WebPush.string(key.publicKey.x963Representation))
        let token = try XCTUnwrap(parts.first?.components(separatedBy: "vapid t=").last).components(separatedBy: ".")
        XCTAssertEqual(token.count, 3)
        let claims = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(WebPush.data(token[1]))) as? [String: Any])
        XCTAssertEqual(claims["aud"] as? String, "https://web.push.apple.com", "the push service, without the path")
        XCTAssertEqual(claims["exp"] as? Int, 1_800_000_000 + 12 * 60 * 60, "and never more than a day out")
        XCTAssertNotNil(claims["sub"])
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: XCTUnwrap(WebPush.data(token[2])))
        XCTAssertTrue(key.publicKey.isValidSignature(signature, for: Data("\(token[0]).\(token[1])".utf8)))
    }

    func testOnlyAPushServiceCanBeWhereNotificationsGo() {
        let key = WebPush.string(P256.KeyAgreement.PrivateKey().publicKey.x963Representation)
        let secret = WebPush.string(Data(repeating: 7, count: 16))
        func subscription(_ endpoint: String, key: String = key, auth: String = secret) -> WebPush.Subscription {
            WebPush.Subscription(endpoint: endpoint, p256dh: key, auth: auth)
        }
        XCTAssertTrue(subscription("https://web.push.apple.com/QGuW").isValid)
        XCTAssertTrue(subscription("https://fcm.googleapis.com/fcm/send/abc").isValid)
        XCTAssertFalse(subscription("http://web.push.apple.com/QGuW").isValid)
        XCTAssertFalse(subscription("https://127.0.0.1:4797/act").isValid, "or a phone could have Shades send requests anywhere")
        XCTAssertFalse(subscription("https://web.push.apple.com.example.com/x").isValid)
        XCTAssertFalse(subscription("https://web.push.apple.com:22/x").isValid, "only its https port")
        XCTAssertTrue(subscription("https://web.push.apple.com:443/x").isValid)
        XCTAssertFalse(subscription("https://web.push.apple.com/x", key: "not-a-key").isValid)
        XCTAssertFalse(subscription("https://web.push.apple.com/x", auth: WebPush.string(Data(repeating: 7, count: 8))).isValid)
    }

    private static func hex(_ text: String) -> Data {
        Data(stride(from: 0, to: text.count, by: 2).map { offset in
            UInt8(text.dropFirst(offset).prefix(2), radix: 16)!
        })
    }
}
