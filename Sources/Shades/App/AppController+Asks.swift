import Foundation
import ShadesCore

/// Something a kitten needs your yes for and then does itself. Its card shows exactly what it would do, and Allow says
/// yes to only that, in The Kitty Litter's own note, never in your words.
extension AppController {
    /// Shades reads what a kitten's decision would have it do on a yes. If that's something exact, the decision's card
    /// offers Allow and Deny for it. All it reads is the sorter's decision line, never the note filed beside it, the
    /// report or your screen.
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

    /// The card goes, and the kitten's thread hears what you pressed and exactly what it was for.
    func answerAsk(_ entry: InboxEntry, _ outcome: Prompts.AskOutcome) {
        guard let ask = entry.ask else { return }
        inbox.remove(entry.id)
        keepInbox()
        inboxChanged()
        let text = Prompts.askAnswered(ask, outcome)
        forwardTask = Task {
            do {
                for try await _ in backend.forward(threadID: entry.threadID, text: text, attachments: [], behavior: .queue) {}
            } catch {
                say(CatWords.problem(error, while: .agents))
            }
        }
    }
}
