import Foundation
import ShadesCore

/// The cat keeping an eye on itself, so that when something's wrong it can say what, rather
/// than you having to work it out from the symptoms.
extension AppController {
    /// Runs once the app is up. The install script waits for the report this writes.
    func startHealthChecks() {
        healthTask = Task {
            await waitForThreadList()
            let findings = await runHealthCheck()
            // Your permissions are your business, and the caption says so when it matters.
            // A bad signature isn't something you'd ever think to look for, so it gets said.
            if let bad = findings.first(where: { $0.check == HealthCheck.signature && !$0.ok }) {
                say(CatWords.finding(bad), seconds: 20)
            }
        }
    }

    /// You asked: go through everything, and say how it went.
    func checkMyselfPressed() {
        healthTask = Task {
            let findings = await runHealthCheck()
            let problems = findings.filter { !$0.ok }
            let text = problems.isEmpty ? CatWords.allGood : problems.map(CatWords.finding).joined(separator: "\n\n")
            post(caption: CatWords.selfCheckCaption, text: text, threadID: nil)
        }
    }

    @discardableResult
    func runHealthCheck() async -> [HealthFinding] {
        var facts = systemFacts()
        facts.reachedT3 = threadListArrived
        facts.inboxSaves = !inboxSaveFailed
        facts.t3GivesRunIDs = !latestThreads.contains { $0.status == .completed && $0.lastRunID == nil }

        for kitten in loadKittens() where !kitten.planned {
            if !fileExists(kitten.folder + "/CLAUDE.md") { facts.kittensWithoutInstructions.append(kitten.name) }
            if facts.reachedT3, await backend.projectID(atPath: kitten.workspace) == nil {
                facts.kittensNotInT3.append(kitten.name)
            }
            // Only Claude Code reads the settings that make up the block.
            if !kitten.seesScreen, settings.frontierModel.provider != "claudeAgent" || !screenBlockGaps(kitten.folder).isEmpty {
                facts.kittensOffScreenInNameOnly.append(kitten.name)
            }
        }

        let findings = HealthCheck.findings(from: facts)
        health = findings
        reportHealth(findings)
        return findings
    }

    /// Why the screen can't be seen, if the real reason isn't what it looks like.
    var screenBlockedBy: String? {
        health?.first { $0.check == HealthCheck.signature && !$0.ok }.map(CatWords.finding)
    }
}
