import Foundation

public struct Step<State> {
    public let name: String
    public let next: (State) throws -> State?

    public init(_ name: String, _ next: @escaping (State) throws -> State?) {
        self.name = name
        self.next = next
    }
}

public struct Counterexample: CustomStringConvertible {
    public let steps: [String]
    public let problem: String

    public var description: String {
        (steps.enumerated().map { "\($0.offset + 1). \($0.element)" } + ["Then: \(problem)"]).joined(separator: "\n")
    }
}

public struct Exploration {
    public let statesSeen: Int
    public let counterexample: Counterexample?
    public let reachedEveryState: Bool
}

public func explore<State: Hashable>(
    from start: State,
    steps: [Step<State>],
    upTo depth: Int,
    checking problem: (State) -> String?
) throws -> Exploration {
    var seen: Set<State> = [start]
    var frontier: [(state: State, path: [String])] = [(start, [])]
    for level in 0...depth {
        for (state, path) in frontier {
            if let found = problem(state) {
                return Exploration(statesSeen: seen.count, counterexample: Counterexample(steps: path, problem: found), reachedEveryState: false)
            }
        }
        var next: [(state: State, path: [String])] = []
        for (state, path) in frontier {
            for step in steps {
                guard let after = try step.next(state), !seen.contains(after) else { continue }
                if level == depth { return Exploration(statesSeen: seen.count, counterexample: nil, reachedEveryState: false) }
                seen.insert(after)
                next.append((after, path + [step.name]))
            }
        }
        if next.isEmpty { return Exploration(statesSeen: seen.count, counterexample: nil, reachedEveryState: true) }
        frontier = next
    }
    return Exploration(statesSeen: seen.count, counterexample: nil, reachedEveryState: false)
}
