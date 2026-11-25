import Foundation
import ShadesCore

extension AppController {
    static let reviewTimeout: TimeInterval = 90
    static let reviewTitle = "Shades review:"

    var settingsFiles: SettingsFiles {
        SettingsFiles(home: home, kittenFolders: loadKittens().map(\.folder))
    }

    func readable(_ report: String?) -> String? {
        report.map { ChangeRequests.withoutBlocks($0, saying: Prompts.changeCardLine) }
    }

    func fileChangeRequests(in report: String, of thread: AgentThread) {
        Task {
            let asked = await changeRequests(in: report, of: thread)
            guard !asked.isEmpty else { return }
            asked.forEach { inbox.ask($0) }
            keepInbox()
            inboxChanged()
        }
    }

    func changeRequests(in report: String?, of thread: AgentThread) async -> [InboxEntry] {
        guard let report, let kitten = kitten(of: thread) else { return [] }
        let asked = ChangeRequests.all(in: report)
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
