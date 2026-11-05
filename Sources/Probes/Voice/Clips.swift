import Foundation

/// Spoken test clips, made with `say` in a temp folder that's safe to delete.
enum Clips {
    struct Clip {
        let utterance: Utterance
        let voice: String
        let url: URL
    }

    static let folder = FileManager.default.temporaryDirectory.appendingPathComponent("shades-voice-clips", isDirectory: true)

    static func all(voices: [String] = Corpus.voices, utterances: [Utterance] = Corpus.utterances) throws -> [Clip] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var clips: [Clip] = []
        for utterance in utterances {
            for voice in voices {
                let url = folder.appendingPathComponent("\(utterance.id)-\(slug(voice)).wav")
                if !FileManager.default.fileExists(atPath: url.path) {
                    try render(utterance.spoken, voice: voice, to: url)
                }
                clips.append(Clip(utterance: utterance, voice: voice, url: url))
            }
        }
        return clips
    }

    private static func slug(_ voice: String) -> String {
        String(voice.prefix { $0 != " " }).lowercased()
    }

    private static func render(_ text: String, voice: String, to url: URL) throws {
        let aiff = url.deletingPathExtension().appendingPathExtension("aiff")
        defer { try? FileManager.default.removeItem(at: aiff) }
        try run("/usr/bin/say", ["-v", voice, "-o", aiff.path, text])
        try run("/usr/bin/afconvert", ["-f", "WAVE", "-d", "LEI16@16000", "-c", "1", aiff.path, url.path])
    }

    private static func run(_ path: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "clips", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "\(path) failed"])
        }
    }
}
