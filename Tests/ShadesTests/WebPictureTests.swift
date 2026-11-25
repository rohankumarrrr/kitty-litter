import Network
@testable import Shades
import TestSupport
import XCTest

@MainActor
final class WebPictureTests: XCTestCase {
    private let onTheWeb: [UInt8] = [93, 184, 215, 14]
    private let atHome: [UInt8] = [192, 168, 1, 2]
    private let picture = PictureResponse(status: 200, headers: ["content-type": "image/png"], body: Data("png".utf8))

    func testAPictureIsFetchedFromTheAddressThatWasCheckedEvenIfTheNameAnswersDifferentlyLater() async {
        var lookups = 0
        var asked: [PictureRequest] = []
        let url = URL(string: "https://pictures.example/a.png")!
        let data = await WebPicture.fetch(url, resolve: { _ in
            lookups += 1
            return lookups == 1 ? [self.onTheWeb] : [[127, 0, 0, 1]]
        }, get: { request in
            asked.append(request)
            return self.picture
        })
        XCTAssertEqual(data, Data("png".utf8))
        XCTAssertEqual(asked, [PictureRequest(url: url, address: onTheWeb)], "it connects to the address it checked")
        XCTAssertEqual(lookups, 1, "the name is looked up once, so it can't answer differently in between")
    }

    func testANameThatAnswersWithAnyHomeAddressIsNeverAsked() async {
        var asked = 0
        let data = await WebPicture.fetch(URL(string: "https://pictures.example/a.png")!, resolve: { _ in [self.onTheWeb, self.atHome] }, get: { _ in
            asked += 1
            return self.picture
        })
        XCTAssertNil(data)
        XCTAssertEqual(asked, 0)
    }

    func testARedirectIsCheckedAgainAndOneIntoYourNetworkIsRefused() async {
        var asked: [PictureRequest] = []
        let addresses = ["pictures.example": onTheWeb, "router.example": atHome, "cdn.example": [151, 101, 1, 1]]
        func fetch(_ location: String) async -> Data? {
            asked = []
            return await WebPicture.fetch(URL(string: "https://pictures.example/a.png")!, resolve: { addresses[$0].map { [$0] } }, get: { request in
                asked.append(request)
                return request.url.host == "pictures.example"
                    ? PictureResponse(status: 302, headers: ["location": location], body: Data())
                    : self.picture
            })
        }
        let followed = await fetch("https://cdn.example/b.png")
        XCTAssertEqual(followed, Data("png".utf8))
        XCTAssertEqual(asked.map(\.address), [onTheWeb, [151, 101, 1, 1]], "each hop goes to the address checked for it")
        let refused = await fetch("http://router.example/admin.png")
        XCTAssertNil(refused)
        XCTAssertEqual(asked.count, 1, "the router is never asked")
        let local = await fetch("http://127.0.0.1/a.png")
        XCTAssertNil(local)
        XCTAssertEqual(asked.count, 1)
    }

    func testRedirectsStopAfterFive() async {
        var asked = 0
        let data = await WebPicture.fetch(URL(string: "https://pictures.example/0")!, resolve: { _ in [self.onTheWeb] }, get: { _ in
            asked += 1
            return PictureResponse(status: 301, headers: ["location": "/\(asked)"], body: Data())
        })
        XCTAssertNil(data)
        XCTAssertEqual(asked, WebPicture.redirectsFollowed + 1)
    }

    func testOnlyAPictureNoBiggerThanTheLimitComesBack() async {
        func fetch(_ response: PictureResponse) async -> Data? {
            await WebPicture.fetch(URL(string: "https://pictures.example/a")!, resolve: { _ in [self.onTheWeb] }, get: { _ in response })
        }
        let jpeg = await fetch(PictureResponse(status: 200, headers: ["content-type": "Image/JPEG; charset=binary"], body: Data([1])))
        XCTAssertEqual(jpeg, Data([1]))
        let page = await fetch(PictureResponse(status: 200, headers: ["content-type": "text/html"], body: Data([1])))
        XCTAssertNil(page)
        let drawing = await fetch(PictureResponse(status: 200, headers: ["content-type": "image/svg+xml; charset=utf-8"], body: Data([1])))
        XCTAssertNil(drawing, "an SVG can carry script")
        let missing = await fetch(PictureResponse(status: 404, headers: ["content-type": "image/png"], body: Data([1])))
        XCTAssertNil(missing)
        let huge = await fetch(PictureResponse(status: 200, headers: ["content-type": "image/png"], body: Data(count: WebPicture.biggest + 1)))
        XCTAssertNil(huge)
    }

    func testAnAnswerIsReadWithItsLengthOrInChunksAndNothingAmbiguousIsTrusted() {
        func parse(_ text: String) -> PictureResponse? { PictureResponse(parsing: Data(text.utf8)) }
        XCTAssertEqual(parse("HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: 3\r\n\r\npngEXTRA")?.body, Data("png".utf8))
        XCTAssertEqual(parse("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\npn\r\n1;note\r\ng\r\n0\r\n\r\n")?.body, Data("png".utf8))
        XCTAssertEqual(parse("HTTP/1.0 302 Found\r\nLOCATION: /b.png\r\n\r\n")?.headers["location"], "/b.png")
        XCTAssertEqual(parse("HTTP/1.1 200 OK\r\nContent-Type: image/gif\r\n\r\nall of it")?.body, Data("all of it".utf8), "with neither, it's everything until the end")
        XCTAssertNil(parse("HTTP/1.1 200 OK\r\nContent-Length: 3\r\nContent-Length: 5\r\n\r\npngpn"), "two lengths")
        XCTAssertNil(parse("HTTP/1.1 200 OK\r\nContent-Length: 9\r\n\r\npng"), "cut short")
        XCTAssertNil(parse("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\npn"), "chunks cut short")
        XCTAssertNil(parse("HTTP/1.1 200 OK\r\nTransfer-Encoding: gzip\r\n\r\npng"))
        XCTAssertNil(parse("SSH-2.0-OpenSSH\r\n\r\n"))
        XCTAssertNil(parse("HTTP/1.1 200 OK\r\nno colon here\r\n\r\npng"))
    }

    func testAChunkSizeNearTheLargestNumberIsRefusedNotACrash() {
        for size in ["7fffffffffffffff", "7ffffffffffffffe", "ffffffffffffffff"] {
            XCTAssertNil(PictureResponse(parsing: Data("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n\(size)\r\npng\r\n0\r\n\r\n".utf8)), size)
        }
    }

    func testAPortBeyondTheLastOneIsRefusedNotACrash() async throws {
        let url = try XCTUnwrap(URL(string: "https://pictures.example:70000/a.png"))
        let response = await PinnedHTTP.get(PictureRequest(url: url, address: onTheWeb), biggest: 1024, timeout: 1)
        XCTAssertNil(response)
    }

    func testTheConnectionGoesToThePinnedAddressAndNamesTheHostItAskedFor() async throws {
        for answer in [
            "HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: 3\r\nConnection: close\r\n\r\npng",
            "HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n3\r\npng\r\n0\r\n\r\n",
        ] {
            let server = try OneAnswer(Data(answer.utf8))
            let listening = await until { server.port != nil }
            XCTAssertTrue(listening, "the stand-in server is listening")
            let port = try XCTUnwrap(server.port)
            let url = try XCTUnwrap(URL(string: "http://pictures.invalid:\(port)/a%20b.png?size=2"))
            let response = await PinnedHTTP.get(PictureRequest(url: url, address: [127, 0, 0, 1]), biggest: 1024, timeout: 5)
            XCTAssertEqual(response?.body, Data("png".utf8), "a name that never resolves still reached the pinned address")
            let heard = String(decoding: server.heard, as: UTF8.self)
            XCTAssertTrue(heard.hasPrefix("GET /a%20b.png?size=2 HTTP/1.1\r\n"), heard)
            XCTAssertTrue(heard.contains("\r\nHost: pictures.invalid:\(port)\r\n"), heard)
            XCTAssertTrue(heard.hasSuffix("\r\n\r\n"), heard)
            server.stop()
        }
    }

    func testAnAnswerBiggerThanTheLimitIsDropped() async throws {
        let server = try OneAnswer(Data(("HTTP/1.1 200 OK\r\nContent-Type: image/png\r\n\r\n" + String(repeating: "x", count: 200_000)).utf8))
        let listening = await until { server.port != nil }
        XCTAssertTrue(listening)
        let url = try XCTUnwrap(URL(string: "http://pictures.invalid:\(try XCTUnwrap(server.port))/big.png"))
        let response = await PinnedHTTP.get(PictureRequest(url: url, address: [127, 0, 0, 1]), biggest: 1024, timeout: 5)
        XCTAssertNil(response)
        server.stop()
    }
}

private final class OneAnswer: @unchecked Sendable {
    private let listener: NWListener
    private(set) var heard = Data()
    private(set) var port: UInt16?

    init(_ answer: Data) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { [weak self] state in
            if case .ready = state { self?.port = self?.listener.port?.rawValue }
        }
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .main)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, _, _ in
                self?.heard.append(data ?? Data())
                connection.send(content: answer, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener.start(queue: .main)
    }

    func stop() {
        listener.cancel()
    }
}
