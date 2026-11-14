import Foundation
import ShadesCore

/// One question and the lists the router was shown for it. A reply's numbers only mean anything
/// against these, so one that comes back late can't land on a newer list.
struct QuickTurn {
    let question: String
    let snapshot: ScreenSnapshot?
    /// What the router was shown, which is all it can point at.
    let seen: ScreenSnapshot?
    let generation: Int
    let sessions: [AgentThread]
    let kittens: [Kitten]
    /// The conversation it's following up, if any, which is never its own to hide or archive.
    let following: String?

    func kitten(numbered number: Int) -> Kitten? {
        kittens.indices.contains(number - 1) ? kittens[number - 1] : nil
    }
}

/// Ask: look at the screen, take the question, stream the answer, and hand off real work.
extension AppController {
    /// The cat was clicked. It always gets a word, and then you get to ask.
    func catClicked() {
        stage.catPet()
        if !approvals.isEmpty && approvalsHidden {
            approvalsHidden = false
            renderBubble()
            return
        }
        askPressed()
    }

    func askPressed() {
        flow = Task { await beginAsk() }
    }

    /// Something was dropped onto the cat, or `nil` if it couldn't be read. Only what was dropped goes with
    /// the question, so there's no look at the screen.
    func dropped(_ snapshot: ScreenSnapshot?) {
        guard let snapshot else {
            say(CatWords.cantReadThat)
            return
        }
        flow = Task {
            // An Ask that's still opening shows its box first, so the drop, which came later, replaces it.
            while openingAsk { try? await Task.sleep(nanoseconds: 50_000_000) }
            if stage.isInputVisible { stage.hideInput() }
            await beginAsk(dropped: snapshot)
        }
    }

    func beginAsk(dropped: ScreenSnapshot? = nil) async {
        if stage.isInputVisible {
            stage.hideInput()
            return
        }
        guard !openingAsk else { return }
        openingAsk = true
        defer { openingAsk = false }
        stage.catWake()

        if let dropped {
            let capture = Task { Capture(snapshot: dropped, error: nil) }
            dropIsOpen = true
            showBox(InputRequest(
                placeholder: CatWords.askAboutDrop,
                attachment: dropped.droppedNames.isEmpty ? nil : dropped.droppedNames.joined(separator: ", "),
                allowsEmpty: true,
                onSubmit: { [weak self] question in
                    self?.dropIsOpen = false
                    self?.ask(question.isEmpty ? CatWords.summarize : question, capture: capture)
                },
                onCancel: { [weak self] in self?.dropIsOpen = false }
            ))
            return
        }

        // The look at the screen comes first, before anything can take focus.
        let capture = startLook(CaptureOptions())
        let early = await firstOf(seconds: Self.panelWait) { await capture.value }
        showBox(InputRequest(
            placeholder: CatWords.askPlaceholder,
            caption: early.flatMap(askCaption),
            allowsEmpty: false,
            onSubmit: { [weak self] question in self?.ask(question, capture: capture) },
            onCancel: {}
        ))
    }

    func askCaption(_ capture: Capture) -> String? {
        if let error = capture.error { return CatWords.problem(error, while: .seeing) }
        guard let snapshot = capture.snapshot else { return CatWords.cantSeeScreen }
        if snapshot.isPrivate { return CatWords.privateApp }
        // Missing permissions mean missing fields rather than errors.
        if snapshot.screenshotJPEG == nil { return screenBlockedBy ?? CatWords.needsScreenRecording }
        return CatWords.looking(at: snapshot)
    }

    func ask(_ question: String, snapshot: ScreenSnapshot?) {
        ask(question, capture: Task { Capture(snapshot: snapshot, error: nil) })
    }

    func ask(_ question: String, capture: Task<Capture, Never>?) {
        replyGeneration += 1
        questionsAsked += 1
        let generation = replyGeneration
        line = nil
        // You've moved on, and may well be sending what it asked for.
        notices.removeAll { $0.text == CatWords.sendTheLink }
        reply = Reply()
        renderBubble()
        replyTask = Task {
            let snapshot = await capture?.value.snapshot
            if generation == replyGeneration {
                reply?.note = snapshot?.isPrivate == true ? CatWords.privateApp : screenTip()
                if reply?.note != nil { renderBubble() }
            }
            await runQuickTurn(question, snapshot: snapshot, generation: generation)
        }
    }

    enum TurnEnd {
        case finished
        case failed(message: String?, error: Error?, sawText: Bool)
    }

    func runQuickTurn(_ question: String, snapshot: ScreenSnapshot?, generation: Int) async {
        // Lockdown has no router to wait for.
        if settings.lockdown != nil {
            if generation == replyGeneration {
                reply = nil
                renderBubble()
            }
            return sendLockedDown(question, snapshot: snapshot)
        }
        await waitForThreadList()
        // One that's been overtaken still goes to the router, because there could be a correction in it.
        guard !takenBack.contains(generation) else { return }

        let current = quick.thread(at: now())
        if generation == replyGeneration { quickIsFresh = current == nil }
        let sessions = rosterThreads(excluding: current)
        let briefs = await briefs(for: sessions)
        guard !takenBack.contains(generation) else { return }
        let all = loadKittens()
        let kittens = all.filter { !$0.planned }
        // Settings can change while T3 answers, so the model that's checked is the one that runs.
        let model = settings.quickModel
        let projectID: String
        do {
            projectID = try await routerProjectID(for: model)
        } catch {
            return quickTurnFailed(.failed(message: nil, error: error, sawText: false), generation: generation)
        }
        guard !takenBack.contains(generation) else { return }
        // Whoever it's passed to gets their own say on the snapshot, so this only holds it back from here.
        let shared = settings.quickMode == .fullAccess ? nil : snapshot
        guard shared != nil || snapshot?.isDropped != true else {
            let refused = CatWords.cantTakeFiles(ModelNames.friendly(model))
            // It could have held a correction, and nothing else will say it went nowhere.
            guard generation == replyGeneration else {
                return post(caption: CatWords.earlierMessageCaption, text: refused, threadID: nil)
            }
            reply = nil
            say(refused)
            return
        }
        // A message queues behind one already running, so one that's been overtaken keeps out of the way.
        let following = generation == replyGeneration ? quick.thread(at: now()) : nil
        let turn = QuickTurn(
            question: question,
            snapshot: snapshot,
            seen: shared,
            generation: generation,
            sessions: sessions,
            kittens: kittens,
            following: following
        )
        let prompt = AgentPrompt(
            // A question can run over several lines, and a title can't.
            title: String(question.prefix { !$0.isNewline }.prefix(60)),
            text: Prompts.quick(question: question, snapshot: shared, sessions: briefs, kittens: kittens, notSetUp: all.filter(\.planned)),
            attachments: attachments(for: shared),
            model: model,
            runtimeMode: settings.quickMode,
            projectID: projectID
        )

        let start: () -> AsyncThrowingStream<AgentReplyEvent, Error> = { [backend] in backend.start(prompt) }
        var end: TurnEnd
        if let following {
            end = await consume(backend.followUp(threadID: following, prompt), turn: turn)
            // The old thread might have gone. Nothing was shown yet, so just start fresh.
            if case .failed(_, _, false) = end, !takenBack.contains(generation) {
                if generation == replyGeneration {
                    quick.reset()
                    quickIsFresh = true
                }
                end = await consume(start(), turn: turn)
            }
        } else {
            end = await consume(start(), turn: turn)
        }

        quickTurnFailed(end, generation: generation)
    }

    private func quickTurnFailed(_ end: TurnEnd, generation: Int) {
        guard case .failed(let message, let error, _) = end else { return }
        guard generation == replyGeneration else {
            // There could have been a correction in it, and nothing else will tell you it's gone.
            if !takenBack.contains(generation) {
                post(caption: CatWords.earlierMessageCaption, text: CatWords.earlierMessageFailed, threadID: nil)
            }
            return
        }
        reply = nil
        if let error {
            say(CatWords.problem(error, while: .agents))
        } else {
            say(message ?? CatWords.noReply)
        }
    }

    func consume(_ stream: AsyncThrowingStream<AgentReplyEvent, Error>, turn: QuickTurn) async -> TurnEnd {
        var holdback = ReplyHoldback()
        var thread: String?
        var finished = false
        do {
            for try await event in stream {
                switch event {
                case .started(let threadID):
                    thread = threadID
                    watch.markQuick(threadID)
                    guard turn.generation == replyGeneration else {
                        // A thread of its own is only here to find a correction, so no newer question should route into it.
                        if threadID != turn.following { hiddenThreads.insert(threadID) }
                        continue
                    }
                    quick.use(threadID, at: now())
                    reply?.threadID = threadID
                case .text(let delta):
                    guard let text = holdback.add(delta), turn.generation == replyGeneration else { continue }
                    reply?.text = text
                    renderBubble()
                case .needsApproval(let request):
                    addApproval(request)
                case .finished(let fullText):
                    finished = true
                    finish(holdback.read(fullText: fullText), turn: turn, thread: thread)
                case .failed(let message):
                    return .failed(message: message, error: nil, sawText: !holdback.text.isEmpty)
                }
            }
        } catch {
            // The reply was already read and acted on, so it got through, whatever broke after it.
            if finished { return .finished }
            return .failed(message: nil, error: error, sawText: !holdback.text.isEmpty)
        }
        if !finished {
            finish(holdback.read(fullText: nil), turn: turn, thread: thread)
        }
        return .finished
    }

    func finish(_ reading: ReplyHoldback.Reading, turn: QuickTurn, thread: String?) {
        // The ten minutes run from the last time the thread was used.
        if let thread, thread == quick.thread(at: now()) {
            quick.use(thread, at: now())
            wrapUpQuickThread(thread, after: reading)
        } else if let thread, hiddenThreads.contains(thread) {
            // It was overtaken before it joined the conversation, so nothing will use it again.
            Task { [backend] in try? await backend.archive(threadID: thread) }
        }
        // Esc takes a message back. Being overtaken only loses the rest of it.
        guard !takenBack.contains(turn.generation) else { return }
        let owners = reading.corrections.compactMap(turn.kitten(numbered:))
        if owners.count < reading.corrections.count {
            post(caption: CatWords.correctionCaption, text: CatWords.lostTheCorrection, threadID: nil)
        }
        var copies = owners
        // Your words only, so a page that fools the router gains no new place to send what's on it.
        defer { copies.forEach { give(turn.question, to: $0, snapshot: nil, as: .correctionCopy) } }
        guard turn.generation == replyGeneration else { return }
        switch reading.outcome {
        case .answer(let text, let point):
            // It only points with what the router was shown, and if it can't find the spot, it says so.
            let region = point.flatMap { turn.seen?.region(for: $0) }
            if text.isEmpty && point == nil {
                reply = nil
                // A kitten takes a moment to say anything, and "thinking" shouldn't stay up until it does.
                renderBubble()
                if reading.wentNowhere, !reading.corrections.isEmpty {
                    // The rest was meant for somewhere else, so the owner only gets its copy.
                    say(CatWords.lostTheSession)
                } else if owners.count == 1 {
                    give(turn.question, to: owners[0], snapshot: turn.snapshot, as: .correction)
                    copies = []
                } else if reading.corrections.isEmpty {
                    say(CatWords.noReply)
                }
            } else if text.isEmpty && region == nil {
                // It meant to point, so the rest isn't a correction alone, and the owner only gets its copy.
                reply = nil
                say(CatWords.cantPoint)
            } else {
                reply?.text = text.isEmpty ? CatWords.overHere : text
                reply?.done = true
                reply?.pointingAt = region
                if point != nil && region == nil { reply?.note = CatWords.cantPoint }
                renderBubble()
            }
        case .rewrite(let text):
            reply?.text = text
            reply?.done = true
            if let selected = turn.snapshot?.selectedText { reply?.replacing = (selected, turn.snapshot?.bundleID) }
            renderBubble()
        case .handoff(let task):
            reply = nil
            handOff(task: task, question: turn.question, snapshot: turn.snapshot)
        case .route(let session):
            reply = nil
            guard turn.sessions.indices.contains(session - 1) else {
                say(CatWords.lostTheSession)
                return
            }
            let thread = turn.sessions[session - 1]
            let home = owners.first { KittenBoard.isInFolder(thread.projectPath, of: $0) }
            forward(turn.question, to: thread, snapshot: turn.snapshot, correction: home != nil) { [weak self] in
                // It couldn't take what you dropped, so the owner gets its correction on its own, without it.
                if let home { self?.give(turn.question, to: home, snapshot: nil, as: .correctionCopy) }
            }
            copies.removeAll { $0 == home }
        case .kitten(let number):
            reply = nil
            renderBubble()
            guard let kitten = turn.kitten(numbered: number) else {
                say(CatWords.lostTheSession)
                return
            }
            give(turn.question, to: kitten, snapshot: turn.snapshot, as: owners.contains(kitten) ? .correction : .work)
            copies.removeAll { $0 == kitten }
        }
    }

    /// Replace was pressed on a rewrite. It only goes in while what you'd selected is still selected,
    /// and is copied otherwise, so it never lands somewhere you didn't mean.
    func replaceSelection(with text: String) {
        guard let selection = reply?.replacing else { return }
        reply = nil
        replyGeneration += 1
        renderBubble()
        flow = Task {
            guard await !inserter.replaceSelection(selection.text, in: selection.bundleID, with: text) else { return }
            stage.copyToPasteboard(text)
            say(CatWords.rewriteCopied)
        }
    }

    /// Its job is done, whether that was answering or passing the work on. A new thread that
    /// only passed something on has nothing worth keeping, so it goes rather than cluttering T3.
    private func wrapUpQuickThread(_ threadID: String, after reading: ReplyHoldback.Reading) {
        var passedOn = false
        switch reading.outcome {
        case .answer(let text, let point):
            if text.isEmpty && point == nil {
                if reading.corrections.isEmpty { return }
                passedOn = true
            }
        case .rewrite:
            break
        case .handoff, .route, .kitten:
            passedOn = true
        }
        if passedOn && quickIsFresh {
            quick.reset()
            Task { [backend] in try? await backend.archive(threadID: threadID) }
        } else {
            Task { [backend] in try? await backend.settle(threadID: threadID) }
        }
        quickIsFresh = false
    }

    /// Sits by what the answer points at, and goes home once that answer's gone. An approval needs
    /// the cat with you first, and it comes back here after.
    func catFollowsReply() {
        guard !catIsAway else { return }
        if let region = reply?.pointingAt {
            stage.catRun(toRegion: region) {}
        } else {
            stage.catGoHome()
        }
    }

    // MARK: - Handing off

    var frontierName: String { ModelNames.friendly(settings.frontierModel) }

    /// The quick agent decided this needs more, so it goes straight to the frontier agent, which says so.
    func handOff(task: String, question: String, snapshot: ScreenSnapshot?, asked: Int? = nil, onStarted: ((String?) -> Void)? = nil) {
        // With full access, neither the page nor the quick agent's reading of it gets to reach it.
        guard settings.frontierMode != .fullAccess else {
            guard snapshot?.isDropped != true else {
                onStarted?(nil)
                say(CatWords.cantTakeFiles(frontierName))
                return
            }
            startFrontier(
                title: question,
                text: Prompts.frontier(request: question, snapshot: nil, screenshotPath: nil),
                snapshot: nil,
                missesScreen: ScreenWords.pointAtScreen(question),
                asked: asked,
                onStarted: onStarted
            )
            return
        }
        let path = saveScreenshot(of: snapshot)
        // The task is the quick agent's reading of it, and the question is what you really said.
        let request = "\(task)\n\n\(Prompts.ownWordsLabel)\(question)"
        startFrontier(
            title: task,
            text: Prompts.frontier(request: request, snapshot: snapshot, screenshotPath: path),
            snapshot: snapshot,
            missesScreen: !carriesScreen(snapshot) && ScreenWords.pointAtScreen(question),
            asked: asked,
            onStarted: onStarted
        )
    }

    func saveScreenshot(of snapshot: ScreenSnapshot?) -> String? {
        guard let snapshot, !snapshot.isPrivate else { return nil }
        return (try? context.saveScreenshot(of: snapshot)) ?? nil
    }

    /// What was dropped or attached goes by each picture's own name, which is how Messages finds it again after a restart.
    func attachments(for snapshot: ScreenSnapshot?) -> [AgentAttachment] {
        guard let snapshot, !snapshot.isPrivate else { return [] }
        if snapshot.isDropped { return snapshot.pictures }
        guard let jpeg = snapshot.screenshotJPEG else { return [] }
        return [AgentAttachment(name: "screen.jpg", mimeType: "image/jpeg", data: jpeg)]
    }

    /// Why an agent's being started, which decides how you hear about it.
    enum Errand {
        /// Real work, which it may pass on to another thread.
        case work
        /// A correction, whose report has to reach you even if it starts threads elsewhere.
        case correction
        /// The same, while the rest of the message goes somewhere else.
        case correctionCopy
    }

    /// A copy goes out alongside the rest of the message, so it waits its turn rather than talking over that. One
    /// that's `unasked` comes once the work's well under way, so Do Not Disturb holds it.
    func tell(_ text: String, threadID: String? = nil, as errand: Errand, fades: Bool = false, unasked: Bool = false) {
        if errand == .correctionCopy {
            post(caption: CatWords.correctionCaption, text: text, threadID: threadID, unasked: unasked)
        } else {
            say(text, threadID: threadID, fades: fades, unasked: unasked)
        }
    }

    /// `onStarted` hears the new thread, or `nil` if there isn't one. `asked` is the question it came from, if not the latest.
    /// `youPicked` leaves out saying who has it, since you can see where it went, but a problem or warning still comes.
    func startFrontier(
        title: String?,
        text: String,
        snapshot: ScreenSnapshot?,
        projectID: String? = nil,
        name: String? = nil,
        as errand: Errand = .work,
        youPicked: Bool = false,
        missesScreen: Bool = false,
        asked: Int? = nil,
        onStarted: ((String?) -> Void)? = nil
    ) {
        let name = name ?? frontierName
        let asked = asked ?? questionsAsked
        let prompt = AgentPrompt(
            title: title.map { String($0.prefix(80)) },
            text: text,
            attachments: attachments(for: snapshot),
            model: settings.frontierModel,
            runtimeMode: settings.frontierMode,
            projectID: projectID
        )
        if errand != .correctionCopy, !youPicked { say(CatWords.handingOff(modelName: name)) }
        frontierTask = Task {
            var startedThread: String?
            var warning: Int?
            do {
                for try await event in backend.start(prompt) {
                    switch event {
                    case .started(let threadID):
                        startedThread = threadID
                        if errand == .work { dispatchers.insert(threadID) } else { noteCorrection(in: threadID) }
                        onStarted?(threadID)
                        // Your work with the cat itself, outside Messages and any kitten's folder, lives in its DM.
                        if errand == .work, projectID == nil, messagesThreads[threadID] == nil { catsWork[threadID] = now() }
                        let said = errand == .correctionCopy ? CatWords.correctionSent(to: name) : CatWords.onIt(modelName: name)
                        if missesScreen {
                            warning = sayPassedOn(said, threadID: threadID, missesScreen: true, asked: asked)
                        } else if !youPicked {
                            tell(said, threadID: threadID, as: errand, fades: true)
                        }
                    case .needsApproval(let request):
                        addApproval(request)
                    case .failed(let message):
                        // Only this turn's, since words sent to the thread after it started still went without your screen.
                        if let warning { takeBackNotice(warning) }
                        tell(message, as: errand, unasked: startedThread != nil)
                    case .text, .finished:
                        break
                    }
                }
                if startedThread == nil {
                    onStarted?(nil)
                    tell(CatWords.noReply, as: errand)
                }
            } catch {
                if startedThread == nil { onStarted?(nil) }
                tell(CatWords.problem(error, while: .agents), as: errand, unasked: startedThread != nil)
            }
        }
    }
}
