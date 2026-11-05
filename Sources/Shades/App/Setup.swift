import AppKit
import ShadesContext

/// Asks macOS for what the cat needs: once by itself on first launch, then from the menu.
/// The microphone is left out, because macOS asks for that the first time you talk.
@MainActor
enum Setup {
    private static let askedKey = "askedForPermissions"

    static func runOnFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: askedKey) else { return }
        UserDefaults.standard.set(true, forKey: askedKey)
        Permissions.requestScreenRecording()
        Permissions.promptForAccessibility()
        Task { await askDefaultBrowser() }
    }

    /// macOS only asks once, so after that the way to change an answer is System Settings.
    static func openSettingsForWhatsMissing() {
        if !Permissions.hasScreenRecording {
            Permissions.openSettings(.screenRecording)
        } else if !Permissions.hasAccessibility {
            Permissions.openSettings(.accessibility)
        } else {
            Permissions.openSettings(.automation)
        }
    }

    private static func askDefaultBrowser() async {
        guard let page = URL(string: "https://example.com"),
              let browser = NSWorkspace.shared.urlForApplication(toOpen: page),
              let bundleID = Bundle(url: browser)?.bundleIdentifier
        else { return }
        _ = await Permissions.requestBrowserAutomation(bundleID: bundleID)
    }
}
