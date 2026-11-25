import Foundation

actor T3Auth {
    private let home: URL
    private let store: T3CredentialStoring
    private let label: String
    private let ttl: String
    private let renewBefore: TimeInterval
    private let revokesWhatItCantRead: Bool
    private let http: URLSession

    private var credential: T3Credential?
    private var environment: T3Wire.Environment?
    private var savedHere: Set<String> = []

    init(home: URL, store: T3CredentialStoring, label: String, ttl: String, renewBefore: TimeInterval, revokesWhatItCantRead: Bool = true, http: URLSession? = nil) {
        self.home = home
        self.store = store
        self.label = label
        self.ttl = ttl
        self.renewBefore = renewBefore
        self.revokesWhatItCantRead = revokesWhatItCantRead
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        self.http = http ?? URLSession(configuration: configuration)
    }

    static var defaultHome: URL {
        if let path = ProcessInfo.processInfo.environment["T3CODE_HOME"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".t3", isDirectory: true)
    }

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

    func currentOrigin() throws -> URL { try readOrigin() }

    var environmentID: String? { environment?.environmentId }

    func signOut() async {
        let current = credential ?? (try? store.load())
        credential = nil
        guard let current else { return }
        try? store.delete(sessionID: current.sessionID)
        _ = try? await runCommandLine(["auth", "session", "revoke", current.sessionID])
    }

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

    private func token(origin: URL, forceNew: Bool) async throws -> String {
        if !forceNew, let usable = try await usableCredential(origin: origin) { return usable.token }

        let previous = credential ?? (try? store.load())
        let leftByLastBuild = revokesWhatItCantRead ? try? store.newestUnreadableSessionID() : nil
        let issued = try await issueSession()
        if (try? store.save(issued)) != nil { savedHere.insert(issued.sessionID) }
        credential = issued

        // Outside the repo: deleting a Keychain item another build saved shows a dialog and waits on it, even with prompts off.
        if let previous, savedHere.contains(previous.sessionID) { try? store.delete(sessionID: previous.sessionID) }
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
        guard let (data, response) = try? await http.data(for: request), let status = (response as? HTTPURLResponse)?.statusCode else {
            throw T3Error.notRunning
        }
        if status == 401 { return nil }
        guard status == 200 else { throw T3Error.notRunning }
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
