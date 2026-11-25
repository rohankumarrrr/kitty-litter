import Foundation
import ShadesContext
import ShadesCore

enum MessagesAction: Equatable {
    case send(String, to: MessageTarget, shownIn: ChannelID?, alsoSent: Bool = false, files: [Drop] = [], alternate: Bool = false)
    case startTopic(String, with: Kitten, id: String, files: [Drop] = [])
    case approval(ApprovalRequest, ApprovalDecision)
    case ignore(ApprovalRequest)
    case answer(AgentQuestion, [[String]])
    case inbox(InboxAction)
    case seen(ChannelSelection, keepingUnread: Set<String> = [])
    case markUnread(String, from: String)
    case markRead([String])
    case tryAgain(String)
    case doNotDisturb
    case older(ChannelID)
    case notifications(ChannelID, ChannelNotifications)
    case react(String, Reaction)
    case find(String)
    case showPicture(URL)
}

extension AppController {
    func channelsPressed(selecting selection: ChannelSelection? = nil) {
        inboxNudge = false
        catchingUp = false
        if selection == .activity { nudgeOnClose = false }
        stage.showChannels(channels.open(threads: latestThreads), selecting: selection)
        renderBubble()
    }

    func messagesHome(ofThread id: String) -> ChannelID? {
        guard let thread = latestThreads.first(where: { $0.id == id }) else { return messagesThreads[id] != nil ? .shades : nil }
        if isWithShades(thread) { return thread.isLiveTest ? nil : .shades }
        if let kitten = KittenBoard.owner(of: thread, among: loadKittens()) { return .of(kitten) }
        return isCatsWork(thread) || messagesThreads[id] != nil ? .shades : nil
    }

    func opensInMessages(_ threadID: String) -> Bool {
        settings.openInMessages && messagesHome(ofThread: threadID) != nil
    }

    func showInMessages(_ threadID: String) {
        guard settings.openInMessages, let home = messagesHome(ofThread: threadID) else { return openThread(threadID) }
        if notices.first?.threadID == threadID, notices.first?.questionID == nil { notices.removeFirst() }
        if line?.threadID == threadID { line = nil }
        channelsPressed(selecting: .thread(threadID, in: .channel(home)))
    }

    func messagesHotkeyPressed() {
        if stage.isChannelsInFront {
            stage.hideChannels()
        } else {
            channelsPressed()
        }
    }

    func isWithShades(_ thread: AgentThread) -> Bool {
        inRouterFolder(thread) && !thread.title.hasPrefix(Self.reviewTitle)
    }

    func inRouterFolder(_ thread: AgentThread) -> Bool {
        guard let path = thread.projectPath else { return false }
        if let known = inRouterFolderByPath[path] { return known }
        if knownRouterFolder == nil { knownRouterFolder = routerFolder().map(Self.standardized) }
        guard let folder = knownRouterFolder else { return false }
        let inside = Self.standardized(path) == folder
        inRouterFolderByPath[path] = inside
        return inside
    }

    private static func standardized(_ path: String) -> String {
        URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
    }

    func isCatsWork(_ thread: AgentThread) -> Bool {
        Self.isCatsWork(thread, kept: catsWork)
    }

    static func isCatsWork(_ thread: AgentThread, kept: [String: Date]) -> Bool {
        kept[thread.id] != nil || (thread.projectPath == nil && thread.title.hasPrefix(fixTitle))
    }

    func channelsClosed() {
        if phone?.isHolding != true { channels.close() }
        messagesClosings += 1
        if listeningBox == .messages { cancelListening() }
        if awaySeen {
            awaySeen = false
            away = []
        }
        guard nudgeOnClose else { return }
        nudgeOnClose = false
        guard CatWords.inboxSummary(inboxEntries) != nil else { return }
        inboxNudge = true
        renderBubble()
    }

    var waiting: Waiting {
        let owners = KittenBoard.Owners(loadKittens())
        var waiting = Waiting(approvals: approvals.pending, reports: inbox.entries, away: away, doNotDisturb: settings.doNotDisturb)
        waiting.notifications = settings.channelNotifications
        waiting.phone = settings.phone
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
        case .send(let words, let target, let channel, let alsoSent, let files, let alternate):
            send(words, to: target, shownIn: channel, alsoSent: alsoSent, files: files, alternate: alternate)
        case .startTopic(let words, let kitten, let id, let files):
            send(words, to: .newThread(kitten), shownIn: .of(kitten), echoID: id, files: files)
        case .approval(let request, let decision):
            answer(request, decision)
        case .ignore(let request):
            ignore(request)
        case .answer(let question, let answers):
            answer(question, with: answers)
        case .inbox(let action):
            inboxAction(action)
        case .doNotDisturb:
            doNotDisturbPressed()
        case .seen(let selection, let kept):
            if selection.place == .activity, !away.isEmpty { awaySeen = true }
            channels.lookingAt = selection
            markRead(channels.threads(in: selection).filter { !kept.contains($0.id) })
        case .markRead(let threads):
            markRead(threads.compactMap(channels.listed))
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
        case .find(let words):
            channels.find(words)
        case .showPicture(let url):
            channels.pictures.show(url)
        }
    }

    private func markRead(_ threads: [AgentThread]) {
        let lastSaid = { [channels] in channels.messages(in: $0).last { !$0.isStillGoing && !$0.isSending }?.id }
        guard inbox.markRead(threads, upTo: lastSaid) else { return }
        keepInbox()
        channels.refresh()
    }

    func keepAlsoSent(_ heard: [String: ChannelBook.HeardAlsoSent]) {
        let new = heard.keys.filter { inbox.alsoSent[$0] == nil }
        guard !new.isEmpty else { return }
        for id in new { inbox.alsoSent[id] = now() }
        keepInbox()
    }

    func send(_ words: String, to target: MessageTarget, shownIn channel: ChannelID?, alsoSent: Bool = false, echoID: String = "sent-\(UUID().uuidString)", files: [Drop] = [], alternate: Bool = false) {
        guard !files.isEmpty else { return send(words, to: target, shownIn: channel, alsoSent: alsoSent, echoID: echoID, snapshot: nil, alternate: alternate) }
        let words = words.isEmpty ? CatWords.summarize : words
        let files = Array(files.prefix(Drop.mostAtOnce))
        let shown = files.map { ChannelFile(name: $0.name, thumbnail: $0.thumbnail()) }
        attachTask = Task {
            let snapshot = await Task.detached { Drop.snapshot(of: files) }.value
            guard let snapshot else {
                showSent(words, echoID: echoID, files: shown, to: target, in: channel)
                return channels.failed(echoID, because: CatWords.cantReadThat)
            }
            send(words, to: target, shownIn: channel, alsoSent: alsoSent, echoID: echoID, snapshot: snapshot, files: shown, alternate: alternate)
        }
    }

    private func showSent(_ words: String, echoID: String, files: [ChannelFile], to target: MessageTarget, in channel: ChannelID?) {
        guard let channel else { return }
        var threadID = ""
        if case .thread(let id, _, _) = target { threadID = id }
        let message = ChannelMessage(exchangeID: echoID, kind: .ask, speaker: .you, text: words, at: now(), threadID: threadID, threadTitle: "", files: files)
        channels.sent(message, in: channel, startsThread: { if case .newThread = target { true } else { false } }(), isReply: !threadID.isEmpty)
    }

    private func send(_ words: String, to target: MessageTarget, shownIn channel: ChannelID?, alsoSent: Bool, echoID: String, snapshot: ScreenSnapshot?, files: [ChannelFile] = [], alternate: Bool = false) {
        func echo(threadID: String = "", title: String = "", startsThread: Bool = false, isReply: Bool = false) {
            guard let channel else { return }
            let message = ChannelMessage(exchangeID: echoID, kind: .ask, speaker: .you, text: words, at: now(), threadID: threadID, threadTitle: title, files: files, isSending: true)
            channels.sent(message, in: channel, startsThread: startsThread, alsoSent: alsoSent && !threadID.isEmpty, isReply: isReply, target: target)
        }
        switch target {
        case .router where settings.lockdown != nil:
            echo()
            sendLockedDown(words, echoID: echoID, file: snapshot)
        case .router:
            echo()
            let previous = messagesTurn
            let sentAt = now()
            let asked = questionsAsked
            messagesTurn = Task {
                await previous?.value
                await route(words, sentAt: sentAt, asked: asked, echoID: echoID, file: snapshot)
            }
        case .newThread(let kitten):
            echo(startsThread: true)
            let title = String(words.prefix { !$0.isNewline }.prefix(60))
            give(words, to: kitten, snapshot: snapshot, youPicked: true, onStarted: { [weak self] threadID in
                self?.channels.started(echoID, in: threadID, title: title)
            }, refused: { [weak self] in
                self?.channels.failed(echoID, because: CatWords.cantTakeFiles(kitten.name))
            })
        case .thread(let id, let title, let report):
            echo(threadID: id, title: title, isReply: true)
            let behavior = alternate ? settings.followUpBehavior.other : settings.followUpBehavior
            guard let snapshot else { return reply(words, toThread: id, marking: report, echoID: echoID, behavior: behavior) }
            guard let thread = latestThreads.first(where: { $0.id == id }) ?? channels.listed(id) else {
                return channels.failed(echoID, because: CatWords.cantTakeFiles(title))
            }
            forward(words, to: thread, snapshot: snapshot, youPicked: true, behavior: behavior) { [weak self] in
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

    private func route(_ words: String, sentAt: Date, asked: Int, echoID: String, file: ScreenSnapshot? = nil) async {
        var talk: String?
        func passedOn(_ what: String) {
            catSays(what, thread: talk)
        }
        func notSent(_ why: String) {
            channels.failed(echoID, because: why)
            if !channels.isOpen { catSays(why) }
        }
        func started(in home: ChannelID) -> (String?) -> Void {
            { [weak self] started in
                guard let self, let started else { return }
                self.messagesThreads[started] = self.messagesThreads[started] ?? sentAt
                self.channels.sent(ChannelMessage(exchangeID: "started-\(echoID)", kind: .ask, speaker: .you, text: words, at: sentAt, threadID: started, threadTitle: ""), in: home)
            }
        }
        await waitForThreadList()
        let current = file == nil ? messagesQuick.thread(at: now()) : nil
        let owners = loadKittens()
        let sessions = rosterThreads(excluding: current) { [messagesThreads] thread in
            messagesThreads[thread.id] != nil || KittenBoard.owner(of: thread, among: owners) != nil
        }
        let briefs = await briefs(for: sessions)
        let kittens = owners.filter { !$0.planned }
        let model = settings.quickModel
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
        let isFresh = turn == nil
        if turn == nil {
            if file == nil { messagesQuick.reset() }
            turn = await routerTurn(backend.start(prompt), joins: file == nil, echoID: echoID)
        }
        guard let (reading, threadID) = turn else {
            notSent(CatWords.noReply)
            return
        }
        talk = threadID
        channels.started(echoID, in: threadID, alsoSent: true)
        let corrected = reading.corrections.compactMap { kittens.indices.contains($0 - 1) ? kittens[$0 - 1] : nil }
        if corrected.count < reading.corrections.count { catSays(CatWords.lostTheCorrection) }
        var copies = corrected
        defer { copies.forEach { give(words, to: $0, snapshot: nil, as: .correctionCopy) } }
        switch reading.outcome {
        case .answer(let text, _) where !text.isEmpty || reading.corrections.isEmpty, .rewrite(let text):
            catSays(text.isEmpty ? CatWords.noReply : text, thread: talk)
            Task { [backend] in try? await backend.settle(threadID: threadID) }
            return
        case .answer:
            if reading.wentNowhere {
                catSays(CatWords.lostTheSession)
            } else if corrected.count == 1 {
                give(words, to: corrected[0], snapshot: nil, as: .correction, asked: asked, onStarted: started(in: .of(corrected[0])))
                copies = []
            }
            if !reading.wentNowhere, !corrected.isEmpty { passedOn(CatWords.passedOnCorrection) }
        case .handoff(let task):
            handOff(task: task, question: words, snapshot: file, asked: asked, onStarted: started(in: .shades))
            passedOn(CatWords.handedOff(task))
        case .route(let session):
            guard sessions.indices.contains(session - 1) else {
                catSays(CatWords.lostTheSession)
                return
            }
            let thread = sessions[session - 1]
            if KittenBoard.owner(of: thread, among: owners) == nil { messagesThreads[thread.id] = messagesThreads[thread.id] ?? sentAt }
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
                catSays(CatWords.lostTheSession)
                return
            }
            let kitten = kittens[number - 1]
            give(words, to: kitten, snapshot: file, as: corrected.contains(kitten) ? .correction : .work, asked: asked, onStarted: started(in: .of(kitten)))
            copies.removeAll { $0 == kitten }
            passedOn(CatWords.passedOnToKitten)
        }
        if isFresh {
            if file == nil { messagesQuick.reset() }
            Task { [backend] in try? await backend.archive(threadID: threadID) }
        } else {
            Task { [backend] in try? await backend.settle(threadID: threadID) }
        }
    }

    private func sendLockedDown(_ words: String, echoID: String, file: ScreenSnapshot?) {
        let sentAt = now()
        sendLockedDown(words, snapshot: file, youPicked: true, sent: { [weak self] id, starting in
            guard let self else { return }
            guard let id else { return self.channels.failed(echoID, because: CatWords.didntStart) }
            self.channels.delivered(echoID)
            if starting, let kitten = self.lockedDownKitten {
                self.messagesThreads[id] = self.messagesThreads[id] ?? sentAt
                self.channels.sent(ChannelMessage(exchangeID: "started-\(echoID)", kind: .ask, speaker: .you, text: words, at: sentAt, threadID: id, threadTitle: ""), in: .of(kitten))
            }
            self.catSays(starting ? CatWords.passedOnToKitten : CatWords.passedOnToSession)
        }, refused: { [weak self] in
            self?.channels.failed(echoID, because: CatWords.cantTakeFiles(self?.lockedDownKitten?.name ?? CatWords.shades))
        }, unheard: { [weak self] in
            self?.channels.failed(echoID, because: $0)
        })
    }

    private func routerTurn(_ stream: AsyncThrowingStream<AgentReplyEvent, Error>, joins: Bool = true, echoID: String) async -> (reading: ReplyHoldback.Reading, threadID: String)? {
        var holdback = ReplyHoldback()
        var fullText: String?
        var thread: String?
        var raised: Set<String> = []
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
                    raised.insert(request.id)
                    addApproval(request)
                case .finished(let text):
                    runEnded(asking: raised)
                    fullText = text
                case .failed:
                    runEnded(asking: raised)
                    return nil
                }
            }
        } catch {
            if fullText == nil { return nil }
        }
        guard let thread else { return nil }
        return (holdback.read(fullText: fullText), thread)
    }

    private func catSays(_ text: String, thread: String? = nil) {
        guard channels.isOpen else { return post(caption: CatWords.shades, text: text, threadID: nil) }
        let message = ChannelMessage(exchangeID: "cat-\(UUID().uuidString)", kind: .reply, speaker: .cat, text: text, at: now(), threadID: thread ?? "", threadTitle: "")
        channels.sent(message, in: .shades, alsoSent: thread != nil)
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
