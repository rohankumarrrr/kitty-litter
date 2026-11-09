import Foundation
import ShadesContext
import ShadesCore

/// What Messages can ask for. Nothing in it can say anything for you: sending takes words you typed, and a file only
/// goes with them if you attached it.
enum MessagesAction: Equatable {
    /// `alsoSent` is a thread's "Also send to #channel", which shows your reply in `shownIn` as well.
    case send(String, to: MessageTarget, shownIn: ChannelID?, alsoSent: Bool = false, file: Drop? = nil)
    /// A new thread in the kitten's folder. `id` is what Messages calls it until T3 has its thread.
    case startTopic(String, with: Kitten, id: String, file: Drop? = nil)
    case approval(ApprovalRequest, ApprovalDecision)
    /// Every part of a question's answer, in order: the options picked, or your own words alone.
    case answer(AgentQuestion, [[String]])
    case inbox(InboxAction)
    /// `keepingUnread` are threads you marked unread while looking, which stay that way until you move on.
    case seen(ChannelSelection, keepingUnread: Set<String> = [])
    /// That message in that thread, and everything after it, is new to you again, to come back to.
    case markUnread(String, from: String)
    /// Words you sent that went nowhere, by their exchange ID, sent again as they were.
    case tryAgain(String)
    case doNotDisturb
    /// You've scrolled back past the top of a channel.
    case older(ChannelID)
    /// What a channel tells you, from its header.
    case notifications(ChannelID, ChannelNotifications)
    /// Puts a reaction on a message, by its `ChannelMessage.id`, or takes it off. It's a mark kept on your Mac, and
    /// tells no agent anything.
    case react(String, Reaction)
}

/// Messages, laid out like Slack: Activity, your threads, #general, a channel for each kitten and a DM with the cat. Each
/// T3 session is a thread. Opening it captures nothing, and nothing typed in it takes your screen, since you're
/// looking at Messages and not your work.
extension AppController {
    /// Opens it, at `selection` if it's given. Looking at it covers whatever the cat was nudging you about.
    func channelsPressed(selecting selection: ChannelSelection? = nil) {
        inboxNudge = false
        catchingUp = false
        // Shown Activity, you've seen what came in while it was open, so closing it has nothing new to say.
        if selection == .activity { nudgeOnClose = false }
        stage.showChannels(channels.open(threads: latestThreads), selecting: selection)
        renderBubble()
    }

    /// Where Messages shows a thread, if it does: #general, its kitten's channel or the cat's DM. It's worked out from
    /// the live list, so the bubble can offer it before Messages has read a word.
    func messagesHome(ofThread id: String) -> ChannelID? {
        if messagesThreads[id] != nil { return .general }
        guard let thread = latestThreads.first(where: { $0.id == id }) else { return nil }
        if isWithShades(thread) { return thread.isLiveTest ? nil : .shades }
        if let kitten = KittenBoard.owner(of: thread, among: loadKittens()) { return .of(kitten) }
        return isCatsWork(thread) ? .shades : nil
    }

    /// The bubble's Open: the thread beside where it lives, and the bubble's done with it. T3 is only for a thread
    /// Messages doesn't show.
    func showInMessages(_ threadID: String) {
        guard let home = messagesHome(ofThread: threadID) else { return backend.open(threadID: threadID) }
        if notices.first?.threadID == threadID, notices.first?.questionID == nil { notices.removeFirst() }
        if line?.threadID == threadID { line = nil }
        channelsPressed(selecting: .thread(threadID, in: .channel(home)))
    }

    /// The hotkey brings it in front of you from anywhere, and closes it if it's already there. Open isn't enough,
    /// since it can be behind your work, and closing it then would take a second press to see it.
    func messagesHotkeyPressed() {
        if stage.isChannelsInFront {
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

    /// Work the cat started for you outside Messages, which lives in its DM. A fix from before Shades kept these is
    /// known by the title it gave it, in T3's own folder for work with no project.
    func isCatsWork(_ thread: AgentThread) -> Bool {
        Self.isCatsWork(thread, kept: catsWork)
    }

    static func isCatsWork(_ thread: AgentThread, kept: [String: Date]) -> Bool {
        kept[thread.id] != nil || (thread.projectPath == nil && thread.title.hasPrefix(fixTitle))
    }

    func channelsClosed() {
        // A phone that's looking keeps it reading. Once it stops too, what's been read waits for the next look.
        if phone?.isHolding != true { channels.close() }
        messagesClosings += 1
        if awaySeen {
            awaySeen = false
            away = []
        }
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
        var waiting = Waiting(approvals: approvals.pending, reports: inbox.entries, away: away, doNotDisturb: settings.doNotDisturb)
        waiting.notifications = settings.channelNotifications
        waiting.phone = settings.phone
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
        case .send(let words, let target, let channel, let alsoSent, let file):
            // An @kitten in #general goes straight to that kitten, rather than the router choosing.
            let named = target == .router && channel == .general ? MessageTarget.mentioned(in: words, among: loadKittens().filter { !$0.planned }) : nil
            send(words, to: named.map(MessageTarget.newThread) ?? target, shownIn: channel, alsoSent: alsoSent, file: file)
        case .startTopic(let words, let kitten, let id, let file):
            send(words, to: .newThread(kitten), shownIn: .of(kitten), echoID: id, file: file)
        case .approval(let request, let decision):
            answer(request, decision)
        case .answer(let question, let answers):
            answer(question, with: answers)
        case .inbox(let action):
            inboxAction(action)
        case .doNotDisturb:
            doNotDisturbPressed()
        case .seen(let selection, let kept):
            if selection.place == .activity, !away.isEmpty { awaySeen = true }
            channels.lookingAt = selection
            let seen = channels.threads(in: selection).filter { !kept.contains($0.id) }
            // A reply still being written, or words on their way, haven't been seen as they'll be.
            let last = { [channels] in channels.messages(in: $0).last { !$0.isStillGoing && !$0.isSending }?.id }
            if inbox.markRead(seen, upTo: last) {
                keepInbox()
                channels.refresh()
            }
        case .markUnread(let thread, let message):
            inbox.markUnread(thread, from: message, of: channels.messages(in: thread).map(\.id))
            keepInbox()
            channels.refresh()
        case .tryAgain(let id):
            guard let sent = channels.toTryAgain(id), let words = sent.message.text, let target = sent.target else { return }
            send(words, to: target, shownIn: sent.channel, alsoSent: sent.alsoSent, echoID: id)
        case .older(let channel):
            channels.older(in: channel)
        case .notifications(let channel, let notifications):
            setNotifications(notifications, for: channel)
        case .react(let message, let reaction):
            inbox.react(reaction, to: message, at: now())
            keepInbox()
            channels.refresh()
        }
    }

    /// A reply also sent to a channel is only words while T3 doesn't have it, so it's kept once T3 does, as the ID of
    /// T3's copy, and read back from its thread after a restart.
    func keepAlsoSent(_ heard: [String: ChannelBook.HeardAlsoSent]) {
        let new = heard.filter { inbox.alsoSent[$0.key] == nil && inbox.alsoSentToGeneral[$0.key] == nil }
        guard !new.isEmpty else { return }
        for (id, line) in new {
            if line.channel == .general {
                inbox.alsoSentToGeneral[id] = Inbox.ShownInGeneral(thread: line.thread, at: now())
            } else {
                inbox.alsoSent[id] = now()
            }
        }
        keepInbox()
    }

    /// Each way of sending passes on your words and nothing else: no screen, and nothing anyone else said. What's shown
    /// meanwhile is kept in memory only, and a reply also sent to a channel is too until T3 has it. A file you attached
    /// goes the way one dropped onto the cat does, only where your screen may, and where it can't, nothing goes and
    /// Messages says why.
    func send(_ words: String, to target: MessageTarget, shownIn channel: ChannelID?, alsoSent: Bool = false, echoID: String = "sent-\(UUID().uuidString)", file: Drop? = nil) {
        guard let file else { return send(words, to: target, shownIn: channel, alsoSent: alsoSent, echoID: echoID, snapshot: nil) }
        let words = words.isEmpty ? CatWords.summarize : words
        let shown = ChannelFile(name: file.name, thumbnail: file.thumbnail())
        // It's read off the main thread, since a long PDF takes a moment.
        attachTask = Task {
            let snapshot = await Task.detached { file.snapshot() }.value
            guard let snapshot else {
                showSent(words, echoID: echoID, file: shown, to: target, in: channel)
                return channels.failed(echoID, because: CatWords.cantReadThat)
            }
            send(words, to: target, shownIn: channel, alsoSent: alsoSent, echoID: echoID, snapshot: snapshot, file: shown)
        }
    }

    /// A file that couldn't be read still shows where you sent it, with why it went nowhere.
    private func showSent(_ words: String, echoID: String, file: ChannelFile, to target: MessageTarget, in channel: ChannelID?) {
        guard let channel else { return }
        var threadID = ""
        if case .thread(let id, _, _) = target { threadID = id }
        let message = ChannelMessage(exchangeID: echoID, kind: .ask, speaker: .you, text: words, at: now(), threadID: threadID, threadTitle: "", file: file)
        channels.sent(message, in: channel, startsThread: { if case .newThread = target { true } else { false } }(), isReply: !threadID.isEmpty)
    }

    private func send(_ words: String, to target: MessageTarget, shownIn channel: ChannelID?, alsoSent: Bool, echoID: String, snapshot: ScreenSnapshot?, file: ChannelFile? = nil) {
        func echo(threadID: String = "", title: String = "", startsThread: Bool = false, isReply: Bool = false) {
            guard let channel else { return }
            let message = ChannelMessage(exchangeID: echoID, kind: .ask, speaker: .you, text: words, at: now(), threadID: threadID, threadTitle: title, file: file, isSending: true)
            channels.sent(message, in: channel, startsThread: startsThread, alsoSent: alsoSent && !threadID.isEmpty, isReply: isReply, target: target)
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
                await route(words, sentAt: sentAt, asked: asked, answeringIn: channel ?? .general, echoID: echoID, file: snapshot)
            }
        case .newThread(let kitten):
            echo(startsThread: true)
            // The box waits for the new thread, so what you add next goes there too.
            let title = String(words.prefix { !$0.isNewline }.prefix(60))
            let sentAt = now()
            give(words, to: kitten, snapshot: snapshot) { [weak self] threadID in
                // Named with an @ in #general, it lives there, as everything started from there does.
                if channel == .general, let threadID, let self { self.messagesThreads[threadID] = self.messagesThreads[threadID] ?? sentAt }
                self?.channels.started(echoID, in: threadID, title: title)
            }
        case .thread(let id, let title, let report):
            echo(threadID: id, title: title, isReply: true)
            guard let snapshot else { return reply(words, toThread: id, title: title, marking: report, echoID: echoID) }
            // The same as carrying on in a thread from the Ask box, which only takes what you dropped where your screen may go.
            guard let thread = latestThreads.first(where: { $0.id == id }) ?? channels.listed(id) else {
                return channels.failed(echoID, because: CatWords.cantTakeFiles(title))
            }
            forward(words, to: thread, snapshot: snapshot) { [weak self] in
                self?.channels.failed(echoID, because: CatWords.cantTakeFiles(title))
            } unheard: { [weak self] in
                self?.channels.failed(echoID, because: $0)
            }
        case .starting:
            break
        case .question(let question):
            guard snapshot == nil else { return channels.failed(echoID, because: CatWords.answersTakeNoFiles) }
            answer(question, with: [[words]])
        }
    }

    /// The same prompt and model as the Ask box, on Messages' own conversation with the router, so nothing from
    /// your screen is in what it can see, and asking the cat meanwhile can't cut it short. #general and the cat's DM
    /// share that conversation, and the cat answers in whichever you wrote in. `echoID` is what Messages shows of your
    /// words meanwhile, which goes with them into whatever thread they start or land in.
    /// A file goes on a router thread of its own, so Messages' conversation with it never holds one.
    private func route(_ words: String, sentAt: Date, asked: Int, answeringIn place: ChannelID, echoID: String, file: ScreenSnapshot? = nil) async {
        var talk: String?
        // In #general, whoever takes your words answers in their thread. The DM only has the cat, so it says where
        // they went, in the words it uses for the same thing once T3 has the thread.
        func passedOn(_ what: String) {
            if place == .shades { catSays(what, in: place, thread: talk) }
        }
        // Your words say why under them, where they can go again, and the cat says it too if Messages has closed since.
        func notSent(_ why: String) {
            channels.failed(echoID, because: why)
            if !channels.isOpen { catSays(why, in: place) }
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
        let current = file == nil ? messagesQuick.thread(at: now()) : nil
        // Only Messages' own world: the kittens' threads, and work it passed your words to. Anything the Ask box
        // started can hold your screen, and that has to hold after a restart too.
        let owners = loadKittens()
        let sessions = rosterThreads(excluding: current) { [messagesThreads] thread in
            messagesThreads[thread.id] != nil || KittenBoard.owner(of: thread, among: owners) != nil
        }
        let briefs = await briefs(for: sessions)
        let kittens = owners.filter { !$0.planned }
        let model = settings.quickModel
        // As in the Ask box, a router with full access doesn't get what you dropped.
        if file != nil, settings.quickMode == .fullAccess {
            return channels.failed(echoID, because: CatWords.cantTakeFiles(ModelNames.friendly(model)))
        }
        let projectID: String
        do {
            projectID = try await routerProjectID(for: model)
        } catch {
            notSent(CatWords.problem(error, while: .agents))
            return
        }
        let prompt = AgentPrompt(
            title: String(words.prefix { !$0.isNewline }.prefix(60)),
            text: Prompts.quick(question: words, snapshot: file, sessions: briefs, kittens: kittens, notSetUp: owners.filter(\.planned)),
            attachments: attachments(for: file),
            model: model,
            runtimeMode: settings.quickMode,
            projectID: projectID
        )
        var turn: (reading: ReplyHoldback.Reading, threadID: String)?
        if let current { turn = await routerTurn(backend.followUp(threadID: current, prompt), echoID: echoID) }
        // The old thread might have gone, so it starts fresh.
        let isFresh = turn == nil
        if turn == nil {
            if file == nil { messagesQuick.reset() }
            turn = await routerTurn(backend.start(prompt), joins: file == nil, echoID: echoID)
        }
        guard let (reading, threadID) = turn else {
            notSent(CatWords.noReply)
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
            let answer = catSays(text.isEmpty ? CatWords.noReply : text, in: place, thread: talk)
            if place == .general, !text.isEmpty { await keepInGeneral(answerIn: threadID, shownAs: [echoID, answer]) }
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
            handOff(task: task, question: words, snapshot: file, asked: asked, onStarted: startedHere)
            passedOn(CatWords.handedOff(task))
        case .route(let session):
            guard sessions.indices.contains(session - 1) else {
                catSays(CatWords.lostTheSession, in: place)
                return
            }
            let thread = sessions[session - 1]
            // From the first time, so what it said before stays in #general too.
            if KittenBoard.owner(of: thread, among: owners) == nil { messagesThreads[thread.id] = messagesThreads[thread.id] ?? sentAt }
            // A reply in that thread, also sent to #general, as Slack's "Also send to #general" does.
            if place == .general { channels.started(echoID, in: thread.id, title: thread.title, alsoSent: true) }
            let home = corrected.first { KittenBoard.isInFolder(thread.projectPath, of: $0) }
            forward(words, to: thread, snapshot: file, correction: home != nil, asked: asked) { [weak self] in
                self?.channels.failed(echoID, because: CatWords.cantTakeFiles(thread.title))
            } unheard: { [weak self] in
                self?.channels.failed(echoID, because: $0)
            }
            copies.removeAll { $0 == home }
            passedOn(CatWords.passedOnToSession)
        case .kitten(let number):
            guard kittens.indices.contains(number - 1) else {
                catSays(CatWords.lostTheSession, in: place)
                return
            }
            let kitten = kittens[number - 1]
            give(words, to: kitten, snapshot: file, as: corrected.contains(kitten) ? .correction : .work, asked: asked, onStarted: startedHere)
            copies.removeAll { $0 == kitten }
            passedOn(CatWords.passedOnToKitten)
        }
        // A new thread that only passed something on has nothing worth keeping.
        if isFresh {
            if file == nil { messagesQuick.reset() }
            Task { [backend] in try? await backend.archive(threadID: threadID) }
        } else {
            Task { [backend] in try? await backend.settle(threadID: threadID) }
        }
    }

    /// `nil` if the turn didn't work out. The thread is the one it ran in, since a turn that waited on an approval
    /// can outlast the conversation, and its reply still counts.
    /// `joins` makes it Messages' conversation with the router, which a turn carrying a file never does. Your words,
    /// shown as `echoID`, count as delivered once the turn starts, since the cat has them while it thinks.
    private func routerTurn(_ stream: AsyncThrowingStream<AgentReplyEvent, Error>, joins: Bool = true, echoID: String) async -> (reading: ReplyHoldback.Reading, threadID: String)? {
        var holdback = ReplyHoldback()
        var fullText: String?
        var thread: String?
        do {
            for try await event in stream {
                switch event {
                case .started(let threadID):
                    thread = threadID
                    if joins { messagesQuick.use(threadID, at: now()) }
                    watch.markQuick(threadID)
                    channels.delivered(echoID)
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
    /// reply in the talk, also sent to the DM, and in #general a message of their own. Returns what Messages calls it.
    @discardableResult
    private func catSays(_ text: String, in place: ChannelID, thread: String? = nil) -> String {
        let id = "cat-\(UUID().uuidString)"
        guard channels.isOpen else {
            post(caption: place == .shades ? CatWords.shades : "#\(CatWords.general)", text: text, threadID: nil)
            return id
        }
        let message = ChannelMessage(exchangeID: id, kind: .reply, speaker: .cat, text: text, at: now(), threadID: thread ?? "", threadTitle: "")
        channels.sent(message, in: place, alsoSent: thread != nil)
        return id
    }

    /// The cat's answer in #general is a turn of Messages' talk with the router, which T3 keeps, so only which turn
    /// it was is saved, and #general reads it back from there after a restart. Turns go one at a time, so the latest
    /// one you asked is this one.
    private func keepInGeneral(answerIn threadID: String, shownAs sent: [String]) async {
        guard let turn = await backend.exchanges(threadID: threadID)?.last(where: { $0.asker == .you }) else { return }
        inbox.answersInGeneral[turn.id] = now()
        keepInbox()
        channels.heard(sent, as: turn.id)
    }

    func answer(_ question: AgentQuestion, with answers: [[String]]) {
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
