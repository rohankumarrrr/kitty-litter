import Foundation
import ShadesCore

struct QuickTurn {
    let question: String
    let snapshot: ScreenSnapshot?
    let seen: ScreenSnapshot?
    let generation: Int
    let sessions: [AgentThread]
    let kittens: [Kitten]
    let following: String?

    func kitten(numbered number: Int) -> Kitten? {
        kittens.indices.contains(number - 1) ? kittens[number - 1] : nil
    }
}

extension AppController {
    func catClicked() {
        stage.catPet()
        if !askable.isEmpty && approvalsHidden {
            approvalsHidden = false
            renderBubble()
            return
        }
        askPressed()
    }

    func askPressed() {
        flow = Task { await beginAsk() }
    }

    func dropped(_ snapshot: ScreenSnapshot?) {
        guard let snapshot else {
            say(CatWords.cantReadThat)
            return
        }
        flow = Task {
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
        if settings.lockdown != nil {
            guard !takenBack.contains(generation) else { return }
            if generation == replyGeneration {
                reply = nil
                renderBubble()
            }
            return sendLockedDown(question, snapshot: snapshot)
        }
        await waitForThreadList()
        guard !takenBack.contains(generation) else { return }

        let current = quick.thread(at: now())
        if generation == replyGeneration { quickIsFresh = current == nil }
        let sessions = rosterThreads(excluding: current)
        let briefs = await briefs(for: sessions)
        guard !takenBack.contains(generation) else { return }
        let all = loadKittens()
        let kittens = all.filter { !$0.planned }
        let model = settings.quickModel
        let projectID: String
        do {
            projectID = try await routerProjectID(for: model)
        } catch {
            return quickTurnFailed(.failed(message: nil, error: error, sawText: false), generation: generation)
        }
        guard !takenBack.contains(generation) else { return }
        let shared = settings.quickMode == .fullAccess ? nil : snapshot
        guard shared != nil || snapshot?.isDropped != true else {
            let refused = CatWords.cantTakeFiles(ModelNames.friendly(model))
            guard generation == replyGeneration else {
                return post(caption: CatWords.earlierMessageCaption, text: refused, threadID: nil)
            }
            reply = nil
            say(refused)
            return
        }
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
            if finished { return .finished }
            return .failed(message: nil, error: error, sawText: !holdback.text.isEmpty)
        }
        if !finished {
            finish(holdback.read(fullText: nil), turn: turn, thread: thread)
        }
        return .finished
    }

    func finish(_ reading: ReplyHoldback.Reading, turn: QuickTurn, thread: String?) {
        if let thread, thread == quick.thread(at: now()) {
            quick.use(thread, at: now())
            wrapUpQuickThread(thread, after: reading)
        } else if let thread, hiddenThreads.contains(thread) {
            Task { [backend] in try? await backend.archive(threadID: thread) }
        }
        guard !takenBack.contains(turn.generation) else { return }
        let owners = reading.corrections.compactMap(turn.kitten(numbered:))
        if owners.count < reading.corrections.count {
            post(caption: CatWords.correctionCaption, text: CatWords.lostTheCorrection, threadID: nil)
        }
        var copies = owners
        defer { copies.forEach { give(turn.question, to: $0, snapshot: nil, as: .correctionCopy) } }
        guard turn.generation == replyGeneration else { return }
        switch reading.outcome {
        case .answer(let text, let point):
            let region = point.flatMap { turn.seen?.region(for: $0) }
            if text.isEmpty && point == nil {
                reply = nil
                renderBubble()
                if reading.wentNowhere, !reading.corrections.isEmpty {
                    say(CatWords.lostTheSession)
                } else if owners.count == 1 {
                    give(turn.question, to: owners[0], snapshot: turn.snapshot, as: .correction)
                    copies = []
                } else if reading.corrections.isEmpty {
                    say(CatWords.noReply)
                }
            } else if text.isEmpty && region == nil {
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

    func catFollowsReply() {
        guard !catIsAway else { return }
        if let region = reply?.pointingAt {
            stage.catRun(toRegion: region) {}
        } else {
            stage.catGoHome()
        }
    }

    var frontierName: String { ModelNames.friendly(settings.frontierModel) }

    func handOff(task: String, question: String, snapshot: ScreenSnapshot?, asked: Int? = nil, onStarted: ((String?) -> Void)? = nil) {
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

    func attachments(for snapshot: ScreenSnapshot?) -> [AgentAttachment] {
        guard let snapshot, !snapshot.isPrivate else { return [] }
        if snapshot.isDropped { return snapshot.pictures }
        guard let jpeg = snapshot.screenshotJPEG else { return [] }
        return [AgentAttachment(name: "screen.jpg", mimeType: "image/jpeg", data: jpeg)]
    }

    enum Errand {
        case work
        case correction
        case correctionCopy
    }

    func tell(_ text: String, threadID: String? = nil, as errand: Errand, fades: Bool = false, unasked: Bool = false) {
        if errand == .correctionCopy {
            post(caption: CatWords.correctionCaption, text: text, threadID: threadID, unasked: unasked)
        } else {
            say(text, threadID: threadID, fades: fades, unasked: unasked)
        }
    }

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
