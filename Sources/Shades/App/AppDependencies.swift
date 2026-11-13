import Foundation
import ShadesCore

/// Everything the app needs from outside itself, all behind the contracts in Core.
struct AppDependencies {
    var backend: AgentBackend
    var context: ScreenContextProviding
    var voice: VoiceEngine
    var inserter: TextInserting
    var keys: KeyHoldMonitoring
    var settings: Settings
    /// Where changed settings go.
    var saveSettings: (Settings) -> Void
    /// A one-time tip for seeing more of the screen, such as a browser setting to turn on.
    var screenTip: () -> String? = { nil }
    /// The kittens there are right now. Read for every question, so a new one just needs its folder.
    var kittens: () -> [Kitten] = { [] }
    /// What the cat can find out about its own situation, for its self-check.
    var systemFacts: () -> HealthFacts = { HealthFacts() }
    var fileExists: (String) -> Bool = { _ in true }
    /// What's missing from what keeps a kitten in this folder off your screen.
    var screenBlockGaps: (String) -> [String] = { _ in [] }
    /// The folder the router runs in, once what keeps it from passing your screen on is in place. `nil` if that
    /// can't be done, and then the router doesn't run.
    var routerFolder: () -> String? = { nil }
    /// Where each self-check's findings go.
    var reportHealth: ([HealthFinding]) -> Void = { _ in }
    /// What was in the inbox when the app last stopped.
    var inbox = Inbox(since: .distantPast)
    var saveInbox: (Inbox) throws -> Void = { _ in }
    /// Off for a copy trying a flow out, which may be testing with one of these itself.
    var hidesTestThreads = true
    /// Where a notification that something needs you goes.
    var notify: (NeedsYouAlert) -> Void = { _ in }
    /// Takes notifications back by ID, once what they were about isn't waiting anymore.
    var withdrawNotifications: ([String]) -> Void = { _ in }
    /// Takes back every notification Shades has posted.
    var clearNotifications: () -> Void = {}
    /// Where the hashes of paired phones' tokens are kept.
    var phoneKeys: PhoneKeyStoring = MemoryPhoneKeys()
    /// Puts the phone page, on this loopback port, on your tailnet, and returns the address to open.
    var servePhone: (UInt16) async throws -> String = { _ in throw TailscaleServe.Problem(errorDescription: "Tailscale isn't set up here.") }
    /// Takes it off your tailnet.
    var stopServingPhone: () async -> Void = {}
    /// Sends a notification to a phone's push service, and returns its status, or `nil` if it didn't get there.
    var sendPush: (URLRequest) async -> Int? = { _ in nil }
    /// The pictures and PDFs you've opened lately, for Attach in Messages.
    var recentFiles: @Sendable () -> [URL] = { [] }
    /// A web picture a reply points at, fetched once you've pressed Show on it.
    var webPicture: @Sendable (URL) async -> Data? = { _ in nil }
}
