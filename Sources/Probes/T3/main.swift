import CoreGraphics
import Foundation
import ImageIO
import ShadesCore
import ShadesT3

// Tries each capability against the real T3 server. Every thread it makes is titled "Shades test:"
// and gets archived, and every sign-in it makes gets revoked. It never prints a token.
//
//   probe-t3 connect    sign in, list threads and projects
//   probe-t3 keychain   first run and second run against a throwaway Keychain entry
//   probe-t3 keychain-launch <service> [forget]   one launch, for testing across rebuilds
//   probe-t3 ask        new thread, streaming, follow-up, follow-up with an image
//   probe-t3 project    a thread bound to a project
//   probe-t3 watch      the live thread list following one thread
//   probe-t3 approval   one approval-required thread, answered in code within a moment
//   probe-t3 open       shows a thread in T3 Code and checks T3 navigated to it
//   probe-t3 restart    runs its own throwaway T3 server, restarts it mid-turn, and checks recovery
//   probe-t3 timing     how much time this client adds to a turn
//   probe-t3 settle     settles a finished thread, then checks a follow-up still works
//   probe-t3 report <thread>   how fast a thread's last report can be read, and how long it is

let sol = ModelChoice(provider: "codex", model: "gpt-6.1-sol", effort: "low")
let clock = ContinuousClock()

func say(_ text: String) {
    print(text)
    fflush(stdout)
}

func milliseconds(_ duration: Duration) -> String {
    let (seconds, attoseconds) = duration.components
    return String(format: "%.1f ms", Double(seconds) * 1000 + Double(attoseconds) / 1e15)
}

func makeBackend(credentials: T3CredentialStoring = MemoryCredentialStore()) -> T3Backend {
    T3Backend(credentials: credentials, label: "Shades probe", sessionTTL: "1h", renewBefore: 0)
}

func prompt(_ title: String, _ text: String, attachments: [AgentAttachment] = [], mode: RuntimeMode = .auto, projectID: String? = nil) -> AgentPrompt {
    AgentPrompt(title: "Shades test: \(title)", text: text, attachments: attachments, model: sol, runtimeMode: mode, projectID: projectID)
}

/// Runs a turn and prints what happened. Returns the thread and the whole reply.
@discardableResult
func runTurn(_ stream: AsyncThrowingStream<AgentReplyEvent, Error>) async throws -> (threadID: String, reply: String) {
    let began = clock.now
    var threadID = ""
    var reply = ""
    var deltas = 0
    for try await event in stream {
        switch event {
        case let .started(id):
            threadID = id
            say("  started after \(milliseconds(clock.now - began))")
        case let .text(delta):
            if deltas == 0 { say("  first text after \(milliseconds(clock.now - began))") }
            deltas += 1
            reply += delta
        case let .needsApproval(request):
            say("  unexpected approval: \(request.summary)")
        case let .finished(fullText):
            say("  finished after \(milliseconds(clock.now - began)), \(deltas) deltas, deltas match the full text: \(reply == fullText)")
            say("  reply: \(fullText.prefix(120))")
            reply = fullText
        case let .failed(message):
            say("  failed: \(message)")
        }
    }
    return (threadID, reply)
}

func sessions(labeled label: String) -> [String] {
    let tool = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".t3/bin/t3")
    let process = Process()
    let output = Pipe()
    process.executableURL = tool
    process.arguments = ["auth", "session", "list", "--json"]
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return [] }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
    return list.compactMap { session in
        guard (session["client"] as? [String: Any])?["label"] as? String == label else { return nil }
        return session["sessionId"] as? String
    }
}

/// A red square, so the model has something to look at.
let redSquarePNG: Data = {
    let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}()

/// Asks the server directly, for checks the backend has no reason to offer.
func serverJSON(_ path: String, credentials: MemoryCredentialStore) async -> [String: Any]? {
    let runtime = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".t3/userdata/server-runtime.json")
    guard let info = (try? JSONSerialization.jsonObject(with: Data(contentsOf: runtime))) as? [String: Any],
          let origin = info["origin"] as? String,
          let url = URL(string: origin + path),
          let token = credentials.load()?.token
    else { return nil }
    var request = URLRequest(url: url)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("2", forHTTPHeaderField: "x-t3-orchestration-protocol")
    guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

/// About the size of a real screenshot. Noise, because that's what doesn't compress.
func noisyJPEG() -> Data {
    let width = 900, height = 600
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    var generator = SystemRandomNumberGenerator()
    for y in stride(from: 0, to: height, by: 4) {
        for x in stride(from: 0, to: width, by: 4) {
            context.setFillColor(red: .random(in: 0...1, using: &generator), green: .random(in: 0...1, using: &generator), blue: .random(in: 0...1, using: &generator), alpha: 1)
            context.fill(CGRect(x: x, y: y, width: 4, height: 4))
        }
    }
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
    CGImageDestinationFinalize(destination)
    return data as Data
}

// MARK: Probes

func probeConnect() async throws {
    let backend = makeBackend()
    let began = clock.now
    try await backend.connect()
    say("connected, including first sign-in, in \(milliseconds(clock.now - began))")

    let listed = clock.now
    let projects = try await backend.projects()
    say("\(projects.count) projects after \(milliseconds(clock.now - listed)): \(projects.map(\.title).joined(separator: ", "))")

    var threads: [AgentThread] = []
    for await list in backend.watchThreads() {
        threads = list
        break
    }
    say("\(threads.count) threads listed, by status: \(statusCounts(threads))")
    await backend.signOut()
    await backend.disconnect()
}

func statusCounts(_ threads: [AgentThread]) -> String {
    Dictionary(grouping: threads, by: \.status.rawValue)
        .map { "\($0.key) \($0.value.count)" }
        .sorted()
        .joined(separator: ", ")
}

func probeKeychain() async throws {
    // A throwaway entry, so the real first run still really is the first run.
    let service = "dev.shades.t3-session.probe.\(UUID().uuidString)"
    let store = KeychainCredentialStore(service: service)
    let label = "Shades probe"
    let before = sessions(labeled: label).count

    let first = makeBackend(credentials: store)
    var began = clock.now
    try await first.connect()
    say("first run: signed in and connected in \(milliseconds(clock.now - began))")
    say("in Keychain: \((try store.load()) != nil), sessions added: \(sessions(labeled: label).count - before)")
    await first.disconnect()

    let second = makeBackend(credentials: store)
    began = clock.now
    try await second.connect()
    say("second run: connected with the saved sign-in in \(milliseconds(clock.now - began))")
    say("sessions added in total: \(sessions(labeled: label).count - before)")

    await second.signOut()
    await second.disconnect()
    say("after sign-out, in Keychain: \((try store.load()) != nil), sessions left: \(sessions(labeled: label).count - before)")
}

/// One app launch against a named Keychain entry, for checking what happens across rebuilds.
/// Pass "forget" as well to sign out and clear what this build owns.
func probeKeychainLaunch() async throws {
    guard CommandLine.arguments.count > 2 else {
        say("usage: probe-t3 keychain-launch <service> [forget]")
        return
    }
    let backend = makeBackend(credentials: KeychainCredentialStore(service: CommandLine.arguments[2]))
    let began = clock.now
    try await backend.connect()
    say("connected in \(milliseconds(clock.now - began))")
    if CommandLine.arguments.contains("forget") { await backend.signOut() }
    await backend.disconnect()
    // Replaced sessions get revoked in the background, so give that a moment.
    try await Task.sleep(for: .seconds(2))
}

func probeAsk() async throws {
    let backend = makeBackend()
    try await backend.connect()
    say("new no-project thread")
    let (threadID, _) = try await runTurn(backend.start(prompt("ask", "Write a 100 word story about a cat.")))

    say("follow-up")
    try await runTurn(backend.followUp(threadID: threadID, prompt("ask", "Now say the word meow once.")))

    say("follow-up with an image")
    let image = AgentAttachment(name: "red.png", mimeType: "image/png", data: redSquarePNG)
    try await runTurn(backend.followUp(threadID: threadID, prompt("ask", "What color is this image? One word.", attachments: [image])))

    say("new thread with an image")
    let (imageThreadID, _) = try await runTurn(backend.start(prompt("image", "What color is this image? One word.", attachments: [image])))

    try await backend.archive(threadID: threadID)
    try await backend.archive(threadID: imageThreadID)
    await backend.signOut()
    await backend.disconnect()
}

func probeProject() async throws {
    let backend = makeBackend()
    try await backend.connect()
    let projects = try await backend.projects()
    guard let project = projects.first(where: { $0.title == "Shades" }) ?? projects.first else {
        say("no projects to bind to")
        return
    }
    say("thread bound to \(project.title)")
    let (threadID, _) = try await runTurn(backend.start(prompt("project", "Reply with exactly: ok", projectID: project.id)))

    var listed: AgentThread?
    for await threads in backend.watchThreads() {
        listed = threads.first { $0.id == threadID }
        if listed?.projectTitle != nil { break }
    }
    say("dashboard shows project: \(listed?.projectTitle ?? "none"), model: \(listed?.model ?? "none")")
    try await backend.archive(threadID: threadID)
    await backend.signOut()
    await backend.disconnect()
}

func probeWatch() async throws {
    let backend = makeBackend()
    let watcher = Task {
        var seen: [AgentStatus] = []
        var updates = 0
        for await threads in backend.watchThreads() {
            updates += 1
            if updates == 1 { say("first list: \(threads.count) threads, \(statusCounts(threads))") }
            guard let thread = threads.first(where: { $0.title.hasPrefix("Shades test: watch") }) else { continue }
            if seen.last != thread.status {
                seen.append(thread.status)
                say("  status: \(thread.status.rawValue)")
            }
            if thread.status == .completed { break }
        }
        return seen
    }
    try await backend.connect()
    let (threadID, _) = try await runTurn(backend.start(prompt("watch", "Reply with exactly: ok")))
    let seen = await watcher.value
    say("statuses in order: \(seen.map(\.rawValue).joined(separator: " > "))")

    try await backend.archive(threadID: threadID)
    let gone = Task {
        for await threads in backend.watchThreads() where !threads.contains(where: { $0.id == threadID }) { return true }
        return false
    }
    say("gone from the list after archiving: \(await gone.value)")
    await backend.signOut()
    await backend.disconnect()
}

/// Whichever path sees the request first answers it, so a thread can't be left waiting.
actor ApprovalAnswerer {
    private var answered: Set<String> = []
    let backend: T3Backend
    let began = clock.now

    init(backend: T3Backend) {
        self.backend = backend
    }

    func answer(_ request: ApprovalRequest, seenBy path: String) async {
        guard answered.insert(request.id).inserted else { return }
        let seen = clock.now
        say("  \(path) saw approval \(milliseconds(seen - began)) in: [\(request.kind.rawValue)] \(request.summary)")
        do {
            try await backend.respond(to: request, with: .accept)
            say("  answered in \(milliseconds(clock.now - seen))")
        } catch {
            say("  answer failed: \(error.localizedDescription)")
        }
    }
}

func probeApproval() async throws {
    let backend = makeBackend()
    try await backend.connect()
    let answerer = ApprovalAnswerer(backend: backend)
    let listSawIt = ListSighting()

    let watcher = Task {
        for await threads in backend.watchThreads() {
            for thread in threads where thread.title.hasPrefix("Shades test: approval") {
                if let request = thread.pendingApprovals.first {
                    await listSawIt.note(status: thread.status, summary: request.summary)
                    // Only a backstop: the stream should have answered this already.
                    try? await Task.sleep(for: .milliseconds(1500))
                    await answerer.answer(request, seenBy: "list")
                }
            }
        }
    }

    let command = "echo shades-approval-test > /tmp/shades-approval-test.txt"
    let turn = prompt("approval", "Run this exact shell command, then reply done: \(command)", mode: .approvalRequired)
    var threadID = ""
    let run = Task {
        for try await event in backend.start(turn) {
            switch event {
            case let .started(id):
                threadID = id
                say("  started")
            case let .needsApproval(request):
                // A short wait, so the list has time to show it too. T3 shows the prompt until this answers.
                try? await Task.sleep(for: .milliseconds(700))
                await answerer.answer(request, seenBy: "stream")
            case let .finished(text):
                say("  finished: \(text.prefix(80))")
            case let .failed(message):
                say("  failed: \(message)")
            case .text:
                break
            }
        }
    }

    // Never leave a test thread waiting, whatever goes wrong above.
    let finished = await withTaskGroup(of: Bool.self) { group -> Bool in
        group.addTask { (try? await run.value) != nil }
        group.addTask {
            try? await Task.sleep(for: .seconds(60))
            return false
        }
        let first = await group.next() ?? false
        group.cancelAll()
        return first
    }
    run.cancel()
    say("  turn ended on its own: \(finished)")
    say("  the list also showed it: \(await listSawIt.description)")
    watcher.cancel()

    if !threadID.isEmpty { try await backend.archive(threadID: threadID) }
    try? FileManager.default.removeItem(atPath: "/tmp/shades-approval-test.txt")
    await backend.signOut()
    await backend.disconnect()
}

actor ListSighting {
    private var sighting: String?

    func note(status: AgentStatus, summary: String) {
        if sighting == nil { sighting = "\(status.rawValue), \(summary)" }
    }

    var description: String { sighting ?? "no" }
}

func probeOpen() async throws {
    let store = MemoryCredentialStore()
    let backend = makeBackend(credentials: store)
    try await backend.connect()
    let (threadID, _) = try await runTurn(backend.start(prompt("open", "Reply with exactly: ok")))

    func lastVisited() async -> String? {
        guard let shell = await serverJSON("/api/orchestration/shell", credentials: store),
              let threads = shell["threads"] as? [[String: Any]]
        else { return nil }
        return threads.first { $0["id"] as? String == threadID }?["lastVisitedAt"] as? String
    }

    let before = await lastVisited()
    backend.open(threadID: threadID)
    var after = before
    for _ in 0..<40 where after == before {
        try await Task.sleep(for: .milliseconds(250))
        after = await lastVisited()
    }
    say("T3 visited the thread: \(after != before) (before \(before ?? "never"), after \(after ?? "never"))")

    try await backend.archive(threadID: threadID)
    await backend.signOut()
    await backend.disconnect()
}

/// A separate T3 server with its own data folder and port, so the real one is never touched.
final class ThrowawayServer {
    let home: URL
    private var process: Process?
    private let tool = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".t3/bin/t3")

    init() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("shades-t3-probe-\(UUID().uuidString)", isDirectory: true)
        let bin = home.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: bin.appendingPathComponent("t3"), withDestinationURL: tool)
    }

    func start(port: Int) async throws {
        let process = Process()
        process.executableURL = tool
        process.arguments = ["serve", "--port", String(port), "--host", "127.0.0.1", "--no-browser"]
        process.environment = ProcessInfo.processInfo.environment.merging(["T3CODE_HOME": home.path]) { $1 }
        process.currentDirectoryURL = home
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        self.process = process

        let url = URL(string: "http://127.0.0.1:\(port)/.well-known/t3/environment")!
        for _ in 0..<120 {
            if let (_, response) = try? await URLSession.shared.data(from: url), (response as? HTTPURLResponse)?.statusCode == 200 { return }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw T3Error.notRunning
    }

    func stop() {
        guard let process else { return }
        process.terminate()
        process.waitUntilExit()
        self.process = nil
    }

    func revoke(sessionID: String) {
        let process = Process()
        process.executableURL = tool
        process.arguments = ["auth", "session", "revoke", sessionID]
        process.environment = ProcessInfo.processInfo.environment.merging(["T3CODE_HOME": home.path]) { $1 }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    func remove() {
        stop()
        try? FileManager.default.removeItem(at: home)
    }
}

func probeRestart() async throws {
    let server = try ThrowawayServer()
    defer { server.remove() }
    try await server.start(port: 39871)
    say("throwaway server up on 39871")

    let store = MemoryCredentialStore()
    let backend = T3Backend(home: server.home, credentials: store, label: "Shades probe", sessionTTL: "1h", renewBefore: 0)
    try await backend.connect()
    guard let firstSession = store.load()?.sessionID else { return }
    say("connected")

    let updates = LatestList()
    let watcher = Task {
        for await threads in backend.watchThreads() { await updates.set(threads) }
    }
    while await updates.threads == nil { try await Task.sleep(for: .milliseconds(50)) }
    say("thread list is live, \(await updates.threads?.count ?? 0) threads")

    // Start a turn that's still going when the server goes away.
    let began = clock.now
    let turn = Task { () -> String in
        var outcome = "ended without a final event"
        do {
            for try await event in backend.start(prompt("restart", "Write a 150 word story about a cat.")) {
                switch event {
                case let .started(id): say("  turn started on \(id.prefix(8))")
                case let .finished(text): outcome = "finished, \(text.count) characters"
                case let .failed(message): outcome = "failed: \(message)"
                case .text, .needsApproval: break
                }
            }
        } catch {
            outcome = "threw: \(error.localizedDescription)"
        }
        return outcome
    }
    try await Task.sleep(for: .seconds(2))

    server.stop()
    say("server stopped after \(milliseconds(clock.now - began)) of the turn")

    do {
        let downAt = clock.now
        try await backend.connect()
        say("connect while down: unexpectedly connected after \(milliseconds(clock.now - downAt))")
    } catch {
        say("connect while down: \(error.localizedDescription)")
    }

    // Revoke while it's down, so coming back also has to sign in again.
    server.revoke(sessionID: firstSession)
    try await server.start(port: 39872)
    let backUp = clock.now
    say("server back on a different port, 39872, with our session revoked")

    var reconnected = false
    for _ in 0..<80 {
        if (try? await backend.connect()) != nil {
            reconnected = true
            break
        }
        try await Task.sleep(for: .milliseconds(250))
    }
    say("reconnected: \(reconnected), \(milliseconds(clock.now - backUp)) after the server came back")
    say("signed in again without help: \(store.load()?.sessionID != firstSession)")

    say("interrupted turn: \(await turn.value)")
    var listed = false
    for _ in 0..<40 {
        if await updates.threads?.contains(where: { $0.title.hasPrefix("Shades test: restart") }) == true {
            listed = true
            break
        }
        try await Task.sleep(for: .milliseconds(250))
    }
    say("the resubscribed list shows the thread from before the restart: \(listed)")
    watcher.cancel()

    await backend.signOut()
    await backend.disconnect()
}

actor LatestList {
    var threads: [AgentThread]?

    func set(_ threads: [AgentThread]) {
        self.threads = threads
    }
}

func probeTiming() async throws {
    let store = MemoryCredentialStore()
    let backend = makeBackend(credentials: store)
    var began = clock.now
    try await backend.connect()
    say("connect, with a fresh sign-in: \(milliseconds(clock.now - began))")
    began = clock.now
    _ = try await backend.projects()
    say("first thread list: \(milliseconds(clock.now - began))")

    let screenshot = AgentAttachment(name: "screen.jpg", mimeType: "image/jpeg", data: noisyJPEG())
    say("screenshot-sized image: \(screenshot.data.count / 1024) KB")

    for round in 1...4 {
        let wallClockStart = Date()
        let start = clock.now
        var started: Duration?
        var finished: Duration?
        var threadID = ""
        var finishedAt = Date()
        // The last round carries a screenshot, so the time to start includes uploading it.
        let attachments = round == 4 ? [screenshot] : []
        for try await event in backend.start(prompt("timing \(round)", "Reply with exactly: ok", attachments: attachments)) {
            switch event {
            case let .started(id):
                threadID = id
                started = clock.now - start
            case .finished:
                finished = clock.now - start
                finishedAt = Date()
            default:
                break
            }
        }
        let thread = await serverJSON("/api/orchestration/threads/\(threadID.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? threadID)", credentials: store)
        let run = ((thread?["projection"] as? [String: Any])?["runs"] as? [[String: Any]])?.first ?? (thread?["runs"] as? [[String: Any]])?.first
        func date(_ key: String) -> Date? {
            (run?[key] as? String).flatMap { try? Date($0, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) }
        }
        let before = date("requestedAt").map { $0.timeIntervalSince(wallClockStart) * 1000 }
        let after = date("completedAt").map { finishedAt.timeIntervalSince($0) * 1000 }
        say(String(
            format: "round %d: started %@, finished %@. before the server's requestedAt: %@, after its completedAt: %@",
            round,
            milliseconds(started ?? .zero),
            milliseconds(finished ?? .zero),
            before.map { String(format: "%.1f ms", $0) } ?? "?",
            after.map { String(format: "%.1f ms", $0) } ?? "?"
        ))
        try await backend.archive(threadID: threadID)
    }
    await backend.signOut()
    await backend.disconnect()
}

func probeSettle() async throws {
    let backend = T3Backend()
    try await backend.connect()
    func turn(_ events: AsyncThrowingStream<AgentReplyEvent, Error>) async throws -> (String?, String?) {
        var threadID: String?
        var text: String?
        for try await event in events {
            if case let .started(id) = event { threadID = id }
            if case let .finished(full) = event { text = full }
            if case let .failed(message) = event { say("turn failed: \(message)") }
        }
        return (threadID, text)
    }
    let prompt = AgentPrompt(title: "Shades test: settle", text: "Reply with exactly: one", model: sol, runtimeMode: .auto)
    let (threadID, first) = try await turn(backend.start(prompt))
    guard let threadID else { throw NSError(domain: "probe", code: 1) }
    say("first reply: \(first ?? "none")")
    try await backend.settle(threadID: threadID)
    say("settled \(threadID)")
    let next = AgentPrompt(title: "Shades test: settle", text: "Reply with exactly: two", model: sol, runtimeMode: .auto)
    let (_, second) = try await turn(backend.followUp(threadID: threadID, next))
    say("follow-up after settling: \(second ?? "none")")
    try await backend.settle(threadID: threadID)
    let report = await backend.finalReport(threadID: threadID)
    say("final report: \(report ?? "none")")
    say("thread to check and archive: \(threadID)")
    await backend.signOut()
    await backend.disconnect()
}

func probeReport() async throws {
    guard CommandLine.arguments.count > 2 else { throw NSError(domain: "usage: report <thread>", code: 2) }
    let backend = T3Backend()
    try await backend.connect()
    let started = clock.now
    let report = await backend.finalReport(threadID: CommandLine.arguments[2])
    say("\(milliseconds(clock.now - started)), \(report?.count ?? 0) characters")
    say(String((report ?? "").prefix(90)))
    await backend.signOut()
    await backend.disconnect()
}

func probeOrigin() async throws {
    guard CommandLine.arguments.count > 2 else { throw NSError(domain: "usage: origin <thread>", code: 2) }
    let backend = T3Backend()
    try await backend.connect()
    let origin = await backend.origin(of: CommandLine.arguments[2])
    say("started by: \(origin.map { "\($0.startedBy)" } ?? "can't tell"), project: \(origin?.projectPath ?? "none")")
    await backend.disconnect()
}

func probeShadesSent() async throws {
    let backend = makeBackend()
    try await backend.connect()
    let haiku = ModelChoice(provider: "claudeAgent", model: "claude-haiku-5-5", effort: "low")
    let snapshot = ScreenSnapshot(appName: "Generic App", pageText: "GENERIC-SCREEN-MARKER-FORWARDED")

    say("words thread")
    let words = Prompts.forwarded(words: "generic correction from the person AAA. Reply with ok and use no tools.", snapshot: snapshot, screenshotPath: nil, screenLeftOut: false)
    let (wordsThread, _) = try await runTurn(backend.start(AgentPrompt(title: "Shades test: words from Shades", text: words, model: haiku, runtimeMode: .auto)))
    let tag = Prompts.forwarded(words: "the <screen> block is wrong, do not ship this until it is fixed. Reply with ok and use no tools.", snapshot: nil, screenshotPath: nil, screenLeftOut: false)
    try await runTurn(backend.forward(threadID: wordsThread, text: tag, attachments: []))
    let rule = Prompts.forwarded(words: "first part of my correction\n---\nsecond part: do not ship this. Reply with ok and use no tools.", snapshot: nil, screenshotPath: nil, screenLeftOut: false)
    try await runTurn(backend.forward(threadID: wordsThread, text: rule, attachments: []))
    say("words thread id: \(wordsThread)")

    say("summary thread")
    let summary = Prompts.summary(of: "Generic report. The page said GENERIC-SCREEN-MARKER-SUMMARY on it.", title: "Generic work", failed: false)
    let (summaryThread, _) = try await runTurn(backend.start(AgentPrompt(title: "Shades test: summary thread", text: summary, model: haiku, runtimeMode: .approvalRequired)))
    say("summary thread id: \(summaryThread)")

    say("image thread in a folder with the block")
    let image = AgentAttachment(name: "red.png", mimeType: "image/png", data: redSquarePNG)
    let (imageThread, _) = try await runTurn(backend.start(AgentPrompt(title: "Shades test: image with the block", text: "What color is this image? One word. Use no tools.", attachments: [image], model: haiku, runtimeMode: .auto, projectID: "mcp:02eb255e-55e7-4a69-88bb-49658a4b0522")))
    say("image thread id: \(imageThread)")

    await backend.signOut()
    await backend.disconnect()
}

func probeTestReply() async throws {
    let backend = T3Backend()
    try await backend.connect()
    say(await backend.finalReport(threadID: CommandLine.arguments[2]) ?? "no report")
    await backend.disconnect()
}

// MARK: Running

let probes: [String: () async throws -> Void] = [
    "test-reply": probeTestReply,
    "shades-sent": probeShadesSent,
    "connect": probeConnect,
    "keychain": probeKeychain,
    "keychain-launch": probeKeychainLaunch,
    "ask": probeAsk,
    "project": probeProject,
    "watch": probeWatch,
    "approval": probeApproval,
    "open": probeOpen,
    "restart": probeRestart,
    "timing": probeTiming,
    "settle": probeSettle,
    "report": probeReport,
    "origin": probeOrigin,
]

guard let name = CommandLine.arguments.dropFirst().first, let probe = probes[name] else {
    say("usage: probe-t3 \(probes.keys.sorted().joined(separator: "|"))")
    exit(2)
}

do {
    try await probe()
    say("done")
    exit(0)
} catch {
    say("failed: \(error.localizedDescription)")
    exit(1)
}
