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
            ("dashboard", stage.dashboard.panel),
            ("kittens", stage.kittens.panel),
            ("channels", stage.channels.panel),
            ("inbox", stage.inbox.panel),
        ]
    }

    private func handle(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let word = trimmed.split(separator: " ").first.map(String.init) ?? ""
        let rest = String(trimmed.dropFirst(word.count)).trimmingCharacters(in: .whitespaces)
        switch word {
        case "help":
            print("ask [question] | fix | kittens | channels | channel needs|everyone|[kitten] | send [words] | pose [frame] | submit [text] | esc | talk | dictate | dash | settings | allow | deny | session | handoff yes|no | approval [kind] [summary] | report decision|shipped|note|long | inbox [reply|done|clear] | finish | quiet | pet | run x y | home | theme light|dark|system | private on|off | t3 on|off | screen on|off | ears on|off | menu | menuclose | windows | draw [folder] | wait [seconds] | buttons | typed | front | quit")
        case "ask":
            if rest.isEmpty {
                controller.askPressed()
            } else {
                controller.ask(rest, snapshot: ScreenSnapshot(appName: "Safari", windowTitle: "Pricing"))
            }
        case "fix":
            controller.fixPressed()
        case "submit":
            stage.input.submit(rest)
        case "esc":
            if stage.input.isVisible {
                stage.input.cancel()
            } else if stage.inbox.isVisible {
                stage.inbox.hide()
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
        case "channel":
            // channel needs | everyone | the start of a kitten's name, the same as clicking it in the sidebar.
            let kitten = Demo.kittens.first { $0.name.lowercased().hasPrefix(rest.lowercased()) }
            switch rest {
            case "needs": stage.channels.view.select(.needsYou)
            case "everyone": stage.channels.view.select(.channel(.everyone))
            default: if let kitten, !rest.isEmpty { stage.channels.view.select(.channel(.direct(kitten))) }
            }
        case "send":
            // The same as typing into Messages' box and pressing Return.
            stage.channels.view.pane.composer.send(rest)
        case "dash":
            stage.toggleDashboard()
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
            // The same as pressing the first row's buttons, so nothing has to click.
            let first = controller.inboxEntries.first { $0.questionID == nil }
            switch rest {
            case "reply":
                if let first { controller.inboxAction(.reply(first)) }
            case "done":
                if let first { controller.inboxAction(.done(id: first.id)) }
            case "clear":
                controller.inboxAction(.clear(.shipped))
            default:
                controller.inboxPressed()
            }
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
            let folder = URL(fileURLWithPath: rest.isEmpty ? "shades-windows" : rest, isDirectory: true)
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
