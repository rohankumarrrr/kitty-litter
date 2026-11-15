import CZlib
import Foundation

/// gzip, as a phone's browser takes it. On a stream, each event is flushed, so the page can read it as soon as it lands.
final class Gzip {
    private var stream = z_stream()
    private let isOpen: Bool

    init() {
        // 15 bits of window, and 16 more for gzip's wrapping rather than zlib's.
        isOpen = deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 15 + 16, 8, Z_DEFAULT_STRATEGY, zlibVersion(), Int32(MemoryLayout<z_stream>.size)) == Z_OK
    }

    deinit {
        if isOpen { deflateEnd(&stream) }
    }

    static func whole(_ data: Data) -> Data {
        Gzip().deflated(data, Z_FINISH)
    }

    /// What's needed to read everything given so far, packed without looking back at anything before it, so nothing
    /// sent earlier changes its size.
    func flushed(_ data: Data) -> Data {
        deflated(data, Z_FULL_FLUSH)
    }

    /// An event whose parts are each packed on their own. Words a kitten writes, which can be someone else's, would
    /// pack smaller beside the same words of yours, so nothing is packed against anything in another part, or sent before.
    func packed(_ parts: [Data]) -> Data {
        parts.reduce(into: Data()) { $0 += flushed($1) }
    }

    func finished() -> Data {
        deflated(Data(), Z_FINISH)
    }

    private func deflated(_ data: Data, _ flush: Int32) -> Data {
        guard isOpen else { return Data() }
        var input = data
        var output = Data()
        var room = [Bytef](repeating: 0, count: 64 * 1024)
        input.withUnsafeMutableBytes { bytes in
            stream.next_in = bytes.bindMemory(to: Bytef.self).baseAddress
            stream.avail_in = uInt(bytes.count)
            repeat {
                room.withUnsafeMutableBufferPointer { room in
                    stream.next_out = room.baseAddress
                    stream.avail_out = uInt(room.count)
                    _ = deflate(&stream, flush)
                    output.append(room.baseAddress!, count: room.count - Int(stream.avail_out))
                }
            } while stream.avail_out == 0
        }
        return output
    }
}
