@testable import ShadesVoice
import TestSupport
import XCTest

final class VocabularyQueueModelTests: XCTestCase {
    func testEveryOrderOfSetsAndLoadsLoadsOneListAtATimeAndTheNewestWins() throws {
        let exploration = try explore(from: Engine(), steps: Engine.steps, upTo: 20, checking: \.broken)
        XCTAssertNil(exploration.counterexample, exploration.counterexample?.description ?? "")
        XCTAssertTrue(exploration.reachedEveryState, "every order fits in the bound")
        XCTAssertGreaterThan(exploration.statesSeen, 200, "it explored too little to mean anything")
    }

    func testASecondListWhileTheFirstIsLoadingWaitsForIt() {
        var engine = Engine()
        for name in ["\"Project 1\" is set", "the first drain takes the next list", "\"Project 2\" is set", "the second drain takes the next list"] {
            if let step = Engine.steps.first(where: { $0.name == name }), let next = try? step.next(engine) { engine = next }
            XCTAssertNil(engine.broken, name)
        }
        XCTAssertEqual(engine.loading, [["Project 1"]], "the second isn't loaded while the first is")
        XCTAssertEqual(engine.drains.count, 1, "since it joins the drain that's running instead of starting its own, as each list did before")
        XCTAssertEqual(engine.queue.waiting, ["Project 2"], "and goes in next")
    }
}

private struct Engine: Hashable {
    enum Drain: Hashable {
        case taking, loading([String]), done
    }

    static let callers = [["Project 1"], ["Project 2"], ["Project 3"]]
    static let ordinals = ["first", "second", "third"]
    static let waiter = 2

    var queue = VocabularyQueue<Int>()
    var drains: [Drain] = []
    var set: [Int] = []
    var applied: [[String]] = []
    var waiterDrain: Int?

    var loading: [[String]] {
        drains.compactMap { if case .loading(let words) = $0 { words } else { nil } }
    }

    static func == (left: Engine, right: Engine) -> Bool {
        left.key == right.key
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(key)
    }

    private var key: String {
        "\(String(describing: queue.waiting)) \(String(describing: queue.drain)) \(drains) \(set) \(applied) \(String(describing: waiterDrain))"
    }

    static var steps: [Step<Engine>] {
        let sets = callers.indices.map { caller in
            Step<Engine>("\"\(callers[caller][0])\" is set") { engine in
                guard !engine.set.contains(caller) else { return nil }
                var next = engine
                next.set.append(caller)
                let drain = next.queue.add(callers[caller]) {
                    next.drains.append(.taking)
                    return next.drains.count - 1
                }
                if caller == waiter { next.waiterDrain = drain }
                return next
            }
        }
        let drains = callers.indices.flatMap { id in
            [
                Step<Engine>("the \(ordinals[id]) drain takes the next list") { engine in
                    guard id < engine.drains.count, engine.drains[id] == .taking else { return nil }
                    var next = engine
                    next.drains[id] = next.queue.next().map(Drain.loading) ?? .done
                    return next
                },
                Step<Engine>("the recognizer finishes loading for the \(ordinals[id]) drain") { engine in
                    guard id < engine.drains.count, case .loading(let words) = engine.drains[id] else { return nil }
                    var next = engine
                    next.applied.append(words)
                    next.drains[id] = .taking
                    return next
                },
            ]
        }
        return sets + drains
    }

    var broken: String? {
        if loading.count > 1 { return "the recognizer loads \(loading) at once, which crashed the app" }
        let running = drains.filter { $0 != .done }.count
        let newest = set.last.map { Self.callers[$0] }
        if running == 0, let newest, applied.last != newest { return "everything's settled with \(String(describing: applied.last)) loaded, but the newest list is \(newest)" }
        if let waiterDrain, drains[waiterDrain] == .done, let at = set.firstIndex(of: Self.waiter) {
            let fresh = set[at...].map { Self.callers[$0] }
            if !applied.contains(where: fresh.contains) { return "applyVocabulary returned before \(Self.callers[Self.waiter]) or anything newer loaded" }
        }
        return nil
    }
}
