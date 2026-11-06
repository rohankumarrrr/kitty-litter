import Foundation
import ShadesCore

/// Keeps up with the agents: what they're doing, how the cat feels about it, and what they're asking.
extension AppController {
    func connect() async {
        do {
            try await backend.connect()
        } catch {
            stage.showStatus(CatWords.cantReachT3, needsYou: false)
            say(CatWords.problem(error, while: .agents))
        }
    }

    func threadsChanged(_ threads: [AgentThread]) {
        tidyLeftoverSummaries(threads)
        hideTestThreads(threads)
        latestThreads = threads
        threadListArrived = true
        let asked = Set(threads.compactMap(\.pendingQuestion?.id))
        answeredQuestions.formIntersection(asked)
        let events = watch.update(threads)
        let hadApprovals = !approvals.isEmpty
        approvals.sync(with: threads.filter { !hiddenThreads.contains($0.id) })
        approvalsChanged(hadApprovals: hadApprovals)
        dropAnsweredQuestions(threads)

        stage.catAgentsBusy(watch.isBusy)
        stage.showStatus(watch.summary, needsYou: watch.needsYouCount > 0)
        if stage.isKittensVisible { stage.showKittens(kittenStatuses) }
        channels.threadsChanged(threads)
        updateVocabulary(threads)

        for event in events {
            switch event {
            case .finished(let thread):
                stage.catCelebrate()
                if !goesToInbox(thread) { reportOn(thread, failed: false) }
            case .failed(let thread):
                dropScreenWarning(for: thread.id, run: thread.lastRunID)
                if !goesToInbox(thread) { reportOn(thread, failed: true) }
            case .hasQuestion(let question):
                announce(question)
            }
        }
        dropScreenWarnings(forFailuresIn: threads)
        fileOwedReports()
    }

    /// A live test isn't for you, so nothing about it reaches the inbox or the bubble. Probes follow their own
    /// streams, and a copy trying a flow out keeps seeing them, so a test can still see its own result.
    private func hideTestThreads(_ threads: [AgentThread]) {
        guard hidesTestThreads else { return }
        for thread in threads where thread.isLiveTest {
            hiddenThreads.insert(thread.id)
            watch.markQuick(thread.id)
        }
    }

    var kittenStatuses: [KittenStatus] {
        KittenBoard.statuses(kittens: loadKittens(), threads: latestThreads)
    }

    /// Normally there's just Shades. This shows everyone else, and how they're doing.
    func kittensPressed() {
        if stage.isKittensVisible {
            stage.hideKittens()
        } else {
            stage.showKittens(kittenStatuses)
        }
    }

    /// Project names are the words speech recognition most often gets wrong.
    func updateVocabulary(_ threads: [AgentThread]) {
        let words = Array(Set(settings.vocabulary + projectNames + threads.compactMap(\.projectTitle))).sorted()
        guard words != vocabulary else { return }
        vocabulary = words
        voice.setVocabulary(words)
    }

    func addApproval(_ request: ApprovalRequest) {
        let hadApprovals = !approvals.isEmpty
        approvals.add(request)
        approvalsChanged(hadApprovals: hadApprovals)
    }

    func approvalsChanged(hadApprovals: Bool) {
        channels.refresh()
        notifyNeedsYou()
        if approvals.isEmpty {
            approvalsOnShow = false
            approvalsHidden = false
            if catIsAway {
                catIsAway = false
                catFollowsReply()
            }
        } else if !hadApprovals {
            // It comes to you first, then asks.
            approvalsOnShow = false
            approvalsHidden = false
            catIsAway = true
            stage.catComeToYou { [weak self] in
                self?.approvalsOnShow = true
                self?.renderBubble()
            }
        }
        renderBubble()
    }

    func answer(_ request: ApprovalRequest, _ decision: ApprovalDecision) {
        let hadApprovals = !approvals.isEmpty
        approvals.answer(request.id)
        approvalsChanged(hadApprovals: hadApprovals)
        Task { [backend] in
            do {
                try await backend.respond(to: request, with: decision)
            } catch {
                let hadApprovals = !approvals.isEmpty
                approvals.restore(request)
                approvalsChanged(hadApprovals: hadApprovals)
                say(CatWords.approvalFailed)
            }
        }
    }
}
