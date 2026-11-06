import CryptoKit
import Foundation
import Security

/// Who may use Messages from a phone. What the server takes reaches T3 as your own words, and anything on this Mac can
/// reach it on loopback, kittens' shells included, so a key is the only way in. A phone gets one by typing or
/// scanning a code that only a Shades window shows, which captures leave out. The page keeps its key in its own
/// storage and sends it in a header, since a cookie would go to every port on the Mac's name. Shades keeps only a hash.
@MainActor
final class PhoneDoor {
    struct Pairing: Equatable {
        var code: String
        var until: Date

        /// In two halves, so it's easy to read out and type.
        var shown: String { "\(code.prefix(4))-\(code.suffix(4))" }
    }

    private static let letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    private static let codeLength = 8
    private static let pairingSeconds: TimeInterval = 600
    /// A wrong code this many times uses the code up, so guessing gets nowhere.
    private static let tries = 5

    private let keys: PhoneKeyStoring
    private var hashes: Set<String>
    private(set) var pairing: Pairing?
    private var triesLeft = 0

    init(keys: PhoneKeyStoring) {
        self.keys = keys
        hashes = Set(keys.load(PhoneKeys.paired))
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
        keys.save(PhoneKeys.paired, hashes.sorted())
        return token
    }

    func admits(_ request: PhoneServer.Request) -> Bool {
        guard let header = request.headers["authorization"], header.hasPrefix("Bearer ") else { return false }
        return hashes.contains(Self.hash(String(header.dropFirst(7))))
    }

    func forgetPhones() {
        hashes = []
        keys.save(PhoneKeys.paired, [])
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

/// What Shades keeps for phones, each a short list of lines under its own name.
protocol PhoneKeyStoring {
    func load(_ name: String) -> [String]
    func save(_ name: String, _ lines: [String])
}

enum PhoneKeys {
    /// The hashes of paired phones' keys.
    static let paired = "paired"
    /// Where to send each phone's notifications.
    static let pushes = "pushes"
    /// The key Shades signs its notifications with.
    static let signing = "signing"
}

/// For the demo and tests, which never touch the Keychain.
final class MemoryPhoneKeys: PhoneKeyStoring {
    var saved: [String: [String]] = [:]

    var hashes: [String] { saved[PhoneKeys.paired] ?? [] }

    func load(_ name: String) -> [String] { saved[name] ?? [] }
    func save(_ name: String, _ lines: [String]) { saved[name] = lines }
}

/// In the login Keychain rather than a file a kitten could rewrite to let itself in, or read to send as you. As with the
/// T3 sign-in, a build signed differently can't read them, which only means pairing again, and this never calls
/// `SecItemUpdate`, since that shows a dialog for another build's item.
final class KeychainPhoneKeys: PhoneKeyStoring {
    private static func item(_ name: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "dev.shades.phone",
            kSecAttrAccount as String: name,
        ]
    }

    func load(_ name: String) -> [String] {
        withoutPrompts {
            var query = Self.item(name)
            query[kSecReturnData as String] = true
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
            var result: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return [] }
            return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
        }
    }

    func save(_ name: String, _ lines: [String]) {
        withoutPrompts {
            SecItemDelete(Self.item(name) as CFDictionary)
            guard !lines.isEmpty else { return }
            var attributes = Self.item(name)
            attributes[kSecValueData as String] = Data(lines.joined(separator: "\n").utf8)
            attributes[kSecAttrLabel as String] = "Shades: phone \(name)"
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
