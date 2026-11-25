import Foundation
import ShadesCore

private final class FirstAnswer<Value>: @unchecked Sendable {
    var continuation: CheckedContinuation<Value?, Never>?

    func finish(_ value: Value?) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}

private struct T3Answers {
    var silence: T3Silence?
    var reached = false
    var frontDoorError: Error?
    var kittensNotInT3: [Kitten] = []
}

extension AppController {
    func startHealthChecks() {
        healthTask = Task {
            await waitForThreadList()
            let findings = await runHealthCheck()
            if findings.contains(HealthCheck.badSignature) {
                say(CatWords.finding(HealthCheck.badSignature), unasked: true)
            }
        }
    }

    func checkMyselfPressed() {
        healthTask = Task {
            await runHealthCheck(each: { [weak self] in self?.sayHowItWent($0) })
        }
    }

    private func sayHowItWent(_ findings: [HealthFinding]) {
        notices.removeAll { $0.caption == CatWords.selfCheckCaption && $0.threadID == nil }
        let problems = findings.filter { !$0.ok }
        let text = problems.isEmpty ? CatWords.allGood : problems.map(CatWords.finding).joined(separator: "\n\n")
        post(caption: CatWords.selfCheckCaption, text: text, threadID: nil)
    }

    @discardableResult
    func runHealthCheck(each: (([HealthFinding]) -> Void)? = nil) async -> [HealthFinding] {
        healthChecks += 1
        let check = healthChecks
        let kittens = loadKittens().filter { !$0.planned }
        let asking = Task { await askT3(about: kittens) }
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

    private func askT3(about kittens: [Kitten]) async -> T3Answers {
        var answers = T3Answers()
        do { _ = try await routerProjectID(for: settings.quickModel) } catch { answers.frontDoorError = error }
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
        facts.lockdownKittenGone = settings.lockdown != nil && lockedDownKitten == nil
        facts.t3GivesRunIDs = !latestThreads.contains { $0.status == .completed && $0.lastRunID == nil }
        switch t3.frontDoorError {
        case let problem as FrontDoorProblem:
            facts.frontDoorProblem = problem
        case let error? where t3.reached:
            facts.frontDoorProjectTrouble = CatWords.problem(error, while: .agents)
        default:
            break
        }
        for kitten in kittens {
            if !fileExists(kitten.folder + "/CLAUDE.md") { facts.kittensWithoutInstructions.append(kitten.name) }
            // Outside the repo: only Claude Code reads the settings files that make up the screen block.
            if !kitten.seesScreen, settings.frontierModel.provider != "claudeAgent" || !screenBlockGaps(kitten.folder).isEmpty {
                facts.kittensOffScreenInNameOnly.append(kitten.name)
            }
        }

        let findings = HealthCheck.findings(from: facts)
        guard check == healthChecks else { return findings }
        health = findings
        reportHealth(findings, settings.lockdown.map { lockedDownKitten?.name ?? $0.kitten })
        each?(findings)
        return findings
    }

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

    var screenBlockedBy: String? {
        health?.first { $0 == HealthCheck.badSignature }.map(CatWords.finding)
    }
}
