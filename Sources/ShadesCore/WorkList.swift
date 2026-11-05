import Foundation

/// One thing on a kitten's list. A finished one comes off the list, so there's no state for that.
public struct WorkItem: Codable, Equatable, Identifiable, Sendable {
    public enum State: String, Codable, Sendable {
        case proposed, waiting, working, stopped, dropped
    }

    public let id: String
    public var text: String
    public var state: State
    public var threadID: String?
    public var changedAt: Date

    public init(
        id: String = String(UUID().uuidString.prefix(8)).lowercased(),
        text: String,
        state: State,
        threadID: String? = nil,
        at changedAt: Date
    ) {
        self.id = id
        self.text = text
        self.state = state
        self.threadID = threadID
        self.changedAt = changedAt
    }

    public var firstLine: String {
        String(text.prefix { !$0.isNewline }.prefix(80))
    }
}

/// What a kitten has on its plate. It's a record, never permission: a kitten can write to it,
/// so nothing on it can start anything by itself. See docs/kittens.md.
public struct WorkList: Codable, Equatable, Sendable {
    /// How many things a kitten works on at once, while the rest wait their turn.
    public static let slots = 2

    public var items: [WorkItem]

    public init(items: [WorkItem] = []) {
        self.items = items
    }

    /// A dropped item stays so its kitten can see it was declined, but it isn't on anyone's plate.
    public var open: [WorkItem] {
        items.filter { $0.state != .dropped }
    }

    public mutating func put(_ item: WorkItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
    }

    /// `nil` takes the items off the list.
    public mutating func endWork(in thread: String, as state: WorkItem.State?, at date: Date) {
        guard let state else {
            items.removeAll { $0.state != .dropped && $0.threadID == thread }
            return
        }
        change(thread: thread, at: date) { $0.state = state }
    }

    public mutating func moveWork(from thread: String, to next: String, at date: Date) {
        change(thread: thread, at: date) { $0.threadID = next }
    }

    /// A correction belongs to what it corrects, so it doesn't add to the count.
    public mutating func addFollowUp(_ words: String, in thread: String, at date: Date) {
        guard let index = items.firstIndex(where: { $0.state != .dropped && $0.threadID == thread }) else {
            items.append(WorkItem(text: words, state: .working, threadID: thread, at: date))
            return
        }
        items[index].text += "\n\n" + words
        items[index].state = .working
        items[index].changedAt = date
    }

    public func holds(thread: String) -> Bool {
        open.contains { $0.threadID == thread }
    }

    private mutating func change(thread: String, at date: Date, _ update: (inout WorkItem) -> Void) {
        for index in items.indices where items[index].state != .dropped && items[index].threadID == thread {
            update(&items[index])
            items[index].changedAt = date
        }
    }
}
