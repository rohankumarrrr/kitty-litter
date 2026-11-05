import Foundation
import ShadesCore

/// What Messages can ask for. Nothing in it can say anything for you: sending takes words you typed.
enum MessagesAction: Equatable {
    case send(String, to: MessageTarget, shownIn: ChannelID?)
    case approval(ApprovalRequest, ApprovalDecision)
    /// One of a question's options, by its place in the list.
    case pick(AgentQuestion, option: Int)
    case inbox(InboxAction)
    case seen(ChannelSelection)
}

/// Messages: what needs you, a group chat with every kitten, and a DM with each. Opening it captures nothing,
/// and nothing typed in it takes your screen, since you're looking at Messages and not your work.
extension AppController {
    func channelsPressed() {
        stage.showChannels(channels.open(threads: latestThreads))
    }

    func channelsClosed() {
        channels.close()
    }

    /// From the live list, the one place that has the words of approvals and questions.
    var waiting: Waiting {
        let kittens = loadKittens()
        var waiting = Waiting(approvals: approvals.pending, reports: inbox.entries)
        for thread in latestThreads where !hiddenThreads.contains(thread.id) {
            let owner = KittenBoard.owner(of: thread, among: kittens)?.id
            for request in thread.pendingApprovals { waiting.owners[request.id] = owner }
            if let question = thread.pendingQuestion, !answeredQuestions.contains(question.id) {
                waiting.questions.append(question)
                waiting.owners[question.id] = owner
            }
        }
        return waiting
    }

    func messagesAction(_ action: MessagesAction) {
        switch action {
        case .send(let words, let target, let channel):
            send(words, to: target, shownIn: channel)
        case .approval(let request, let decision):
            answer(request, decision)
        case .pick(let question, let option):
            guard let values = question.form?.values, values.indices.contains(option) else { return }
            answer(question, with: values[option])
        case .inbox(let action):
            inboxAction(action)
        case .seen(let selection):
            if inbox.markRead(channels.threads(in: selection)) {
                keepInbox()
                channels.refresh()
            }
        }
    }

    /// Each way of sending passes on your words and nothing else: no screen, and nothing anyone else said.
    func send(_ words: String, to target: MessageTarget, shownIn channel: ChannelID?) {
        if let channel {
            let threadID: String
            let title: String
            if case .thread(let id, let name) = target { (threadID, title) = (id, name) } else { (threadID, title) = ("", "") }
            let echo = ChannelMessage(exchangeID: "sent-\(UUID().uuidString)", kind: .ask, speaker: .you, text: words, at: now(), threadID: threadID, threadTitle: title)
            channels.sent(echo, in: channel)
        }
        switch target {
        case .router:
            // One at a time, since a newer question would otherwise drop the one before it.
            let previous = messagesTurn
            messagesTurn = Task {
                await previous?.value
                ask(words, snapshot: nil)
                messagesGeneration = replyGeneration
                await replyTask?.value
            }
        case .newThread(let kitten):
            give(words, to: kitten, snapshot: nil)
        case .thread(let id, let title):
            reply(words, toThread: id, title: title)
        case .question(let question):
            answer(question, with: words)
        }
    }

    /// The router's own answer, for the group chat. A message it passed on gets its answer from whoever took it.
    func routerAnswered(_ text: String, generation: Int) {
        guard generation == messagesGeneration, !text.isEmpty else { return }
        channels.sent(ChannelMessage(exchangeID: "cat-\(UUID().uuidString)", kind: .reply, speaker: .cat, text: text, at: now(), threadID: "", threadTitle: ""), in: .everyone)
    }

    func answer(_ question: AgentQuestion, with value: String) {
        answeredQuestions.insert(question.id)
        channels.refresh()
        Task { [backend] in
            do {
                try await backend.answer(question, with: value)
            } catch {
                answeredQuestions.remove(question.id)
                channels.refresh()
                say(CatWords.approvalFailed)
            }
        }
    }
}
