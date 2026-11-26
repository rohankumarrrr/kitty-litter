import Foundation
import ShadesCore

extension AppController {
    var effectiveQuickModel: ModelChoice {
        clearExpiredClaudeLimit()
        return claudeLimit.effectiveModel(for: settings.quickModel, fallback: settings.fallbackModel, at: now())
    }

    var effectiveFrontierModel: ModelChoice {
        clearExpiredClaudeLimit()
        return claudeLimit.effectiveModel(for: settings.frontierModel, fallback: settings.fallbackModel, at: now())
    }

    var activeClaudeFallback: ClaudeFallbackStatus? {
        clearExpiredClaudeLimit()
        let at = now()
        guard let resetAt = claudeLimit.resetAt,
              claudeLimit.usesFallback(for: settings.quickModel, at: at)
                || claudeLimit.usesFallback(for: settings.frontierModel, at: at)
        else { return nil }
        return ClaudeFallbackStatus(
            fallbackModel: settings.fallbackModel,
            primaryModel: settings.frontierModel.isClaude ? settings.frontierModel : settings.quickModel,
            resetAt: resetAt
        )
    }

    func isFallbackFrontDoor(_ model: ModelChoice) -> Bool {
        clearExpiredClaudeLimit()
        return claudeLimit.usesFallback(for: settings.quickModel, at: now()) && model == settings.fallbackModel
    }

    @discardableResult
    func clearExpiredClaudeLimit() -> Bool {
        guard claudeLimit.clearIfReset(at: now()) else { return false }
        saveClaudeLimit(claudeLimit)
        claudeLimitResetTask?.cancel()
        claudeLimitResetTask = nil
        quick.reset()
        messagesQuick.reset()
        return true
    }

    @discardableResult
    func noteClaudeUsageLimit(resetAt: Date?, message: String? = nil, text: String? = nil) -> Bool {
        let at = now()
        let resolved = resetAt
            ?? ClaudeUsageLimit.parseReset(in: text, relativeTo: at)
            ?? ClaudeUsageLimit.parseReset(in: message, relativeTo: at)
        let wasActive = claudeLimit.isActive(at: at)
        guard claudeLimit.noteLimit(resetAt: resolved, now: at) else { return false }
        saveClaudeLimit(claudeLimit)
        if !wasActive {
            quick.reset()
            messagesQuick.reset()
        }
        scheduleClaudeLimitReset()
        if health != nil { healthTask = Task { await runHealthCheck() } }
        return true
    }

    func updateClaudeLimit(from threads: [AgentThread]) {
        let at = now()
        let cleared = clearExpiredClaudeLimit()
        let wasActive = claudeLimit.isActive(at: at)
        let changed = claudeLimit.noteThreads(threads, now: at)
        if changed {
            saveClaudeLimit(claudeLimit)
            if !wasActive {
                quick.reset()
                messagesQuick.reset()
            }
            scheduleClaudeLimitReset()
        }
        if (cleared || changed), health != nil {
            healthTask = Task { await runHealthCheck() }
        }
    }

    func scheduleClaudeLimitReset() {
        claudeLimitResetTask?.cancel()
        claudeLimitResetTask = nil
        guard let resetAt = claudeLimit.resetAt else { return }
        let wait = resetAt.timeIntervalSince(now())
        guard wait > 0 else {
            if clearExpiredClaudeLimit(), health != nil {
                healthTask = Task { await runHealthCheck() }
            }
            return
        }
        let capped = min(wait + 1, 24 * 60 * 60)
        claudeLimitResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(capped))
            guard !Task.isCancelled, let self else { return }
            if self.clearExpiredClaudeLimit() {
                if self.health != nil { self.healthTask = Task { await self.runHealthCheck() } }
            } else {
                self.scheduleClaudeLimitReset()
            }
        }
    }

    func discardFailedFallbackThread(_ threadID: String?) {
        guard let threadID else { return }
        hiddenThreads.insert(threadID)
        dispatchers.remove(threadID)
        catsWork.removeValue(forKey: threadID)
        Task { [backend] in try? await backend.archive(threadID: threadID) }
    }
}
