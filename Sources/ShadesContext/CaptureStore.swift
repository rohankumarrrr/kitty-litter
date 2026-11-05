import Foundation
import ShadesCore

/// Screenshots saved for agents to open. Only you can read them, and they don't stay around.
struct CaptureStore: Sendable {
    static let maxAge: TimeInterval = 7 * 24 * 60 * 60
    private static let prefix = "capture-"
    private static let suffix = ".jpg"

    var directory = Settings.directory.appendingPathComponent("captures", isDirectory: true)

    func save(_ jpeg: Data, now: Date = Date()) throws -> String {
        let files = FileManager.default
        try files.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        removeOld(now: now)

        let name = "\(Self.prefix)\(Int(now.timeIntervalSince1970))-\(UUID().uuidString.prefix(8))\(Self.suffix)"
        let path = directory.appendingPathComponent(name).path
        // Opened with its permissions in place, so it's never readable by others, even for a moment.
        let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: jpeg)
        } catch {
            try? files.removeItem(atPath: path)
            throw error
        }
        return path
    }

    /// Leaves anything we didn't write alone.
    func removeOld(now: Date = Date()) {
        let files = FileManager.default
        let cutoff = now.addingTimeInterval(-Self.maxAge)
        let names = (try? files.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasPrefix(Self.prefix) && name.hasSuffix(Self.suffix) {
            let url = directory.appendingPathComponent(name)
            let modified = (try? files.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
            if let modified, modified < cutoff { try? files.removeItem(at: url) }
        }
    }
}
