import Foundation
import ShadesCore

struct AppDependencies {
    var backend: AgentBackend
    var context: ScreenContextProviding
    var voice: VoiceEngine
    var inserter: TextInserting
    var keys: KeyHoldMonitoring
    var settings: Settings
    var saveSettings: (Settings) -> Void
    var screenTip: () -> String? = { nil }
    var kittens: () -> [Kitten] = { [] }
    var systemFacts: () async -> HealthFacts = { HealthFacts() }
    var fileExists: (String) -> Bool = { _ in true }
    var home = FileManager.default.homeDirectoryForCurrentUser.path
    var screenBlockGaps: (String) -> [String] = { _ in [] }
    var routerFolder: () -> String? = { nil }
    var reportHealth: ([HealthFinding], String?) -> Void = { _, _ in }
    var kittensCheckSummary: () -> Data? = { nil }
    var inbox = Inbox(since: .distantPast)
    var saveInbox: (Inbox) throws -> Void = { _ in }
    var claudeLimit = ClaudeUsageLimit()
    var saveClaudeLimit: (ClaudeUsageLimit) -> Void = { _ in }
    var hidesTestThreads = true
    var notify: (NeedsYouAlert) -> Void = { _ in }
    var withdrawNotifications: ([String]) -> Void = { _ in }
    var clearNotifications: () -> Void = {}
    var phoneKeys: PhoneKeyStoring = MemoryPhoneKeys()
    var servePhone: (UInt16) async throws -> String = { _ in throw TailscaleServe.Problem(errorDescription: "Tailscale isn't set up here.") }
    var stopServingPhone: () async -> Void = {}
    var sendPush: (URLRequest) async -> Int? = { _ in nil }
    var recentFiles: @Sendable () -> [URL] = { [] }
    var webPicture: @Sendable (URL) async -> Data? = { _ in nil }
}
