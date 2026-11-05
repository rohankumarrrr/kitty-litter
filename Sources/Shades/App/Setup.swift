import AppKit
import ShadesContext
import ShadesVoice

/// Asks macOS for what the cat needs: once by itself on first launch, then from the menu.
@MainActor
enum Setup {
    private static let askedKey = "askedForPermissions"

    static func runOnFirstLaunch(then done: @escaping @MainActor () -> Void) {
        guard !UserDefaults.standard.bool(forKey: askedKey) else { return }
        UserDefaults.standard.set(true, forKey: askedKey)
        Permissions.requestScreenRecording()
        Permissions.promptForAccessibility()
        KeyHoldMonitor.requestPermission()
        Task {
            _ = await MicrophoneSource.requestAccess()
            await askDefaultBrowser()
            done()
        }
    }

    /// Screen Recording and the hold keys only take effect after a restart.
    static func restart() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    /// macOS only asks once, so after that the way to change an answer is System Settings.
    /// Asking comes first anyway, because that's what puts the app in Settings' list.
    static func openSettingsForWhatsMissing() {
        if !Permissions.hasScreenRecording {
            Permissions.requestScreenRecording()
            Permissions.openSettings(.screenRecording)
        } else if !Permissions.hasAccessibility {
            Permissions.promptForAccessibility()
            Permissions.openSettings(.accessibility)
        } else if !KeyHoldMonitor.hasPermission, let page = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(page)
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
