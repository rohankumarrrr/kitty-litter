import Foundation
import Security

public struct T3Credential: Sendable, Equatable {
    public var sessionID: String
    public var token: String

    public init(sessionID: String, token: String) {
        self.sessionID = sessionID
        self.token = token
    }
}

public protocol T3CredentialStoring: Sendable {
    func load() throws -> T3Credential?
    func save(_ credential: T3Credential) throws
    func delete(sessionID: String) throws
    func newestUnreadableSessionID() throws -> String?
}

// Outside the repo: the login Keychain has no per-query way to forbid dialogs, only this process-wide switch.
public enum KeychainPrompts {
    private static let turn = NSLock()

    public static func off<Result>(_ body: () throws -> Result) rethrows -> Result {
        try turn.withLock {
            SecKeychainSetUserInteractionAllowed(false)
            defer { SecKeychainSetUserInteractionAllowed(true) }
            return try body()
        }
    }
}

// Outside the repo: a self-signed build can't read Keychain items another build made, and changing or deleting one shows a dialog even with prompts off.
public final class KeychainCredentialStore: T3CredentialStoring, @unchecked Sendable {
    public static let defaultService = "dev.shades.t3-session"

    private let service: String

    public init(service: String = KeychainCredentialStore.defaultService) {
        self.service = service
    }

    public func load() throws -> T3Credential? {
        try KeychainPrompts.off {
            for sessionID in try sessionIDs() {
                if let token = readToken(sessionID) {
                    return T3Credential(sessionID: sessionID, token: token)
                }
            }
            return nil
        }
    }

    public func save(_ credential: T3Credential) throws {
        try KeychainPrompts.off {
            var attributes = item(credential.sessionID)
            attributes[kSecValueData as String] = Data(credential.token.utf8)
            attributes[kSecAttrLabel as String] = "Shades: T3 Code sign-in"
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let status = SecItemAdd(attributes as CFDictionary, nil)
            guard status == errSecSuccess else { throw T3Error.keychain(status: status) }
        }
    }

    public func delete(sessionID: String) throws {
        try KeychainPrompts.off {
            let status = SecItemDelete(item(sessionID) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw T3Error.keychain(status: status)
            }
        }
    }

    public func newestUnreadableSessionID() throws -> String? {
        try KeychainPrompts.off {
            try sessionIDs().first { readToken($0) == nil }
        }
    }

    private func item(_ sessionID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sessionID,
        ]
    }

    private func readToken(_ sessionID: String) -> String? {
        var result: CFTypeRef?
        var query = item(sessionID)
        query[kSecReturnData as String] = true
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func sessionIDs() throws -> [String] {
        var result: CFTypeRef?
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw T3Error.keychain(status: status) }
        return (result as? [[String: Any]] ?? [])
            .sorted {
                let left = $0[kSecAttrModificationDate as String] as? Date ?? .distantPast
                let right = $1[kSecAttrModificationDate as String] as? Date ?? .distantPast
                return left > right
            }
            .compactMap { $0[kSecAttrAccount as String] as? String }
    }
}

public final class MemoryCredentialStore: T3CredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var credential: T3Credential?

    public init() {}

    public func load() -> T3Credential? {
        lock.withLock { credential }
    }

    public func save(_ credential: T3Credential) {
        lock.withLock { self.credential = credential }
    }

    public func delete(sessionID: String) {
        lock.withLock { if credential?.sessionID == sessionID { credential = nil } }
    }

    public func newestUnreadableSessionID() -> String? { nil }
}
