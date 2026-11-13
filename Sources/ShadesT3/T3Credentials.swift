import Foundation
import Security

/// A bearer session on the T3 server.
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
    /// The latest session the store knows about but can no longer read, which can be revoked.
    func newestUnreadableSessionID() throws -> String?
}

/// The login Keychain has no per-query way to promise "never show a dialog", and this is the switch for it. It's
/// process-wide, so it goes back on straight after, and callers take turns with it: the phone's keys load on the main
/// thread while signing in to T3 reads off it, and one turning it back on mid-call would let the other's read show a dialog.
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

/// Keeps the session in the login Keychain.
///
/// Items belong to the exact binary that made them unless the app is signed with a Team ID, which a
/// self-signed certificate doesn't have, so a rebuilt app can't read them. Asking would pop up a
/// dialog on every rebuild, so this never asks: an unreadable item just means signing in again.
///
/// Reading and adding are safe here, but changing or deleting an item made by another build shows a
/// dialog even with prompts turned off, and waits on it, so this never calls SecItemUpdate, and `T3Auth`
/// only deletes what its own run saved.
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

    /// Newest first. Attributes can be listed without any access to the secrets.
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

/// Holds the session for as long as the process lives, for tests and probes.
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
