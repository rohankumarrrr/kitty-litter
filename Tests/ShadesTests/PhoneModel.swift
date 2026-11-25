import Foundation

@MainActor
protocol PhoneModel {
    associatedtype Event: Hashable
    static var events: [Event] { get }
    init()
    func enabled(_ event: Event) -> Bool
    mutating func apply(_ event: Event) -> String
    var fingerprint: String { get }
    func broken() -> String?
    mutating func finish() -> String?
}

struct PhoneWalk {
    var states = 0
    var counterexample: String?
}

@MainActor
func walkEveryOrder<Model: PhoneModel>(_ model: Model.Type, upTo depth: Int) -> PhoneWalk {
    var walk = PhoneWalk()
    var seen: Set<String> = []
    var frontier: [(path: [Model.Event], enabled: [Model.Event])] = []
    var start = Model()
    seen.insert(start.fingerprint)
    frontier.append(([], Model.events.filter(start.enabled)))
    if let problem = start.broken() ?? start.finish() {
        walk.counterexample = "From the start: \(problem)"
        return walk
    }
    for _ in 0..<depth {
        var next: [(path: [Model.Event], enabled: [Model.Event])] = []
        for (path, enabled) in frontier {
            for event in enabled {
                var model = Model()
                var trace: [String] = []
                for step in path + [event] { trace.append(model.apply(step)) }
                guard seen.insert(model.fingerprint).inserted else { continue }
                walk.states += 1
                let story = trace.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
                if let problem = model.broken() {
                    walk.counterexample = "\(story)\nThen: \(problem)"
                    return walk
                }
                next.append((path + [event], Model.events.filter(model.enabled)))
                if let problem = model.finish() {
                    walk.counterexample = "\(story)\nThen, with the network fine from here on: \(problem)"
                    return walk
                }
            }
        }
        frontier = next
    }
    return walk
}
