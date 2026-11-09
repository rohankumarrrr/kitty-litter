import Foundation
import ShadesCore

/// Whichever of two answers comes first, which is the only one taken. Both come on the main actor.
private final class FirstAnswer<Value>: @unchecked Sendable {
    var continuation: CheckedContinuation<Value?, Never>?

    func finish(_ value: Value?) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}

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
                say(CatWords.finding(bad), unasked: true)
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
        facts.inboxSaves = !inboxSaveFailed
        facts.shortcutsTaken = takenShortcuts
        // Signing in can wait on a Keychain dialog, and nothing can cut that short, so T3 gets a while to answer and the
        // report goes out either way. The install waits for it, and a copy that never reports gets rolled back.
        let frontDoor: Result<String, Error>? = await withinT3Wait { [self] in
            do { return .success(try await routerProjectID(for: settings.quickModel)) } catch { return .failure(error) }
        }
        facts.t3DidntAnswer = frontDoor == nil
        var frontDoorError: Error?
        if case .failure(let error)? = frontDoor { frontDoorError = error }
        // Right after a launch T3 can take some seconds to send its first list. Finding the front door waits for it,
        // so whether T3 is there is only judged once that's done.
        await waitForThreadList()
        facts.reachedT3 = threadListArrived
        facts.t3GivesRunIDs = !latestThreads.contains { $0.status == .completed && $0.lastRunID == nil }
        switch frontDoorError {
        case let problem as FrontDoorProblem:
            facts.frontDoorProblem = problem
        // With T3 out of reach, that's the finding.
        case let error? where facts.reachedT3:
            facts.frontDoorProjectTrouble = CatWords.problem(error, while: .agents)
        default:
            break
        }

        for kitten in loadKittens() where !kitten.planned {
            if !fileExists(kitten.folder + "/CLAUDE.md") { facts.kittensWithoutInstructions.append(kitten.name) }
            if facts.reachedT3, await backend.projectID(atPath: kitten.workspace) == nil {
                facts.kittensNotInT3.append(kitten)
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

    /// What `work` comes to, or `nil` if it's still going after `t3Wait`, when it's left to finish on its own.
    private func withinT3Wait<Value>(_ work: @escaping @MainActor () async -> Value) async -> Value? {
        let once = FirstAnswer<Value>()
        let wait = t3Wait
        return await withCheckedContinuation { continuation in
            once.continuation = continuation
            Task { @MainActor in once.finish(await work()) }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                once.finish(nil)
            }
        }
    }

    /// Why the screen can't be seen, if the real reason isn't what it looks like.
    var screenBlockedBy: String? {
        health?.first { $0.check == HealthCheck.signature && !$0.ok }.map(CatWords.finding)
    }
}
