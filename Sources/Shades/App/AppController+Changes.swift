import Foundation
import ShadesCore

extension AppController {
    static let reviewTimeout: TimeInterval = 90
    static let reviewTitle = "Shades review:"

    var settingsFiles: SettingsFiles {
        SettingsFiles(home: home, kittenFolders: loadKittens().map(\.folder))
    }

    func readable(_ report: String?) -> String? {
        report.map { ChangeRequests.withoutBlocks($0, saying: Prompts.changeCardLine, withdrawn: Prompts.withdrawnLine) }
    }

    func fileChangeRequests(in report: String, of thread: AgentThread) {
        let earlier = changeFiling[thread.id]
        changeFiling[thread.id] = Task {
            await earlier?.value
            let asked = await changeRequests(in: report, of: thread)
            let withdrew = withdrawRequests(in: report, of: thread)
            guard withdrew || !asked.isEmpty else { return }
            asked.forEach { inbox.ask($0, title: title(ofThread:)) }
            keepInbox()
            inboxChanged()
        }
    }

    @discardableResult
    func withdrawRequests(in report: String?, of thread: AgentThread) -> Bool {
        guard let report, kitten(of: thread) != nil else { return false }
        let withdrawn = ChangeRequests.withdrawals(in: report)
        guard !withdrawn.isEmpty else { return false }
        let files = settingsFiles
        let before = inbox.entries
        for asked in withdrawn {
            inbox.withdraw(asked, file: files.shown(listed: asked), by: thread.id, title: title(ofThread:))
        }
        return inbox.entries != before
    }

    func title(ofThread id: String) -> String? {
        latestThreads.first { $0.id == id }?.title
    }

    func retireStaleChanges() {
        let waiting = inbox.entries.filter { $0.change?.problem == nil && $0.change?.file.isEmpty == false }
        guard !waiting.isEmpty else { return }
        let files = settingsFiles
        let before = inbox.entries
        for entry in waiting {
            guard var change = entry.change, let staleness = files.staleness(of: change) else { continue }
            switch staleness {
            case .alreadyMade:
                inbox.remove(entry.id)
            case .cantBeMade(let reason):
                change.problem = reason
                inbox.cantBeMade(entry.id, because: reason, row: CatWords.changeRow(change))
            }
        }
        guard inbox.entries != before else { return }
        keepInbox()
        inboxChanged()
    }

    func changeRequests(in report: String?, of thread: AgentThread) async -> [InboxEntry] {
        guard let report, let kitten = kitten(of: thread) else { return [] }
        let asked = ChangeRequests.cards(in: report)
        guard !asked.isEmpty else { return [] }
        let files = settingsFiles
        var entries: [InboxEntry] = []
        for found in asked {
            let entry = { (text: String, change: ChangeRequest?, ask: AskRequest?) in
                InboxEntry(id: "change-\(UUID().uuidString)", kind: .decision, text: text, threadID: thread.id, threadTitle: thread.title, at: self.now(), change: change, ask: ask)
            }
            switch found {
            case .success(.change(let request)):
                var change = files.check(request)
                if change.problem == nil {
                    change.review = await lookInto(Prompts.reviewChange(change, by: kitten.name, now: files.current(change)), about: change.file)
                }
                entries.append(entry(CatWords.changeRow(change), change, nil))
            case .success(.ask(var ask)):
                ask.review = await lookInto(Prompts.reviewAsk(ask, by: kitten.name, task: thread.title), about: thread.title)
                entries.append(entry(CatWords.askRow(ask, by: kitten.name), nil, ask))
            case .failure(let problem):
                var change = ChangeRequest(file: "", replace: nil, with: "", why: nil)
                change.problem = problem.reason
                entries.append(entry(CatWords.changeRow(change), change, nil))
            case .success(.withdraw):
                break
            }
        }
        return entries
    }

    func lookInto(_ prompt: String, about subject: String) async -> String? {
        let model = settings.quickModel
        guard let projectID = try? await routerProjectID(for: model) else { return nil }
        let prompt = AgentPrompt(
            title: String("\(Self.reviewTitle) \(subject)".prefix(80)),
            text: prompt,
            model: model,
            runtimeMode: .approvalRequired,
            projectID: projectID
        )
        let said = await firstOf(seconds: Self.reviewTimeout) { [self] in await summarize(prompt) }
        return said ?? nil
    }

    func allow(_ id: String) {
        guard let entry = inbox.entries.first(where: { $0.id == id }) else { return }
        if entry.change != nil { allowChange(entry) } else if entry.ask != nil { answerAsk(entry, .allowed) }
    }

    func deny(_ id: String) {
        guard let entry = inbox.entries.first(where: { $0.id == id }) else { return }
        if entry.change != nil { answer(entry, .denied) } else if entry.ask != nil { answerAsk(entry, .denied) }
    }

    private func allowChange(_ entry: InboxEntry) {
        guard let change = entry.change, change.problem == nil else { return }
        do {
            try settingsFiles.apply(change)
            answer(entry, .made)
            retireStaleChanges()
        } catch {
            let reason = (error as? ChangeRequests.Problem)?.reason ?? error.localizedDescription
            say(CatWords.changeFailed(reason))
            answer(entry, .failed(reason))
        }
    }

    private func answer(_ entry: InboxEntry, _ outcome: Prompts.ChangeOutcome) {
        guard let change = entry.change else { return }
        inbox.remove(entry.id)
        keepInbox()
        inboxChanged()
        let text = Prompts.changeAnswered(change, outcome)
        forwardTask = Task {
            for thread in [entry.threadID] + change.alsoAskedIn {
                do {
                    for try await _ in backend.forward(threadID: thread, text: text, attachments: [], behavior: .queue) {}
                } catch {
                    say(CatWords.problem(error, while: .agents))
                }
            }
        }
    }
}
