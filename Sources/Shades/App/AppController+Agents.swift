import Foundation
import ShadesCore

extension AppController {
    func connect() async {
        do {
            try await backend.connect()
        } catch {
            stage.showStatus(CatWords.cantReachT3, needsYou: false)
            say(CatWords.problem(error, while: .agents), unasked: true)
        }
    }

    func threadsChanged(_ threads: [AgentThread]) {
        tidyLeftoverSummaries(threads)
        hideTestThreads(threads)
        latestThreads = threads
        if !threadListArrived, health?.contains(HealthCheck.cantReachT3) == true {
            healthTask = Task { await runHealthCheck() }
        }
        if !threadListArrived {
            Task { [weak self, warmDelay] in
                try? await Task.sleep(for: warmDelay)
                guard let self else { return }
                self.channels.warm(threads: self.latestThreads)
            }
        }
        threadListArrived = true
        for thread in threads where isWithShades(thread) { watch.markQuick(thread.id) }
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
            case .turnEnded(let thread):
                if !goesToInbox(thread) { reportOn(thread, failed: false) }
            case .failed(let thread):
                dropScreenWarning(for: thread.id, run: thread.lastRunID)
                if !goesToInbox(thread) { reportOn(thread, failed: true) }
            case .hasQuestion(let question):
                announce(question)
            }
        }
        dropScreenWarnings(forFailuresIn: threads)
        if inbox.follow(threads, at: now()) {
            keepInbox()
            inboxChanged()
        }
        fileOwedReports()
        retireStaleChanges()
    }

    private func hideTestThreads(_ threads: [AgentThread]) {
        guard hidesTestThreads else { return }
        for thread in threads where thread.isLiveTest {
            hiddenThreads.insert(thread.id)
            watch.markQuick(thread.id)
        }
    }

    var kittenStatuses: [KittenStatus] {
        KittenBoard.statuses(kittens: loadKittens(), threads: latestThreads.filter { !isWithShades($0) })
    }

    func kittensPressed() {
        if stage.isKittensVisible {
            stage.hideKittens()
        } else {
            stage.showKittens(kittenStatuses)
        }
    }

    func kittenPressed(_ status: KittenStatus) {
        guard let threadID = status.threadID else { return channelsPressed(selecting: .channel(.of(status.kitten))) }
        showInMessages(threadID)
    }

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
        let comes = approvals.pending.map { mayPopUp(.approval($0.id)) }.contains(true)
        let hadApprovals = hadApprovals && (hadAskable || askable.isEmpty)
        hadAskable = !askable.isEmpty
        if approvals.isEmpty {
            approvalsOnShow = false
            approvalsHidden = false
            if catIsAway {
                catIsAway = false
                catFollowsReply()
            }
        } else if !hadApprovals, !comes {
            approvalsOnShow = true
            approvalsHidden = true
        } else if !hadApprovals {
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

    func ignore(_ request: ApprovalRequest) {
        let hadApprovals = !approvals.isEmpty
        approvals.answer(request.id)
        approvalsChanged(hadApprovals: hadApprovals)
    }

    func runEnded(asking ids: Set<String>) {
        let hadApprovals = !approvals.isEmpty
        if approvals.runEnded(asking: ids) { approvalsChanged(hadApprovals: hadApprovals) }
    }
}
