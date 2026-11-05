import CryptoKit
import Foundation
import ShadesCore

/// Downloads models the first time they're needed. They never ship in the repo.
public enum ModelStore {
    public static var folder: URL {
        Settings.directory.appendingPathComponent("models", isDirectory: true)
    }

    /// Fetches a file unless it's already here, checking its size and checksum before anyone trusts it.
    static func fetch(
        from url: URL,
        to destination: URL,
        byteCount: Int64,
        sha256: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let manager = FileManager.default
        if let size = (try? manager.attributesOfItem(atPath: destination.path))?[.size] as? Int64, size == byteCount {
            progress(1)
            return
        }
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        let download = FileDownload(progress: progress)
        let temporary = try await download.run(url)
        defer { try? manager.removeItem(at: temporary) }

        let size = (try manager.attributesOfItem(atPath: temporary.path)[.size] as? Int64) ?? 0
        guard size == byteCount, try digest(of: temporary) == sha256 else {
            throw VoiceError.downloadFailed(destination.lastPathComponent)
        }
        try? manager.removeItem(at: destination)
        try manager.moveItem(at: temporary, to: destination)
        progress(1)
    }

    static func digest(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 4 * 1024 * 1024), !data.isEmpty {
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// One download with progress, because URLSession only reports progress to a delegate.
private final class FileDownload: NSObject, URLSessionDownloadDelegate {
    private let progress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<URL, Error>?

    init(progress: @escaping @Sendable (Double) -> Void) {
        self.progress = progress
    }

    func run(_ url: URL) async throws -> URL {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The system deletes `location` as soon as this returns, so it has to move right here.
        let kept = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 else {
                throw VoiceError.downloadFailed(downloadTask.originalRequest?.url?.lastPathComponent ?? "a model")
            }
            try FileManager.default.moveItem(at: location, to: kept)
            continuation?.resume(returning: kept)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
