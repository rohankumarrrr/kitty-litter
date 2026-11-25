import Foundation

struct CorrectionSends {
    struct Before {
        var wasDispatcher: Bool
        var wasCorrected: Bool
    }

    private var going: [String: Int] = [:]
    private var before: [String: Before] = [:]
    private var reached: Set<String> = []

    mutating func start(_ threadID: String, wasDispatcher: Bool, wasCorrected: Bool) {
        if going[threadID, default: 0] == 0 { before[threadID] = Before(wasDispatcher: wasDispatcher, wasCorrected: wasCorrected) }
        going[threadID, default: 0] += 1
    }

    mutating func end(_ threadID: String, reached got: Bool) -> Before? {
        if got { reached.insert(threadID) }
        let left = going[threadID, default: 1] - 1
        guard left == 0 else {
            going[threadID] = left
            return nil
        }
        defer {
            going[threadID] = nil
            before[threadID] = nil
            reached.remove(threadID)
        }
        return reached.contains(threadID) ? nil : before[threadID]
    }
}
