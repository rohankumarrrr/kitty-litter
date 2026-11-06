import Foundation

/// Puts the phone page on your tailnet with Tailscale Serve, the way T3 Code's own pairing does, so the phone gets a
/// real certificate for your Mac's tailnet name. Only devices on your tailnet can reach it.
///
/// Serve keeps forwarding after Shades stops, and whatever took Shades' loopback port then would get what your phone
/// sends, its key included. So while the page is on, a small helper waits on a pipe from Shades, and takes the page off
/// once that pipe closes, which happens whenever Shades stops, a crash included.
@MainActor
final class TailscaleServe {
    struct Problem: LocalizedError {
        var errorDescription: String?
    }

    /// Wherever the command-line tool or the app is.
    nonisolated static let places = ["/usr/local/bin/tailscale", "/opt/homebrew/bin/tailscale", "/Applications/Tailscale.app/Contents/MacOS/Tailscale"]

    let port: UInt16
    private let tool: String?
    private(set) var helper: (process: Process, pipe: Pipe)?

    init(port: UInt16, tool: String? = TailscaleServe.places.first(where: FileManager.default.isExecutableFile)) {
        self.port = port
        self.tool = tool
    }

    /// Serves the loopback port over HTTPS on `port`, and returns the address to open.
    func serve(to local: UInt16) async throws -> String {
        guard let tool else { throw Problem(errorDescription: "Tailscale isn't installed.") }
        _ = try await Self.run(tool, ["serve", "--bg", "--https=\(port)", "http://127.0.0.1:\(local)"])
        if helper == nil { helper = try watch(tool) }
        let status = try await Self.run(tool, ["status", "--json"])
        struct Status: Decodable {
            struct Peer: Decodable {
                var DNSName: String
            }
            var me: Peer
            enum CodingKeys: String, CodingKey { case me = "Self" }
        }
        let name = try JSONDecoder().decode(Status.self, from: status).me.DNSName
        guard !name.isEmpty else { throw Problem(errorDescription: "Tailscale didn't say this Mac's name.") }
        return "https://\(name.hasSuffix(".") ? String(name.dropLast()) : name):\(port)"
    }

    func stop() async {
        // Stopped first, so it can't take the page off after it's back on.
        helper?.process.terminate()
        helper = nil
        guard let tool else { return }
        _ = try? await Self.run(tool, ["serve", "--https=\(port)", "off"])
    }

    /// Shades never writes to the pipe. The system closes it when Shades stops, however it stops.
    private func watch(_ tool: String) throws -> (process: Process, pipe: Pipe) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "read _; exec \"$0\" serve --https=\"$1\" off", tool, String(port)]
        let pipe = Pipe()
        process.standardInput = pipe
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return (process, pipe)
    }

    private nonisolated static func run(_ tool: String, _ arguments: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: tool)
                process.arguments = arguments
                let output = Pipe()
                let errors = Pipe()
                process.standardOutput = output
                process.standardError = errors
                do {
                    try process.run()
                } catch {
                    return continuation.resume(throwing: error)
                }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let said = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    let line = said.split(separator: "\n").first.map(String.init) ?? "it stopped with \(process.terminationStatus)"
                    return continuation.resume(throwing: Problem(errorDescription: "Tailscale said: \(line)"))
                }
                continuation.resume(returning: data)
            }
        }
    }
}
