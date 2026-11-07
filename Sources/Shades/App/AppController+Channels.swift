import Foundation
import ShadesCore

/// What Messages can ask for. Nothing in it can say anything for you: sending takes words you typed.
enum MessagesAction: Equatable {
    /// `alsoSent` is a thread's "Also send to #channel", which shows your reply in `shownIn` as well.
    case send(String, to: MessageTarget, shownIn: ChannelID?, alsoSent: Bool = false)
    /// A new thread in the kitten's folder. `id` is what Messages calls it until T3 has its thread.
    case startTopic(String, with: Kitten, id: String)
    case approval(ApprovalRequest, ApprovalDecision)
    /// Every part of a question's answer, in order.
    case answer(AgentQuestion, [String])
    case inbox(InboxAction)
    case seen(ChannelSelection)
}

/// Messages, laid out like Slack: Activity, your threads, #general, a channel for each kitten and a DM with the cat. Each
/// T3 session is a thread. Opening it captures nothing, and nothing typed in it takes your screen, since you're
/// looking at Messages and not your work.
extension AppController {
    /// Opens it, at `selection` if it's given. Looking at it covers whatever the cat was nudging you about.
    func channelsPressed(selecting selection: ChannelSelection? = nil) {
        inboxNudge = false
        // Shown Activity, you've seen what came in while it was open, so closing it has nothing new to say.
        if selection == .activity { nudgeOnClose = false }
        stage.showChannels(channels.open(threads: latestThreads), selecting: selection)
        renderBubble()
    }

    /// The hotkey opens it from anywhere, and closes it if it's already open.
    func messagesHotkeyPressed() {
        if stage.isChannelsVisible {
            stage.hideChannels()
        } else {
            channelsPressed()
        }
    }

    /// Only the Ask box and Messages start threads in the router's folder, so each one there is a talk with the cat.
    func isWithShades(_ thread: AgentThread) -> Bool {
        if knownRouterFolder == nil { knownRouterFolder = routerFolder().map(Self.standardized) }
        guard let folder = knownRouterFolder, let path = thread.projectPath else { return false }
        return Self.standardized(path) == folder
    }

    private static func standardized(_ path: String) -> String {
        URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
    }

    func channelsClosed() {
        // A phone that's looking keeps it reading. Once it stops too, what's been read waits for the next look.
        if phone?.isHolding != true { channels.close() }
        messagesClosings += 1
        guard nudgeOnClose else { return }
        nudgeOnClose = false
        // Only if something's still there to say. Otherwise a note later on would bring it up, which notes don't.
        guard !CatWords.inboxHeadline(inboxEntries).isEmpty else { return }
        inboxNudge = true
        renderBubble()
    }

    /// From the live list, the one place that has the words of approvals and questions.
    var waiting: Waiting {
        let owners = KittenBoard.Owners(loadKittens())
        var waiting = Waiting(approvals: approvals.pending, reports: inbox.entries)
        // What used to be the dashboard: work the cat started outside any kitten, while it's going or just finished.
        waiting.shadesWork = watch.rows(at: now()).filter { !hiddenThreads.contains($0.id) && owners.of($0) == nil }
        for thread in latestThreads where !hiddenThreads.contains(thread.id) {
            let owner = owners.of(thread)?.id
            for request in thread.pendingApprovals {
                waiting.owners[request.id] = owner
                waiting.listed[request.id] = thread.id
            }
            if let question = thread.pendingQuestion, !answeredQuestions.contains(question.id) {
                waiting.questions.append(question)
                waiting.owners[question.id] = owner
                waiting.listed[question.id] = thread.id
            }
        }
        return waiting
    }

    func messagesAction(_ action: MessagesAction) {
        switch action {
        case .send(let words, let target, let channel, let alsoSent):
            send(words, to: target, shownIn: channel, alsoSent: alsoSent)
        case .startTopic(let words, let kitten, let id):
            send(words, to: .newThread(kitten), shownIn: .of(kitten), echoID: id)
        case .approval(let request, let decision):
            answer(request, decision)
        case .answer(let question, let answers):
            answer(question, with: answers)
        case .inbox(let action):
            inboxAction(action)
        case .seen(let selection):
            channels.lookingAt = selection
            if inbox.markRead(channels.threads(in: selection)) {
                keepInbox()
                channels.refresh()
            }
        }
    }

    /// Each way of sending passes on your words and nothing else: no screen, and nothing anyone else said. What's shown
    /// meanwhile, and a reply also sent to a channel, is kept in memory only.
    func send(_ words: String, to target: MessageTarget, shownIn channel: ChannelID?, alsoSent: Bool = false, echoID: String = "sent-\(UUID().uuidString)") {
        func echo(threadID: String = "", title: String = "", startsThread: Bool = false) {
            guard let channel else { return }
            let message = ChannelMessage(exchangeID: echoID, kind: .ask, speaker: .you, text: words, at: now(), threadID: threadID, threadTitle: title)
            channels.sent(message, in: channel, startsThread: startsThread, alsoSent: alsoSent && !threadID.isEmpty)
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
                await route(words, sentAt: sentAt, asked: asked, answeringIn: channel ?? .general, echoID: echoID)
            }
        case .newThread(let kitten):
            echo(startsThread: true)
            // The box waits for the new thread, so what you add next goes there too.
            let title = String(words.prefix { !$0.isNewline }.prefix(60))
            give(words, to: kitten, snapshot: nil) { [weak self] threadID in
                self?.channels.started(echoID, in: threadID, title: title)
            }
        case .thread(let id, let title, let report):
            echo(threadID: id, title: title)
            reply(words, toThread: id, title: title, marking: report)
        case .starting:
            break
        case .question(let question):
            answer(question, with: [words])
        }
    }

    /// The same prompt and model as the Ask box, on Messages' own conversation with the router, so nothing from
    /// your screen is in what it can see, and asking the cat meanwhile can't cut it short. #general and the cat's DM
    /// share that conversation, and the cat answers in whichever you wrote in. `echoID` is what Messages shows of your
    /// words meanwhile, which goes with them into whatever thread they start or land in.
    private func route(_ words: String, sentAt: Date, asked: Int, answeringIn place: ChannelID, echoID: String) async {
        var talk: String?
        // In #general, whoever takes your words answers in their thread. The DM only has the cat, so it says where
        // they went, in the words it uses for the same thing once T3 has the thread.
        func passedOn(_ what: String) {
            if place == .shades { catSays(what, in: place, thread: talk) }
        }
        // A new session lives in #general under your words, wherever it's passed after that.
        let startedHere = { [weak self] (started: String?) in
            guard let self, let started else { return }
            self.messagesThreads[started] = self.messagesThreads[started] ?? sentAt
            if place == .general {
                self.channels.started(echoID, in: started)
            } else {
                let parent = ChannelMessage(exchangeID: "general-\(echoID)", kind: .ask, speaker: .you, text: words, at: sentAt, threadID: started, threadTitle: "")
                self.channels.sent(parent, in: .general)
            }
        }
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
            return catSays(CatWords.problem(error, while: .agents), in: place)
        }
        let prompt = AgentPrompt(
            title: String(words.prefix { !$0.isNewline }.prefix(60)),
            text: Prompts.quick(question: words, snapshot: nil, sessions: briefs, kittens: kittens, notSetUp: owners.filter(\.planned)),
            model: model,
            runtimeMode: settings.quickMode,
            projectID: projectID
        )
        var turn: (reading: ReplyHoldback.Reading, threadID: String)?
        if let current { turn = await routerTurn(backend.followUp(threadID: current, prompt)) }
        // The old thread might have gone, so it starts fresh.
        let isFresh = turn == nil
        if turn == nil {
            messagesQuick.reset()
            turn = await routerTurn(backend.start(prompt))
        }
        guard let (reading, threadID) = turn else {
            catSays(CatWords.noReply, in: place)
            return
        }
        // In the DM, what you said is part of the talk, and keeps showing there as a reply also sent to it.
        if place == .shades {
            talk = threadID
            channels.started(echoID, in: threadID, alsoSent: true)
        }
        // As in the Ask box: a correction reaches its owner, in a copy of its own if your words go somewhere else.
        let corrected = reading.corrections.compactMap { kittens.indices.contains($0 - 1) ? kittens[$0 - 1] : nil }
        if corrected.count < reading.corrections.count { catSays(CatWords.lostTheCorrection, in: place) }
        var copies = corrected
        defer { copies.forEach { give(words, to: $0, snapshot: nil, as: .correctionCopy) } }
        switch reading.outcome {
        // There's nothing selected in Messages to replace, so a rewrite is only an answer here.
        case .answer(let text, _) where !text.isEmpty || reading.corrections.isEmpty, .rewrite(let text):
            catSays(text.isEmpty ? CatWords.noReply : text, in: place, thread: talk)
            Task { [backend] in try? await backend.settle(threadID: threadID) }
            return
        case .answer:
            if reading.wentNowhere {
                // The rest was meant for somewhere else, so the owner only gets its copy.
                catSays(CatWords.lostTheSession, in: place)
            } else if corrected.count == 1 {
                give(words, to: corrected[0], snapshot: nil, as: .correction, asked: asked, onStarted: startedHere)
                copies = []
            }
            if !reading.wentNowhere, !corrected.isEmpty { passedOn(CatWords.passedOnCorrection) }
        case .handoff(let task):
            handOff(task: task, question: words, snapshot: nil, asked: asked, onStarted: startedHere)
            passedOn(CatWords.handedOff(task))
        case .route(let session):
            guard sessions.indices.contains(session - 1) else { return catSays(CatWords.lostTheSession, in: place) }
            let thread = sessions[session - 1]
            // From the first time, so what it said before stays in #general too.
            if KittenBoard.owner(of: thread, among: owners) == nil { messagesThreads[thread.id] = messagesThreads[thread.id] ?? sentAt }
            // A reply in that thread, also sent to #general, as Slack's "Also send to #general" does.
            if place == .general { channels.started(echoID, in: thread.id, title: thread.title, alsoSent: true) }
            let home = corrected.first { KittenBoard.isInFolder(thread.projectPath, of: $0) }
            forward(words, to: thread, snapshot: nil, correction: home != nil, asked: asked)
            copies.removeAll { $0 == home }
            passedOn(CatWords.passedOnToSession)
        case .kitten(let number):
            guard kittens.indices.contains(number - 1) else { return catSays(CatWords.lostTheSession, in: place) }
            let kitten = kittens[number - 1]
            give(words, to: kitten, snapshot: nil, as: corrected.contains(kitten) ? .correction : .work, asked: asked, onStarted: startedHere)
            copies.removeAll { $0 == kitten }
            passedOn(CatWords.passedOnToKitten)
        }
        // A new thread that only passed something on has nothing worth keeping.
        if isFresh {
            messagesQuick.reset()
            Task { [backend] in try? await backend.archive(threadID: threadID) }
        } else {
            Task { [backend] in try? await backend.settle(threadID: threadID) }
        }
    }

    /// `nil` if the turn didn't work out. The thread is the one it ran in, since a turn that waited on an approval
    /// can outlast the conversation, and its reply still counts.
    private func routerTurn(_ stream: AsyncThrowingStream<AgentReplyEvent, Error>) async -> (reading: ReplyHoldback.Reading, threadID: String)? {
        var holdback = ReplyHoldback()
        var fullText: String?
        var thread: String?
        do {
            for try await event in stream {
                switch event {
                case .started(let threadID):
                    thread = threadID
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
            // A reply that had finished is what it said, whatever broke after it.
            if fullText == nil { return nil }
        }
        guard let thread else { return nil }
        return (holdback.read(fullText: fullText), thread)
    }

    /// The router's own words, where you wrote, or over the cat if you've closed Messages since. In the DM they're a
    /// reply in the talk, also sent to the DM, and in #general a message of their own.
    private func catSays(_ text: String, in place: ChannelID, thread: String? = nil) {
        guard channels.isOpen else { return post(caption: place == .shades ? CatWords.shades : "#\(CatWords.general)", text: text, threadID: nil) }
        let message = ChannelMessage(exchangeID: "cat-\(UUID().uuidString)", kind: .reply, speaker: .cat, text: text, at: now(), threadID: thread ?? "", threadTitle: "")
        channels.sent(message, in: place, alsoSent: thread != nil)
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
