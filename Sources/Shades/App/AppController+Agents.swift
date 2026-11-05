import Foundation
import ShadesCore

/// Keeps up with the agents: what they're doing, how the cat feels about it, and what they're asking.
extension AppController {
    func connect() async {
        do {
            try await backend.connect()
        } catch {
            stage.showThreads(watch.rows(at: now()), status: CatWords.cantReachT3)
            say(CatWords.problem(error, while: .agents))
        }
    }

    func threadsChanged(_ threads: [AgentThread]) {
        let events = watch.update(threads)
        let hadApprovals = !approvals.isEmpty
        approvals.sync(with: threads.filter { !hiddenThreads.contains($0.id) })
        approvalsChanged(hadApprovals: hadApprovals)
        dropAnsweredQuestions(threads)

        stage.catAgentsBusy(watch.isBusy)
        stage.showThreads(watch.rows(at: now()), status: watch.summary)
        updateVocabulary(threads)

        for event in events {
            switch event {
            case .finished(let thread):
                stage.catCelebrate()
                reportOn(thread, failed: false)
            case .failed(let thread):
                reportOn(thread, failed: true)
            case .hasQuestion(let question):
                announce(question)
            }
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
        if approvals.isEmpty {
            approvalsOnShow = false
            approvalsHidden = false
            if catIsAway {
                catIsAway = false
                stage.catGoHome()
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
