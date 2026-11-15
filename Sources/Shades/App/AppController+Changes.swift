import Foundation
import ShadesCore

/// A settings change a kitten asked for and can't make itself. Shades looks into it, you press Allow or Deny, and only
/// Allow changes the file, exactly as its card showed. Either way the kitten hears how it went, in a note that can't
/// pass for your own words.
extension AppController {
    static let reviewTimeout: TimeInterval = 90
    static let reviewTitle = "Shades review:"

    var settingsFiles: SettingsFiles {
        SettingsFiles(home: home, kittenFolders: loadKittens().map(\.folder))
    }

    /// The report as the sorter and the bubble read it, with each request standing as one line, since it has a card.
    func readable(_ report: String?) -> String? {
        report.map { ChangeRequests.withoutBlocks($0, saying: Prompts.changeCardLine) }
    }

    /// For a kitten without an inbox, whose run isn't filed, so its requests wait in Activity by themselves.
    func fileChangeRequests(in report: String, of thread: AgentThread) {
        Task {
            let asked = await changeRequests(in: report, of: thread)
            guard !asked.isEmpty else { return }
            asked.forEach { inbox.ask($0) }
            keepInbox()
            inboxChanged()
        }
    }

    /// Each request in a kitten's report, checked and looked into, ready for its card. Nothing is saved here, so an inbox
    /// kitten's are saved with the rest of its run.
    func changeRequests(in report: String?, of thread: AgentThread) async -> [InboxEntry] {
        guard let report, let kitten = kitten(of: thread) else { return [] }
        let asked = ChangeRequests.all(in: report)
        guard !asked.isEmpty else { return [] }
        let files = settingsFiles
        var entries: [InboxEntry] = []
        for found in asked {
            var change: ChangeRequest
            switch found {
            case .success(let request):
                change = files.check(request)
            case .failure(let problem):
                change = ChangeRequest(file: "", replace: nil, with: "", why: nil)
                change.problem = problem.reason
            }
            if change.problem == nil { change.review = await review(change, by: kitten.name) }
            entries.append(InboxEntry(
                id: "change-\(UUID().uuidString)",
                kind: .decision,
                text: CatWords.changeRow(change),
                threadID: thread.id,
                threadTitle: thread.title,
                at: now(),
                change: change
            ))
        }
        return entries
    }

    /// Something that can only reply looks into it, in the router's folder, where no tool that acts, sends or reads a
    /// file works. It only ever sees the request and the file, never your screen.
    private func review(_ change: ChangeRequest, by kitten: String) async -> String? {
        let model = settings.quickModel
        guard let projectID = try? await routerProjectID(for: model) else { return nil }
        let prompt = AgentPrompt(
            title: "\(Self.reviewTitle) \(change.file)",
            text: Prompts.reviewChange(change, by: kitten, now: settingsFiles.current(change)),
            model: model,
            runtimeMode: .approvalRequired,
            projectID: projectID
        )
        let said = await firstOf(seconds: Self.reviewTimeout) { [self] in await summarize(prompt) }
        return said ?? nil
    }

    func allowChange(_ id: String) {
        guard let entry = inbox.entries.first(where: { $0.id == id }), let change = entry.change, change.problem == nil else { return }
        do {
            try settingsFiles.apply(change)
            answer(entry, .made)
        } catch {
            let reason = (error as? ChangeRequests.Problem)?.reason ?? error.localizedDescription
            say(CatWords.changeFailed(reason))
            answer(entry, .failed(reason))
        }
    }

    func denyChange(_ id: String) {
        guard let entry = inbox.entries.first(where: { $0.id == id }), entry.change != nil else { return }
        answer(entry, .denied)
    }

    /// The card goes, and each thread that asked hears what happened, queued behind whatever it's doing.
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
