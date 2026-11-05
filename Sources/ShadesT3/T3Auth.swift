import Foundation

/// Finds the running server and keeps a working sign-in for it.
///
/// Signing in means running T3's own `t3 auth session issue`, the way T3 documents for headless
/// clients. Anyone who can run that as this user already has this access, so nobody has to click.
actor T3Auth {
    private let home: URL
    private let store: T3CredentialStoring
    private let label: String
    private let ttl: String
    private let renewBefore: TimeInterval
    private let http: URLSession

    private var credential: T3Credential?
    private var environment: T3Wire.Environment?

    init(home: URL, store: T3CredentialStoring, label: String, ttl: String, renewBefore: TimeInterval) {
        self.home = home
        self.store = store
        self.label = label
        self.ttl = ttl
        self.renewBefore = renewBefore
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        http = URLSession(configuration: configuration)
    }

    static var defaultHome: URL {
        if let path = ProcessInfo.processInfo.environment["T3CODE_HOME"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".t3", isDirectory: true)
    }

    /// The opening request for the socket, with a sign-in the server just accepted.
    func socketRequest(forceNewSession: Bool) async throws -> URLRequest {
        let origin = try await reachableOrigin()
        let token = try await token(origin: origin, forceNew: forceNewSession)

        guard var components = URLComponents(url: origin, resolvingAgainstBaseURL: false) else {
            throw T3Error.notRunning
        }
        components.scheme = origin.scheme == "https" ? "wss" : "ws"
        components.path = T3Wire.Route.socket
        components.queryItems = [T3Wire.protocolQueryItem]
        guard let url = components.url else { throw T3Error.notRunning }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// Where uploads go. Read fresh so a restart on another port is picked up.
    func currentOrigin() throws -> URL { try readOrigin() }

    var environmentID: String? { environment?.environmentId }

    /// Asks the server to end this session and forgets it.
    func signOut() async {
        let current = credential ?? (try? store.load())
        credential = nil
        guard let current else { return }
        try? store.delete(sessionID: current.sessionID)
        _ = try? await runCommandLine(["auth", "session", "revoke", current.sessionID])
    }

    // MARK: Finding the server

    private func readOrigin() throws -> URL {
        let file = home.appendingPathComponent("userdata/server-runtime.json")
        guard let data = try? Data(contentsOf: file),
              let info = try? T3Wire.decoder().decode(T3Wire.RuntimeInfo.self, from: data),
              let origin = URL(string: info.origin)
        else { throw T3Error.notRunning }
        return origin
    }

    private func reachableOrigin() async throws -> URL {
        let origin = try readOrigin()
        let url = origin.appendingPathComponent(T3Wire.Route.environment)
        guard let (data, response) = try? await http.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let environment = try? T3Wire.decoder().decode(T3Wire.Environment.self, from: data)
        else { throw T3Error.notRunning }
        guard environment.isCompatible else {
            throw T3Error.incompatibleServer(version: environment.serverVersion)
        }
        self.environment = environment
        return origin
    }

    // MARK: Signing in

    private func token(origin: URL, forceNew: Bool) async throws -> String {
        if !forceNew, let usable = try await usableCredential(origin: origin) { return usable.token }

        let previous = credential ?? (try? store.load())
        let leftByLastBuild = try? store.newestUnreadableSessionID()
        let issued = try await issueSession()
        // A locked or broken Keychain shouldn't stop the cat. It just signs in again next launch.
        try? store.save(issued)
        credential = issued

        // Old sessions shouldn't linger in T3's list. Best effort: they expire on their own too.
        if let previous { try? store.delete(sessionID: previous.sessionID) }
        let replaced = [previous?.sessionID, leftByLastBuild].compactMap { $0 }
        if !replaced.isEmpty {
            Task {
                for sessionID in replaced {
                    _ = try? await runCommandLine(["auth", "session", "revoke", sessionID])
                }
            }
        }
        return issued.token
    }

    private func usableCredential(origin: URL) async throws -> T3Credential? {
        guard let candidate = credential ?? (try? store.load()) else { return nil }

        var request = URLRequest(url: origin.appendingPathComponent(T3Wire.Route.session))
        request.setValue("Bearer \(candidate.token)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await http.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { throw T3Error.notRunning }
        guard let state = try? T3Wire.decoder().decode(T3Wire.SessionState.self, from: data), state.isUsable else {
            return nil
        }
        if let expiresAt = state.expiresAt, expiresAt.timeIntervalSinceNow < renewBefore { return nil }

        credential = candidate
        return candidate
    }

    private func issueSession() async throws -> T3Credential {
        var arguments = ["auth", "session", "issue", "--ttl", ttl, "--label", label, "--json"]
        for scope in T3Wire.scopes { arguments += ["--scope", scope] }
        let output = try await runCommandLine(arguments)
        guard let session = try? T3Wire.decoder().decode(T3Wire.IssuedSession.self, from: output) else {
            throw T3Error.signInFailed
        }
        return T3Credential(sessionID: session.sessionId, token: session.token)
    }

    /// Output can hold a token, so it goes nowhere but back to the caller, and errors never quote it.
    private func runCommandLine(_ arguments: [String]) async throws -> Data {
        let tool = home.appendingPathComponent("bin/t3")
        guard FileManager.default.isExecutableFile(atPath: tool.path) else {
            throw T3Error.commandLineToolMissing
        }
        var environment = ProcessInfo.processInfo.environment
        environment["T3CODE_HOME"] = home.path

        return try await Task.detached {
            let process = Process()
            let output = Pipe()
            process.executableURL = tool
            process.arguments = arguments
            process.environment = environment
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            do { try process.run() } catch { throw T3Error.signInFailed }
            let timeout = DispatchWorkItem { process.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timeout)
            defer { timeout.cancel() }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw T3Error.signInFailed }
            return data
        }.value
    }
}
