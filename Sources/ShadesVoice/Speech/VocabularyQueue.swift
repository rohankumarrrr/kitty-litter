struct VocabularyQueue<Drain> {
    private(set) var waiting: [String]?
    private(set) var drain: Drain?

    mutating func add(_ words: [String], startingWith start: () -> Drain) -> Drain {
        waiting = words
        if let drain { return drain }
        let started = start()
        drain = started
        return started
    }

    mutating func next() -> [String]? {
        guard let words = waiting else {
            drain = nil
            return nil
        }
        waiting = nil
        return words
    }
}
