import CryptoKit
import Foundation
import Security

/// Who may use Messages from a phone. What the server takes reaches T3 as your own words, and anything on this Mac can
/// reach it on loopback, kittens' shells included, so a token is the only way in. A phone gets one by typing or
/// scanning a code that only a Shades window shows, which captures leave out. The phone keeps its token in a cookie,
/// and Shades keeps only a hash of it.
@MainActor
final class PhoneDoor {
    struct Pairing: Equatable {
        var code: String
        var until: Date

        /// In two halves, so it's easy to read out and type.
        var shown: String { "\(code.prefix(4))-\(code.suffix(4))" }
    }

    static let cookie = "shades_phone"
    private static let letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    private static let codeLength = 8
    private static let pairingSeconds: TimeInterval = 600
    /// A wrong code this many times uses the code up, so guessing gets nowhere.
    private static let tries = 5
    private static let cookieSeconds = 400 * 24 * 60 * 60

    private let keys: PhoneKeyStoring
    private var hashes: Set<String>
    private(set) var pairing: Pairing?
    private var triesLeft = 0

    init(keys: PhoneKeyStoring) {
        self.keys = keys
        hashes = Set(keys.load())
    }

    var hasPhones: Bool { !hashes.isEmpty }

    func openPairing(now: Date) -> Pairing {
        var random = SystemRandomNumberGenerator()
        let code = String((0..<Self.codeLength).map { _ in Self.letters.randomElement(using: &random)! })
        let pairing = Pairing(code: code, until: now.addingTimeInterval(Self.pairingSeconds))
        self.pairing = pairing
        triesLeft = Self.tries
        return pairing
    }

    func closePairing() {
        pairing = nil
    }

    /// A new token if this is the code that's showing. The code works once.
    func pair(_ typed: String, now: Date) -> String? {
        guard let pairing, now < pairing.until else {
            closePairing()
            return nil
        }
        let typed = typed.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard Self.same(typed, pairing.code) else {
            triesLeft -= 1
            if triesLeft <= 0 { closePairing() }
            return nil
        }
        closePairing()
        var random = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &random) }
        let token = Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        hashes.insert(Self.hash(token))
        keys.save(hashes.sorted())
        return token
    }

    /// Only over HTTPS, never to script on the page, and never on a request another site starts.
    static func setCookie(_ token: String) -> String {
        "\(cookie)=\(token); Path=/; Max-Age=\(cookieSeconds); Secure; HttpOnly; SameSite=Strict"
    }

    func admits(_ request: PhoneServer.Request) -> Bool {
        guard let token = Self.token(in: request.headers["cookie"]) else { return false }
        return hashes.contains(Self.hash(token))
    }

    func forgetPhones() {
        hashes = []
        keys.save([])
    }

    private static func token(in header: String?) -> String? {
        header?.split(separator: ";").lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("\(cookie)=") }
            .map { String($0.dropFirst(cookie.count + 1)) }
    }

    private static func hash(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        let (a, b) = (Array(a.utf8), Array(b.utf8))
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

protocol PhoneKeyStoring {
    func load() -> [String]
    func save(_ hashes: [String])
}

/// For the demo and tests, which never touch the Keychain.
final class MemoryPhoneKeys: PhoneKeyStoring {
    var hashes: [String] = []

    func load() -> [String] { hashes }
    func save(_ hashes: [String]) { self.hashes = hashes }
}

/// The hashes of paired phones' tokens, in one login Keychain item rather than a file a kitten could rewrite to let
/// itself in. As with the T3 sign-in, a build signed differently can't read it, which only means pairing again, and this
/// never calls `SecItemUpdate`, since that shows a dialog for another build's item.
final class KeychainPhoneKeys: PhoneKeyStoring {
    private static let item: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "dev.shades.phone",
        kSecAttrAccount as String: "paired",
    ]

    func load() -> [String] {
        withoutPrompts {
            var query = Self.item
            query[kSecReturnData as String] = true
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
            var result: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return [] }
            return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
        }
    }

    func save(_ hashes: [String]) {
        withoutPrompts {
            SecItemDelete(Self.item as CFDictionary)
            guard !hashes.isEmpty else { return }
            var attributes = Self.item
            attributes[kSecValueData as String] = Data(hashes.joined(separator: "\n").utf8)
            attributes[kSecAttrLabel as String] = "Shades: paired phones"
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            SecItemAdd(attributes as CFDictionary, nil)
        }
    }

    private func withoutPrompts<Result>(_ body: () -> Result) -> Result {
        SecKeychainSetUserInteractionAllowed(false)
        defer { SecKeychainSetUserInteractionAllowed(true) }
        return body()
    }
}
