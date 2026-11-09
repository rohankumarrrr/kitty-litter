@testable import ShadesT3
import XCTest

/// Signing in, with T3's server, its `t3` tool and the Keychain all stood in for, so nothing here signs in or touches
/// the Keychain.
final class T3AuthTests: XCTestCase {
    /// Answers as T3's server would: who it is, and what it makes of each saved sign-in, by its token.
    final class FakeServer: URLProtocol {
        nonisolated(unsafe) static var sessions: [String: String] = [:]
        /// Where the fake `t3` tool lists the sign-ins it issued and hasn't revoked.
        nonisolated(unsafe) static var issued: URL?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func stopLoading() {}

        override func startLoading() {
            let token = request.value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(of: "Bearer ", with: "") ?? ""
            let (status, body) = request.url?.path == "/.well-known/t3/environment"
                ? (200, #"{"environmentId":"e","serverVersion":"1","orchestrationProtocolVersion":2}"#)
                : Self.sessions[token].map { (200, $0) } ?? (Self.stillIssued(token) ? (200, T3AuthTests.newScopes) : (401, ""))
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        private static func stillIssued(_ token: String) -> Bool {
            guard let issued, let list = try? String(contentsOf: issued, encoding: .utf8) else { return false }
            return list.split(separator: "\n").contains(Substring(token))
        }
    }

    /// The login Keychain as builds signed with one certificate see it: each can read what any of them saved, newest
    /// first, but deleting one another build saved shows a dialog and waits on it, which is what `prompts` counts.
    final class Keychain: T3CredentialStoring, @unchecked Sendable {
        private let lock = NSLock()
        private let build: String
        private var items: [(credential: T3Credential, build: String)]
        private(set) var saved: [String] = []
        private(set) var deleted: [String] = []
        private(set) var prompts: [String] = []

        init(build: String, items: [(T3Credential, String)]) {
            self.build = build
            self.items = items.map { ($0.0, $0.1) }
        }

        func load() -> T3Credential? { lock.withLock { items.last?.credential } }
        func newestUnreadableSessionID() -> String? { nil }

        func save(_ credential: T3Credential) {
            lock.withLock {
                items.append((credential, build))
                saved.append(credential.sessionID)
            }
        }

        func delete(sessionID: String) {
            lock.withLock {
                if items.contains(where: { $0.credential.sessionID == sessionID && $0.build != build }) { prompts.append(sessionID) }
                items.removeAll { $0.credential.sessionID == sessionID }
                deleted.append(sessionID)
            }
        }
    }

    /// One Keychain service shared by builds that can't read each other's items, as copies built from source are:
    /// each lists every item, newest first, but reads only what its own build saved.
    final class Service: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [(credential: T3Credential, build: String)] = []

        func seenBy(_ build: String) -> T3CredentialStoring { Build(service: self, build: build) }

        private struct Build: T3CredentialStoring {
            let service: Service
            let build: String

            func load() -> T3Credential? { service.newest { $0 == build } }
            func newestUnreadableSessionID() -> String? { service.newest { $0 != build }?.sessionID }
            func save(_ credential: T3Credential) { service.lock.withLock { service.items.append((credential, build)) } }
            func delete(sessionID: String) { service.lock.withLock { service.items.removeAll { $0.credential.sessionID == sessionID } } }
        }

        private func newest(_ readable: (String) -> Bool) -> T3Credential? {
            lock.withLock { items.last { readable($0.build) }?.credential }
        }
    }

    private static let oldScopes = #"{"authenticated":true,"scopes":["orchestration:read","orchestration:operate"],"permissions":["orchestration:read","orchestration:operate"]}"#
    private static let newScopes = #"{"authenticated":true,"scopes":["orchestration:read","orchestration:operate"],"permissions":["orchestration:read","orchestration:operate","filesystem:read"]}"#
    private let fromOldBuild = T3Credential(sessionID: "from-32d9263", token: "t-old")
    private let fromBadBuild = T3Credential(sessionID: "from-fba7276", token: "t-fba")
    private var home: URL!

    override func setUpWithError() throws {
        FakeServer.sessions = [:]
        home = FileManager.default.temporaryDirectory.appendingPathComponent("t3-auth-\(UUID().uuidString)", isDirectory: true)
        let userdata = home.appendingPathComponent("userdata", isDirectory: true)
        let bin = home.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: userdata, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try Data(#"{"origin":"http://t3.test"}"#.utf8).write(to: userdata.appendingPathComponent("server-runtime.json"))
        FakeServer.issued = bin.appendingPathComponent("issued")
        // Each sign-in gets a session of its own, as T3's tool gives, which T3 accepts until it's revoked.
        let tool = """
        #!/bin/sh
        cd "$(dirname "$0")"
        echo "$*" >> calls
        case "$*" in
          *"session issue"*)
            n=$(( $(cat count 2>/dev/null || echo 0) + 1 )); echo $n > count
            echo "t-$n" >> issued
            printf '{"sessionId":"new-%s","token":"t-%s","expiresAt":"2030-01-01T00:00:00.000Z"}' $n $n ;;
          *"session revoke"*)
            grep -vx "t-${4#new-}" issued > issued.next; mv issued.next issued ;;
        esac
        """
        let path = bin.appendingPathComponent("t3")
        try Data(tool.utf8).write(to: path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func auth(_ store: T3CredentialStoring, revokesWhatItCantRead: Bool = true) -> T3Auth {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeServer.self]
        return T3Auth(home: home, store: store, label: "Shades test", ttl: "1h", renewBefore: 0, revokesWhatItCantRead: revokesWhatItCantRead, http: URLSession(configuration: configuration))
    }

    private func toolOutput(_ name: String) -> String {
        (try? String(contentsOf: home.appendingPathComponent("bin/\(name)"), encoding: .utf8)) ?? ""
    }

    private var issued: Int { Int(toolOutput("count").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0 }

    /// Revoking runs on its own after a sign-in, so this gives it a moment to.
    private func revoked() async throws -> [String] {
        let revoked = { self.toolOutput("calls").split(separator: "\n").filter { $0.hasPrefix("auth session revoke ") }.map { String($0.dropFirst(20)) } }
        for _ in 0..<10 where revoked().isEmpty { try await Task.sleep(for: .milliseconds(100)) }
        return revoked()
    }

    private func signedIn(_ keychain: Keychain, forceNew: Bool = false) async throws -> String? {
        try await auth(keychain).socketRequest(forceNewSession: forceNew).value(forHTTPHeaderField: "Authorization")
    }

    /// The scope fba7276 added sent its first launch to sign in again over 32d9263's sign-in, and then delete that
    /// item, which waited on a Keychain dialog and held the whole launch.
    func testOverAnOlderBuildsSignInWithTheOldScopesItSignsInAgainAndDeletesNothing() async throws {
        FakeServer.sessions = ["t-old": Self.oldScopes]
        let keychain = Keychain(build: "fixed", items: [(fromOldBuild, "32d9263")])
        let used = try await signedIn(keychain)
        XCTAssertEqual(used, "Bearer t-1")
        XCTAssertEqual(keychain.saved, ["new-1"])
        XCTAssertEqual(keychain.deleted, [], "the older build's item stays behind")
        XCTAssertEqual(keychain.prompts, [])
    }

    func testOverAnOlderBuildsSignInWithTheNewScopesItUsesIt() async throws {
        FakeServer.sessions = ["t-fba": Self.newScopes]
        let keychain = Keychain(build: "fixed", items: [(fromBadBuild, "fba7276")])
        let used = try await signedIn(keychain)
        XCTAssertEqual(used, "Bearer t-fba")
        XCTAssertEqual(keychain.saved, [])
        XCTAssertEqual(keychain.deleted, [])
    }

    /// The Mac as fba7276 left it: 32d9263's item, then the one fba7276 saved before it waited on the dialog.
    func testOverBothItemsItUsesTheNewestAndDeletesNothing() async throws {
        FakeServer.sessions = ["t-old": Self.oldScopes, "t-fba": Self.newScopes]
        let keychain = Keychain(build: "fixed", items: [(fromOldBuild, "32d9263"), (fromBadBuild, "fba7276")])
        let used = try await signedIn(keychain)
        XCTAssertEqual(used, "Bearer t-fba")
        XCTAssertEqual(keychain.deleted, [])

        // fba7276 never got to revoke anything, but if T3 had, it signs in again, and still deletes nothing.
        FakeServer.sessions = ["t-old": Self.oldScopes]
        let revoked = Keychain(build: "fixed", items: [(fromOldBuild, "32d9263"), (fromBadBuild, "fba7276")])
        let usedAgain = try await signedIn(revoked)
        XCTAssertEqual(usedAgain, "Bearer t-1")
        XCTAssertEqual(revoked.deleted, [])
        XCTAssertEqual(revoked.prompts, [])
    }

    func testSigningInAgainInTheSameRunDeletesOnlyWhatThatRunSaved() async throws {
        FakeServer.sessions = ["t-old": Self.oldScopes]
        let keychain = Keychain(build: "fixed", items: [(fromOldBuild, "32d9263")])
        let auth = auth(keychain)
        _ = try await auth.socketRequest(forceNewSession: false)
        _ = try await auth.socketRequest(forceNewSession: true)
        XCTAssertEqual(keychain.saved, ["new-1", "new-2"])
        XCTAssertEqual(keychain.deleted, ["new-1"], "its own goes")
        XCTAssertEqual(keychain.prompts, [])
    }

    /// A saved sign-in T3 had revoked read as T3 not running, so the cat never signed in again.
    func testASignInT3RevokedMeansSigningInAgain() async throws {
        let keychain = Keychain(build: "fixed", items: [(fromOldBuild, "32d9263")])
        let used = try await signedIn(keychain)
        XCTAssertEqual(used, "Bearer t-1")
        XCTAssertEqual(keychain.saved, ["new-1"])
    }

    /// Copies built from source share a service but can't read each other's sign-ins, so each took the other's for one
    /// an older build left and revoked it, then signed in again over it on every reconnect.
    func testTwoCopiesRunningAtOnceKeepTheirOwnSignIns() async throws {
        let service = Service()
        let x = auth(service.seenBy("x"), revokesWhatItCantRead: false)
        let y = auth(service.seenBy("y"), revokesWhatItCantRead: false)
        _ = try await x.socketRequest(forceNewSession: false)
        _ = try await y.socketRequest(forceNewSession: false)
        let revoked = try await revoked()
        XCTAssertEqual(revoked, [])
        for _ in 1...3 {
            _ = try await x.socketRequest(forceNewSession: false)
            _ = try await y.socketRequest(forceNewSession: false)
        }
        XCTAssertEqual(issued, 2, "each signs in once")
    }

    /// The installed app is the only copy on its service, so a sign-in there it can't read was left by a build signed
    /// differently, and goes from T3's list.
    func testTheInstalledAppRevokesASignInItCantRead() async throws {
        let service = Service()
        try service.seenBy("signed differently").save(T3Credential(sessionID: "left", token: "t-left"))
        _ = try await auth(service.seenBy("installed")).socketRequest(forceNewSession: false)
        let revoked = try await revoked()
        XCTAssertEqual(revoked, ["left"])
    }
}
