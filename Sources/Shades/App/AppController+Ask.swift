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

    func beginAsk() async {
        if stage.isInputVisible {
            stage.hideInput()
            return
        }
        guard !openingAsk else { return }
        openingAsk = true
        defer { openingAsk = false }
        stage.catWake()

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

        let prompt = AgentPrompt(
            // A question can run over several lines, and a title can't.
            title: String(question.prefix { !$0.isNewline }.prefix(60)),
            text: Prompts.quick(question: question, snapshot: snapshot, sessions: briefs, kittens: kittens),
            attachments: attachments(for: snapshot),
            model: settings.quickModel,
            runtimeMode: settings.quickMode
        )

        let start: () -> AsyncThrowingStream<AgentReplyEvent, Error> = { [backend] in backend.start(prompt) }
        var end: TurnEnd
        if let thread = quick.thread(at: now()) {
            end = await consume(backend.followUp(threadID: thread, prompt), question: question, snapshot: snapshot, generation: generation)
            // The old thread might have gone. Nothing was shown yet, so just start fresh.
            if case .failed(_, _, false) = end {
                quick.reset()
                quickIsFresh = true
                end = await consume(start(), question: question, snapshot: snapshot, generation: generation)
            }
        } else {
            end = await consume(start(), question: question, snapshot: snapshot, generation: generation)
        }

        guard generation == replyGeneration, case .failed(let message, let error, _) = end else { return }
        reply = nil
        if let error {
            say(CatWords.problem(error, while: .agents))
        } else {
            say(message ?? CatWords.noReply)
        }
    }

    func consume(
        _ stream: AsyncThrowingStream<AgentReplyEvent, Error>,
        question: String,
        snapshot: ScreenSnapshot?,
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
                    finish(holdback.finish(fullText: fullText), question: question, snapshot: snapshot, generation: generation)
                case .failed(let message):
                    return .failed(message: message, error: nil, sawText: !holdback.text.isEmpty)
                }
            }
        } catch {
            return .failed(message: nil, error: error, sawText: !holdback.text.isEmpty)
        }
        if !finished {
            finish(holdback.finish(fullText: nil), question: question, snapshot: snapshot, generation: generation)
        }
        return .finished
    }

    func finish(_ outcome: ReplyHoldback.Outcome, question: String, snapshot: ScreenSnapshot?, generation: Int) {
        // The ten minutes run from the last time the thread was used.
        if let threadID = quick.thread(at: now()) {
            quick.use(threadID, at: now())
            wrapUpQuickThread(threadID, after: outcome)
        }
        guard generation == replyGeneration else { return }
        switch outcome {
        case .answer(let text):
            if text.isEmpty {
                reply = nil
                say(CatWords.noReply)
            } else {
                reply?.text = text
                reply?.done = true
                renderBubble()
            }
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

    /// Its job is done, whether that was answering or passing the work on. A new thread that
    /// only passed something on has nothing worth keeping, so it goes rather than cluttering T3.
    private func wrapUpQuickThread(_ threadID: String, after outcome: ReplyHoldback.Outcome) {
        var passedOn = false
        switch outcome {
        case .answer(let text):
            if text.isEmpty { return }
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

    // MARK: - Handing off

    var frontierName: String { ModelNames.friendly(settings.frontierModel) }

    /// The quick agent decided this needs more, so it goes straight to the frontier agent, which says so.
    func handOff(task: String, question: String, snapshot: ScreenSnapshot?) {
        let path = saveScreenshot(of: snapshot)
        // The task is the quick agent's reading of it, and the question is what you really said.
        let request = "\(task)\n\nTheir own words: \(question)"
        startFrontier(
            title: task,
            text: Prompts.frontier(request: request, snapshot: snapshot, screenshotPath: path),
            snapshot: snapshot
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

    func startFrontier(title: String?, text: String, snapshot: ScreenSnapshot?, projectID: String? = nil, name: String? = nil, missesScreen: Bool = false) {
        let name = name ?? frontierName
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
            do {
                for try await event in backend.start(prompt) {
                    switch event {
                    case .started(let threadID):
                        startedThread = threadID
                        dispatchers.insert(threadID)
                        sayPassedOn(CatWords.onIt(modelName: name), threadID: threadID, missesScreen: missesScreen)
                    case .needsApproval(let request):
                        addApproval(request)
                    case .failed(let message):
                        dropScreenWarning(for: startedThread)
                        say(message)
                    case .text, .finished:
                        break
                    }
                }
                if startedThread == nil { say(CatWords.noReply) }
            } catch {
                say(CatWords.problem(error, while: .agents))
            }
        }
    }
}
