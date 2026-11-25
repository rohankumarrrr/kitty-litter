import CryptoKit
import Foundation
import Security
import ShadesT3

@MainActor
final class PhoneDoor {
    struct Pairing: Equatable {
        var code: String
        var until: Date

        var shown: String { "\(code.prefix(4))-\(code.suffix(4))" }
    }

    private static let letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    private static let codeLength = 8
    private static let pairingSeconds: TimeInterval = 600
    private static let tries = 5

    private let keys: PhoneKeyStoring
    private var hashes: Set<String>
    private let pairedByAnotherBuild: Bool
    private(set) var pairing: Pairing?
    private var triesLeft = 0

    init(keys: PhoneKeyStoring) {
        self.keys = keys
        hashes = Set(keys.load(PhoneKeys.paired))
        pairedByAnotherBuild = keys.cantRead(PhoneKeys.paired)
    }

    var hasPhones: Bool { !hashes.isEmpty }
    var needsPairingAgain: Bool { hashes.isEmpty && pairedByAnotherBuild }

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
    func load(_ name: String) -> [String]
    func save(_ name: String, _ lines: [String])
    func cantRead(_ name: String) -> Bool
}

enum PhoneKeys {
    static let paired = "paired"
    static let pushes = "pushes"
    static let signing = "signing"
}

final class MemoryPhoneKeys: PhoneKeyStoring {
    var saved: [String: [String]] = [:]
    var unreadable: Set<String> = []

    var hashes: [String] { saved[PhoneKeys.paired] ?? [] }

    func load(_ name: String) -> [String] { saved[name] ?? [] }
    func save(_ name: String, _ lines: [String]) { saved[name] = lines }
    func cantRead(_ name: String) -> Bool { unreadable.contains(name) }
}

// Outside the repo: without a Team ID, a build can't read Keychain items an earlier build saved, and changing or deleting one shows a dialog that waits.
final class KeychainPhoneKeys: PhoneKeyStoring {
    private let keychain: PhoneKeychain
    private var savedHere: [String: String] = [:]
    private var unreadable: Set<String> = []

    init(keychain: PhoneKeychain = LoginPhoneKeychain()) {
        self.keychain = keychain
    }

    func load(_ name: String) -> [String] {
        let items = keychain.items().filter { $0.account == name || $0.account.hasPrefix(name + ".") }
        if !items.isEmpty, items.allSatisfy({ $0.data == nil }) { unreadable.insert(name) } else { unreadable.remove(name) }
        return items.first { $0.data != nil }?.data.map(Self.lines) ?? []
    }

    func cantRead(_ name: String) -> Bool { unreadable.contains(name) }

    func save(_ name: String, _ lines: [String]) {
        guard load(name) != lines else { return }
        let account = "\(name).\(UUID().uuidString)"
        guard keychain.add(account: account, data: Data(lines.joined(separator: "\n").utf8), label: "Shades: phone \(name)") else { return }
        if let before = savedHere[name] { keychain.delete(account: before) }
        savedHere[name] = account
    }

    private static func lines(_ data: Data) -> [String] {
        String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
    }
}

protocol PhoneKeychain {
    func items() -> [(account: String, data: Data?)]
    func add(account: String, data: Data, label: String) -> Bool
    func delete(account: String)
}

struct LoginPhoneKeychain: PhoneKeychain {
    private static let service = "dev.shades.phone"

    func items() -> [(account: String, data: Data?)] {
        KeychainPrompts.off {
            var result: CFTypeRef?
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: Self.service,
                kSecReturnAttributes as String: true,
                kSecMatchLimit as String: kSecMatchLimitAll,
            ]
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return [] }
            return (result as? [[String: Any]] ?? [])
                .sorted { ($0[kSecAttrModificationDate as String] as? Date ?? .distantPast) > ($1[kSecAttrModificationDate as String] as? Date ?? .distantPast) }
                .compactMap { $0[kSecAttrAccount as String] as? String }
                .map { ($0, read($0)) }
        }
    }

    func add(account: String, data: Data, label: String) -> Bool {
        KeychainPrompts.off {
            var attributes = Self.item(account)
            attributes[kSecValueData as String] = data
            attributes[kSecAttrLabel as String] = label
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
        }
    }

    func delete(account: String) {
        _ = KeychainPrompts.off { SecItemDelete(Self.item(account) as CFDictionary) }
    }

    private func read(_ account: String) -> Data? {
        var query = Self.item(account)
        query[kSecReturnData as String] = true
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func item(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
