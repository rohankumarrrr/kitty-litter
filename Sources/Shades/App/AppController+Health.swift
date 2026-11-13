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

/// What the self-check asked T3. `silence` says it hasn't answered, when the rest is unknown.
private struct T3Answers {
    var silence: T3Silence?
    var reached = false
    var frontDoorError: Error?
    var kittensNotInT3: [Kitten] = []
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
            if findings.contains(HealthCheck.badSignature) {
                say(CatWords.finding(HealthCheck.badSignature), unasked: true)
            }
        }
    }

    /// You asked: go through everything, and say how it went, and again if T3 answers late.
    func checkMyselfPressed() {
        healthTask = Task {
            await runHealthCheck(each: { [weak self] in self?.sayHowItWent($0) })
        }
    }

    /// A newer check takes the place of one still showing, rather than waiting behind it.
    private func sayHowItWent(_ findings: [HealthFinding]) {
        notices.removeAll { $0.caption == CatWords.selfCheckCaption && $0.threadID == nil }
        let problems = findings.filter { !$0.ok }
        let text = problems.isEmpty ? CatWords.allGood : problems.map(CatWords.finding).joined(separator: "\n\n")
        post(caption: CatWords.selfCheckCaption, text: text, threadID: nil)
    }

    /// `each` hears every report this check writes, the late ones too, until a newer check takes over.
    @discardableResult
    func runHealthCheck(each: (([HealthFinding]) -> Void)? = nil) async -> [HealthFinding] {
        healthChecks += 1
        let check = healthChecks
        let kittens = loadKittens().filter { !$0.planned }
        let asking = Task { await askT3(about: kittens) }
        // A new build can't read the last one's sign-in, so it signs in again, which can take T3 a while, and nothing can
        // cut a Keychain dialog short. So the report goes out after `t3Wait` either way, and again once T3 answers. The
        // install waits for the first, and a copy that never reports gets rolled back.
        if let answers = await within(t3Wait, { await asking.value }) {
            return report(answers, kittens: kittens, check: check, each: each)
        }
        if check == healthChecks {
            t3Recheck = Task {
                if await within(t3StuckAfter, { await asking.value }) == nil {
                    report(T3Answers(silence: .stuck), kittens: kittens, check: check, each: each)
                }
                report(await asking.value, kittens: kittens, check: check, each: each)
            }
        }
        return report(T3Answers(silence: .connecting), kittens: kittens, check: check, each: each)
    }

    /// Everything the self-check asks T3, as one, so an answer that comes late can still be reported whole.
    private func askT3(about kittens: [Kitten]) async -> T3Answers {
        var answers = T3Answers()
        do { _ = try await routerProjectID(for: settings.quickModel) } catch { answers.frontDoorError = error }
        // Right after a launch T3 can take some seconds to send its first list. Finding the front door waits for it,
        // so whether T3 is there is only judged once that's done.
        await waitForThreadList()
        answers.reached = threadListArrived
        guard answers.reached else { return answers }
        for kitten in kittens {
            if await backend.projectID(atPath: kitten.workspace) == nil { answers.kittensNotInT3.append(kitten) }
        }
        return answers
    }

    @discardableResult
    private func report(_ t3: T3Answers, kittens: [Kitten], check: Int, each: (([HealthFinding]) -> Void)?) -> [HealthFinding] {
        var facts = systemFacts()
        facts.inboxSaves = !inboxSaveFailed
        facts.shortcutsTaken = takenShortcuts
        facts.phoneNeedsPairingAgain = phone?.door.needsPairingAgain ?? false
        facts.t3Silence = t3.silence
        facts.reachedT3 = t3.reached
        facts.kittensNotInT3 = t3.kittensNotInT3
        facts.t3GivesRunIDs = !latestThreads.contains { $0.status == .completed && $0.lastRunID == nil }
        switch t3.frontDoorError {
        case let problem as FrontDoorProblem:
            facts.frontDoorProblem = problem
        // With T3 out of reach, that's the finding.
        case let error? where t3.reached:
            facts.frontDoorProjectTrouble = CatWords.problem(error, while: .agents)
        default:
            break
        }
        for kitten in kittens {
            if !fileExists(kitten.folder + "/CLAUDE.md") { facts.kittensWithoutInstructions.append(kitten.name) }
            // Only Claude Code reads the settings that make up the block.
            if !kitten.seesScreen, settings.frontierModel.provider != "claudeAgent" || !screenBlockGaps(kitten.folder).isEmpty {
                facts.kittensOffScreenInNameOnly.append(kitten.name)
            }
        }

        let findings = HealthCheck.findings(from: facts)
        // A newer check has started, so what this one found is already out of date.
        guard check == healthChecks else { return findings }
        health = findings
        reportHealth(findings)
        each?(findings)
        return findings
    }

    /// What `work` comes to, or `nil` if it's still going after `seconds`, when it's left to finish on its own.
    private func within<Value>(_ seconds: TimeInterval, _ work: @escaping @MainActor () async -> Value) async -> Value? {
        let once = FirstAnswer<Value>()
        return await withCheckedContinuation { continuation in
            once.continuation = continuation
            Task { @MainActor in once.finish(await work()) }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                once.finish(nil)
            }
        }
    }

    /// Why the screen can't be seen, if the real reason isn't what it looks like.
    var screenBlockedBy: String? {
        health?.first { $0 == HealthCheck.badSignature }.map(CatWords.finding)
    }
}
