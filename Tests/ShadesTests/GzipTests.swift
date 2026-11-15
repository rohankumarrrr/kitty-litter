import CZlib
@testable import Shades
import XCTest

/// The phone's stream packed as its browser reads it. How well words pack depends on what they are, so someone who
/// could get words of their own into a view and see its size could guess at words beside them, one byte at a time.
final class GzipTests: XCTestCase {
    private func unpacked(_ data: Data) -> String {
        var stream = z_stream()
        // 32 more bits of window takes gzip's wrapping, as a browser does.
        XCTAssertEqual(inflateInit2_(&stream, 15 + 32, zlibVersion(), Int32(MemoryLayout<z_stream>.size)), Z_OK)
        defer { inflateEnd(&stream) }
        var input = data
        var output = Data()
        var room = [Bytef](repeating: 0, count: 64 * 1024)
        input.withUnsafeMutableBytes { bytes in
            stream.next_in = bytes.bindMemory(to: Bytef.self).baseAddress
            stream.avail_in = uInt(bytes.count)
            var result = Z_OK
            repeat {
                room.withUnsafeMutableBufferPointer { room in
                    stream.next_out = room.baseAddress
                    stream.avail_out = uInt(room.count)
                    result = inflate(&stream, Z_NO_FLUSH)
                    output.append(room.baseAddress!, count: room.count - Int(stream.avail_out))
                }
            } while result == Z_OK && (stream.avail_in > 0 || stream.avail_out == 0)
        }
        return String(decoding: output, as: UTF8.self)
    }

    /// Letters that never repeat in the same order, so they barely pack, unlike the same letter over and over.
    private func event(_ count: Int, seed: UInt64 = 1) -> String {
        var next = seed
        let letters = (0..<count).map { _ -> Character in
            next = next &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Character(UnicodeScalar(UInt8(32 + (next >> 33) % 95)))
        }
        return "data: " + String(letters) + "\n\n"
    }

    func testEachEventComesToOneOfAFewSizesAndReadsBackAsItWas() {
        let gzip = Gzip()
        var packed = Data()
        var said = ""
        for count in [1, 40, 300, 900, 1_000, 2_500, 9_000, 20_000, 60_000, 150_000] {
            let event = event(count, seed: UInt64(count))
            let sent = gzip.padded(Data(event.utf8))
            XCTAssertEqual(Gzip.size(sent.count), sent.count, "\(count) characters went as \(sent.count) bytes")
            packed += sent
            said += event
        }
        packed += gzip.finished()
        let read = unpacked(packed).components(separatedBy: "\n\n").filter { !$0.isEmpty && !$0.hasPrefix(":") }
        XCTAssertEqual(read.joined(separator: "\n\n") + "\n\n", said, "the page reads every event as it was, and skips what pads it")
    }

    func testAGuessThatPacksBetterIsTheSameSizeOnceItsPadded() {
        let secret = "Your code for the bank is 4F7Q-PL2K, and nobody else should see it."
        func view(guess: String) -> Data {
            Data("data: {\"rows\":[\"\(secret)\",\"A kitten read a page that said: Your code for the bank is \(guess)\"]}\n\n".utf8)
        }
        let right = view(guess: "4F7Q-PL2K"), wrong = view(guess: "9ZXW-MN8R")
        XCTAssertLessThan(Gzip().flushed(right).count, Gzip().flushed(wrong).count, "packed alone, the right guess is smaller")
        XCTAssertEqual(Gzip().padded(right).count, Gzip().padded(wrong).count, "padded, the two look the same")
    }

    /// Swift drops the empty pieces when it splits, and indexing into nothing used to stop the app, from a header any
    /// browser or script that reached the page could send, before its key was ever looked at.
    func testAnyAcceptEncodingIsReadWithoutStoppingTheApp() {
        func takes(_ value: String) -> Bool {
            PhoneServer.Request(method: "GET", path: "/", query: [:], headers: ["accept-encoding": value], body: Data()).takesGzip
        }
        for odd in [";", ";;", " ; ", ",", ""] { XCTAssertFalse(takes(odd), odd) }
        XCTAssertTrue(takes("gzip, deflate, br"))
        XCTAssertTrue(takes("br;q=1.0, GZIP;q=0.5"))
        XCTAssertTrue(takes("gzip, ;"))
        for refused in ["gzip;q=0", "gzip; q=0", "identity, gzip;q=0.000"] { XCTAssertFalse(takes(refused), "q=0 says it isn't wanted: \(refused)") }
    }

    func testThePagesOwnFilesPackWholeAndReadBack() {
        let page = Data(PhonePage.script.utf8)
        let packed = Gzip.whole(page)
        XCTAssertLessThan(packed.count, page.count / 2)
        XCTAssertEqual(unpacked(packed), PhonePage.script)
    }
}
