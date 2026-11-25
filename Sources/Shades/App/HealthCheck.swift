import Foundation
import ShadesCore

struct HealthFinding: Codable, Equatable {
    var check: String
    var ok: Bool
    var problem: String?
    var fix: String?

    static func good(_ check: String) -> HealthFinding {
        HealthFinding(check: check, ok: true)
    }
}

struct HealthReport: Codable, Equatable {
    var pid: Int32
    var version: String
    var checkedAt: Date
    var ok: Bool
    var findings: [HealthFinding]
    var lockdown: String?
}

struct HealthFacts: Equatable {
    var isBundled = true
    var isSignedWithIdentity = true
    var signatureIsValid = true
    var isSignedByTeam = true
    var hasScreenRecording = true
    var hasAccessibility = true
    var hasInputMonitoring = true
    var microphoneDenied = false
    var skillsInstalled = true
    var reachedT3 = true
    var t3Silence: T3Silence?
    var kittensNotInT3: [Kitten] = []
    var kittensWithoutInstructions: [String] = []
    var kittensOffScreenInNameOnly: [String] = []
    var frontDoorProblem: FrontDoorProblem?
    var frontDoorProjectTrouble: String?
    var inboxSaves = true
    var waitingLeft = 0
    var waitingLeftWithoutYou = 0
    var t3GivesRunIDs = true
    var shortcutsTaken: [String] = []
    var otherCopies: [Int32] = []
    var phoneNeedsPairingAgain = false
    var lockdownKittenGone = false
    var shownName: String?
}

enum T3Silence: Equatable {
    case connecting
    case stuck
}

enum HealthCheck {
    static let signature = "signature"
    static let cantReachT3 = HealthFinding(
        check: "T3 Code",
        ok: false,
        problem: "I can't reach T3 Code, so my agents can't run.",
        fix: "Open T3 Code."
    )
    static let badSignature = HealthFinding(
        check: signature,
        ok: false,
        problem: "This copy of me isn't signed properly, so macOS ignores my permissions, whatever System Settings shows.",
        fix: "Run scripts/install.sh."
    )
    static let noTeam = HealthFinding(
        check: signature,
        ok: false,
        problem: "I'm not signed by a developer team, so the next install of me can't read what I keep in the Keychain. A paired phone will need pairing again, and I'll sign in to T3 Code again.",
        fix: "Add your Apple ID in Xcode › Settings › Accounts, make an Apple Development certificate under Manage Certificates, then run scripts/install.sh."
    )

    static func findings(from facts: HealthFacts) -> [HealthFinding] {
        var results: [HealthFinding] = []

        // Outside the repo: macOS ignores a badly signed app's permissions, and a copy that isn't a bundle gets those of whatever started it.
        let signatureGood = !facts.isBundled || (facts.isSignedWithIdentity && facts.signatureIsValid)
        if signatureGood {
            results.append((!facts.isBundled || facts.isSignedByTeam) ? .good(signature) : noTeam)
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
            results.append(badSignature)
        }

        switch facts.t3Silence {
        case .connecting?:
            results.append(HealthFinding(
                check: "T3 Code",
                ok: false,
                problem: "I'm still connecting to T3 Code, so my agents can't run yet.",
                fix: "Give it a minute. I'll check again by myself once it answers."
            ))
        case .stuck?:
            results.append(HealthFinding(
                check: "T3 Code",
                ok: false,
                problem: "T3 Code still hasn't answered me, so my agents can't run.",
                fix: "If macOS is showing a Keychain dialog, answer it. If not, quit and reopen T3 Code."
            ))
        case nil:
            results.append(facts.reachedT3 ? .good("T3 Code") : cantReachT3)
        }
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
        if facts.lockdownKittenGone {
            results.append(HealthFinding(
                check: "lockdown",
                ok: false,
                problem: "Lockdown is on for a kitten that isn't set up any more, so I'm holding on to everything you ask.",
                fix: "Turn Lockdown off in my menu, or pick another kitten there."
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
        results.append(waitingFinding(facts))
        results.append(facts.t3GivesRunIDs ? .good("T3 run IDs") : HealthFinding(
            check: "T3 run IDs",
            ok: false,
            problem: "T3 Code has stopped saying which run a thread last finished, so reports go to the bubble instead of the inbox, and a restart can lose them.",
            fix: "Run swift run probe-t3 to see what changed."
        ))
        results.append(shortcutsFinding(facts))
        if facts.isBundled, let shown = facts.shownName, shown != CatWords.appName {
            results.append(HealthFinding(
                check: "name",
                ok: false,
                problem: "The Dock and ⌘Tab call me \(shown), not \(CatWords.appName).",
                fix: "Run scripts/install.sh."
            ))
        } else {
            results.append(.good("name"))
        }
        if facts.phoneNeedsPairingAgain {
            results.append(HealthFinding(
                check: "phone",
                ok: false,
                problem: "Your phone needs pairing again, since this build of me can't read its pairing.",
                fix: "Choose \(CatWords.pairItem) from my menu, then scan the code or type it on your phone."
            ))
        }
        return results
    }

    static let waitingRowsToJudge = 4

    private static func waitingFinding(_ facts: HealthFacts) -> HealthFinding {
        let (all, withoutYou) = (facts.waitingLeft, facts.waitingLeftWithoutYou)
        guard all >= waitingRowsToJudge, withoutYou * 2 > all else { return .good("waiting on you") }
        return HealthFinding(
            check: "waiting on you",
            ok: false,
            problem: "\(withoutYou) of the \(all) things that left Waiting on you this week went without you, so it's asking you about things that sort themselves out.",
            fix: "Ask Clawde to read \(WaitingRecord.fileName), next to inbox.json, which says where each one came from and how it left."
        )
    }

    private static func shortcutsFinding(_ facts: HealthFacts) -> HealthFinding {
        guard !facts.shortcutsTaken.isEmpty else { return .good("shortcuts") }
        let taken = facts.shortcutsTaken.joined(separator: " and ")
        let them = facts.shortcutsTaken.count == 1 ? "it" : "them"
        guard !facts.otherCopies.isEmpty else {
            return HealthFinding(
                check: "shortcuts",
                ok: false,
                problem: "Another app has \(taken), so pressing \(them) does nothing here.",
                fix: "Use my menu for \(them), or change the other app's shortcut and choose Restart from my menu."
            )
        }
        let one = facts.otherCopies.count == 1
        let copies = facts.otherCopies.map(String.init).joined(separator: " and ")
        return HealthFinding(
            check: "shortcuts",
            ok: false,
            problem: one
                ? "Another copy of me, process \(copies), probably has \(taken), so pressing \(them) does nothing here."
                : "Other copies of me, processes \(copies), probably have \(taken), so pressing \(them) does nothing here.",
            fix: "Quit \(one ? "that copy" : "those copies"), then choose Restart from my menu."
        )
    }

    static func report(_ findings: [HealthFinding], pid: Int32, version: String, at date: Date, lockdown: String? = nil) -> HealthReport {
        HealthReport(pid: pid, version: version, checkedAt: date, ok: findings.allSatisfy(\.ok), findings: findings, lockdown: lockdown)
    }
}
