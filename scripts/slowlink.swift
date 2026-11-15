#!/usr/bin/env swift
// A phone's slow link in front of the demo's phone page, for timing what it's like away from home.
//
//   swift scripts/slowlink.swift <port> <page-port> [seconds-each-way] [bytes-a-second] [control-file]
//
// Listens on 127.0.0.1:<port> and passes everything to the page on <page-port>, each way after the delay, sharing the
// bandwidth between connections as one phone's link does. The defaults are 0.15 seconds and 125000 bytes a second,
// about 1 Mbps. It prints each connection as it closes, with what it asked for, how long the Mac took to answer, and
// how much went each way.
//
// Write a word to the control file to change what the link does. Only a new line is read, so add a number after it.
//   cut   every open connection goes silent without closing, as an iPhone leaves a stream after the lock screen
//   half  the same, but the Mac's side closes, as it does once Tailscale gives up on the phone
//   open  lists what's open
import Foundation
import Network

let arguments = CommandLine.arguments
guard arguments.count > 2, let port = NWEndpoint.Port(arguments[1]), let page = NWEndpoint.Port(arguments[2]) else {
    print("swift scripts/slowlink.swift <port> <page-port> [seconds-each-way] [bytes-a-second] [control-file]")
    exit(1)
}
let delay = arguments.count > 3 ? Double(arguments[3]) ?? 0.15 : 0.15
let rate = arguments.count > 4 ? Double(arguments[4]) ?? 125_000 : 125_000
let control = arguments.count > 5 ? arguments[5] : nil
let queue = DispatchQueue(label: "slowlink")
let started = Date()

func say(_ line: String) {
    print(String(format: "%8.2f ", Date().timeIntervalSince(started)) + line)
    fflush(stdout)
}

final class Link {
    let number: Int
    let phone: NWConnection
    let mac: NWConnection
    let opened = Date()
    var asked = ""
    var sent = ["up": 0, "down": 0]
    var ended = 0
    var silent = false
    /// How long the Mac took to answer.
    var answered: TimeInterval?

    init(_ number: Int, phone: NWConnection, mac: NWConnection) {
        self.number = number
        self.phone = phone
        self.mac = mac
    }

    var name: String { "#\(number)\(silent ? " silent" : "") \(asked)" }
}

var links: [Int: Link] = [:]
var count = 0
/// When each direction is next free, since a phone's connections share one link.
var free = ["up": Date.distantPast, "down": Date.distantPast]

func pass(_ link: Link, from: NWConnection, to: NWConnection, way: String) {
    from.receive(minimumIncompleteLength: 1, maximumLength: 16384) { data, _, done, error in
        if link.silent {
            if done || error != nil, way == "down", links.removeValue(forKey: link.number) != nil { say("\(link.name) closed by the Mac") }
            if done || error != nil { return }
            return pass(link, from: from, to: to, way: way)
        }
        if let data, !data.isEmpty {
            if link.asked.isEmpty, way == "up" { link.asked = String(decoding: data.prefix(80), as: UTF8.self).components(separatedBy: "\r\n")[0] }
            link.sent[way, default: 0] += data.count
            if way == "down", link.answered == nil { link.answered = Date().timeIntervalSince(link.opened) }
            free[way] = max(Date(), free[way]!).addingTimeInterval(Double(data.count) / rate)
            queue.asyncAfter(wallDeadline: .now() + free[way]!.timeIntervalSinceNow + delay) {
                if !link.silent { to.send(content: data, completion: .idempotent) }
            }
        }
        guard done || error != nil else { return pass(link, from: from, to: to, way: way) }
        // Just after the last of what it sent, which the same deadline wouldn't promise.
        queue.asyncAfter(wallDeadline: .now() + max(free[way]!.timeIntervalSinceNow, 0) + delay + 0.005) {
            guard !link.silent else { return }
            to.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .idempotent)
            link.ended += 1
            guard link.ended == 2 || error != nil, links.removeValue(forKey: link.number) != nil else { return }
            say(String(format: "%@ closed after %.2fs, answered after %.2fs, up %d, down %d", link.name, Date().timeIntervalSince(link.opened), link.answered ?? -1, link.sent["up"]!, link.sent["down"]!))
            queue.asyncAfter(deadline: .now() + 2) {
                link.phone.cancel()
                link.mac.cancel()
            }
        }
    }
}

let parameters = NWParameters.tcp
parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)
let listener = try NWListener(using: parameters)
listener.newConnectionHandler = { phone in
    count += 1
    let link = Link(count, phone: phone, mac: NWConnection(host: .ipv4(.loopback), port: page, using: .tcp))
    links[count] = link
    phone.start(queue: queue)
    link.mac.start(queue: queue)
    pass(link, from: phone, to: link.mac, way: "up")
    pass(link, from: link.mac, to: phone, way: "down")
}
listener.stateUpdateHandler = { state in
    if case .ready = state { say("on 127.0.0.1:\(port) to \(page), \(delay)s each way, \(Int(rate)) bytes a second") }
    if case .failed(let error) = state { say("couldn't listen: \(error)"); exit(1) }
}
listener.start(queue: queue)

var last = ""
let watching = DispatchSource.makeTimerSource(queue: queue)
watching.schedule(deadline: .now(), repeating: 0.2)
watching.setEventHandler {
    guard let control, let line = try? String(contentsOfFile: control, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), line != last else { return }
    last = line
    let open = links.values.sorted { $0.number < $1.number }
    switch line.split(separator: " ").first {
    case "cut":
        open.forEach { $0.silent = true }
        say("silent: " + open.map(\.name).joined(separator: "; "))
    case "half":
        open.forEach { $0.silent = true; $0.mac.cancel() }
        say("silent, the Mac's side closed: " + open.map(\.name).joined(separator: "; "))
    case "open":
        say("\(open.count) open: " + open.map { $0.name + String(format: ", answered after %.2fs, down %d", $0.answered ?? -1, $0.sent["down"]!) }.joined(separator: "; "))
    default:
        break
    }
}
watching.resume()
dispatchMain()
