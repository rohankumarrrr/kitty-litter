import Foundation
import Security
import ShadesContext
import ShadesCore
import ShadesVoice

/// Reads the facts for the self-check from macOS.
enum SystemHealth {
    static func facts(skillsFolder: URL = Kittens.defaultFolder.appendingPathComponent("_skills")) -> HealthFacts {
        var facts = HealthFacts()
        facts.isBundled = Bundle.main.bundleURL.pathExtension == "app"
        let signature = readSignature()
        facts.isSignedWithIdentity = signature.hasIdentity
        facts.signatureIsValid = signature.isValid
        facts.hasScreenRecording = Permissions.hasScreenRecording
        facts.hasAccessibility = Permissions.hasAccessibility
        facts.hasInputMonitoring = KeyHoldMonitor.hasPermission
        facts.microphoneDenied = MicrophoneSource.authorization == .denied
        facts.skillsInstalled = FileManager.default.fileExists(
            atPath: skillsFolder.appendingPathComponent("pstack/skills/poteto-mode/SKILL.md").path
        )
        return facts
    }

    /// An ad hoc signature has no certificates, and that's the kind macOS forgets on every build.
    private static func readSignature() -> (hasIdentity: Bool, isValid: Bool) {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return (false, false) }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return (false, false) }

        var info: CFDictionary?
        let readInfo = SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        let details = info as? [String: Any]
        let certificates = details?[kSecCodeInfoCertificates as String] as? [Any]
        let hasIdentity = readInfo == errSecSuccess && certificates?.isEmpty == false
        let isValid = SecStaticCodeCheckValidity(staticCode, [], nil) == errSecSuccess
        return (hasIdentity, isValid)
    }

    /// Written whole, so a reader never sees half of it.
    static func write(_ report: HealthReport, to file: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(report) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
