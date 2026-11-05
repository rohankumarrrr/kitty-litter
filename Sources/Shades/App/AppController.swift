import CoreGraphics
import Foundation
import ShadesCore

/// The flows that tie the features together. Written only against the contracts in
/// Core and the `CatStage`, so all of it can run without windows, T3 or a microphone.
@MainActor
final class AppController {
    struct Capture: Sendable {
        var snapshot: ScreenSnapshot?
        var error: Error?
    }

    /// How long the panel waits on a look at the screen before opening anyway.
    static let panelWait: TimeInterval = 1.5
    /// How long anything waits on it at all. A stuck capture can't hold a question up.
    static let captureTimeout: TimeInterval = 4
    nonisolated private static let lineSeconds: TimeInterval = 5
    private static let settleSeconds: TimeInterval = 2
    private static let longestLine = 200

    private let backend: AgentBackend
    private let context: ScreenContextProviding
    private let voice: VoiceEngine
    private let inserter: TextInserting
    private let keys: KeyHoldMonitoring
    private let saveSettings: (Settings) -> Void
    private let stage: CatStage
    private let now: () -> Date
    private(set) var settings: Settings

    private var quick = QuickSession()
    private var watch = AgentWatch()
    private var approvals = ApprovalQueue()
    private var vocabulary: [String] = []

    private struct Reply {
        var text = ""
        var done = false
        var threadID: String?
        var note: String?
    }
    private struct HandoffOffer {
        var task: String
        var question: String
        var snapshot: ScreenSnapshot?
    }
    private struct Line {
        var text: String
        var threadID: String?
        var id: Int
    }
    private var heard: String?
    private var approvalsOnShow = false
    private var approvalsHidden = false
    private var catIsAway = false
    private var handoff: HandoffOffer?
    private var reply: Reply?
    private var line: Line?
    private var lineCounter = 0
    private var replyGeneration = 0

    private enum VoiceMode {
        case talk, dictate
    }
    private var voiceMode: VoiceMode?
    private var hearing = false
    private var voiceProblem: Error?
    private var talkLook: Task<Capture, Never>?
    private var openingAsk = false
    private var picking = false
    private var fixIsOpen = false

    // Exposed so tests can wait on a flow to finish.
    private(set) var flow: Task<Void, Never>?
    private(set) var replyTask: Task<Void, Never>?
    private(set) var frontierTask: Task<Void, Never>?
    private(set) var voiceTask: Task<Void, Never>?
    private var listeners: [Task<Void, Never>] = []

    init(dependencies: AppDependencies, stage: CatStage, now: @escaping () -> Date = Date.init) {
        backend = dependencies.backend
        context = dependencies.context
        voice = dependencies.voice
        inserter = dependencies.inserter
        keys = dependencies.keys
        settings = dependencies.settings
        saveSettings = dependencies.saveSettings
        self.stage = stage
        self.now = now
    }

    func start() {
        // The list starts by itself whenever T3 does, so this only needs saying once.
        let updates = backend.watchThreads()
        // The voice engine's streams last as long as it does, and cancelling a consumer
        // would end them for good. So they're heard once, here, and never let go.
        let partials = voice.partials
        let levels = voice.levels
        listeners = [
            Task { [weak self] in
                for await threads in updates { self?.threadsChanged(threads) }
            },
            Task { [weak self] in
                for await text in partials { self?.heardSoFar(text) }
            },
            Task { [weak self] in
                for await level in levels { self?.levelHeard(level) }
            },
        ]

        Task { await connect() }
        prepareVoice()
        voice.setVocabulary(settings.vocabulary)
        keys.onPress = { [weak self] key in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.keyPressed(key) } }
        }
        keys.onRelease = { [weak self] key in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.keyReleased(key) } }
        }
        startKeys()
    }

    private func startKeys() {
        let held = [settings.talkKey, settings.dictateKey].filter { $0 != .off }
        do {
            try keys.start(keys: held)
        } catch {
            say(CatWords.problem(error, while: .keys))
        }
    }

    func shortcutTaken(_ label: String) {
        say(CatWords.shortcutTaken(label))
    }

    private func prepareVoice() {
        voiceProblem = nil
        Task { [voice] in
            do {
                try await voice.prepare()
            } catch {
                self.voiceProblem = error
            }
        }
    }

    // MARK: - Ask

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

    private func askCaption(_ capture: Capture) -> String? {
        if let error = capture.error { return CatWords.problem(error, while: .seeing) }
        guard let snapshot = capture.snapshot else { return CatWords.cantSeeScreen }
        if snapshot.isPrivate { return CatWords.privateApp }
        // Missing permissions mean missing fields rather than errors.
        if snapshot.screenshotJPEG == nil { return CatWords.needsScreenRecording }
        return CatWords.looking(at: snapshot)
    }

    func ask(_ question: String, snapshot: ScreenSnapshot?) {
        ask(question, capture: Task { Capture(snapshot: snapshot, error: nil) })
    }

    private func ask(_ question: String, capture: Task<Capture, Never>?) {
        replyGeneration += 1
        let generation = replyGeneration
        handoff = nil
        line = nil
        reply = Reply()
        renderBubble()
        replyTask = Task {
            let snapshot = await capture?.value.snapshot
            if generation == replyGeneration, snapshot?.isPrivate == true {
                reply?.note = CatWords.privateApp
                renderBubble()
            }
            await runQuickTurn(question, snapshot: snapshot, generation: generation)
        }
    }

    private enum TurnEnd {
        case finished
        case failed(message: String?, error: Error?, sawText: Bool)
    }

    private func runQuickTurn(_ question: String, snapshot: ScreenSnapshot?, generation: Int) async {
        let prompt = AgentPrompt(
            title: String(question.prefix(60)),
            text: Prompts.quick(question: question, snapshot: snapshot),
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

    private func consume(
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

    private func finish(_ outcome: ReplyHoldback.Outcome, question: String, snapshot: ScreenSnapshot?, generation: Int) {
        // The ten minutes run from the last time the thread was used.
        if let threadID = quick.thread(at: now()) { quick.use(threadID, at: now()) }
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
            handoff = HandoffOffer(task: task, question: question, snapshot: snapshot)
            renderBubble()
        }
    }

    // MARK: - Handing off

    private var frontierName: String { ModelNames.friendly(settings.frontierModel) }

    private func acceptHandoff() {
        guard let offer = handoff else { return }
        handoff = nil
        let snapshot = offer.snapshot
        let path = saveScreenshot(of: snapshot)
        // The task is the quick agent's reading of it, and the question is what you really said.
        let request = "\(offer.task)\n\nTheir own words: \(offer.question)"
        startFrontier(
            title: offer.task,
            text: Prompts.frontier(request: request, snapshot: snapshot, screenshotPath: path),
            snapshot: snapshot
        )
    }

    private func saveScreenshot(of snapshot: ScreenSnapshot?) -> String? {
        guard let snapshot, !snapshot.isPrivate else { return nil }
        return (try? context.saveScreenshot(of: snapshot)) ?? nil
    }

    private func attachments(for snapshot: ScreenSnapshot?) -> [AgentAttachment] {
        guard let snapshot, !snapshot.isPrivate, let jpeg = snapshot.screenshotJPEG else { return [] }
        return [AgentAttachment(name: "screen.jpg", mimeType: "image/jpeg", data: jpeg)]
    }

    private func startFrontier(title: String, text: String, snapshot: ScreenSnapshot?) {
        let prompt = AgentPrompt(
            title: String(title.prefix(80)),
            text: text,
            attachments: attachments(for: snapshot),
            model: settings.frontierModel,
            runtimeMode: settings.frontierMode,
            projectID: nil
        )
        say(CatWords.handingOff(modelName: frontierName), seconds: nil)
        frontierTask = Task {
            var started = false
            do {
                for try await event in backend.start(prompt) {
                    switch event {
                    case .started(let threadID):
                        started = true
                        say(CatWords.onIt(modelName: frontierName), threadID: threadID)
                    case .needsApproval(let request):
                        addApproval(request)
                    case .failed(let message):
                        say(message)
                    case .text, .finished:
                        break
                    }
                }
                if !started { say(CatWords.noReply) }
            } catch {
                say(CatWords.problem(error, while: .agents))
            }
        }
    }

    // MARK: - Fix what I'm looking at

    func fixPressed() {
        flow = Task { await beginFix() }
    }

    func beginFix() async {
        guard !picking else { return }
        picking = true
        defer { picking = false }
        stage.hideInput()
        guard let region = await context.pickRegion() else { return }
        stage.catRun(toRegion: region) {}
        let capture = await startLook(CaptureOptions(focusRegion: region)).value
        let snapshot = capture.snapshot ?? ScreenSnapshot(focusRegion: region)

        // With nothing to look at, a description is the only way it can help.
        let canSee = !snapshot.isPrivate && snapshot.screenshotJPEG != nil
        let caption: String
        if let error = capture.error {
            caption = CatWords.problem(error, while: .seeing)
        } else if snapshot.isPrivate {
            caption = CatWords.privateApp
        } else if !canSee {
            caption = CatWords.needsScreenRecording
        } else {
            caption = CatWords.fixCaption(modelName: frontierName)
        }
        fixIsOpen = true
        stage.showInput(InputRequest(
            placeholder: canSee ? CatWords.fixPlaceholder(talkKey: settings.talkKey) : CatWords.tellMeWhatsWrong,
            caption: caption,
            allowsEmpty: canSee,
            onSubmit: { [weak self] description in
                self?.fixIsOpen = false
                self?.sendFix(description, snapshot: snapshot)
            },
            onCancel: { [weak self] in
                self?.fixIsOpen = false
                self?.stage.catGoHome()
            }
        ))
    }

    private func sendFix(_ description: String, snapshot: ScreenSnapshot) {
        let said = description.isEmpty ? nil : description
        let path = saveScreenshot(of: snapshot)
        let what = said ?? snapshot.appName.map { "Something in \($0)" } ?? "Something on screen"
        startFrontier(
            title: "Fix: \(what)",
            text: Prompts.fix(description: said, snapshot: snapshot, screenshotPath: path),
            snapshot: snapshot
        )
        // A moment at the spot to say it's on it, then back home, unless it's needed elsewhere.
        Task {
            try? await Task.sleep(nanoseconds: UInt64(Self.settleSeconds * 1_000_000_000))
            if !catIsAway { stage.catGoHome() }
        }
    }

    // MARK: - Talk and dictate

    func keyPressed(_ key: HoldKey) {
        if key == settings.talkKey {
            talkDown()
        } else if key == settings.dictateKey {
            dictateDown()
        }
    }

    func keyReleased(_ key: HoldKey) {
        if key == settings.talkKey, voiceMode == .talk {
            voiceTask = Task { await talkUp() }
        } else if key == settings.dictateKey, voiceMode == .dictate {
            voiceTask = Task { await dictateUp() }
        }
    }

    private func talkDown() {
        guard voiceMode == nil else { return }
        // The look happens as the key goes down: that's the moment you mean.
        if !fixIsOpen { talkLook = startLook(CaptureOptions()) }
        guard beginListening(.talk) else {
            talkLook = nil
            return
        }
        stage.catWake()
        if !fixIsOpen {
            stage.hideInput()
            heard = ""
            renderBubble()
        }
    }

    private func talkUp() async {
        hearing = false
        stage.catLevel(0)
        heard = nil
        renderBubble()
        do {
            let transcript = try await voice.end()
            voiceMode = nil
            refreshStatus()
            let text = transcript.cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            if fixIsOpen {
                // Saying it counts as pressing Return.
                if !text.isEmpty { stage.submitInput(text) }
                return
            }
            let capture = talkLook
            talkLook = nil
            guard !text.isEmpty else {
                say(CatWords.didntCatch)
                return
            }
            ask(text, capture: capture)
        } catch {
            voiceMode = nil
            refreshStatus()
            say(CatWords.problem(error, while: .listening))
        }
    }

    private func dictateDown() {
        guard voiceMode == nil, beginListening(.dictate) else { return }
        stage.catHold(CatWords.listening)
    }

    private func dictateUp() async {
        hearing = false
        stage.catLevel(0)
        stage.catHold(nil)
        do {
            let transcript = try await voice.end()
            voiceMode = nil
            refreshStatus()
            let text = transcript.cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            do {
                try await inserter.insert(text)
            } catch {
                say(CatWords.problem(error, while: .typing))
            }
        } catch {
            voiceMode = nil
            refreshStatus()
            say(CatWords.problem(error, while: .listening))
        }
    }

    private func beginListening(_ mode: VoiceMode) -> Bool {
        do {
            try voice.begin()
        } catch {
            say(CatWords.problem(voiceProblem ?? error, while: .listening))
            if voiceProblem != nil { prepareVoice() }
            return false
        }
        voiceMode = mode
        hearing = true
        refreshStatus()
        return true
    }

    /// Esc while holding the key means forget it.
    private func cancelListening() {
        voice.cancel()
        hearing = false
        stage.catLevel(0)
        stage.catHold(nil)
        voiceMode = nil
        heard = nil
        talkLook = nil
        renderBubble()
    }

    private func heardSoFar(_ text: String) {
        guard hearing, voiceMode == .talk else { return }
        if fixIsOpen {
            stage.setInputText(text)
        } else {
            heard = text
            renderBubble()
        }
    }

    private func levelHeard(_ level: Float) {
        if hearing { stage.catLevel(level) }
    }

    // MARK: - Watching the agents

    private func connect() async {
        do {
            try await backend.connect()
        } catch {
            stage.showThreads(watch.rows(at: now()), status: CatWords.cantReachT3)
            say(CatWords.problem(error, while: .agents))
        }
    }

    func threadsChanged(_ threads: [AgentThread]) {
        let events = watch.update(threads)
        let hadApprovals = !approvals.isEmpty
        approvals.sync(with: threads)
        approvalsChanged(hadApprovals: hadApprovals)

        stage.catAgentsBusy(watch.isBusy)
        stage.showThreads(watch.rows(at: now()), status: watch.summary)
        updateVocabulary(threads)

        for event in events {
            switch event {
            case .finished(let thread):
                stage.catCelebrate()
                say(CatWords.finished(thread), threadID: thread.id)
            case .failed(let thread):
                say(CatWords.failed(thread), threadID: thread.id)
            case .hasQuestion(let thread):
                say(CatWords.hasQuestion(thread), threadID: thread.id)
            }
        }
    }

    /// Project names are the words speech recognition most often gets wrong.
    private func updateVocabulary(_ threads: [AgentThread]) {
        let words = Array(Set(settings.vocabulary + threads.compactMap(\.projectTitle))).sorted()
        guard words != vocabulary else { return }
        vocabulary = words
        voice.setVocabulary(words)
    }

    private func addApproval(_ request: ApprovalRequest) {
        let hadApprovals = !approvals.isEmpty
        approvals.add(request)
        approvalsChanged(hadApprovals: hadApprovals)
    }

    private func approvalsChanged(hadApprovals: Bool) {
        if approvals.isEmpty {
            approvalsOnShow = false
            approvalsHidden = false
            if catIsAway {
                catIsAway = false
                stage.catGoHome()
            }
        } else if !hadApprovals {
            // It comes to you first, then asks.
            approvalsOnShow = false
            approvalsHidden = false
            catIsAway = true
            stage.catComeToYou { [weak self] in
                self?.approvalsOnShow = true
                self?.renderBubble()
            }
        }
        renderBubble()
    }

    private func answer(_ request: ApprovalRequest, _ decision: ApprovalDecision) {
        let hadApprovals = !approvals.isEmpty
        approvals.answer(request.id)
        approvalsChanged(hadApprovals: hadApprovals)
        Task { [backend] in
            do {
                try await backend.respond(to: request, with: decision)
            } catch {
                let hadApprovals = !approvals.isEmpty
                approvals.restore(request)
                approvalsChanged(hadApprovals: hadApprovals)
                say(CatWords.approvalFailed)
            }
        }
    }

    // MARK: - The bubble

    func bubbleAction(_ action: BubbleAction) {
        switch action {
        case .open(let threadID):
            backend.open(threadID: threadID)
        case .copy(let text):
            stage.copyToPasteboard(text)
        case .approval(let request, let decision):
            answer(request, decision)
        case .acceptHandoff:
            acceptHandoff()
        case .declineHandoff:
            handoff = nil
            renderBubble()
        }
    }

    /// Esc means "not now" for anything. A click somewhere else is softer: it can't lose
    /// an approval, and you may well be working while a reply is on the way.
    func bubbleDismissed(byClick: Bool) {
        guard let content = currentBubble else { return }
        switch content {
        case .listening:
            if !byClick { cancelListening() }
            return
        case .approval:
            guard !byClick else { return }
            approvalsHidden = true
        case .handoff:
            handoff = nil
        case .thinking:
            guard !byClick else { return }
            reply = nil
            replyGeneration += 1
        case .reply:
            reply = nil
            replyGeneration += 1
        case .line:
            line = nil
        }
        renderBubble()
    }

    private var currentBubble: BubbleContent? {
        if let heard { return .listening(heard) }
        if approvalsOnShow, !approvalsHidden, let request = approvals.first {
            return .approval(request, position: approvals.position, total: approvals.total)
        }
        if let handoff { return .handoff(task: handoff.task, modelName: frontierName) }
        if let reply {
            if reply.text.isEmpty { return .thinking(note: reply.note) }
            return .reply(text: reply.text, done: reply.done, threadID: reply.threadID, note: reply.note)
        }
        if let line { return .line(line.text, threadID: line.threadID) }
        return nil
    }

    private func renderBubble() {
        stage.showBubble(currentBubble)
        refreshStatus()
    }

    private func refreshStatus() {
        let status: CatStatus
        if voiceMode != nil {
            status = .listening
        } else if !approvals.isEmpty || handoff != nil {
            status = .attention
        } else if reply?.text.isEmpty == true {
            status = .thinking
        } else if watch.needsYouCount > 0 {
            status = .attention
        } else {
            status = .none
        }
        stage.catStatus(status)
    }

    /// One short line from the cat, which clears itself unless `seconds` is `nil`.
    private func say(_ text: String, threadID: String? = nil, seconds: TimeInterval? = AppController.lineSeconds) {
        lineCounter += 1
        let id = lineCounter
        line = Line(text: String(text.prefix(Self.longestLine)), threadID: threadID, id: id)
        renderBubble()
        guard let seconds else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, self.line?.id == id else { return }
            self.line = nil
            self.renderBubble()
        }
    }

    // MARK: - The screen

    private func startLook(_ options: CaptureOptions) -> Task<Capture, Never> {
        let context = self.context
        return Task {
            let result = await firstOf(seconds: Self.captureTimeout) { () -> Capture in
                do {
                    return Capture(snapshot: try await context.snapshot(options), error: nil)
                } catch {
                    return Capture(snapshot: nil, error: error)
                }
            }
            return result ?? Capture(snapshot: nil, error: nil)
        }
    }

    // MARK: - Settings

    func openThread(_ threadID: String) {
        backend.open(threadID: threadID)
    }

    func settingsPressed() {
        stage.showSettings(settings) { [weak self] updated in
            self?.apply(updated)
        }
    }

    private func apply(_ updated: Settings) {
        let keysChanged = updated.talkKey != settings.talkKey || updated.dictateKey != settings.dictateKey
        settings = updated
        saveSettings(updated)
        updateVocabulary(watch.threads)
        if keysChanged {
            keys.stop()
            startKeys()
        }
    }
}

/// Runs `work`, giving up after a while. It keeps going in the background if it's late.
func firstOf<T: Sendable>(seconds: TimeInterval, _ work: @escaping @Sendable () async -> T) async -> T? {
    await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
        let gate = OnceGate()
        Task {
            let value = await work()
            if gate.claim() { continuation.resume(returning: value) }
        }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if gate.claim() { continuation.resume(returning: nil) }
        }
    }
}

private final class OnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}
