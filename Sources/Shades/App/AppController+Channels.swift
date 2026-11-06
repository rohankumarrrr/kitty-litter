import Foundation
import ShadesCore

/// What Messages can ask for. Nothing in it can say anything for you: sending takes words you typed.
enum MessagesAction: Equatable {
    case send(String, to: MessageTarget, shownIn: ChannelID?)
    case approval(ApprovalRequest, ApprovalDecision)
    /// Every part of a question's answer, in order.
    case answer(AgentQuestion, [String])
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
        case .answer(let question, let answers):
            answer(question, with: answers)
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
        let echoID = "sent-\(UUID().uuidString)"
        func echo(threadID: String = "", title: String = "") {
            guard let channel else { return }
            channels.sent(ChannelMessage(exchangeID: echoID, kind: .ask, speaker: .you, text: words, at: now(), threadID: threadID, threadTitle: title), in: channel)
        }
        switch target {
        case .router:
            echo()
            // One at a time, so each goes where it's meant to before the next is read.
            let previous = messagesTurn
            let sentAt = now()
            // Asking the cat something while the router thinks moves on from this, as it would in the Ask box.
            let asked = questionsAsked
            messagesTurn = Task {
                await previous?.value
                await route(words, sentAt: sentAt, asked: asked)
            }
        case .newThread(let kitten):
            echo()
            // The box waits for the new thread, so what you add next goes there too.
            let title = String(words.prefix { !$0.isNewline }.prefix(60))
            give(words, to: kitten, snapshot: nil) { [weak self] threadID in
                self?.channels.started(echoID, in: threadID, title: title)
            }
        case .thread(let id, let title):
            echo(threadID: id, title: title)
            reply(words, toThread: id, title: title)
        case .starting:
            break
        case .question(let question):
            answer(question, with: [words])
        }
    }

    /// The same prompt and model as the Ask box, on Messages' own conversation with the router, so nothing from
    /// your screen is in what it can see, and asking the cat meanwhile can't cut it short.
    private func route(_ words: String, sentAt: Date, asked: Int) async {
        await waitForThreadList()
        let current = messagesQuick.thread(at: now())
        // Only Messages' own world: the kittens' threads, and work it passed your words to. Anything the Ask box
        // started can hold your screen, and that has to hold after a restart too.
        let owners = loadKittens()
        let sessions = rosterThreads(excluding: current) { [messagesThreads] thread in
            messagesThreads[thread.id] != nil || KittenBoard.owner(of: thread, among: owners) != nil
        }
        let briefs = await briefs(for: sessions)
        let kittens = owners.filter { !$0.planned }
        let model = settings.quickModel
        let projectID: String
        do {
            projectID = try await routerProjectID(for: model)
        } catch {
            return catSays(CatWords.problem(error, while: .agents))
        }
        let prompt = AgentPrompt(
            title: String(words.prefix { !$0.isNewline }.prefix(60)),
            text: Prompts.quick(question: words, snapshot: nil, sessions: briefs, kittens: kittens),
            model: model,
            runtimeMode: settings.quickMode,
            projectID: projectID
        )
        var outcome: ReplyHoldback.Outcome?
        if let current { outcome = await routerTurn(backend.followUp(threadID: current, prompt)) }
        // The old thread might have gone, so it starts fresh.
        let isFresh = outcome == nil
        if outcome == nil {
            messagesQuick.reset()
            outcome = await routerTurn(backend.start(prompt))
        }
        guard let outcome, let threadID = messagesQuick.thread(at: now()) else {
            catSays(CatWords.noReply)
            return
        }
        switch outcome {
        case .answer(let text), .rewrite(let text):
            catSays(text.isEmpty ? CatWords.noReply : text)
            Task { [backend] in try? await backend.settle(threadID: threadID) }
            return
        case .handoff(let task):
            handOff(task: task, question: words, snapshot: nil, asked: asked) { [weak self] started in
                if let started { self?.messagesThreads[started] = sentAt }
            }
        case .route(let session):
            guard sessions.indices.contains(session - 1) else { return catSays(CatWords.lostTheSession) }
            let thread = sessions[session - 1]
            // From the first time, so what it said before stays in Everyone too.
            if KittenBoard.owner(of: thread, among: owners) == nil { messagesThreads[thread.id] = messagesThreads[thread.id] ?? sentAt }
            forward(words, to: thread, snapshot: nil, asked: asked)
        case .kitten(let number):
            guard kittens.indices.contains(number - 1) else { return catSays(CatWords.lostTheSession) }
            give(words, to: kittens[number - 1], snapshot: nil, asked: asked)
        }
        // A new thread that only passed something on has nothing worth keeping.
        if isFresh {
            messagesQuick.reset()
            Task { [backend] in try? await backend.archive(threadID: threadID) }
        } else {
            Task { [backend] in try? await backend.settle(threadID: threadID) }
        }
    }

    /// `nil` if the turn didn't work out.
    private func routerTurn(_ stream: AsyncThrowingStream<AgentReplyEvent, Error>) async -> ReplyHoldback.Outcome? {
        var holdback = ReplyHoldback()
        var fullText: String?
        do {
            for try await event in stream {
                switch event {
                case .started(let threadID):
                    messagesQuick.use(threadID, at: now())
                    watch.markQuick(threadID)
                case .text(let delta):
                    _ = holdback.add(delta)
                case .needsApproval(let request):
                    addApproval(request)
                case .finished(let text):
                    fullText = text
                case .failed:
                    return nil
                }
            }
        } catch {
            return nil
        }
        return holdback.finish(fullText: fullText)
    }

    /// The router's own words, in the group chat, or over the cat if you've closed Messages since.
    private func catSays(_ text: String) {
        guard channels.isOpen else { return post(caption: CatWords.everyone, text: text, threadID: nil) }
        channels.sent(ChannelMessage(exchangeID: "cat-\(UUID().uuidString)", kind: .reply, speaker: .cat, text: text, at: now(), threadID: "", threadTitle: ""), in: .everyone)
    }

    func answer(_ question: AgentQuestion, with answers: [String]) {
        answeredQuestions.insert(question.id)
        channels.refresh()
        Task { [backend] in
            do {
                try await backend.answer(question, with: answers)
            } catch {
                answeredQuestions.remove(question.id)
                channels.refresh()
                say(CatWords.approvalFailed)
            }
        }
    }
}
