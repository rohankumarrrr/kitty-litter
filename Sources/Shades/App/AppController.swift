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
    let loadKittens: () -> [Kitten]
    let screenBlockGaps: (String) -> [String]
    let systemFacts: () -> HealthFacts
    let fileExists: (String) -> Bool
    let reportHealth: ([HealthFinding]) -> Void
    let saveInbox: (Inbox) throws -> Void
    let hidesTestThreads: Bool
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
    /// Threads the cat started to do real work, which may pass it on to another thread.
    var dispatchers: Set<String> = []
    var inbox: Inbox
    /// Threads whose report is being read and sorted, so each is only filed once.
    var filing: Set<String> = []
    /// Summaries that were already running when the app started, which nobody's following.
    var leftoverSummaries: Set<String> = []
    /// Runs that don't belong to a kitten with an inbox, so nobody reads the kittens again for them.
    var notForInbox: Set<String> = []
    var notForInboxSince = Date.distantPast
    /// Whether the bubble should mention the inbox.
    var inboxNudge = false
    var inboxReplyIsOpen = false
    /// Counts the boxes that take what you say, so words meant for one can't land in the next.
    var boxesOpened = 0
    /// The box what's being said belongs in, fixed when the key goes down.
    var talkBox: Int?
    var inboxSaveFailed = false
    var latestThreads: [AgentThread] = []
    var threadListArrived = false
    /// A thread can stop for a moment and pick up again, as when a reviewer it started hands back.
    /// Waiting a little before saying it's finished means that doesn't read as done.
    var reportDelay: TimeInterval = 5
    /// How long a question waits for the first list of sessions, so one asked right after launch can still be routed.
    var threadListWait: TimeInterval = 2
    /// The sessions the router was shown for the question it's on, in the order it saw them.
    var roster: [AgentThread] = []
    /// The kittens it was shown, in the same way.
    var kittens: [Kitten] = []
    /// Whether the quick thread is on its first turn, with no conversation worth keeping yet.
    var quickIsFresh = false
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
    var healthTask: Task<Void, Never>?
    var health: [HealthFinding]?
    var forwardTask: Task<Void, Never>?
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
        loadKittens = dependencies.kittens
        screenBlockGaps = dependencies.screenBlockGaps
        systemFacts = dependencies.systemFacts
        fileExists = dependencies.fileExists
        reportHealth = dependencies.reportHealth
        inbox = dependencies.inbox
        saveInbox = dependencies.saveInbox
        hidesTestThreads = dependencies.hidesTestThreads
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
        startInbox()
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
        case .openInbox:
            inboxPressed()
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
        case .inbox:
            // Clicking elsewhere shouldn't lose something that needs you.
            guard !byClick || !inboxEntries.contains(where: \.needsYou) else { return }
            inboxNudge = false
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
        if inboxNudge {
            let headline = CatWords.inboxHeadline(inboxEntries)
            if !headline.isEmpty { return .inbox(headline) }
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
        } else if watch.needsYouCount > 0 || inbox.entries.contains(where: \.needsYou) {
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

    func apply(_ updated: Settings) {
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
