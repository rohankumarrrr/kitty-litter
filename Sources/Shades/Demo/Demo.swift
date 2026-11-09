import AppKit
import CoreGraphics
import CryptoKit
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
    /// What was said in the threads it started, and in any you replied in, as T3 keeps it.
    private var said: [String: [Exchange]] = [:]
    /// When each canned thread last moved, which a reply into it does.
    private var moved: [String: Date] = [:]
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
        if connectFails {
            return AsyncThrowingStream { $0.finish(throwing: DemoError(errorDescription: "T3 Code isn't running. Open it and try again.")) }
        }
        print("[demo] forwarded to \(threadID) with \(attachments.count) attachments: \(Self.oneLine(text))")
        // Kept as T3 keeps it, so Messages reads your words back from the thread once it's moved.
        // T3 keeps what was attached by name, as a real echo does.
        let asked = Exchange(id: UUID().uuidString, asker: .you, askedAt: Date(), ask: Prompts.ownWords(in: text), files: Prompts.droppedNames(in: text).map { ExchangeFile(name: $0) })
        lock.withLock {
            said[threadID, default: DemoChannels.transcripts[threadID] ?? DemoBusy.transcripts[threadID] ?? []].append(asked)
            moved[threadID] = Date()
        }
        update { threads in
            guard let index = threads.firstIndex(where: { $0.id == threadID }) else { return }
            threads[index].status = .running
            threads[index].updatedAt = Date()
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

    func answer(_ question: AgentQuestion, with answers: [[String]]) async throws {
        print("[demo] answered: \(answers.map { $0.joined(separator: ", ") }.joined(separator: " | "))")
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
        return lock.withLock {
            threads + DemoChannels.threads.map { thread in
                var thread = thread
                thread.updatedAt = moved[thread.id] ?? thread.updatedAt
                return thread
            }
        }
    }

    /// Who started each thread, so passing a file on can check it, as T3 can. The ones a kitten asked another
    /// kitten in were started by that kitten's thread.
    func origin(of threadID: String) async -> ThreadOrigin? {
        guard let thread = await allThreads()?.first(where: { $0.id == threadID }) else { return nil }
        let askedBy = ["demo-steve-from-clawde": "demo-clawde-main", "demo-clawde-from-steve": "demo-steve-fonts", "demo-steve-from-pepper": "demo-pepper-plans"]
        return ThreadOrigin(title: thread.title, projectPath: thread.projectPath, startedBy: askedBy[threadID].map(ThreadOrigin.Starter.thread) ?? .person)
    }

    /// Made-up pictures, as T3 would give them: the one you sent in the logo thread, and the one in Steve's folder.
    func picture(attachmentID: String) async -> Data? {
        attachmentID == DemoChannels.sentPicture ? Demo.samplePicture() : nil
    }

    func picture(threadID: String, path: String) async -> Data? {
        (threadID, path) == DemoChannels.folderPicture ? Demo.samplePicture() : nil
    }

    func exchanges(threadID: String) async -> [Exchange]? {
        lock.withLock { said[threadID] } ?? DemoChannels.transcripts[threadID] ?? DemoBusy.transcripts[threadID] ?? []
    }

    /// As T3's search does: every thread with a message that has all the words, including threads Messages hasn't read.
    /// It takes a moment, as T3's does, so Messages can be seen looking.
    func threads(matching words: String) async -> [String]? {
        if connectFails { return nil }
        try? await Task.sleep(for: .seconds(1))
        let words = words.lowercased().split(whereSeparator: \.isWhitespace)
        var found: [String] = []
        for thread in await allThreads() ?? [] {
            let said = (await exchanges(threadID: thread.id) ?? []).flatMap { [$0.ask, $0.reply].compactMap { $0?.lowercased() } }
            if said.contains(where: { text in words.allSatisfy { text.contains($0) } }) { found.append(thread.id) }
        }
        return found
    }

    /// Hundreds more threads, with long conversations, as T3 would list them for someone who uses it all day.
    func makeBusy() {
        update { threads in
            guard !threads.contains(where: { $0.id == DemoBusy.longThread }) else { return }
            threads += DemoBusy.threads
        }
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
                moreCount: 1,
                form: AnswerForm(parts: [
                    AnswerForm.Part(
                        key: "font",
                        text: "Which pixel font should the headings use?",
                        options: ["Silkscreen (Recommended)", "Press Start 2P", "Keep the system font"],
                        values: ["Silkscreen", "Press Start 2P", "Keep the system font"],
                        takesOwnWords: true
                    ),
                    AnswerForm.Part(
                        key: "pages",
                        text: "Which pages should get it?",
                        options: ["Home", "Pricing", "Blog"],
                        values: ["home", "pricing", "blog"],
                        takesOwnWords: true,
                        picksSeveral: true
                    ),
                ])
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
            "scheduled": ("demo-morning", "Clawde: Morning check", "\(Prompts.decisionMarker) Merge the package updates? The tests pass with both."),
        ]
        guard let (threadID, title, reply) = replies[kind] else { return }
        sortedReplies[title] = reply
        // A schedule starts a thread of its own each time it runs, so it isn't listed until then.
        update { threads in
            guard !threads.contains(where: { $0.id == threadID }) else { return }
            threads.append(AgentThread(id: threadID, title: title, projectTitle: nil, status: .running, model: "claude-opus-5-5", updatedAt: Date(), runtimeMode: .auto))
        }
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
        let asked = Exchange(id: "\(threadID)-1", asker: .you, askedAt: Date(), ask: Prompts.dispatched(in: prompt.text))
        lock.withLock { said[threadID] = [asked] }
        return AsyncThrowingStream { continuation in
            Task {
                continuation.yield(.started(threadID: threadID))
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                self.lock.withLock {
                    self.said[threadID]?[0].reply = "Done."
                    self.said[threadID]?[0].repliedAt = Date()
                }
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
    static func elements(on screen: CGRect) -> [ScreenElement] {
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
    /// A made-up picture to attach: a keyboard, drawn.
    static func samplePicture() -> Data? {
        let image = NSImage(size: NSSize(width: 800, height: 500), flipped: false) { rect in
            NSColor(srgbRed: 0.18, green: 0.44, blue: 0.37, alpha: 1).setFill()
            rect.fill()
            NSColor(srgbRed: 0.96, green: 0.94, blue: 0.9, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 80, y: 150, width: 640, height: 200), xRadius: 24, yRadius: 24).fill()
            NSColor(white: 0.15, alpha: 1).setFill()
            for row in 0..<3 {
                for key in 0..<10 {
                    NSBezierPath(roundedRect: NSRect(x: 110 + key * 60, y: 180 + row * 55, width: 48, height: 42), xRadius: 6, yRadius: 6).fill()
                }
            }
            return true
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    /// The same picture as a file, as one you'd have opened lately.
    static func samplePictureFile() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("keyboard.png")
        guard let data = samplePicture(), (try? data.write(to: url)) != nil else { return nil }
        return url
    }

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

    /// Made-up theme files where T3 Code, Cursor and iTerm2 keep theirs, in a temporary folder standing in for your
    /// home, so the theme menu has something to offer without reading the real ones.
    static func sampleThemes() -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("shades-demo-themes", isDirectory: true)
        let files = [
            ".t3/userdata/themes/opal-horizon.json": ##"{ "version": 1, "name": "Opal Horizon", "appearance": "dark", "canvas": "#0C0A10", "accent": "#8A6CFF" }"##,
            ".t3/userdata/themes/paper.json": ##"{ "version": 1, "name": "Paper", "appearance": "light", "canvas": "#FBFAF7", "accent": "#B4532A" }"##,
            ".cursor/extensions/demo.opal-horizon-1.0.0/package.json": ##"{ "name": "opal-horizon", "publisher": "demo", "version": "1.0.0", "contributes": { "themes": [ { "label": "Opal Horizon", "uiTheme": "vs-dark", "path": "./themes/opal-horizon.json" } ] } }"##,
            ".cursor/extensions/demo.opal-horizon-1.0.0/themes/opal-horizon.json": ##"{ "name": "Opal Horizon", "type": "dark", "colors": { "editor.background": "#0C0A10", "editor.foreground": "#E7E4EC", "descriptionForeground": "#837D90", "sideBar.background": "#0A080D", "sideBar.border": "#FFFFFF0F", "button.background": "#7458E8" } }"##,
            "Library/Application Support/iTerm2/DynamicProfiles/opal-horizon.json": ##"{ "Profiles": [ { "Name": "Opal Horizon", "Background Color": { "Red Component": 0.047, "Green Component": 0.039, "Blue Component": 0.063 }, "Foreground Color": { "Red Component": 0.906, "Green Component": 0.894, "Blue Component": 0.925 }, "Cursor Color": { "Red Component": 0.725, "Green Component": 0.651, "Blue Component": 1 } } ] }"##,
        ]
        for (path, text) in files {
            let file = home.appendingPathComponent(path)
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(text.utf8).write(to: file)
        }
        return home
    }

    /// Enough of a team to show every state in the kitten view.
    /// A phone's half of a push subscription, which `phone subscribe` hands the page.
    static let phone = P256.KeyAgreement.PrivateKey()
    static let phoneAuth = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
    static var phoneSubscription: WebPush.Subscription {
        WebPush.Subscription(endpoint: "https://web.push.apple.com/demo-phone", p256dh: WebPush.string(phone.publicKey.x963Representation), auth: WebPush.string(phoneAuth))
    }

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
            routerFolder: { DemoChannels.routerFolder },
            notify: { print("[demo] notified: \(CatWords.notification($0)), which opens \($0.threadID)") },
            withdrawNotifications: { print("[demo] took back \($0.count) notification\($0.count == 1 ? "" : "s")") },
            // The page stays on loopback, on a free port, so it's never on your tailnet or in the real app's way.
            servePhone: { "http://127.0.0.1:\($0)" },
            stopServingPhone: { print("[demo] phone page off") },
            // Nothing leaves the Mac. The stand-in phone opens what it's sent, to show what a real one would get.
            sendPush: { request in
                let opened = request.httpBody.flatMap { try? WebPush.decrypt($0, with: Demo.phone, auth: Demo.phoneAuth) }
                print("[demo] pushed to \(request.url?.host ?? "?"): \(opened.map { String(decoding: $0, as: UTF8.self) } ?? "nothing it could open")")
                return 201
            },
            saveTheme: { print("[demo] Messages in \($0.map { "\($0.name)'s colours" } ?? "Shades' own colours"), not saved in demo mode") },
            installedThemes: {
                let home = Demo.sampleThemes()
                return ColorTheme.installed(home: home, t3Home: home.appendingPathComponent(".t3", isDirectory: true))
            },
            recentFiles: { [Demo.samplePictureFile(), Demo.samplePDF()].compactMap { $0 } },
            // Nothing leaves the Mac, so a web picture you press Show on is a made-up one.
            webPicture: { url in
                print("[demo] would fetch the picture at \(url.absoluteString)")
                return Demo.samplePicture()
            }
        )
        return Parts(dependencies: dependencies, backend: backend, context: context, voice: voice, inserter: inserter, keys: keys)
    }
}
