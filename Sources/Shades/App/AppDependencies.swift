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
}
