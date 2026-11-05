import Foundation
import ShadesCore

/// One thing the cat checked about itself.
struct HealthFinding: Codable, Equatable {
    var check: String
    var ok: Bool
    var problem: String?
    var fix: String?

    static func good(_ check: String) -> HealthFinding {
        HealthFinding(check: check, ok: true)
    }
}

/// What the running app last found. It's written to a file, so the install script can tell the
/// app really came up, and an agent can look at how it's doing. There's nothing private in it.
struct HealthReport: Codable, Equatable {
    var pid: Int32
    var version: String
    var checkedAt: Date
    var ok: Bool
    var findings: [HealthFinding]
}

/// What the cat can find out about its own situation. Gathered elsewhere, so what it means can be tested.
struct HealthFacts: Equatable {
    var isBundled = true
    var isSignedWithIdentity = true
    var signatureIsValid = true
    var hasScreenRecording = true
    var hasAccessibility = true
    var hasInputMonitoring = true
    var microphoneDenied = false
    var skillsInstalled = true
    var reachedT3 = true
    /// Kittens taking work whose folders aren't T3 projects, or have no instructions.
    var kittensNotInT3: [Kitten] = []
    var kittensWithoutInstructions: [String] = []
    /// Kittens that aren't meant to see your screen, with nothing to stop them.
    var kittensOffScreenInNameOnly: [String] = []
    /// Why the router won't run, if it won't: no folder to keep it from passing your screen on, a model that
    /// doesn't read it, or what T3 said when asked for the folder's project.
    var frontDoorProblem: FrontDoorProblem?
    var frontDoorProjectTrouble: String?
    var inboxSaves = true
    /// Whether finished threads say which run they last finished, which is how the inbox tells reports apart.
    var t3GivesRunIDs = true
}

enum HealthCheck {
    static let signature = "signature"

    static func findings(from facts: HealthFacts) -> [HealthFinding] {
        var results: [HealthFinding] = []

        // macOS ties permissions to a signature, so with a bad one every permission looks off, whatever
        // System Settings shows. Saying "turn it on" would send you after the wrong thing, so this
        // gets said instead of those. A copy that isn't a bundle gets its permissions some other way.
        let signatureGood = !facts.isBundled || (facts.isSignedWithIdentity && facts.signatureIsValid)
        if signatureGood {
            results.append(.good(signature))
            results.append(facts.hasScreenRecording ? .good("screen recording") : HealthFinding(
                check: "screen recording",
                ok: false,
                problem: "I don't have Screen Recording, so I can't see your screen.",
                fix: "Turn it on in System Settings, then choose Restart from my menu."
            ))
            results.append(facts.hasAccessibility ? .good("accessibility") : HealthFinding(
                check: "accessibility",
                ok: false,
                problem: "I don't have Accessibility, so I can't read selected text or type your dictation.",
                fix: "Turn it on in System Settings."
            ))
            results.append(facts.hasInputMonitoring ? .good("input monitoring") : HealthFinding(
                check: "input monitoring",
                ok: false,
                problem: "I don't have Input Monitoring, so I can't feel your hold keys.",
                fix: "Turn it on in System Settings, then choose Restart from my menu."
            ))
            results.append(facts.microphoneDenied ? HealthFinding(
                check: "microphone",
                ok: false,
                problem: "I'm not allowed to use the microphone, so I can't hear you.",
                fix: "Turn it on in System Settings."
            ) : .good("microphone"))
        } else {
            results.append(HealthFinding(
                check: signature,
                ok: false,
                problem: "This copy of me isn't signed properly, so macOS ignores my permissions, whatever System Settings shows.",
                fix: "Run scripts/install.sh."
            ))
        }

        results.append(facts.reachedT3 ? .good("T3 Code") : HealthFinding(
            check: "T3 Code",
            ok: false,
            problem: "I can't reach T3 Code, so my agents can't run.",
            fix: "Open T3 Code."
        ))
        for kitten in facts.kittensNotInT3 {
            results.append(HealthFinding(
                check: "kitten: \(kitten.name)",
                ok: false,
                problem: "\(kitten.name) isn't a T3 project, so nothing can reach them.",
                fix: "Add \(kitten.workspace) as a project in T3."
            ))
        }
        for name in facts.kittensWithoutInstructions {
            results.append(HealthFinding(
                check: "kitten: \(name)",
                ok: false,
                problem: "\(name) has no instructions.",
                fix: "Write a CLAUDE.md in their folder, or mark them as planned."
            ))
        }
        for name in facts.kittensOffScreenInNameOnly {
            results.append(HealthFinding(
                check: "kitten: \(name)",
                ok: false,
                problem: "\(name) isn't meant to see your screen, but nothing stops them.",
                fix: "Put the screen block from docs/kittens.md in their folder, and run them on a Claude model."
            ))
        }
        switch (facts.frontDoorProblem, facts.frontDoorProjectTrouble) {
        case (.noFolder?, _):
            results.append(HealthFinding(
                check: "front door",
                ok: false,
                problem: "I can't get the folder I answer from ready, so I won't take questions.",
                fix: "Check that I can write to my folder in Application Support."
            ))
        case (.notClaude?, _):
            results.append(HealthFinding(
                check: "front door",
                ok: false,
                problem: "My front door model doesn't read Claude's settings, so I won't take questions, since nothing would stop it passing your screen to another thread.",
                fix: "Choose a Claude model for Front door model in my settings."
            ))
        case (nil, let trouble?):
            results.append(HealthFinding(
                check: "front door",
                ok: false,
                problem: "T3 won't give me the project I answer from, so I won't take questions. \(trouble)",
                fix: "Open T3 Code, and check it still has a project called Shades router."
            ))
        case (nil, nil):
            results.append(.good("front door"))
        }
        results.append(facts.skillsInstalled ? .good("kitten skills") : HealthFinding(
            check: "kitten skills",
            ok: false,
            problem: "The skills kittens work by aren't installed.",
            fix: "Run scripts/install-kitten-skills.sh."
        ))
        results.append(facts.inboxSaves ? .good("inbox") : HealthFinding(
            check: "inbox",
            ok: false,
            problem: "I can't save your inbox, so a restart would lose what's in it.",
            fix: "Check that I can write to my folder in Application Support."
        ))
        results.append(facts.t3GivesRunIDs ? .good("T3 run IDs") : HealthFinding(
            check: "T3 run IDs",
            ok: false,
            problem: "T3 Code has stopped saying which run a thread last finished, so reports go to the bubble instead of the inbox, and a restart can lose them.",
            fix: "Run swift run probe-t3 to see what changed."
        ))
        return results
    }

    static func report(_ findings: [HealthFinding], pid: Int32, version: String, at date: Date) -> HealthReport {
        HealthReport(pid: pid, version: version, checkedAt: date, ok: findings.allSatisfy(\.ok), findings: findings)
    }
}
