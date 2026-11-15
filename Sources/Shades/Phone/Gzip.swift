import CZlib
import Foundation

/// gzip, as a phone's browser takes it. On a stream, each event is flushed, so the page can read it as soon as it lands.
final class Gzip {
    /// What a stored block adds around its bytes once the stream's flushed, and the flush after it.
    private static let storedCost = 10
    private static let storedMost = 4096
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

    /// An event whose parts are each packed on their own, then made up to one of a few sizes with a comment the page
    /// skips. Words a kitten writes, which can be someone else's, would pack smaller beside the same words of yours,
    /// so nothing is packed against anything in another part, or sent before.
    func padded(_ parts: [Data]) -> Data {
        let packed = parts.reduce(into: Data()) { $0 += flushed($1) }
        let size = Self.size(packed.count + Self.storedCost + 3)
        return packed + stored(size - packed.count)
    }

    /// The smallest of 1, 1.5, 2, 3, 4, 6, 8 KB and so on that holds `count` bytes.
    static func size(_ count: Int) -> Int {
        var step = 1024
        while true {
            if count <= step { return step }
            if count <= step * 3 / 2 { return step * 3 / 2 }
            step *= 2
        }
    }

    func finished() -> Data {
        deflated(Data(), Z_FINISH)
    }

    /// Exactly `count` bytes of an SSE comment, kept as it is rather than packed, so its size can be known ahead.
    private func stored(_ count: Int) -> Data {
        guard isOpen else { return Data() }
        let blocks = (count + Self.storedMost + Self.storedCost - 1) / (Self.storedMost + Self.storedCost)
        var comment = Data(":".utf8) + Data(repeating: UInt8(ascii: " "), count: count - Self.storedCost * blocks - 3) + Data("\n\n".utf8)
        var output = Data()
        level(0)
        for left in stride(from: blocks, to: 0, by: -1) {
            let part = comment.prefix((comment.count + left - 1) / left)
            output += deflated(part, Z_FULL_FLUSH)
            comment.removeFirst(part.count)
        }
        level(Z_DEFAULT_COMPRESSION)
        return output
    }

    /// Right after a flush there's nothing left to pack at the old level, so nothing is written here.
    private func level(_ level: Int32) {
        stream.avail_out = 0
        deflateParams(&stream, level, Z_DEFAULT_STRATEGY)
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
