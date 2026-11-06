import Foundation

/// Puts the phone page on your tailnet with Tailscale Serve, the way T3 Code's own pairing does, so the phone gets a
/// real certificate for your Mac's tailnet name. Only devices on your tailnet can reach it.
enum Tailscale {
    struct Problem: LocalizedError {
        var errorDescription: String?
    }

    /// Wherever the command-line tool or the app is.
    private static let places = ["/usr/local/bin/tailscale", "/opt/homebrew/bin/tailscale", "/Applications/Tailscale.app/Contents/MacOS/Tailscale"]

    /// Serves the port over HTTPS on the same port, and returns the address to open.
    static func serve(_ port: UInt16) async throws -> String {
        _ = try await run(["serve", "--bg", "--https=\(port)", "http://127.0.0.1:\(port)"])
        let status = try await run(["status", "--json"])
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

    static func stopServing(_ port: UInt16) async {
        _ = try? await run(["serve", "--https=\(port)", "off"])
    }

    private static func run(_ arguments: [String]) async throws -> Data {
        guard let tool = places.first(where: FileManager.default.isExecutableFile) else {
            throw Problem(errorDescription: "Tailscale isn't installed.")
        }
        return try await withCheckedThrowingContinuation { continuation in
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
