import AppKit
import ShadesCore

/// Plays the demo: a little script when it starts, a few menu items, and commands typed
/// on stdin, so you can try each flow without any real keys, permissions or agents.
@MainActor
final class DemoDriver {
    private let parts: Demo.Parts
    private let controller: AppController
    private let stage: AppStage

    init(parts: Demo.Parts, controller: AppController, stage: AppStage) {
        self.parts = parts
        self.controller = controller
        self.stage = stage
    }

    func start(script: Bool) {
        parts.inserter.onInsert = { [weak self] text in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.stage.catSay("typed: \(text)") }
            }
        }
        stage.menuBar.extras = [
            .init(title: "Try talking") { [weak self] in self?.hold(.talk) },
            .init(title: "Try dictating") { [weak self] in self?.hold(.dictate) },
            .init(title: "Ask for permission") { [weak self] in self?.parts.backend.requestApproval() },
            .init(title: "Ask a question") { [weak self] in self?.parts.backend.askQuestion(threadID: "demo-research") },
            .init(title: "Finish all the work") { [weak self] in self?.parts.backend.stopEverything() },
        ]
        readCommands()
        print("Demo mode. Type a command, or use the menu bar item. Try: help")
        if script {
            Task {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                parts.backend.requestApproval()
            }
        }
    }

    private enum Held {
        case talk, dictate
    }

    private func hold(_ held: Held) {
        let key = held == .talk ? controller.settings.talkKey : controller.settings.dictateKey
        parts.keys.onPress?(key)
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            parts.keys.onRelease?(key)
        }
    }

    private func readCommands() {
        let driver = self
        // A file stands in for typing, since an agent can only start the app with a plain `swift run`.
        // It quits when the file runs out, since a run left going can't be found from the agent's sandbox.
        let file = DevFlags.commandsFile
        if let file, freopen(file, "r", stdin) == nil {
            print("Couldn't read \(file)")
        }
        Thread.detachNewThread {
            while let line = readLine() {
                if line.hasPrefix("wait "), let seconds = Double(line.dropFirst(5).trimmingCharacters(in: .whitespaces)) {
                    Thread.sleep(forTimeInterval: seconds)
                    continue
                }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { driver.handle(line) }
                }
            }
            if file != nil {
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        }
    }

    private var windows: [(String, NSWindow)] {
        [
            ("cat", stage.cat.panel),
            ("bubble", stage.bubble.panel),
            ("input", stage.input.panel),
            ("kittens", stage.kittens.panel),
            ("channels", stage.channels.panel),
        ]
    }

    private func handle(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let word = trimmed.split(separator: " ").first.map(String.init) ?? ""
        let rest = String(trimmed.dropFirst(word.count)).trimmingCharacters(in: .whitespaces)
        switch word {
        case "help":
            print("ask [question] | drop pdf|[path]|[link] | select [text] | replace | fix | kittens | channels | messages | channel needs|done|everyone|[kitten] | thread | back | send [words] | pose [frame] | submit [text] | esc | talk | dictate | settings | allow | deny | session | handoff yes|no | approval [kind] [summary] | report decision|shipped|note|long | inbox [reply|done|clear] | notification | finish | quiet | pet | run x y | home | theme light|dark|system | private on|off | t3 on|off | screen on|off | ears on|off | menu | menuclose | windows | draw [folder] | wait [seconds] | buttons | typed | front | quit")
        case "ask":
            if rest.isEmpty {
                controller.askPressed()
            } else {
                controller.ask(rest, snapshot: ScreenSnapshot(appName: "Safari", windowTitle: "Pricing", selectedText: parts.inserter.selection))
            }
        case "select":
            // What's selected in the pretend app, for the next ask to read. Alone, it's a click somewhere else.
            parts.inserter.selection = rest.isEmpty ? nil : rest
        case "replace":
            // The same as pressing Replace under a rewrite.
            if case .reply(let text, true, _, _, true)? = stage.bubble.content { controller.bubbleAction(.replace(text)) }
        case "drop":
            // The same as letting go of it over the cat. `drop pdf` makes up a syllabus to drop.
            let url = rest == "pdf" ? Demo.samplePDF() : URL(string: rest)?.scheme == nil ? URL(fileURLWithPath: rest) : URL(string: rest)
            let pasteboard = NSPasteboard(name: NSPasteboard.Name("shades-demo-drop"))
            pasteboard.clearContents()
            if let url { pasteboard.writeObjects([url as NSURL]) }
            print("dropped \(url?.lastPathComponent ?? rest), taken: \(stage.cat.view.onDrop?(pasteboard) ?? false)")
        case "fix":
            controller.fixPressed()
        case "submit":
            stage.input.submit(rest)
        case "esc":
            if stage.input.isVisible {
                stage.input.cancel()
            } else {
                controller.bubbleDismissed(byClick: false)
            }
        case "clickaway":
            controller.bubbleDismissed(byClick: true)
        case "talk":
            hold(.talk)
        case "dictate":
            hold(.dictate)
        case "kittens":
            controller.kittensPressed()
        case "channels":
            controller.channelsPressed()
        case "messages":
            // The same as pressing ⌃⌘M: it opens Messages, or closes it if it's open.
            controller.messagesHotkeyPressed()
        case "channel":
            // channel needs | done | everyone | the start of a kitten's name, the same as clicking it in the sidebar.
            let kitten = Demo.kittens.first { $0.name.lowercased().hasPrefix(rest.lowercased()) }
            switch rest {
            case "needs": stage.channels.view.select(.needsYou)
            case "done": stage.channels.view.select(.done)
            case "everyone": stage.channels.view.select(.channel(.everyone))
            default: if let kitten, !rest.isEmpty { stage.channels.view.select(.channel(.direct(kitten))) }
            }
        case "thread":
            // The same as clicking the title over the last thread in the conversation that's showing.
            let view = stage.channels.view
            if case .channel(let id) = view.selection, let last = view.pane.shown.last(where: { if case .subject = $0 { true } else { false } }),
               case .subject(_, _, let threadID) = last {
                view.select(.thread(threadID, in: id))
            }
        case "back":
            stage.channels.view.select(stage.channels.view.selection.place)
        case "send":
            // The same as typing into Messages' box and pressing Return.
            stage.channels.view.pane.composer.send(rest)
        case "settings":
            controller.settingsPressed()
        case "allow", "deny", "session":
            if case .approval(let request, _, _)? = stage.bubble.content {
                let decision: ApprovalDecision = word == "allow" ? .accept : word == "deny" ? .decline : .acceptForSession
                controller.bubbleAction(.approval(request, decision))
            }
        case "question":
            parts.backend.askQuestion(threadID: rest.isEmpty ? "demo-research" : rest)
        case "approval":
            let parts = rest.split(separator: " ", maxSplits: 1).map(String.init)
            let kind = parts.first.flatMap(ApprovalKind.init(rawValue:)) ?? .command
            let threadID = kind == .fileRead ? "demo-research" : "demo-tidy"
            self.parts.backend.requestApproval(threadID: threadID, kind: kind, summary: parts.count > 1 ? parts[1] : "npm run build && npm test")
        case "report":
            parts.backend.report(rest)
        case "inbox":
            // The same as pressing a report's buttons in Messages, so nothing has to click.
            let first = controller.inboxEntries.first { $0.questionID == nil }
            switch rest {
            case "reply":
                // The same as pressing the first report's Reply: its thread opens with the box ready.
                controller.channelsPressed(selecting: .needsYou)
                if let first { stage.channels.view.pane.reply(to: first) }
            case "done":
                if let first { controller.inboxAction(.done(id: first.id)) }
            case "clear":
                controller.inboxAction(.clear(.shipped))
            default:
                controller.channelsPressed(selecting: .needsYou)
            }
        case "notification":
            // The same as clicking the last notification.
            controller.notificationClicked()
        case "finish":
            parts.backend.finish(threadID: rest.isEmpty ? "demo-tidy" : rest)
        case "quiet":
            parts.backend.stopEverything()
        case "pet":
            stage.catPet()
        case "pose":
            // pose [frame [flip]], or just "pose" to let go.
            let words = rest.split(separator: " ").map(String.init)
            stage.cat.hold(words.first.flatMap(CatFrame.init(rawValue:)).map { CatPose(frame: $0, flip: words.count > 1) })
        case "run":
            let values = rest.split(separator: " ").compactMap { Double($0) }
            if values.count == 2 { stage.cat.run(to: CGPoint(x: values[0], y: values[1])) }
        case "home":
            stage.catGoHome()
        case "theme":
            NSApp.appearance = rest == "dark" ? NSAppearance(named: .darkAqua) : rest == "light" ? NSAppearance(named: .aqua) : nil
        case "private":
            parts.context.isPrivate = rest == "on"
        case "t3":
            parts.backend.connectFails = rest == "off"
        case "screen":
            parts.context.fails = rest == "off"
        case "ears":
            parts.voice.downloading = rest == "off"
        case "windows":
            for (name, window) in windows {
                print("window \(name) id=\(window.windowNumber) visible=\(window.isVisible) key=\(window.isKeyWindow) frame=\(NSStringFromRect(window.frame)) clicks=\(!window.ignoresMouseEvents)")
            }
            print("state \(stage.cat.brain.state) pose=\(stage.cat.brain.pose.frame.rawValue) active=\(NSApp.isActive)")
        case "draw":
            // Each window draws itself into a picture, so nothing reads the screen.
            let folder = URL(fileURLWithPath: rest.isEmpty ? ".verify/shades/windows" : rest, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (name, window) in windows where window.isVisible {
                let file = folder.appendingPathComponent("\(name).png")
                let drawn = (window.contentView?.superview ?? window.contentView).flatMap { ChannelImages.png(of: $0) }
                print((try? drawn?.write(to: file)) == nil ? "couldn't draw \(name)" : "drew \(name) \(file.path)")
            }
        case "buttons":
            for case let button as QuietButton in stage.bubble.view.subviews {
                let frame = stage.bubble.panel.convertToScreen(button.convert(button.bounds, to: nil))
                print("button \(button.accessibilityLabel() ?? "") \(frame.midX) \(frame.midY)")
            }
            let text = stage.bubble.panel.convertToScreen(stage.bubble.view.textView.convert(stage.bubble.view.textView.bounds, to: nil))
            print("text \(text.minX) \(text.maxY)")
        case "typed":
            print("typed [\(stage.input.typedText)]")
        case "menu":
            stage.menuBar.popUpMenu(at: NSPoint(x: 0, y: 64), in: stage.cat.view)
        case "menuclose":
            stage.menuBar.closeMenu()
        case "front":
            print("front \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "nothing")")
        case "quit":
            NSApp.terminate(nil)
        default:
            break
        }
        fflush(stdout)
    }
}
