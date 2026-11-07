import AppKit
import ShadesCore

/// Plays the demo: a little script when it starts, a few menu items, and commands typed
/// on stdin, so you can try each flow without any real keys, permissions or agents.
@MainActor
final class DemoDriver {
    private let parts: Demo.Parts
    private let controller: AppController
    private let stage: AppStage
    private var phone: DemoPhone?
    private var recorder: DemoRecorder?

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

    /// Messages on your phone, on loopback only: `on` and `off` are the switch in Settings, `pair` shows a code, and
    /// `open` loads the page at a phone's size, pairing with the code that's showing. The rest go through the page.
    private func phone(_ line: String) {
        let word = line.split(separator: " ").first.map(String.init) ?? ""
        let rest = String(line.dropFirst(word.count)).trimmingCharacters(in: .whitespaces)
        switch word {
        case "on", "off":
            var settings = controller.settings
            settings.phone = word == "on"
            controller.apply(settings)
            Task {
                await controller.phoneTask?.value
                print("[demo] phone page \(word) \(controller.phoneAddress ?? "")")
                fflush(stdout)
            }
        case "pair":
            controller.pairPhone()
        case "open":
            guard let address = controller.phoneAddress else { return print("The phone page isn't on. Try: phone on") }
            let key = rest.isEmpty ? PhonePlace.home : phoneKey(rest)
            // As scanning the picture does: the page pairs with the code that's showing.
            let code = controller.phone?.door.pairing.map { "#pair=\($0.code)" } ?? ""
            let phone = self.phone ?? DemoPhone()
            self.phone = phone
            phone.open(URL(string: "\(address)/?key=\(key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")\(code)")!)
        case "go":
            runOnPhone("go(\(DemoPhone.quoted(phoneKey(rest))))")
        case "send":
            // The same as typing into the page's box and pressing Send.
            runOnPhone("$('words').value = \(DemoPhone.quoted(rest)); $('box').requestSubmit(); 'sent'")
        case "press":
            // The same as tapping the first button that says this.
            runOnPhone("(() => { const b = [...document.querySelectorAll('button')].find((b) => !b.disabled && !b.closest('[hidden]') && b.textContent.trim() === \(DemoPhone.quoted(rest))); if (!b) return 'no button'; b.click(); return 'pressed' })()")
        case "answer":
            // The same as typing into a question card's box.
            runOnPhone("(() => { const i = document.querySelector('.card input'); if (!i) return 'no box'; i.value = \(DemoPhone.quoted(rest)); i.dispatchEvent(new Event('input')); return 'typed' })()")
        case "subscribe":
            // What turning notifications on does, with a stand-in for the phone's push service.
            guard let phone else { return print("The page isn't open. Try: phone open") }
            let subscription = String(decoding: (try? JSONEncoder().encode(Demo.phoneSubscription)) ?? Data(), as: UTF8.self)
            Task {
                print("[phone] subscribed: \(await phone.runAsync("const r = await post('/push', \(subscription)); return r ? String(r.status) : 'unreachable'"))")
                fflush(stdout)
            }
        case "text":
            runOnPhone("document.body.innerText.split('\\n').filter((l) => l.trim()).join(' | ')")
        case "select":
            // The same as pressing and dragging over those words on the page.
            runOnPhone("(() => { const words = \(DemoPhone.quoted(rest)); const walk = document.createTreeWalker($('rows'), NodeFilter.SHOW_TEXT); for (let node = walk.nextNode(); node; node = walk.nextNode()) { const at = node.data.indexOf(words); if (at < 0) continue; const range = document.createRange(); range.setStart(node, at); range.setEnd(node, at + words.length); getSelection().removeAllRanges(); getSelection().addRange(range); return 'selected [' + getSelection().toString() + ']'; } return 'no such words' })()")
        case "unselect":
            // The same as tapping somewhere else on the page.
            runOnPhone("getSelection().removeAllRanges(); 'unselected'")
        case "close":
            phone?.close()
            phone = nil
        default:
            print("phone on | off | pair | open [place] | go [place] | send [words] | press [button] | answer [words] | subscribe | text | select [words] | unselect | close")
        }
    }

    /// `record <file.gif> <window>...` records those windows, or `phone`, until `record stop` writes the GIF.
    private func record(_ line: String) {
        if line == "stop" {
            print(recorder?.stop() ?? "Nothing's recording. Try: record <file.gif> cat bubble")
            recorder = nil
            ClickAway.isPaused = false
            stage.pointer = { NSEvent.mouseLocation }
            return
        }
        let words = line.split(separator: " ").map(String.init)
        guard let file = words.first, words.count > 1 else { return print("record <file.gif> cat | bubble | input | kittens | channels | pairing | phone ... | stop") }
        let names = Set(words.dropFirst())
        let recorder = DemoRecorder(
            file: URL(fileURLWithPath: file),
            windows: { [weak self] in
                guard let self else { return [] }
                return self.windows.compactMap { name, window in
                    guard names.contains(name), window.isVisible else { return nil }
                    // The cat is pixel art on a layer, which a drawn copy would smooth, so its own picture goes in.
                    if name == "cat", let sprite = self.stage.cat.view.layer?.contents {
                        let view = self.stage.cat.view
                        return ((sprite as! CGImage), window.convertToScreen(view.convert(view.bounds, to: nil)))
                    }
                    guard let view = window.contentView?.superview ?? window.contentView,
                          let image = ChannelImages.bitmap(of: view, scale: DemoRecorder.scale)?.cgImage
                    else { return nil }
                    return (image, window.frame)
                }
            },
            onPage: names.contains("cat"),
            phone: names.contains("phone") ? phone : nil
        )
        self.recorder = recorder
        // The person's own clicks and typing go on around the demo, and mustn't close what's being recorded.
        ClickAway.isPaused = true
        let screen = NSScreen.screens.first?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        stage.pointer = { CGPoint(x: screen.minX + screen.width * 0.55, y: screen.minY + screen.height * 0.3) }
        recorder.start()
    }

    /// The same as dragging over those words in Messages: the first message showing them gets the keyboard, the way
    /// pressing in it does, and they're selected.
    private func highlight(_ words: String) {
        let panel = stage.channels.panel
        for view in allSubviews(of: panel.contentView) {
            guard let text = view as? ChannelTextView else { continue }
            let range = (text.string as NSString).range(of: words)
            guard range.location != NSNotFound else { continue }
            panel.makeKey()
            panel.makeFirstResponder(text)
            text.setSelectedRange(range)
            return print("highlighted [\(words)] key=\(panel.isKeyWindow) front=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "nothing")")
        }
        print("no message shows [\(words)]")
    }

    private func allSubviews(of view: NSView?) -> [NSView] {
        guard let view else { return [] }
        return view.subviews + view.subviews.flatMap { allSubviews(of: $0) }
    }

    private func runOnPhone(_ script: String) {
        guard let phone else { return print("The page isn't open. Try: phone open") }
        Task {
            print("[phone] \(await phone.run(script))")
            fflush(stdout)
        }
    }

    /// needs, done, everyone, home, the start of a kitten's name for its DM, or a key as it is.
    private func phoneKey(_ place: String) -> String {
        if ["needs", "done", "everyone", "home"].contains(place) { return place }
        if let kitten = Demo.kittens.first(where: { $0.name.lowercased().hasPrefix(place.lowercased()) }) {
            return PhonePlace.key(.channel(.direct(kitten)))
        }
        return place
    }

    private var windows: [(String, NSWindow)] {
        [
            ("cat", stage.cat.panel),
            ("bubble", stage.bubble.panel),
            ("input", stage.input.panel),
            ("kittens", stage.kittens.panel),
            ("channels", stage.channels.panel),
            ("pairing", stage.pairing.panel),
        ]
    }

    private func handle(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let word = trimmed.split(separator: " ").first.map(String.init) ?? ""
        let rest = String(trimmed.dropFirst(word.count)).trimmingCharacters(in: .whitespaces)
        switch word {
        case "help":
            print("busy | perf | ask [question] | drop pdf|[path]|[link] | select [text] | replace | fix | kittens | channels | messages | channel needs|done|everyone|shades|[kitten] | thread | back | scroll [points] | send [words] | pose [frame] | submit [text] | esc | talk | dictate | settings | phone on|off|pair|open|go|send|press|answer|subscribe|text|select|unselect|close | type [words] | record [file.gif] [windows]|stop | allow | deny | session | handoff yes|no | approval [kind] [summary] | report decision|shipped|note|long | inbox [reply|done|clear] | notification | finish | quiet | pet | run x y | home | theme light|dark|system | themes | colors [app/name]|[file]|shades | highlight [words] | copy | private on|off | t3 on|off | screen on|off | ears on|off | menu | menuclose | windows | draw [folder] | wait [seconds] | buttons | typed | front | quit")
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
        case "busy":
            // Hundreds more threads, with long conversations, for timing Messages under a real load.
            parts.backend.makeBusy()
        case "perf":
            Task { await DemoBench.run(controller: controller, stage: stage) }
        case "kittens":
            controller.kittensPressed()
        case "channels":
            controller.channelsPressed()
        case "messages":
            // The same as pressing ⌃⌘B: it opens Messages, or closes it if it's open.
            controller.messagesHotkeyPressed()
        case "channel":
            // channel needs | done | everyone | shades | the start of a kitten's name, the same as clicking it in the sidebar.
            let kitten = Demo.kittens.first { $0.name.lowercased().hasPrefix(rest.lowercased()) }
            switch rest {
            case "needs": stage.channels.view.select(.needsYou)
            case "done": stage.channels.view.select(.done)
            case "everyone": stage.channels.view.select(.channel(.everyone))
            case "shades": stage.channels.view.select(.channel(.shades))
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
        case "scroll":
            // Moves what Messages shows by that many points, up if it's negative, the way scrolling would.
            let pane = stage.channels.view.pane
            if let points = Double(rest) { pane.scrollOffset = min(max(pane.scrollOffset + points, 0), pane.scrollOffset + pane.distanceFromBottom) }
        case "send":
            // The same as typing into Messages' box and pressing Return.
            stage.channels.view.pane.composer.send(rest)
        case "settings":
            controller.settingsPressed()
        case "phone":
            phone(rest)
        case "type":
            // Fills the Ask box a letter at a time, the way typing looks. `submit` with the same words sends it.
            Task {
                for count in 1...max(rest.count, 1) {
                    stage.input.setText(String(rest.prefix(count)))
                    try? await Task.sleep(nanoseconds: 45_000_000)
                }
            }
        case "record":
            record(rest)
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
        case "themes":
            // What Theme in Messages offers, in the order it does.
            for item in stage.themeMenu.items(controller.installedThemes(), current: controller.theme) {
                print(item.isSeparatorItem ? "theme ---" : "theme \(item.state == .on ? "*" : " ") \(item.title)\(item.isEnabled ? "" : " (a note)")")
                for theme in item.submenu?.items ?? [] {
                    print("theme   \(theme.state == .on ? "*" : " ") \(theme.title) \((theme.representedObject as? URL)?.path ?? "")")
                }
            }
        case "colors":
            // The same as picking a theme from that menu, by its app and name such as "Cursor/Opal Horizon", or
            // dropping a theme file onto Messages.
            let listed = controller.installedThemes().first { "\($0.app)/\($0.theme.name)" == rest }
            controller.themeChosen(rest == "shades" ? .plain : .file(listed?.file ?? URL(fileURLWithPath: (rest as NSString).expandingTildeInPath)))
            print("colors \(controller.theme.map { "\($0.name) paper=\(ColorTheme.hex($0.paper)) text=\(ColorTheme.hex($0.text)) accent=\(ColorTheme.hex($0.accent)) yours=\(ColorTheme.hex($0.yours))" } ?? CatWords.plainTheme)")
        case "highlight":
            highlight(rest)
        case "copy":
            // Where ⌘C in Messages would go and what it would copy, without copying, so your pasteboard is left alone.
            let target = NSApp.target(forAction: #selector(NSText.copy(_:)), to: nil, from: stage.channels.panel)
            let words = (target as? NSTextView).map { ($0.string as NSString).substring(with: $0.selectedRange()) }
            print("copy goes to \(target.map { String(describing: type(of: $0)) } ?? "nothing") with [\(words ?? "")] types=\((target as? NSTextView)?.writablePasteboardTypes.map(\.rawValue) ?? [])")
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
            if let phone {
                let file = folder.appendingPathComponent("phone.png")
                Task {
                    print(await phone.draw(to: file) ? "drew phone \(file.path)" : "couldn't draw phone")
                    fflush(stdout)
                }
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
