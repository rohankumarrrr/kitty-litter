import AppKit
import ApplicationServices

public enum Permissions {
    public enum Automation: Sendable, Equatable {
        case allowed, denied, notAsked, notRunning
    }

    public enum Pane: String, Sendable {
        case screenRecording = "Privacy_ScreenCapture"
        case accessibility = "Privacy_Accessibility"
        case automation = "Privacy_Automation"
        case microphone = "Privacy_Microphone"
        case inputMonitoring = "Privacy_ListenEvent"
    }

    public static var hasScreenRecording: Bool { CGPreflightScreenCaptureAccess() }

    @discardableResult
    public static func requestScreenRecording() -> Bool { CGRequestScreenCaptureAccess() }

    public static var hasAccessibility: Bool { AXIsProcessTrusted() }

    @discardableResult
    public static func promptForAccessibility() -> Bool {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    public static func browserAutomation(bundleID: String) async -> Automation {
        await automation(bundleID: bundleID, askUser: false)
    }

    public static func requestBrowserAutomation(bundleID: String) async -> Automation {
        await automation(bundleID: bundleID, askUser: true)
    }

    public static func browsersDeniedAutomation() async -> [String] {
        var denied: [String] = []
        for browser in Browser.known where await browserAutomation(bundleID: browser.bundleID) == .denied {
            denied.append(browser.bundleID)
        }
        return denied
    }

    public static func openSettings(_ pane: Pane) {
        let address = "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)"
        if let url = URL(string: address) { NSWorkspace.shared.open(url) }
    }

    private static func automation(bundleID: String, askUser: Bool) async -> Automation {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else { return .notRunning }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
                continuation.resume(returning: automation(from: AppleEvents.status(of: target, askUser: askUser)))
            }
        }
    }

    static func automation(from failure: AppleEvents.Failure?) -> Automation {
        switch failure {
        case nil: return .allowed
        case .notAllowed: return .denied
        case .appGone: return .notRunning
        default: return .notAsked
        }
    }
}
