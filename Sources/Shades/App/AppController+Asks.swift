import Foundation
import ShadesCore

extension AppController {
    func readDecision(_ id: String, decision: String, of thread: AgentThread) {
        guard let kitten = kitten(of: thread) else { return }
        Task {
            guard let reply = await lookInto(Prompts.readDecision(decision, by: kitten.name, task: thread.title), about: thread.title),
                  let ask = AskRequest(readingDecision: reply), inbox.attach(ask, to: id)
            else { return }
            keepInbox()
            inboxChanged()
        }
    }

    func answerAsk(_ entry: InboxEntry, _ outcome: Prompts.AskOutcome) {
        guard let ask = entry.ask else { return }
        inbox.remove(entry.id, because: outcome == .denied ? .denied : .allowed, at: now())
        keepInbox()
        inboxChanged()
        let text = Prompts.askAnswered(ask, outcome)
        forwardTask = Task {
            do {
                inbox.appWillWrite(to: entry.threadID, at: now())
                for try await _ in backend.forward(threadID: entry.threadID, text: text, attachments: [], behavior: .queue) {}
            } catch {
                say(CatWords.problem(error, while: .agents))
            }
        }
    }
}
