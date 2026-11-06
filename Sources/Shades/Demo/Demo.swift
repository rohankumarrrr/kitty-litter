import AppKit
import CoreGraphics
import Foundation
import ShadesCore

// `swift run shades --demo`: pretend versions of everything, so the whole app runs
// without T3, permissions or a microphone. Nothing here leaves this process.

private struct DemoError: LocalizedError {
    var errorDescription: String?
}

/// A fake T3: canned streaming replies, a running thread, an agent that asks permission and a kitten with an inbox.
final class DemoBackend: AgentBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var threads: [AgentThread]
    private var watchers: [UUID: AsyncStream<[AgentThread]>.Continuation] = [:]
    private var counter = 0
    /// What sorting a thread's report comes to, by the thread's title.
    private var sortedReplies: [String: String] = [:]
    var connectFails = false
    var onOpen: ((String) -> Void)?

    init() {
        threads = [
            AgentThread(id: "demo-tidy", title: "Steve Pawsniak: Tidy up the pricing page", projectTitle: "site", status: .running, model: "claude-opus-5-5", updatedAt: Date(), runtimeMode: .auto),
            AgentThread(id: "demo-research", title: "Compare pixel fonts", projectTitle: nil, status: .running, model: "gpt-6.1-sol", updatedAt: Date(), runtimeMode: .auto),
            AgentThread(id: "demo-login", title: "Clawde: Fix login", projectTitle: nil, status: .idle, model: "claude-opus-5-5", updatedAt: Date(), runtimeMode: .auto),
            AgentThread(id: "demo-icon", title: "Clawde: New icon", projectTitle: nil, status: .idle, model: "claude-opus-5-5", updatedAt: Date(), runtimeMode: .auto),
        ]
    }

    func connect() async throws {
        if connectFails { throw DemoError(errorDescription: "T3 Code isn't running. Open it and try again.") }
    }

    func start(_ prompt: AgentPrompt) -> AsyncThrowingStream<AgentReplyEvent, Error> {
        let id = nextID()
        print("[demo] started \(id) with \(prompt.attachments.count) attachments: \(Self.oneLine(prompt.text))")
        if prompt.text.contains("<report>") {
            let reply = sortedReplies.first { prompt.text.contains("Task: \($0.key)") }?.value ?? ""
            return AsyncThrowingStream { continuation in
                continuation.yield(.started(threadID: id))
                continuation.yield(.finished(fullText: reply))
                continuation.finish()
            }
        }
        if prompt.text.contains("started from the user's desktop cat") {
            return frontierTurn(threadID: id, prompt: prompt)
        }
        return quickTurn(threadID: id, prompt: prompt)
    }

    func followUp(threadID: String, _ prompt: AgentPrompt) -> AsyncThrowingStream<AgentReplyEvent, Error> {
        print("[demo] carried on in \(threadID) with \(prompt.attachments.count) attachments: \(Self.oneLine(prompt.text))")
        return quickTurn(threadID: threadID, prompt: prompt)
    }

    func forward(threadID: String, text: String, attachments: [AgentAttachment]) -> AsyncThrowingStream<AgentReplyEvent, Error> {
        print("[demo] forwarded to \(threadID) with \(attachments.count) attachments: \(Self.oneLine(text))")
        update { threads in
            guard let index = threads.firstIndex(where: { $0.id == threadID }) else { return }
            threads[index].status = .running
        }
        return AsyncThrowingStream { continuation in
            continuation.yield(.started(threadID: threadID))
            continuation.finish()
        }
    }

    func watchThreads() -> AsyncStream<[AgentThread]> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            watchers[id] = continuation
            let now = threads
            lock.unlock()
            continuation.yield(now)
        }
    }

    func respond(to request: ApprovalRequest, with decision: ApprovalDecision) async throws {
        print("[demo] \(decision.rawValue): \(request.summary)")
        update { threads in
            guard let index = threads.firstIndex(where: { $0.id == request.threadID }) else { return }
            threads[index].pendingApprovals.removeAll { $0.id == request.id }
        }
    }

    func answer(_ question: AgentQuestion, with answers: [String]) async throws {
        print("[demo] answered: \(answers.joined(separator: " | "))")
        update { threads in
            guard let index = threads.firstIndex(where: { $0.id == question.threadID }) else { return }
            threads[index].pendingQuestion = nil
            threads[index].status = .running
        }
    }

    func projectID(atPath path: String) async -> String? { "demo-project" }

    func report(threadID: String, run: String?) async throws -> String? {
        try? await Task.sleep(nanoseconds: 800_000_000)
        return """
        Moved the pricing page to the new grid and fixed the checkout button on small screens. \
        It's in a pull request, and the tests pass. It needs your review before it can go out.
        """
    }

    func allThreads() async -> [AgentThread]? {
        if connectFails { return nil }
        return lock.withLock { threads } + DemoChannels.threads
    }

    func exchanges(threadID: String) async -> [Exchange]? {
        DemoChannels.transcripts[threadID] ?? []
    }

    /// An agent stops to ask you something, which then shows on the dashboard too.
    func askQuestion(threadID: String) {
        update { threads in
            guard let index = threads.firstIndex(where: { $0.id == threadID }) else { return }
            threads[index].status = .waitingForAnswer
            threads[index].pendingQuestion = AgentQuestion(
                id: "demo-question-\(threadID)",
                threadID: threadID,
                threadTitle: threads[index].title,
                text: "Which pixel font should the headings use?",
                options: ["Silkscreen (Recommended)", "Press Start 2P", "Keep the system font"],
                form: AnswerForm(parts: [AnswerForm.Part(
                    key: "font",
                    text: "Which pixel font should the headings use?",
                    options: ["Silkscreen (Recommended)", "Press Start 2P", "Keep the system font"],
                    values: ["Silkscreen", "Press Start 2P", "Keep the system font"],
                    takesOwnWords: true
                )])
            )
        }
    }

    func open(threadID: String) {
        print("[demo] would open \(threadID) in T3")
        DispatchQueue.main.async { self.onOpen?(threadID) }
    }

    // MARK: - Canned behaviour

    func requestApproval(threadID: String = "demo-tidy", kind: ApprovalKind = .command, summary: String = "npm run build && npm test") {
        let id = nextID()
        update { threads in
            guard let index = threads.firstIndex(where: { $0.id == threadID }) else { return }
            threads[index].pendingApprovals.append(ApprovalRequest(
                id: id,
                threadID: threadID,
                threadTitle: threads[index].title,
                kind: kind,
                summary: summary,
                createdAt: Date()
            ))
        }
    }

    func finish(threadID: String, status: AgentStatus = .completed) {
        update { threads in
            guard let index = threads.firstIndex(where: { $0.id == threadID }) else { return }
            Self.end(&threads[index], status: status)
        }
    }

    /// The kitten with an inbox finishes a run. Its report comes to what's asked for here once it's sorted.
    func report(_ kind: String) {
        let replies = [
            "decision": ("demo-login", "Clawde: Fix login", "\(Prompts.decisionMarker) Ship the login fix? Tests pass, and it only touches the sign-in page."),
            "shipped": ("demo-icon", "Clawde: New icon", "\(Prompts.shippedMarker) The new icon is live and healthy."),
            "note": ("demo-login", "Clawde: Fix login", "\(Prompts.noteMarker) The risk is low, since nothing else uses that page."),
            "long": ("demo-login", "Clawde: Fix login", "\(Prompts.decisionMarker) \(String(repeating: "Should the sign-in page keep its old layout for now? ", count: 12))"),
        ]
        guard let (threadID, title, reply) = replies[kind] else { return }
        sortedReplies[title] = reply
        finish(threadID: threadID)
    }

    func stopEverything() {
        update { threads in
            for index in threads.indices where threads[index].status.isActive {
                Self.end(&threads[index], status: .completed)
            }
        }
    }

    private static func end(_ thread: inout AgentThread, status: AgentStatus) {
        thread.status = status
        thread.updatedAt = Date()
        thread.lastRunID = UUID().uuidString
        thread.lastRunEndedAt = thread.updatedAt
        thread.pendingQuestion = nil
    }

    private static func oneLine(_ text: String) -> String {
        String(text.split(whereSeparator: \.isNewline).joined(separator: " / ").prefix(90))
    }

    private func nextID() -> String {
        lock.lock()
        defer { lock.unlock() }
        counter += 1
        return "demo-\(counter)"
    }

    private func update(_ change: (inout [AgentThread]) -> Void) {
        lock.lock()
        change(&threads)
        let now = threads
        let targets = Array(watchers.values)
        lock.unlock()
        targets.forEach { $0.yield(now) }
    }

    private func quickTurn(threadID: String, prompt: AgentPrompt) -> AsyncThrowingStream<AgentReplyEvent, Error> {
        let question = prompt.text.components(separatedBy: "Their question: ").last ?? ""
        let reply = Self.reply(to: question)
        return AsyncThrowingStream { continuation in
            Task {
                if self.connectFails {
                    continuation.finish(throwing: DemoError(errorDescription: "T3 Code isn't running. Open it and try again."))
                    return
                }
                continuation.yield(.started(threadID: threadID))
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                var sent = ""
                for word in reply.split(separator: " ", omittingEmptySubsequences: false) {
                    let piece = sent.isEmpty ? String(word) : " \(word)"
                    sent += piece
                    continuation.yield(.text(delta: piece))
                    try? await Task.sleep(nanoseconds: 35_000_000)
                }
                continuation.yield(.finished(fullText: sent))
                continuation.finish()
            }
        }
    }

    private func frontierTurn(threadID: String, prompt: AgentPrompt) -> AsyncThrowingStream<AgentReplyEvent, Error> {
        update { threads in
            threads.insert(AgentThread(
                id: threadID,
                title: prompt.title ?? "Something for Opus",
                projectTitle: nil,
                status: .running,
                model: prompt.model.model,
                updatedAt: Date(),
                runtimeMode: .auto
            ), at: 0)
        }
        return AsyncThrowingStream { continuation in
            Task {
                continuation.yield(.started(threadID: threadID))
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                self.finish(threadID: threadID)
                continuation.yield(.finished(fullText: "Done."))
                continuation.finish()
            }
        }
    }

    private static func reply(to question: String) -> String {
        let lower = question.lowercased()
        if lower.contains("follow") || lower.contains("what you") { return "\(Prompts.routeMarker) 1" }
        if lower.contains("interview") || lower.contains("resume") { return "\(Prompts.kittenMarker) 1" }
        if lower.contains("budget") { return "\(Prompts.kittenMarker) 2" }
        if lower.contains("tighten") { return "\(Prompts.rewriteMarker) The new pricing page is live, with three plans to pick from." }
        if lower.contains("clawde") { return "\(Prompts.kittenMarker) 3" }
        if lower.hasPrefix("summarize") {
            return "It's a one-page syllabus for Intro to Statistics. Week 1 covers describing data, week 2 is probability, and the final is on December 12."
        }
        // Before the hand-off words, since "where do I change this?" is a question about the screen.
        if lower.contains("where") {
            if lower.contains("logo") { return "It's at the top left.\n\(Prompts.pointMarker) 9" }
            if lower.contains("share") { return "It's in Safari's toolbar, top right.\n\(Prompts.pointMarker) 4" }
            return "It's the Start free trial button, on the right under the Pro plan.\n\(Prompts.pointMarker) 2"
        }
        if ["fix", "change", "refactor", "build", "rewrite"].contains(where: lower.contains) {
            return "\(Prompts.handoffMarker) Fix the Buy button on the pricing page so it opens checkout."
        }
        if lower.contains("long") {
            return (1...14).map { _ in
                "The pricing page has three plans, and the middle one is highlighted because it's the one they'd like you to pick."
            }.joined(separator: " ")
        }
        if lower.contains("hello") || lower.contains("hi ") {
            return "Hi. I'm a cat. What's up?"
        }
        return "That's the pricing page in Safari. The Pro plan is $12 a month, billed yearly, and the button on the right starts a free trial."
    }
}

/// A fake pair of eyes that always sees the same pricing page.
final class DemoContext: ScreenContextProviding, @unchecked Sendable {
    var isPrivate = false
    var fails = false
    var regionCancelled = false

    func snapshot(_ options: CaptureOptions) async throws -> ScreenSnapshot {
        try await Task.sleep(nanoseconds: 80_000_000)
        // Missing permissions mean missing fields rather than errors, as with the real thing.
        if fails { return ScreenSnapshot(appName: "Safari", bundleID: "com.apple.Safari", windowTitle: "Pricing") }
        if isPrivate {
            return ScreenSnapshot(isPrivate: true)
        }
        let screen = await MainActor.run { NSScreen.screens.first?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900) }
        return ScreenSnapshot(
            appName: "Safari",
            bundleID: "com.apple.Safari",
            windowTitle: "Pricing",
            url: URL(string: "https://example.com/pricing"),
            pageText: "Pro plan, $12 a month.",
            screenshotJPEG: Self.fakeJPEG,
            focusRegion: options.focusRegion,
            screenshotArea: screen,
            elements: options.includeElements ? Self.elements(on: screen) : []
        )
    }

    /// The pricing page's heading, its trial button and its plan, and Safari's Share button just under
    /// the menu bar, where they'd sit on the main display.
    private static func elements(on screen: CGRect) -> [ScreenElement] {
        func at(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
            CGRect(x: screen.minX + screen.width * x, y: screen.maxY - screen.height * y - height, width: width, height: height)
        }
        return [
            ScreenElement(role: "heading", label: "Pricing", frame: at(0.2, 0.18, 160, 40)),
            ScreenElement(role: "button", label: "Start free trial", frame: at(0.62, 0.55, 180, 44)),
            ScreenElement(role: "text", label: "Pro plan, $12 a month", frame: at(0.6, 0.45, 220, 24)),
            ScreenElement(role: "button", label: "Share", frame: at(0.9, 0.035, 28, 28)),
        ]
    }

    func pickRegion() async -> CGRect? {
        try? await Task.sleep(nanoseconds: 300_000_000)
        if regionCancelled { return nil }
        let frame = await MainActor.run { NSScreen.screens.first?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900) }
        return CGRect(x: frame.midX - 160, y: frame.midY - 80, width: 320, height: 160)
    }

    func saveScreenshot(of snapshot: ScreenSnapshot) throws -> String? {
        snapshot.screenshotJPEG == nil ? nil : "/tmp/shades-demo-screenshot.jpg"
    }

    private static let fakeJPEG: Data = {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 3,
            hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        return rep.representation(using: .jpeg, properties: [:]) ?? Data()
    }()
}

/// A fake pair of ears that always hears the same sentence.
final class DemoVoice: VoiceEngine {
    let partials: AsyncStream<String>
    let levels: AsyncStream<Float>
    private let partialsContinuation: AsyncStream<String>.Continuation
    private let levelsContinuation: AsyncStream<Float>.Continuation
    private var feed: Task<Void, Never>?
    private let words = ["what's", "this", "button", "for"]
    private var startedAt = Date()
    var downloading = false

    init() {
        // One pair of streams for the life of the engine, the same as the real one.
        (partials, partialsContinuation) = AsyncStream.makeStream(of: String.self, bufferingPolicy: .bufferingNewest(1))
        (levels, levelsContinuation) = AsyncStream.makeStream(of: Float.self, bufferingPolicy: .bufferingNewest(1))
    }

    func prepare() async throws {}
    func setVocabulary(_ words: [String]) {}

    func begin() throws {
        if downloading { throw DemoError(errorDescription: "Still fetching my ears. Try again in a minute.") }
        startedAt = Date()
        let words = self.words
        let partialsContinuation = self.partialsContinuation
        let levelsContinuation = self.levelsContinuation
        feed = Task {
            var heard: [String] = []
            for tick in 0..<400 where !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
                levelsContinuation.yield(Float(abs(sin(Double(tick) / 3))))
                if tick % 8 == 7, heard.count < words.count {
                    heard.append(words[heard.count])
                    partialsContinuation.yield(heard.joined(separator: " "))
                }
            }
        }
    }

    func end() async throws -> Transcript {
        stop()
        return Transcript(raw: "what's this button for", cleaned: "What's this button for?", audioSeconds: Date().timeIntervalSince(startedAt), latencySeconds: 0.02)
    }

    func cancel() {
        stop()
    }

    private func stop() {
        feed?.cancel()
    }
}

final class DemoInserter: TextInserting {
    var onInsert: ((String) -> Void)?
    /// What's selected in the pretend app right now.
    var selection: String?

    func insert(_ text: String) async throws {
        print("[demo] would type: \(text)")
        onInsert?(text)
    }

    func replaceSelection(_ original: String, in bundleID: String?, with text: String) async -> Bool {
        guard original == selection else {
            print("[demo] the selection moved, so nothing was replaced")
            return false
        }
        print("[demo] would replace the selection with: \(text)")
        selection = nil
        return true
    }
}

final class DemoKeys: KeyHoldMonitoring {
    var onPress: ((HoldKey) -> Void)?
    var onRelease: ((HoldKey) -> Void)?
    func start(keys: [HoldKey]) throws {}
    func stop() {}
}

enum Demo {
    struct Parts {
        var dependencies: AppDependencies
        var backend: DemoBackend
        var context: DemoContext
        var voice: DemoVoice
        var inserter: DemoInserter
        var keys: DemoKeys
    }

    /// A made-up one-page syllabus in a temporary file, for dropping onto the cat.
    static func samplePDF() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("syllabus.pdf")
        var page = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let pdf = CGContext(url as CFURL, mediaBox: &page, nil) else { return nil }
        let text = NSAttributedString(
            string: "Intro to Statistics\nWeek 1: Describing data\nWeek 2: Probability\nFinal exam: December 12",
            attributes: [.font: NSFont.systemFont(ofSize: 18)]
        )
        let frame = CTFramesetterCreateFrame(
            CTFramesetterCreateWithAttributedString(text), CFRange(), CGPath(rect: page.insetBy(dx: 72, dy: 72), transform: nil), nil
        )
        pdf.beginPDFPage(nil)
        CTFrameDraw(frame, pdf)
        pdf.endPDFPage()
        pdf.closePDF()
        return url
    }

    /// Enough of a team to show every state in the kitten view.
    static let kittens = [
        Kitten(name: "Steve Pawsniak", role: "Professional", covers: "Their career, resume and interviews.", folder: "/demo/steve"),
        Kitten(name: "Pepper", role: "Finance", covers: "Their money.", folder: "/demo/pepper", color: 0xb3261e, seesScreen: false),
        Kitten(name: "Clawde", role: "The system", covers: "Shades and the other kittens.", folder: "/demo/clawde", color: 0xd9730d, seesScreen: false, usesInbox: true),
        Kitten(name: "Cali", role: "Scheduling", covers: "Their time.", folder: "/demo/cali", planned: true, color: 0x1e7fb3),
        Kitten(name: "Furbit", role: "Health", covers: "Their health.", folder: "/demo/furbit", planned: true, color: 0x2e9e4f),
    ]

    static func make() -> Parts {
        let backend = DemoBackend()
        let context = DemoContext()
        let voice = DemoVoice()
        let inserter = DemoInserter()
        let keys = DemoKeys()
        let dependencies = AppDependencies(
            backend: backend,
            context: context,
            voice: voice,
            inserter: inserter,
            keys: keys,
            settings: Settings(),
            saveSettings: { _ in print("[demo] settings aren't saved in demo mode") },
            kittens: { Demo.kittens },
            routerFolder: { "demo-router" },
            notify: { print("[demo] notified: \(CatWords.notification($0))") },
            withdrawNotifications: { print("[demo] took back \($0.count) notification\($0.count == 1 ? "" : "s")") },
            // The page stays on loopback, on a free port, so it's never on your tailnet or in the real app's way.
            servePhone: { "http://127.0.0.1:\($0)" },
            stopServingPhone: { print("[demo] phone page off") }
        )
        return Parts(dependencies: dependencies, backend: backend, context: context, voice: voice, inserter: inserter, keys: keys)
    }
}
