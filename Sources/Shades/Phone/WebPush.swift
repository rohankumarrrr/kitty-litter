import CryptoKit
import Foundation

// Outside the repo: push services only take what's encrypted as RFC 8291 says and signed as RFC 8292 (VAPID) says.
enum WebPush {
    struct Subscription: Codable, Equatable {
        var endpoint: String
        var p256dh: String
        var auth: String

        private static let services = ["push.apple.com", "fcm.googleapis.com", "push.services.mozilla.com", "notify.windows.com"]

        var isValid: Bool {
            guard let url = URL(string: endpoint), url.scheme == "https", url.port == nil || url.port == 443, let host = url.host?.lowercased(),
                  Self.services.contains(where: { host == $0 || host.hasSuffix("." + $0) }),
                  let key = WebPush.data(p256dh), (try? P256.KeyAgreement.PublicKey(x963Representation: key)) != nil,
                  WebPush.data(auth)?.count == 16
            else { return false }
            return true
        }
    }

    private static let recordSize: UInt32 = 4096

    static func encrypt(
        _ plaintext: Data,
        for phone: P256.KeyAgreement.PublicKey,
        auth: Data,
        blocks: Int = 512,
        sender: P256.KeyAgreement.PrivateKey = P256.KeyAgreement.PrivateKey(),
        salt: Data = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
    ) throws -> Data {
        let senderPublic = sender.publicKey.x963Representation
        let (key, nonce) = try keys(
            secret: sender.sharedSecretFromKeyAgreement(with: phone),
            auth: auth,
            phone: phone.x963Representation,
            sender: senderPublic,
            salt: salt
        )
        let padded = (plaintext.count / blocks + 1) * blocks
        let sealed = try AES.GCM.seal(plaintext + Data([2]) + Data(count: padded - plaintext.count - 1), using: key, nonce: nonce)
        var size = recordSize.bigEndian
        return salt + Data(bytes: &size, count: 4) + Data([UInt8(senderPublic.count)]) + senderPublic + sealed.ciphertext + sealed.tag
    }

    static func decrypt(_ body: Data, with phone: P256.KeyAgreement.PrivateKey, auth: Data) throws -> Data {
        let body = Data(body)
        guard body.count > 21 else { throw CryptoKitError.incorrectParameterSize }
        let salt = body.prefix(16)
        let idLength = Int(body[20])
        guard body.count > 21 + idLength + 16 else { throw CryptoKitError.incorrectParameterSize }
        let senderPublic = body.subdata(in: 21..<21 + idLength)
        let record = body.suffix(from: 21 + idLength)
        let (key, nonce) = try keys(
            secret: phone.sharedSecretFromKeyAgreement(with: P256.KeyAgreement.PublicKey(x963Representation: senderPublic)),
            auth: auth,
            phone: phone.publicKey.x963Representation,
            sender: senderPublic,
            salt: Data(salt)
        )
        let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: record.dropLast(16), tag: record.suffix(16))
        let padded = try AES.GCM.open(box, using: key)
        guard let end = padded.lastIndex(where: { $0 != 0 }), padded[end] == 2 else { throw CryptoKitError.authenticationFailure }
        return padded[padded.startIndex..<end]
    }

    private static func keys(secret: SharedSecret, auth: Data, phone: Data, sender: Data, salt: Data) throws -> (SymmetricKey, AES.GCM.Nonce) {
        let ikm = secret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: auth,
            sharedInfo: Data("WebPush: info".utf8) + Data([0]) + phone + sender,
            outputByteCount: 32
        )
        func derive(_ info: String, _ count: Int) -> Data {
            HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, salt: salt, info: Data("Content-Encoding: \(info)".utf8) + Data([0]), outputByteCount: count)
                .withUnsafeBytes { Data($0) }
        }
        return (SymmetricKey(data: derive("aes128gcm", 16)), try AES.GCM.Nonce(data: derive("nonce", 12)))
    }

    static func vapid(for endpoint: URL, key: P256.Signing.PrivateKey, now: Date) throws -> String {
        guard let scheme = endpoint.scheme, let host = endpoint.host else { throw URLError(.badURL) }
        let header = string(Data(#"{"typ":"JWT","alg":"ES256"}"#.utf8))
        let claims: [String: Any] = [
            "aud": "\(scheme)://\(host)",
            "exp": Int(now.timeIntervalSince1970) + 12 * 60 * 60,
            "sub": "https://github.com/rohankumarrrr/kitty-litter",
        ]
        let body = string(try JSONSerialization.data(withJSONObject: claims, options: [.sortedKeys, .withoutEscapingSlashes]))
        let signature = try key.signature(for: Data("\(header).\(body)".utf8)).rawRepresentation
        return "vapid t=\(header).\(body).\(string(signature)), k=\(string(key.publicKey.x963Representation))"
    }

    static func request(_ payload: Data, to subscription: Subscription, key: P256.Signing.PrivateKey, now: Date) throws -> URLRequest {
        guard subscription.isValid, let url = URL(string: subscription.endpoint), let phone = data(subscription.p256dh), let auth = data(subscription.auth) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try encrypt(payload, for: P256.KeyAgreement.PublicKey(x963Representation: phone), auth: auth)
        request.setValue(try vapid(for: url, key: key, now: now), forHTTPHeaderField: "Authorization")
        request.setValue("aes128gcm", forHTTPHeaderField: "Content-Encoding")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("43200", forHTTPHeaderField: "TTL")
        request.setValue("high", forHTTPHeaderField: "Urgency")
        return request
    }

    static func string(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func data(_ string: String) -> Data? {
        var base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }
}
