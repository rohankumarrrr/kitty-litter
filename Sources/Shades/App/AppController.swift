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
    static let settleSeconds: TimeInterval = 2
    private static let longestLine = 200

    let backend: AgentBackend
    let context: ScreenContextProviding
    let voice: VoiceEngine
    let inserter: TextInserting
    let keys: KeyHoldMonitoring
    let saveSettings: (Settings) -> Void
    let screenTip: () -> String?
    let stage: CatStage
    let now: () -> Date
    private(set) var settings: Settings

    var quick = QuickSession()
    var watch = AgentWatch()
    var approvals = ApprovalQueue()
    var vocabulary: [String] = []
    /// Your T3 projects, which speech recognition should expect to hear.
    var projectNames: [String] = [] {
        didSet { updateVocabulary(watch.threads) }
    }

    struct Reply {
        var text = ""
        var done = false
        var threadID: String?
        var note: String?
    }
    /// Something an agent has to tell you, which stays until you've had a chance to read it.
    struct Notice {
        var id: Int
        var caption: String
        var text: String
        var threadID: String?
        /// Set for a question, which goes away by itself once it's answered.
        var questionID: String?
    }
    struct Line {
        var text: String
        var threadID: String?
        var id: Int
    }
    var heard: String?
    var approvalsOnShow = false
    var approvalsHidden = false
    var catIsAway = false
    var reply: Reply?
    var line: Line?
    var notices: [Notice] = []
    /// Threads that are the cat's own plumbing, like writing a summary.
    var hiddenThreads: Set<String> = []
    var lineCounter = 0
    var replyGeneration = 0

    enum VoiceMode {
        case talk, dictate
    }
    var voiceMode: VoiceMode?
    var hearing = false
    var voiceProblem: Error?
    var talkLook: Task<Capture, Never>?
    var openingAsk = false
    var picking = false
    var fixIsOpen = false
    var fetchingEarsSince: Date?
    var fetchingEarsLine = false

    // Exposed so tests can wait on a flow to finish.
    var flow: Task<Void, Never>?
    var replyTask: Task<Void, Never>?
    var frontierTask: Task<Void, Never>?
    var reportTask: Task<Void, Never>?
    var voiceTask: Task<Void, Never>?
    private var listeners: [Task<Void, Never>] = []

    init(dependencies: AppDependencies, stage: CatStage, now: @escaping () -> Date = Date.init) {
        backend = dependencies.backend
        context = dependencies.context
        voice = dependencies.voice
        inserter = dependencies.inserter
        keys = dependencies.keys
        settings = dependencies.settings
        saveSettings = dependencies.saveSettings
        screenTip = dependencies.screenTip
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

    func startKeys() {
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

    func prepareVoice() {
        voiceProblem = nil
        Task { [voice] in
            do {
                try await voice.prepare()
            } catch {
                self.voiceProblem = error
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
        case .notice:
            // Clicking elsewhere shouldn't lose a question you haven't answered.
            guard let notice = notices.first, !(byClick && notice.questionID != nil) else { return }
            notices.removeFirst()
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

    var currentBubble: BubbleContent? {
        if let heard { return .listening(heard) }
        if approvalsOnShow, !approvalsHidden, let request = approvals.first {
            return .approval(request, position: approvals.position, total: approvals.total)
        }
        if let reply {
            if reply.text.isEmpty { return .thinking(note: reply.note) }
            return .reply(text: reply.text, done: reply.done, threadID: reply.threadID, note: reply.note)
        }
        if let line { return .line(line.text, threadID: line.threadID) }
        if let notice = notices.first {
            return .notice(caption: notice.caption, text: notice.text, threadID: notice.threadID)
        }
        return nil
    }

    func renderBubble() {
        stage.showBubble(currentBubble)
        refreshStatus()
    }

    func refreshStatus() {
        let status: CatStatus
        if voiceMode != nil {
            status = .listening
        } else if !approvals.isEmpty {
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
    func say(_ text: String, threadID: String? = nil, seconds: TimeInterval? = AppController.lineSeconds) {
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
