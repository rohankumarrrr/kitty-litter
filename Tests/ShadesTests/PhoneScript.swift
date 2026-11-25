import Foundation
import JavaScriptCore
@testable import Shades
import XCTest

@MainActor
final class PhoneScript {
    struct Request: Equatable {
        let id: Int
        let method: String
        let path: String
        let query: [String: String]
        let headers: [String: String]
        let body: String
        let at: Double

        var json: [String: Any] {
            (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] ?? [:]
        }

        var act: String? { path == "/act" ? json["act"] as? String : nil }
    }

    enum Reply {
        case status(Int)
        case json(Any)
        case stream(String?)
        case unreachable
    }

    nonisolated static let pass = "a-paired-phone"
    static let startedAt: Double = 1_000_000_000_000

    let context: JSContext
    var mac: (Request) -> Reply? = { _ in nil }
    private(set) var requests: [Request] = []
    private(set) var pending: [Request] = []
    private(set) var streams: [Request] = []
    private(set) var followed: [String] = []
    private(set) var errors: [String] = []
    private(set) var stored: [String: String]
    private(set) var scrolledTo: [String] = []
    private(set) var picking = 0
    private(set) var closedByPage: [Int] = []
    private static let machine = JSVirtualMachine()!

    init(at key: String = PhonePlace.home, hash: String = "", stored: [String: String] = ["shades.key": PhoneScript.pass], standalone: Bool = false) {
        self.stored = stored
        context = JSContext(virtualMachine: Self.machine)
        context.exceptionHandler = { [weak self] _, error in
            MainActor.assumeIsolated { self?.errors.append(error?.toString() ?? "an error") }
        }
        let native = JSValue(newObjectIn: context)!
        native.setValue(Self.startedAt, forProperty: "startedAt")
        native.setValue(String(decoding: (try? JSONSerialization.data(withJSONObject: stored)) ?? Data("{}".utf8), as: UTF8.self), forProperty: "storage")
        native.setValue(standalone, forProperty: "standalone")
        let request: @convention(block) (String, String, String, String) -> Int = { [weak self] method, address, headers, body in
            MainActor.assumeIsolated { self?.asked(method, address, headers, body) ?? 0 }
        }
        let closed: @convention(block) (Int) -> Void = { [weak self] id in
            MainActor.assumeIsolated { self?.pageClosed(id) }
        }
        let stored: @convention(block) (String) -> Void = { [weak self] json in
            MainActor.assumeIsolated { self?.stored = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: String] ?? [:] }
        }
        let followed: @convention(block) (String, String) -> Void = { [weak self] address, _ in
            MainActor.assumeIsolated { self?.followed.append(address) }
        }
        let scrolledTo: @convention(block) (String) -> Void = { [weak self] id in
            MainActor.assumeIsolated { self?.scrolledTo.append(id) }
        }
        let picking: @convention(block) () -> Void = { [weak self] in
            MainActor.assumeIsolated { self?.picking += 1 }
        }
        let log: @convention(block) (String) -> Void = { print("[phone page] \($0)") }
        native.setValue(request, forProperty: "request")
        native.setValue(closed, forProperty: "closed")
        native.setValue(stored, forProperty: "stored")
        native.setValue(followed, forProperty: "followed")
        native.setValue(scrolledTo, forProperty: "scrolledTo")
        native.setValue(picking, forProperty: "picking")
        native.setValue(log, forProperty: "log")
        context.setObject(native, forKeyedSubscript: "__native" as NSString)
        context.evaluateScript(PhoneScriptWorld.browser)
        call("__build", PhonePage.html)
        call("__open", "/?key=\(key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key)\(hash)")
        context.evaluateScript(PhonePage.script)
    }

    @discardableResult
    func run(_ script: String) -> JSValue? {
        context.evaluateScript(script)
    }

    func read(_ expression: String) -> Any? {
        context.evaluateScript("(\(expression))")?.toObject()
    }

    func text(_ id: String) -> String {
        read("document.getElementById('\(id)').textContent") as? String ?? ""
    }

    func isHidden(_ id: String) -> Bool {
        read("document.getElementById('\(id)').hidden") as? Bool ?? false
    }

    var key: String { read("view && view.key") as? String ?? "" }
    var clock: Double { call("__clock")?.toDouble() ?? 0 }
    var timers: String { call("__timers")?.toString() ?? "" }
    var nextTimer: Double? { call("__nextTimerAt").map { $0.toDouble() }.flatMap { $0 >= 0 ? $0 : nil } }

    func tap(_ selector: String, _ text: String? = nil, file: StaticString = #filePath, line: UInt = #line) {
        tick()
        XCTAssertEqual(call("__tap", selector, text ?? NSNull())?.toString(), "tapped", "tapping \(selector) \(text ?? "")", file: file, line: line)
        settle()
    }

    func type(_ text: String, into selector: String, file: StaticString = #filePath, line: UInt = #line) {
        tick()
        XCTAssertEqual(call("__type", selector, text)?.toString(), "typed", "typing into \(selector)", file: file, line: line)
        settle()
    }

    func press(_ key: String, on selector: String, _ text: String? = nil, file: StaticString = #filePath, line: UInt = #line) {
        tick()
        XCTAssertEqual(call("__press", selector, text ?? NSNull(), key)?.toString(), "pressed", "pressing \(key) on \(selector) \(text ?? "")", file: file, line: line)
        settle()
    }

    func answer(_ request: Request, _ reply: Reply) {
        pending.removeAll { $0.id == request.id }
        tick()
        switch reply {
        case .status(let status):
            call("__answer", request.id, status, "")
        case .json(let value):
            let body = (try? JSONSerialization.data(withJSONObject: value)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
            call("__answer", request.id, 200, body)
        case .stream(let first):
            streams.append(request)
            call("__stream", request.id)
            if let first { send(first, on: request) }
        case .unreachable:
            call("__fail", request.id)
        }
    }

    func send(_ data: String, on stream: Request) {
        call("__chunk", stream.id, "data: \(data)\n\n")
    }

    func ping(_ stream: Request) {
        call("__chunk", stream.id, ": ping\n\n")
    }

    func end(_ stream: Request) {
        streams.removeAll { $0.id == stream.id }
        call("__end", stream.id)
    }

    func cut(_ stream: Request) {
        streams.removeAll { $0.id == stream.id }
        call("__fail", stream.id)
    }

    func visible(_ visible: Bool) {
        call("__visible", visible)
        settle()
    }

    func scan(_ code: String) {
        run("location.hash = '#pair=\(code)'")
        settle()
    }

    func settle(file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<1000 {
            if let (next, reply) = pending.lazy.compactMap({ request in self.mac(request).map { (request, $0) } }).first {
                answer(next, reply)
            } else if call("__timersDue")?.toInt32() ?? 0 > 0 {
                call("__fireNextTimer")
            } else {
                return
            }
        }
        XCTFail("the page and the stand-in Mac never settled", file: file, line: line)
    }

    func advance(_ seconds: Double, file: StaticString = #filePath, line: UInt = #line) {
        let until = clock + seconds * 1000
        settle(file: file, line: line)
        while let next = nextTimer, next <= until {
            call("__fireNextTimer")
            settle(file: file, line: line)
        }
        call("__setClock", until)
        settle(file: file, line: line)
    }

    private func tick() {
        call("__setClock", clock + 1)
    }

    @discardableResult
    private func call(_ name: String, _ arguments: Any...) -> JSValue? {
        context.objectForKeyedSubscript(name)?.call(withArguments: arguments)
    }

    private func asked(_ method: String, _ address: String, _ headers: String, _ body: String) -> Int {
        let parts = URLComponents(string: "https://mac.example\(address)")
        let query = (parts?.queryItems ?? []).reduce(into: [String: String]()) { $0[$1.name] = $1.value ?? "" }
        let heard = (try? JSONSerialization.jsonObject(with: Data(headers.utf8))) as? [String: String] ?? [:]
        let request = Request(id: requests.count + 1, method: method, path: parts?.path ?? address, query: query, headers: heard, body: body, at: clock)
        requests.append(request)
        pending.append(request)
        return request.id
    }

    private func pageClosed(_ id: Int) {
        closedByPage.append(id)
        pending.removeAll { $0.id == id }
        streams.removeAll { $0.id == id }
    }
}
