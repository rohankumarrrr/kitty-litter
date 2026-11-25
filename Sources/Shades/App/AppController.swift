import CoreGraphics
import Foundation
import ShadesCore

@MainActor
final class AppController {
    struct Capture: Sendable {
        var snapshot: ScreenSnapshot?
        var error: Error?
    }

    static let panelWait: TimeInterval = 1.5
    static let captureTimeout: TimeInterval = 4
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
    let home: String
    let reportHealth: ([HealthFinding], String?) -> Void
    let saveInbox: (Inbox) throws -> Void
    let hidesTestThreads: Bool
    let notify: (NeedsYouAlert) -> Void
    let withdrawNotifications: ([String]) -> Void
    let clearNotifications: () -> Void
    let phoneKeys: PhoneKeyStoring
    let servePhone: (UInt16) async throws -> String
    let stopServingPhone: () async -> Void
    let sendPush: (URLRequest) async -> Int?
    let recentFiles: @Sendable () -> [URL]
    let stage: CatStage
    let now: () -> Date
    let launchedAt: Date
    let channels: ChannelFeed
    private(set) var settings: Settings

    var quick = QuickSession()
    var watch = AgentWatch()
    var approvals = ApprovalQueue()
    var vocabulary: [String] = []
    var projectNames: [String] = [] {
        didSet { updateVocabulary(watch.threads) }
    }

    struct Reply {
        var text = ""
        var done = false
        var threadID: String?
        var note: String?
        var replacing: (text: String, bundleID: String?)?
        var pointingAt: CGRect?
    }
    struct Notice {
        var id: Int
        var caption: String
        var text: String
        var threadID: String?
        var questionID: String?
        var after: String?
        var followUp = false
    }
    struct Line {
        var text: String
        var threadID: String?
        var id: Int
        var unasked = false
    }
    var heard: String?
    var approvalsOnShow = false
    var approvalsHidden = false
    var hadAskable = false
    var catIsAway = false
    var reply: Reply? {
        didSet {
            if reply?.pointingAt != oldValue?.pointingAt { catFollowsReply() }
        }
    }
    var line: Line?
    var notices: [Notice] = []
    var hiddenThreads: Set<String> = []
    var dispatchers: Set<String> = []
    var correctionSends = CorrectionSends()
    var inbox: Inbox
    var filing: Set<String> = []
    var readRuns: [String: (run: String, done: Bool)] = [:]
    var leftoverSummaries: Set<String> = []
    var notForInbox: Set<String> = []
    var notForInboxSince = Date.distantPast
    var inboxNudge = false
    var nudgeOnClose = false
    var away: [Missed] = [] {
        didSet {
            inbox.away = away
            keepInbox()
            channels.refresh()
        }
    }
    var catchingUp = false
    var awaySeen = false
    var boxesOpened = 0
    var talkBox: Int?
    var talkToMessages: Int?
    var messagesClosings = 0
    var inboxSaveFailed = false
    var knownRouterFolder: String?
    var takenShortcuts: [String] = []
    var answeredQuestions: Set<String> = []
    var messagesTurn: Task<Void, Never>?
    var lockdownTurn: Task<Void, Never>?
    var lockdownStarted: String?
    var messagesQuick = QuickSession()
    var messagesThreads: [String: Date] {
        get { inbox.messagesThreads }
        set {
            inbox.messagesThreads = newValue
            keepInbox()
        }
    }
    var catsWork: [String: Date] {
        get { inbox.catsWork }
        set {
            inbox.catsWork = newValue
            keepInbox()
        }
    }
    var onPhone: [String: Date] {
        get { inbox.onPhone }
        set {
            inbox.onPhone = newValue
            keepInbox()
        }
    }
    var latestThreads: [AgentThread] = []
    var threadListArrived = false
    var notified: Set<String> = []
    var showing: Set<String> = []
    var phone: PhoneLink?
    var phoneAddress: String?
    var phoneListening: UInt16?
    var phoneTask: Task<Void, Never>?
    var phoneTailscale: Task<Void, Never>?
    var phoneGrace: TimeInterval = 20
    var readPriorities: ([Kitten]) -> Priorities = { _ in Priorities() }
    // Outside the repo: a T3 thread can stop for a moment and pick up again, as when a reviewer it started hands back.
    var reportDelay: TimeInterval = 5
    var lineSeconds: TimeInterval = 5
    var threadListWait: TimeInterval = 2
    var t3Wait: TimeInterval = 10
    var t3StuckAfter: TimeInterval = 120
    var t3Recheck: Task<Void, Never>?
    var healthChecks = 0
    var warmDelay: Duration = .seconds(15)
    var quickIsFresh = false
    var lineCounter = 0
    var replyGeneration = 0
    var questionsAsked = 0
    var takenBack: Set<Int> = []

    enum VoiceMode {
        case talk, dictate
    }
    var voiceMode: VoiceMode?
    var takes = 0
    var longestMicTake: TimeInterval = 300
    var hearing = false
    var voiceProblem: Error?
    var talkLook: Task<Capture, Never>?
    var openingAsk = false
    var picking = false
    var fixIsOpen = false
    var dropIsOpen = false
    var fetchingEarsSince: Date?
    var fetchingEarsLine = false

    var flow: Task<Void, Never>?
    var replyTask: Task<Void, Never>?
    var frontierTask: Task<Void, Never>?
    var reportTask: Task<Void, Never>?
    var healthTask: Task<Void, Never>?
    var health: [HealthFinding]?
    var forwardTask: Task<Void, Never>?
    var changeFiling: [String: Task<Void, Never>] = [:]
    var attachTask: Task<Void, Never>?
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
        home = dependencies.home
        reportHealth = dependencies.reportHealth
        inbox = dependencies.inbox
        away = dependencies.inbox.away
        saveInbox = dependencies.saveInbox
        hidesTestThreads = dependencies.hidesTestThreads
        notify = dependencies.notify
        withdrawNotifications = dependencies.withdrawNotifications
        clearNotifications = dependencies.clearNotifications
        phoneKeys = dependencies.phoneKeys
        servePhone = dependencies.servePhone
        stopServingPhone = dependencies.stopServingPhone
        sendPush = dependencies.sendPush
        recentFiles = dependencies.recentFiles
        self.stage = stage
        self.now = now
        launchedAt = now()
        channels = ChannelFeed(backend: dependencies.backend, kittens: dependencies.kittens, web: dependencies.webPicture)
        channels.onChange = { [weak self] in self?.channelsChanged($0) }
        channels.waiting = { [weak self] in self?.waiting ?? Waiting() }
        channels.isUnread = { [weak self] in self?.inbox.isUnread($0) ?? false }
        channels.firstNew = { [weak self] thread, messages in
            self?.inbox.firstNew(in: thread, among: messages.map { ($0.id, $0.speaker == .you) })
        }
        channels.messagesThreads = { [weak self] in self?.messagesThreads ?? [:] }
        channels.isWithShades = { [weak self] in self?.isWithShades($0) ?? false }
        channels.isCatsWork = { [weak self] in self?.isCatsWork($0) ?? false }
        channels.onPhone = { [weak self] in Set(self?.onPhone.keys ?? [:].keys) }
        channels.hasPhone = { [weak self] in self?.settings.phone == true }
        channels.alsoSent = { [weak self] in Set(self?.inbox.alsoSent.keys ?? [:].keys) }
        channels.keepAlsoSent = { [weak self] in self?.keepAlsoSent($0) }
        channels.reactions = { [weak self] in self?.inbox.reactions ?? [:] }
    }

    func start() {
        let updates = backend.watchThreads()
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
        stage.showText(size: settings.textSize, font: settings.messagesFont)
        stage.catDoNotDisturb(settings.doNotDisturb)
        catchingUp = !isHolding && !away.isEmpty
        startKeys()
        startInbox()
        clearNotifications()
        if settings.phone { startPhone() }
    }

    func startKeys() {
        let held = [settings.talkKey, settings.dictateKey].filter { $0 != .off }
        do {
            try keys.start(keys: held)
        } catch {
            say(CatWords.problem(error, while: .keys), unasked: true)
        }
    }

    func shortcutTaken(_ label: String) {
        if !takenShortcuts.contains(label) { takenShortcuts.append(label) }
        say(CatWords.shortcutTaken(label), unasked: true)
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

    func bubbleAction(_ action: BubbleAction) {
        switch action {
        case .open(let threadID):
            openThread(threadID)
        case .show(let threadID):
            showInMessages(threadID)
        case .copy(let text):
            stage.copyToPasteboard(text)
        case .replace(let text):
            replaceSelection(with: text)
        case .approval(let request, let decision):
            answer(request, decision)
        case .openMessages:
            channelsPressed(selecting: .activity)
        case .settings(let pane):
            stage.openSettings(pane)
            line = nil
            renderBubble()
        }
    }

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
            guard !byClick || !catchingUp && !inboxEntries.contains(where: \.needsYou) else { return }
            inboxNudge = false
            catchingUp = false
        }
        renderBubble()
    }

    var currentBubble: BubbleContent? {
        if let heard { return .listening(heard) }
        if approvalsOnShow, !approvalsHidden, let request = askable.first {
            return .approval(request, position: approvals.position, total: approvals.position - 1 + askable.count)
        }
        if let reply {
            if reply.text.isEmpty { return .thinking(note: reply.note) }
            return .reply(text: reply.text, done: reply.done, threadID: reply.threadID, note: reply.note, canReplace: reply.replacing != nil)
        }
        if let line { return .line(line.text, threadID: line.threadID) }
        if let notice = notices.first {
            return .notice(caption: notice.caption, text: notice.text, threadID: notice.threadID, asks: notice.questionID != nil)
        }
        if catchingUp {
            let missed = awayNow
            if !missed.isEmpty { return .inbox(CatWords.whileAway(missed)) }
        }
        if inboxNudge {
            let words = inboxBubbleWords
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
        stage.showListening(in: listeningBox)
    }

    func say(_ text: String, threadID: String? = nil, fades: Bool = false, unasked: Bool = false) {
        if unasked, !mayPopUp(missed(thread: threadID, text: text)) { return }
        lineCounter += 1
        let id = lineCounter
        line = Line(text: String(text.prefix(Self.longestLine)), threadID: threadID, id: id, unasked: unasked)
        renderBubble()
        guard fades else { return }
        Task { [weak self, lineSeconds] in
            try? await Task.sleep(for: .seconds(lineSeconds))
            while let self, self.line?.id == id, self.stage.isPointerOnBubble {
                try? await Task.sleep(for: .seconds(0.5))
            }
            guard let self, self.line?.id == id else { return }
            self.line = nil
            self.renderBubble()
        }
    }

    func openThread(_ threadID: String) {
        Task {
            do { try await backend.open(threadID: threadID) } catch { say(CatWords.problem(error, while: .agents)) }
        }
    }

    func settingsPressed(overMessages: Bool = false) {
        stage.showSettings(settingsForm, overMessages: overMessages)
    }

    var settingsForm: SettingsForm {
        let channels = [SettingsForm.Channel(id: .shades, title: CatWords.shades)]
            + loadKittens().filter { !$0.planned }.map { SettingsForm.Channel(id: .of($0), title: $0.name) }
        return SettingsForm(settings: settings, channels: channels)
    }

    func settingsEdited(_ updated: Settings) {
        var updated = updated
        updated.doNotDisturb = settings.doNotDisturb
        updated.lockdown = settings.lockdown
        updated.channelNotifications = settings.channelNotifications
        apply(updated)
    }

    func apply(_ updated: Settings) {
        let keysChanged = updated.talkKey != settings.talkKey || updated.dictateKey != settings.dictateKey
        let phoneChanged = updated.phone != settings.phone
        let quietChanged = updated.doNotDisturb != settings.doNotDisturb
        let lockdownChanged = updated.lockdown?.kitten != settings.lockdown?.kitten
        let textChanged = updated.textSize != settings.textSize || updated.messagesFont != settings.messagesFont
        let openChanged = updated.openInMessages != settings.openInMessages
        settings = updated
        saveSettings(updated)
        updateVocabulary(watch.threads)
        if keysChanged {
            keys.stop()
            startKeys()
        }
        if phoneChanged {
            updated.phone ? startPhone() : stopPhone()
            channels.refresh()
        }
        if quietChanged { doNotDisturbChanged() }
        if lockdownChanged { self.lockdownChanged() }
        if textChanged {
            stage.showText(size: updated.textSize, font: updated.messagesFont)
            phone?.textSize = updated.textSize
        }
        if openChanged { renderBubble() }
        stage.settingsChanged(settingsForm)
    }
}
