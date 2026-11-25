import Foundation

public struct ScheduledTask: Sendable, Equatable {
    public var title: String
    public var projectID: String
    public var enabled: Bool
    public var runsAtSetTime: Bool
    public var threadID: String?

    public init(title: String, projectID: String, enabled: Bool = true, runsAtSetTime: Bool, threadID: String?) {
        self.title = title
        self.projectID = projectID
        self.enabled = enabled
        self.runsAtSetTime = runsAtSetTime
        self.threadID = threadID
    }

    public var canBeLost: Bool { enabled && (runsAtSetTime || threadID == nil) }
}
