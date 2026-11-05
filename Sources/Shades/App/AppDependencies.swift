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
    /// Where each self-check's findings go.
    var reportHealth: ([HealthFinding]) -> Void = { _ in }
}
