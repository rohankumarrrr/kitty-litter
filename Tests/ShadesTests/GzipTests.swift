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

    func testEachEventReadsBackAsItWasWithNothingAdded() {
        let gzip = Gzip()
        var packed = Data()
        var said = ""
        for count in [1, 40, 300, 900, 1_000, 2_500, 9_000, 20_000, 60_000, 150_000] {
            let event = event(count, seed: UInt64(count))
            packed += gzip.packed([Data(event.utf8)])
            said += event
        }
        packed += gzip.finished()
        XCTAssertEqual(unpacked(packed), said, "the page reads every event as it was, with nothing padding it out")
    }

    /// Padding to a few sizes didn't help: words tuned to sit at the edge of a size told a right guess from a wrong one
    /// every time. What stops it is that a row is never packed against another row, or anything sent before.
    func testAGuessInOneRowDoesntPackAgainstWordsInAnother() {
        let yours = Data(#"{"rows":[{"text":"Your code for the bank is 4F7QPL2K9X, and nobody else should see it."}"#.utf8)
        func kittens(_ guess: String) -> Data { Data(#",{"text":"A page said your code for the bank is \#(guess)."}]}"#.utf8) }
        // The same letters backwards, so the two only differ in whether they repeat your words.
        let right = kittens("4F7QPL2K9X"), wrong = kittens("X9K2LPQ7F4")
        func packed(_ parts: [Data]) -> Int {
            let gzip = Gzip()
            return parts.reduce(0) { $0 + gzip.flushed($1).count }
        }
        XCTAssertLessThan(packed([yours + right]), packed([yours + wrong]), "packed together, the right guess is smaller")
        XCTAssertEqual(packed([yours, right]), packed([yours, wrong]), "packed as rows, the two are the same size")
        func later(_ guess: Data) -> Int {
            let gzip = Gzip()
            _ = gzip.flushed(yours)
            return gzip.flushed(guess).count
        }
        XCTAssertEqual(later(right), later(wrong), "and a later event doesn't pack against an earlier one")
    }

    func testAPingIsTheSameSizeWhateverCameBefore() {
        let ping = Data(": ping\n\n".utf8)
        let after = ["pin", "PIN", "ping ping ping", ""].map { before -> Int in
            let gzip = Gzip()
            _ = gzip.packed([Data("data: {\"text\":\"my \(before)\"}\n\n".utf8)])
            return gzip.flushed(ping).count
        }
        XCTAssertEqual(Set(after).count, 1, "\(after)")
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
