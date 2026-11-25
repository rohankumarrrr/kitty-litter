import CZlib
import Foundation

final class Gzip {
    private var stream = z_stream()
    private let isOpen: Bool

    init() {
        // Outside the repo: zlib takes 15 bits of window plus 16 to wrap its output as gzip rather than zlib.
        isOpen = deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 15 + 16, 8, Z_DEFAULT_STRATEGY, zlibVersion(), Int32(MemoryLayout<z_stream>.size)) == Z_OK
    }

    deinit {
        if isOpen { deflateEnd(&stream) }
    }

    static func whole(_ data: Data) -> Data {
        Gzip().deflated(data, Z_FINISH)
    }

    func flushed(_ data: Data) -> Data {
        deflated(data, Z_FULL_FLUSH)
    }

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
