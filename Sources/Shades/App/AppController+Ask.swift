import Foundation
import ShadesCore

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
        stage.hideInbox()
        stage.catWake()

        if let dropped {
            let capture = Task { Capture(snapshot: dropped, error: nil) }
            dropIsOpen = true
            boxesOpened += 1
            stage.showInput(InputRequest(
                placeholder: CatWords.askAboutDrop,
                caption: CatWords.looking(at: dropped),
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
        stage.showInput(InputRequest(
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
        await waitForThreadList()
        guard generation == replyGeneration else { return }

        let current = quick.thread(at: now())
        quickIsFresh = current == nil
        let sessions = rosterThreads(excluding: current)
        let briefs = await briefs(for: sessions)
        guard generation == replyGeneration else { return }
        roster = sessions
        kittens = loadKittens().filter { !$0.planned }
        // Settings can change while T3 answers, so the model that's checked is the one that runs.
        let model = settings.quickModel
        let projectID: String
        do {
            projectID = try await routerProjectID(for: model)
        } catch {
            guard generation == replyGeneration else { return }
            reply = nil
            say(CatWords.problem(error, while: .agents))
            return
        }
        guard generation == replyGeneration else { return }

        // Whoever it's passed to gets their own say on the snapshot, so this only holds it back from here.
        let shared = settings.quickMode == .fullAccess ? nil : snapshot
        guard shared != nil || snapshot?.droppedName == nil else {
            reply = nil
            say(CatWords.cantTakeFiles(ModelNames.friendly(model)))
            return
        }
        let prompt = AgentPrompt(
            // A question can run over several lines, and a title can't.
            title: String(question.prefix { !$0.isNewline }.prefix(60)),
            text: Prompts.quick(question: question, snapshot: shared, sessions: briefs, kittens: kittens),
            attachments: attachments(for: shared),
            model: model,
            runtimeMode: settings.quickMode,
            projectID: projectID
        )

        let start: () -> AsyncThrowingStream<AgentReplyEvent, Error> = { [backend] in backend.start(prompt) }
        var end: TurnEnd
        if let thread = quick.thread(at: now()) {
            end = await consume(backend.followUp(threadID: thread, prompt), question: question, snapshot: snapshot, seen: shared, generation: generation)
            // The old thread might have gone. Nothing was shown yet, so just start fresh.
            if case .failed(_, _, false) = end {
                quick.reset()
                quickIsFresh = true
                end = await consume(start(), question: question, snapshot: snapshot, seen: shared, generation: generation)
            }
        } else {
            end = await consume(start(), question: question, snapshot: snapshot, seen: shared, generation: generation)
        }

        guard generation == replyGeneration, case .failed(let message, let error, _) = end else { return }
        reply = nil
        if let error {
            say(CatWords.problem(error, while: .agents))
        } else {
            say(message ?? CatWords.noReply)
        }
    }

    /// `seen` is what the router was shown, which is all it can point at.
    func consume(
        _ stream: AsyncThrowingStream<AgentReplyEvent, Error>,
        question: String,
        snapshot: ScreenSnapshot?,
        seen: ScreenSnapshot?,
        generation: Int
    ) async -> TurnEnd {
        var holdback = ReplyHoldback()
        var finished = false
        do {
            for try await event in stream {
                switch event {
                case .started(let threadID):
                    quick.use(threadID, at: now())
                    watch.markQuick(threadID)
                    if generation == replyGeneration { reply?.threadID = threadID }
                case .text(let delta):
                    guard let text = holdback.add(delta), generation == replyGeneration else { continue }
                    reply?.text = text
                    renderBubble()
                case .needsApproval(let request):
                    addApproval(request)
                case .finished(let fullText):
                    finished = true
                    finish(holdback.finish(fullText: fullText), question: question, snapshot: snapshot, seen: seen, generation: generation)
                case .failed(let message):
                    return .failed(message: message, error: nil, sawText: !holdback.text.isEmpty)
                }
            }
        } catch {
            return .failed(message: nil, error: error, sawText: !holdback.text.isEmpty)
        }
        if !finished {
            finish(holdback.finish(fullText: nil), question: question, snapshot: snapshot, seen: seen, generation: generation)
        }
        return .finished
    }

    func finish(_ outcome: ReplyHoldback.Outcome, question: String, snapshot: ScreenSnapshot?, seen: ScreenSnapshot?, generation: Int) {
        // The ten minutes run from the last time the thread was used.
        if let threadID = quick.thread(at: now()) {
            quick.use(threadID, at: now())
            wrapUpQuickThread(threadID, after: outcome)
        }
        guard generation == replyGeneration else { return }
        switch outcome {
        case .answer(let text, let point):
            // It only points with what the router was shown, and if it can't find the spot, it says so.
            let region = point.flatMap { seen?.region(for: $0) }
            if text.isEmpty && region == nil {
                reply = nil
                say(point == nil ? CatWords.noReply : CatWords.cantPoint)
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
            if let selected = snapshot?.selectedText { reply?.replacing = (selected, snapshot?.bundleID) }
            renderBubble()
        case .handoff(let task):
            reply = nil
            handOff(task: task, question: question, snapshot: snapshot)
        case .route(let session):
            reply = nil
            guard roster.indices.contains(session - 1) else {
                say(CatWords.lostTheSession)
                return
            }
            forward(question, to: roster[session - 1], snapshot: snapshot)
        case .kitten(let number):
            reply = nil
            guard kittens.indices.contains(number - 1) else {
                say(CatWords.lostTheSession)
                return
            }
            give(question, to: kittens[number - 1], snapshot: snapshot)
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
    private func wrapUpQuickThread(_ threadID: String, after outcome: ReplyHoldback.Outcome) {
        var passedOn = false
        switch outcome {
        case .answer(let text, let point):
            if text.isEmpty && point == nil { return }
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
            guard snapshot?.droppedName == nil else {
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
        let request = "\(task)\n\nTheir own words: \(question)"
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

    func attachments(for snapshot: ScreenSnapshot?) -> [AgentAttachment] {
        guard let snapshot, !snapshot.isPrivate, let jpeg = snapshot.screenshotJPEG else { return [] }
        return [AgentAttachment(name: "screen.jpg", mimeType: "image/jpeg", data: jpeg)]
    }

    /// `onStarted` hears the new thread, or `nil` if there isn't one. `asked` is the question it came from, if not the latest.
    func startFrontier(
        title: String?,
        text: String,
        snapshot: ScreenSnapshot?,
        projectID: String? = nil,
        name: String? = nil,
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
        say(CatWords.handingOff(modelName: name), seconds: nil)
        frontierTask = Task {
            var startedThread: String?
            var warning: Int?
            do {
                for try await event in backend.start(prompt) {
                    switch event {
                    case .started(let threadID):
                        startedThread = threadID
                        dispatchers.insert(threadID)
                        onStarted?(threadID)
                        warning = sayPassedOn(CatWords.onIt(modelName: name), threadID: threadID, missesScreen: missesScreen, asked: asked)
                    case .needsApproval(let request):
                        addApproval(request)
                    case .failed(let message):
                        // Only this turn's, since words sent to the thread after it started still went without your screen.
                        if let warning { takeBackNotice(warning) }
                        say(message)
                    case .text, .finished:
                        break
                    }
                }
                if startedThread == nil {
                    onStarted?(nil)
                    say(CatWords.noReply)
                }
            } catch {
                if startedThread == nil { onStarted?(nil) }
                say(CatWords.problem(error, while: .agents))
            }
        }
    }
}
