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
    let routerFolder: () -> String?
    let systemFacts: () -> HealthFacts
    let fileExists: (String) -> Bool
    let reportHealth: ([HealthFinding]) -> Void
    let saveInbox: (Inbox) throws -> Void
    let hidesTestThreads: Bool
    let notify: (NeedsYouAlert) -> Void
    let withdrawNotifications: ([String]) -> Void
    let clearNotifications: () -> Void
    let phoneKeys: PhoneKeyStoring
    let servePhone: (UInt16) async throws -> String
    let stopServingPhone: () async -> Void
    let stage: CatStage
    let now: () -> Date
    let launchedAt: Date
    let channels: ChannelFeed
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
        /// What a finished rewrite would go in place of: the selection as it was read, and its app.
        var replacing: (text: String, bundleID: String?)?
        /// Where the answer points, which the cat sits by for as long as the answer's up.
        var pointingAt: CGRect?
    }
    /// Something an agent has to tell you, which stays until you've had a chance to read it.
    struct Notice {
        var id: Int
        var caption: String
        var text: String
        var threadID: String?
        /// Set for a question, which goes away by itself once it's answered.
        var questionID: String?
        /// For a screen warning on work handed to a thread that had already finished a run, that run, which isn't the work.
        var after: String?
        /// A follow-up's warning. The list only names the run a thread last finished, so it can't say which run is
        /// carrying your words, and only the send's own turn failing takes the warning back.
        var followUp = false
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
    var reply: Reply? {
        didSet {
            if reply?.pointingAt != oldValue?.pointingAt { catFollowsReply() }
        }
    }
    var line: Line?
    var notices: [Notice] = []
    /// Threads that are the cat's own plumbing, like writing a summary.
    var hiddenThreads: Set<String> = []
    /// Threads the cat started to do real work, which may pass it on to another thread.
    var dispatchers: Set<String> = []
    /// Corrections still on their way to a session, so one that fails can only take back a mark none of the others earned.
    var correctionSends = CorrectionSends()
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
    /// Something came in while Messages was open, so the bubble mentions it once it's closed.
    var nudgeOnClose = false
    /// Counts the boxes that take what you say, so words meant for one can't land in the next.
    var boxesOpened = 0
    /// The box what's being said belongs in, fixed when the key goes down.
    var talkBox: Int?
    /// What's being said goes into Messages' box, fixed when the key goes down, as how many times Messages had
    /// closed then. Closing it again means the box you were talking to is gone.
    var talkToMessages: Int?
    var messagesClosings = 0
    var inboxSaveFailed = false
    /// Questions answered from Messages, kept out of it until the list catches up.
    var answeredQuestions: Set<String> = []
    /// The router's turn for what you said in Messages, so each waits for the one before.
    var messagesTurn: Task<Void, Never>?
    /// Messages' own conversation with the router, apart from the Ask box's, which can hold your screen.
    var messagesQuick = QuickSession()
    /// Threads no kitten owns that Messages passed your words to, and when, so their answers show in Everyone.
    /// shortcut: kept only while the app runs, so a restart takes them out of Everyone. Save the IDs with the inbox if that matters.
    var messagesThreads: [String: Date] = [:]
    var latestThreads: [AgentThread] = []
    var threadListArrived = false
    /// Everything that's had a notification since the app started, so an answer that didn't go through can't bring a second.
    var notified: Set<String> = []
    /// Those that haven't been taken back.
    var showing: Set<String> = []
    /// Messages on your phone, while it's on.
    var phone: PhoneLink?
    /// Where the phone page is on your tailnet, once Tailscale has said.
    var phoneAddress: String?
    /// The loopback port it's listening on.
    var phoneListening: UInt16?
    var phoneTask: Task<Void, Never>?
    /// What was last asked of Tailscale, so each ask waits for the one before, and turning it off always comes last.
    var phoneTailscale: Task<Void, Never>?
    /// How long Messages stays open after a phone stops looking, so going from place to place on it doesn't close it.
    var phoneGrace: TimeInterval = 20
    /// A thread can stop for a moment and pick up again, as when a reviewer it started hands back.
    /// Waiting a little before saying it's finished means that doesn't read as done.
    var reportDelay: TimeInterval = 5
    /// How long a question waits for the first list of sessions, so one asked right after launch can still be routed.
    var threadListWait: TimeInterval = 2
    /// Whether the quick thread is on its first turn, with no conversation worth keeping yet.
    var quickIsFresh = false
    var lineCounter = 0
    var replyGeneration = 0
    /// Only goes up when you ask something, unlike `replyGeneration`, which closing a reply moves on too.
    var questionsAsked = 0
    /// Generations cancelled with Esc before the reply finished. Being overtaken isn't taking something back.
    var takenBack: Set<Int> = []

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
    var dropIsOpen = false
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
        routerFolder = dependencies.routerFolder
        systemFacts = dependencies.systemFacts
        fileExists = dependencies.fileExists
        reportHealth = dependencies.reportHealth
        inbox = dependencies.inbox
        saveInbox = dependencies.saveInbox
        hidesTestThreads = dependencies.hidesTestThreads
        notify = dependencies.notify
        withdrawNotifications = dependencies.withdrawNotifications
        clearNotifications = dependencies.clearNotifications
        phoneKeys = dependencies.phoneKeys
        servePhone = dependencies.servePhone
        stopServingPhone = dependencies.stopServingPhone
        self.stage = stage
        self.now = now
        launchedAt = now()
        channels = ChannelFeed(backend: dependencies.backend, kittens: dependencies.kittens)
        channels.onChange = { [weak self] in self?.channelsChanged($0) }
        channels.waiting = { [weak self] in self?.waiting ?? Waiting() }
        channels.isUnread = { [weak self] in self?.inbox.isUnread($0) ?? false }
        channels.alsoInEveryone = { [weak self] in self?.messagesThreads ?? [:] }
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
        // Anything from before may have been answered since, and the cat says again whatever's still waiting.
        clearNotifications()
        if settings.phone { startPhone() }
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
        case .replace(let text):
            replaceSelection(with: text)
        case .approval(let request, let decision):
            answer(request, decision)
        case .openMessages:
            channelsPressed(selecting: .needsYou)
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
            takenBack.insert(replyGeneration)
            replyGeneration += 1
        case .reply:
            if !byClick && reply?.done == false { takenBack.insert(replyGeneration) }
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
            return .reply(text: reply.text, done: reply.done, threadID: reply.threadID, note: reply.note, canReplace: reply.replacing != nil)
        }
        if let line { return .line(line.text, threadID: line.threadID) }
        if let notice = notices.first {
            return .notice(caption: notice.caption, text: notice.text, threadID: notice.threadID)
        }
        if inboxNudge {
            let words = CatWords.inboxBubble(inboxEntries)
            if !words.isEmpty { return .inbox(words) }
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
        let phoneChanged = updated.phone != settings.phone
        settings = updated
        saveSettings(updated)
        updateVocabulary(watch.threads)
        if keysChanged {
            keys.stop()
            startKeys()
        }
        if phoneChanged { updated.phone ? startPhone() : stopPhone() }
    }
}
