import AppKit
import ShadesContext
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
    private var cover: NSWindow?

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
        // What VoiceOver was asked to say, which is only ever spoken.
        BubbleController.onAnnounce = { words, priority in
            print("voiceover says\(priority == .high ? " at once" : ""): \(words.replacingOccurrences(of: "\n", with: " / "))")
            fflush(stdout)
        }
        // A reply you also sent to Steve's channel, which Messages keeps in memory only.
        if let steve = Demo.kittens.first { controller.channels.sent(DemoChannels.alsoSentEcho, in: .of(steve), alsoSent: true) }
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
        case "js":
            // Runs a line of script on the page and prints what it comes to, such as where its rows are.
            runOnPhone(rest)
        case "attach":
            // The same as taking a photo with the page's camera button: a made-up picture goes up, as the page sends one.
            guard let phone else { return print("The page isn't open. Try: phone open") }
            Task {
                print("[phone] \(await phone.runAsync(DemoPhone.attachPicture(named: rest.isEmpty ? "keyboard" : rest)))")
                fflush(stdout)
            }
        case "send":
            // The same as typing into the page's box and pressing Send.
            runOnPhone("$('words').value = \(DemoPhone.quoted(rest)); $('box').requestSubmit(); 'sent'")
        case "press":
            // The same as tapping the first button that says this.
            runOnPhone("(() => { const b = [...document.querySelectorAll('button')].find((b) => !b.disabled && !b.closest('[hidden]') && b.textContent.trim() === \(DemoPhone.quoted(rest))); if (!b) return 'no button'; b.click(); return 'pressed' })()")
        case "search":
            // The same as tapping Search and typing those words. The page asks once typing pauses, so `wait 1` first.
            runOnPhone("(() => { if ($('search').hidden) $('find').click(); $('query').value = \(DemoPhone.quoted(rest)); $('query').dispatchEvent(new Event('input')); return 'typed' })()")
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
        case "link":
            // The same as tapping a link in a message: the page shows where it goes, and opens nothing.
            runOnPhone("(() => { const a = [...$('rows').querySelectorAll('[role=link]')].find((a) => a.textContent.includes(\(DemoPhone.quoted(rest)))); if (!a) return 'no link'; a.click(); return $('linktitle').textContent + ' ' + $('linkaddress').textContent })()")
        case "unselect":
            // The same as tapping somewhere else on the page.
            runOnPhone("getSelection().removeAllRanges(); 'unselected'")
        case "close":
            phone?.close()
            phone = nil
        default:
            print("phone on | off | pair | open [place] | go [place] | attach [name] | send [words] | press [button] | search [words] | answer [words] | subscribe | text | select [words] | link [words] | unselect | close")
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
            return print("highlighted [\(words)] key=\(panel.isKeyWindow) front=\(front)")
        }
        print("no message shows [\(words)]")
    }

    /// The same as pressing a link in Messages whose words include these: the pane shows where it goes, and nothing opens.
    private func pressLink(_ words: String) {
        for view in allSubviews(of: stage.channels.panel.contentView) {
            guard let text = view as? ChannelTextView, let storage = text.textStorage else { continue }
            let range = (text.string as NSString).range(of: words)
            guard range.location != NSNotFound, let link = storage.attribute(.link, at: range.location, effectiveRange: nil) as? URL else { continue }
            text.tryToPerform(#selector(ChannelPane.ask(toOpen:)), with: link)
            let bars = allSubviews(of: stage.channels.panel.contentView).compactMap { $0 as? LinkBar }.filter { !$0.isHidden }
            return print("link bar shows \(bars.map { $0.link?.absoluteString ?? "" })")
        }
        print("no link shows [\(words)]")
    }

    /// The same as changing a control in Settings, found by its row: `setting Text size Large` picks Large,
    /// `setting Extra words Pawsniak` types that and presses Return, and a box or a button is pressed, such as
    /// `setting Do Not Disturb` or `setting #general`. Prints what each control on the page says afterwards.
    private func setting(_ words: String) {
        let controls = allSubviews(of: stage.settingsPanel.panel.contentView).filter { $0 is NSControl || $0 is QuietButton }
        func names(_ view: NSView) -> [String] {
            [view.accessibilityIdentifier(), (view as? NSButton)?.title ?? "", (view as? QuietButton)?.accessibilityLabel() ?? ""].filter { !$0.isEmpty }
        }
        let found = controls.flatMap { view in names(view).map { (view, $0) } }
            .filter { words.lowercased().hasPrefix($0.1.lowercased()) }
            .max { $0.1.count < $1.1.count }
        guard let (control, label) = found else { return print("no setting [\(words)]") }
        let choice = String(words.dropFirst(label.count)).trimmingCharacters(in: .whitespaces)
        switch control {
        case let popup as NSPopUpButton:
            guard popup.item(withTitle: choice) != nil else { return print("no choice [\(choice)] in \(label)") }
            popup.selectItem(withTitle: choice)
            popup.sendAction(popup.action, to: popup.target)
        case let box as NSButton:
            box.state = box.state == .on ? .off : .on
            box.sendAction(box.action, to: box.target)
        case let field as NSTextField:
            stage.settingsPanel.panel.makeFirstResponder(field)
            field.stringValue = choice
            field.sendAction(field.action, to: field.target)
        case let button as QuietButton:
            // A menu waits for a click, so `notifications` and `colors` stand in for picking from one.
            guard button.accessibilityRole() != .popUpButton else { return print("\(label) opens a menu: use notifications or colors") }
            button.onPress?()
        default:
            break
        }
        print("set \(label)")
        settingsShown()
    }

    /// Hands Tab, Shift-Tab, Ctrl-Tab or Space to whichever window has the keyboard, the way the key arrives there, without
    /// posting anything to the system. Prints what has the keyboard afterwards.
    private func pressKey(_ characters: String, control: Bool = false) {
        guard let (name, window) = windows.first(where: { $0.1.isKeyWindow }) else { return print("no window has the keyboard") }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: characters == "\u{19}" ? .shift : control ? .control : [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: characters == " " ? 49 : 48
            )
            event.map(window.sendEvent)
        }
        let responder = window.firstResponder
        let view = (responder as? NSTextView).flatMap { $0.isFieldEditor ? $0.delegate as? NSView : nil } ?? responder as? NSView
        let label = view?.accessibilityLabel() ?? ""
        print("focus \(name) \(label.isEmpty ? responder.map { String(describing: type(of: $0)) } ?? "nothing" : label) key=\(window.isKeyWindow) front=\(front)")
    }

    /// Each control on Settings' page as it shows now.
    private func settingsShown() {
        let panel = stage.settingsPanel
        print("settings page=\(panel.page.title) visible=\(panel.isVisible)")
        for view in allSubviews(of: panel.panel.contentView) {
            let id = view.accessibilityIdentifier()
            switch view {
            case let popup as NSPopUpButton: print("  \(id): \(popup.titleOfSelectedItem ?? "")")
            case let field as NSTextField where field.isEditable: print("  \(id): \(field.stringValue)")
            case let box as NSButton where box.allowsMixedState == false && box.title != "": print("  [\(box.state == .on ? "x" : " ")] \(box.title)")
            case let button as QuietButton where !id.isEmpty: print("  \(button.accessibilityLabel() ?? id)")
            default: break
            }
        }
    }

    /// `webpicture` presses the first web picture showing, which only shows its address, and `webpicture show` presses Show.
    private func pressPicture(_ words: String) {
        let view = stage.channels.view
        if words == "show" {
            guard let bar = [view.pane.linkBar, view.threadPane.linkBar].first(where: { !$0.isHidden && $0.isPicture }), let link = bar.link else { return print("no Show to press") }
            bar.open.onPress?()
            return print("showed \(link.absoluteString)")
        }
        let rows = view.pane.shownMessageRows + view.threadPane.shownMessageRows
        guard let row = rows.first(where: { $0.webPictures.first != nil }), let link = row.webPictures.first else { return print("no web picture shows") }
        row.onShowPicture?(link)
        let bars = [view.pane.linkBar, view.threadPane.linkBar].filter { !$0.isHidden }
        print("link bar shows \(bars.map { "\($0.title) \($0.link?.absoluteString ?? "")" })")
    }

    /// `recent` lists what Attach's menu offers, and `recent <n>` picks the nth, as choosing it from the menu does.
    private func pickRecent(_ words: String) {
        let files = controller.recentFiles()
        let items = stage.recentFiles.items(files)
        guard let number = Int(words) else {
            return items.forEach { print($0.isSeparatorItem ? "recent ---" : "recent \($0.title)\($0.isEnabled ? "" : " (a note)")") }
        }
        guard files.indices.contains(number - 1) else { return print("no recent file \(number)") }
        let view = stage.channels.view
        let taken = (view.selection.thread == nil ? view.pane : view.threadPane).composer.attach([.file(files[number - 1])])
        print("attached \(files[number - 1].lastPathComponent), taken: \(taken)")
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

    /// activity, threads, general, home, the start of a kitten's name for its channel, or a key as it is.
    private func phoneKey(_ place: String) -> String {
        if ["activity", "threads", "general", "home"].contains(place) { return place }
        // `steve/demo-steve-yesterday` is that thread, in that kitten's channel.
        let parts = place.split(separator: "/", maxSplits: 1).map(String.init)
        if parts.count == 2, let kitten = Demo.kittens.first(where: { $0.name.lowercased().hasPrefix(parts[0].lowercased()) }) {
            return PhonePlace.key(.thread(parts[1], in: .channel(.of(kitten))))
        }
        if let kitten = Demo.kittens.first(where: { $0.name.lowercased().hasPrefix(place.lowercased()) }) {
            return PhonePlace.key(.channel(.of(kitten)))
        }
        return place
    }

    /// The threads the place that's showing leads to, with the words each is shown by, top to bottom.
    private var shownThreads: [(id: String, words: String)] {
        stage.channels.view.pane.shown.compactMap { row in
            switch row {
            case .parent(let post): return (post.threadID, post.parent.text ?? "")
            case .digest(let digest): return (digest.threadID, digest.parent.text ?? "")
            case .alsoSent(let message, let threadID, _): return (threadID, message.text ?? "")
            default: return nil
            }
        }
    }

    /// What `key` takes, each named for what it does, standing in for the keys `docs/kittens.md` lists.
    private static let shortcuts: [String: MessagesShortcut] = {
        var named: [String: MessagesShortcut] = [
            "previous-thread": .previousThread, "next-thread": .nextThread,
            "previous-place": .previousPlace, "next-place": .nextPlace,
            "previous-unread": .previousUnread, "next-unread": .nextUnread,
            "back": .back, "forward": .forward, "jump": .jump, "search": .search, "esc": .escape,
            "threads": .threads, "activity": .activity, "new": .compose, "close": .close, "shortcuts": .cheatsheet,
        ]
        for number in 1...9 { named["\(number)"] = .place(number) }
        return named
    }()

    /// Whether this copy of The Kitty Litter is in front or another app is, for the output. Never another app's name,
    /// since what a journey prints goes on public pull requests.
    static func front(_ app: NSRunningApplication?) -> String {
        guard let app else { return "nothing" }
        return app.processIdentifier == NSRunningApplication.current.processIdentifier ? CatWords.appName : "another app"
    }

    private var front: String { Self.front(NSWorkspace.shared.frontmostApplication) }

    /// Which place Messages is on and which thread is open, for the output.
    private var whereMessagesIs: String {
        let view = stage.channels.view
        let place: String
        switch view.selection.place {
        case .activity: place = "activity"
        case .threads: place = "threads"
        case .channel(let id): place = view.book?.title(of: id) ?? "?"
        }
        return "place=\(place) thread=\(view.selection.thread ?? "none")"
    }

    private var windows: [(String, NSWindow)] {
        [
            ("cat", stage.cat.panel),
            ("bubble", stage.bubble.panel),
            ("input", stage.input.panel),
            ("kittens", stage.kittens.panel),
            ("channels", stage.channels.panel),
            ("pairing", stage.pairing.panel),
            ("settings", stage.settingsPanel.panel),
        ]
    }

    /// What VoiceOver can find in each window that's showing, and in The Kitty Litter's sidebar.
    private var voiceOverElements: [(window: String, view: NSView)] {
        let roots: [(String, NSView?)] = [
            ("cat", stage.cat.view),
            ("bubble", stage.bubble.view),
            ("kittens", stage.kittens.panel.contentView),
            ("sidebar", stage.channels.view.sidebar),
            ("pairing", stage.pairing.panel.contentView),
        ]
        func elements(in view: NSView) -> [NSView] {
            guard !view.isHidden else { return [] }
            return (view.isAccessibilityElement() ? [view] : []) + view.subviews.flatMap(elements)
        }
        return roots.flatMap { name, root -> [(window: String, view: NSView)] in
            guard let root, root.window?.isVisible == true else { return [] }
            return elements(in: root).map { (name, $0) }
        }
    }

    private func handle(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let word = trimmed.split(separator: " ").first.map(String.init) ?? ""
        let rest = String(trimmed.dropFirst(word.count)).trimmingCharacters(in: .whitespaces)
        switch word {
        case "help":
            print("busy | perf | ask [question] | drop pdf|[path]|[link] | select [text] | replace | fix | kittens | channels | messages | channel activity|threads|general|shades|[kitten] | thread [words] | back | also on|off | attach pdf|picture|[path] | recent [n] | webpicture [show] | key [shortcut] | keyboard on|off | tab [back|control] | space | jump [words] | search [words] | jump-down | jump-up | jump-open | scroll [points] | unread [words] | new [jump] | send [words] | draft [words] | retry | react [reaction] | pose [frame] | submit [text] | esc | talk | dictate | settings [page] | setting [row] [choice] | phone on|off|pair|open|go|send|press|search|answer|subscribe|text|select|link|unselect|close | type [words] | record [file.gif] [windows]|stop | allow | deny | session | handoff yes|no | approval [kind] [summary] | report decision|shipped|note|long | inbox [reply|done|clear] | card [button] | notification [thread] | notify-finished on|off | notifications [channel] [mute|mac [level]|phone [level]] | finish [thread] | quiet | pet | run x y | home | theme light|dark|system | themes | colors [app/name]|[file]|shades | fonts | font [name] | picture on|off | highlight [words] | link [words] | more | copy | private on|off | t3 on|off | screen on|off | ears on|off | menu | menuclose | menuitems | menupress [item] | header [button] | sidebar [button] | dnd | voiceover [window]|press [label]|menu [label] | windows | cover [beside] | draw [folder] | wait [seconds] | buttons | bubble [button] | typed | front | quit")
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
            // The same as pressing ⌃⌘B: it brings Messages in front of you, or closes it if it's already there.
            controller.messagesHotkeyPressed()
        case "channel":
            // channel activity | threads | general | shades | the start of a kitten's name, the same as clicking it in the sidebar.
            let kitten = Demo.kittens.first { $0.name.lowercased().hasPrefix(rest.lowercased()) }
            switch rest {
            case "activity": stage.channels.view.select(.activity)
            case "threads": stage.channels.view.select(.threads)
            case "general": stage.channels.view.select(.channel(.general))
            case "shades": stage.channels.view.select(.channel(.shades))
            default: if let kitten, !rest.isEmpty { stage.channels.view.select(.channel(.of(kitten))) }
            }
        case "thread":
            // The same as clicking the reply bar under the newest thread showing, or under the one whose words include these.
            let chosen = rest.isEmpty ? shownThreads.last : shownThreads.last { $0.words.localizedCaseInsensitiveContains(rest) }
            if let chosen {
                stage.channels.view.open(thread: chosen.id)
                print("thread \(chosen.id)")
            } else {
                print("no thread shows [\(rest)]")
            }
        case "back":
            // The same as the ✕ on a thread's pane.
            stage.channels.view.closeThread()
        case "key":
            // The same as pressing that shortcut in Messages, once a click into it has given it the keyboard. That
            // doesn't make Shades the active app, so `front` stays yours.
            guard let shortcut = Self.shortcuts[rest] else {
                return print("key \(Self.shortcuts.keys.sorted().joined(separator: " | "))")
            }
            let panel = stage.channels.panel
            panel.makeKey()
            let handled = panel.handle(shortcut)
            print("key \(rest) handled=\(handled) \(whereMessagesIs) key=\(panel.isKeyWindow) front=\(front)")
        case "keyboard":
            // Stands in for Keyboard navigation in System Settings, which the demo leaves as it is.
            QuietFocus.fullKeyboardAccess = { rest != "off" }
            print("keyboard navigation \(rest == "off" ? "off" : "on")")
        case "tab", "space":
            pressKey(word == "space" ? " " : rest == "back" ? "\u{19}" : "\t", control: rest == "control")
        case "jump":
            // The same as typing into ⌘K's box, which opens it first if it isn't open.
            let view = stage.channels.view
            if view.jumpBox.isHidden {
                stage.channels.panel.makeKey()
                stage.channels.panel.handle(.jump)
            }
            view.jumpBox.query = rest
            print("jump [\(rest)] \(view.jumpBox.items.map(\.title).joined(separator: ", "))")
        case "search":
            // The same as typing into ⌘F's box, which opens it first if it isn't open.
            let view = stage.channels.view
            if view.jumpBox.isHidden || view.jumpBox.mode != .search {
                stage.channels.panel.makeKey()
                stage.channels.panel.handle(.search)
            }
            // The same words again only says what it shows now, such as what T3 found since.
            if view.jumpBox.query != rest { view.jumpBox.query = rest }
            print("search [\(rest)] \(view.jumpBox.items.map { "\($0.title): \($0.found?.snippet ?? "")" }.joined(separator: " | "))")
        case "jump-down", "jump-up":
            // The arrows in ⌘K's box.
            stage.channels.view.jumpBox.move(by: word == "jump-down" ? 1 : -1)
            print("\(word) \(stage.channels.view.jumpBox.highlighted)")
        case "jump-open":
            // Return in ⌘K's box.
            stage.channels.view.jumpBox.open()
            print("jump-open \(whereMessagesIs)")
            let view = stage.channels.view
            let found = (view.threadPane.isHidden ? view.pane : view.threadPane).shownMessageRows.first(where: \.isFound)
            if let found { print("found \(found.message.id) [\((found.message.text ?? "").prefix(60))]") }
        case "also":
            // The same as clicking "Also send to #channel" under a thread's box.
            let composer = stage.channels.view.threadPane.composer
            composer.alsoSends = rest == "on"
            print("also \(composer.alsoSend.isHidden ? "isn't offered" : "\(composer.alsoSend.title) \(composer.alsoSends ? "on" : "off")")")
        case "more":
            // The same as pressing Show more under the first cut message in the thread pane, or the place without one.
            let view = stage.channels.view
            let pane = view.threadPane.isHidden ? view.pane : view.threadPane
            if let row = pane.longMessageRow { row.pressShowMore() } else { print("no message is cut") }
        case "unread":
            // The same as pressing Mark unread on the newest message whose words include these, in the thread's pane if
            // one's open.
            let view = stage.channels.view
            let pane = view.threadPane.isHidden ? view.pane : view.threadPane
            let row = pane.shownMessageRows.last { $0.onMarkUnread != nil && ($0.accessibilityLabel() ?? "").localizedCaseInsensitiveContains(rest) }
            print(row == nil ? "no message to mark unread shows [\(rest)]" : "marked unread [\(rest)]")
            row?.onMarkUnread?()
        case "new":
            // Where each pane's New line is, and whether its way up to it shows. `new jump` presses that.
            let view = stage.channels.view
            let panes = [("place", view.pane), ("thread", view.threadPane)].filter { !$0.1.isHidden }
            if rest == "jump", let (name, pane) = panes.last(where: { $0.1.jumpTitle != nil }) {
                pane.jumpToNew()
                print("jumped in \(name)")
            }
            for (name, pane) in panes {
                let line = pane.shown.firstIndex { if case .new = $0 { true } else { false } }
                print("new \(name) line=\(line.map { "\(pane.shown[$0])" } ?? "none") jump=\(pane.jumpTitle ?? "none")")
            }
        case "scroll":
            // Moves what Messages shows by that many points, up if it's negative, the way scrolling would.
            let pane = stage.channels.view.pane
            if let points = Double(rest) { pane.scrollOffset = min(max(pane.scrollOffset + points, 0), pane.scrollOffset + pane.distanceFromBottom) }
        case "send":
            // The same as typing into a box in Messages and pressing Return: the open thread's, or the place's.
            let view = stage.channels.view
            (view.selection.thread == nil ? view.pane : view.threadPane).composer.send(rest)
        case "retry":
            // The same as pressing Try again under the last of your messages that went nowhere.
            let view = stage.channels.view
            let row = (view.pane.shownMessageRows + view.threadPane.shownMessageRows).last { $0.onTryAgain != nil }
            print(row == nil ? "nothing to try again" : "tried again")
            row?.onTryAgain?()
        case "draft":
            // The same as typing into that box without sending, such as `draft @pepper how's my budget?`.
            let view = stage.channels.view
            let text = (view.selection.thread == nil ? view.pane : view.threadPane).composer.textView
            text.insertText(rest, replacementRange: NSRange(location: (text.string as NSString).length, length: 0))
        case "react":
            // The same as picking a reaction from React on the last message that takes one, such as `react thumbsUp`.
            let view = stage.channels.view
            let row = (view.pane.shownMessageRows + view.threadPane.shownMessageRows).last { $0.onReact != nil }
            guard let reaction = Reaction(rawValue: rest) else { return print("react " + Reaction.allCases.map(\.rawValue).joined(separator: " | ")) }
            print(row.map { "reacted \(reaction.emoji) to [\(($0.accessibilityLabel() ?? "").prefix(70))]" } ?? "nothing takes a reaction")
            row?.onReact?(reaction)
        case "attach":
            // The same as dropping a file onto that box: `attach pdf` makes up a syllabus, `attach picture` a picture.
            let view = stage.channels.view
            let drop: Drop? = switch rest {
            case "pdf": Demo.samplePDF().map(Drop.file)
            case "picture": Demo.samplePicture().map(Drop.picture)
            default: rest.isEmpty ? nil : .file(URL(fileURLWithPath: rest))
            }
            let taken = drop.map { (view.selection.thread == nil ? view.pane : view.threadPane).composer.attach([$0]) } ?? false
            print("attached \(drop?.name ?? rest), taken: \(taken)")
        case "settings":
            // Opens Settings from the menu, or turns to a page of it: `settings messages`.
            if let page = SettingsPanel.Page.allCases.first(where: { [$0.title.lowercased(), "\($0)"].contains(rest.lowercased()) }) {
                stage.settingsPanel.select(page)
                print("settings page \(page.title)")
            } else {
                controller.settingsPressed()
            }
        case "setting":
            setting(rest)
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
                // The same as pressing the first report's Reply: its thread opens beside its channel with the box ready.
                controller.channelsPressed(selecting: .activity)
                if let first { stage.channels.view.pane.reply(to: first) }
            case "done":
                if let first { controller.inboxAction(.done(id: first.id)) }
            case "clear":
                controller.inboxAction(.clear(.shipped))
            default:
                controller.channelsPressed(selecting: .activity)
            }
        case "card":
            // The same as clicking the button with these words on a card in Messages' main pane.
            let cards = allSubviews(of: stage.channels.view.pane).compactMap { $0 as? CardRowView }
            let button = cards.lazy.flatMap(\.buttons).first { $0.accessibilityLabel() == rest }
            guard let button else { return print("no card button [\(rest)]") }
            print(button.accessibilityPerformPress() ? "pressed \(rest)" : "didn't press \(rest)")
        case "notification":
            // The same as clicking a notification about that thread.
            controller.showInMessages(rest.isEmpty ? "demo-tidy" : rest)
        case "notify-finished":
            // The same as ticking Also when a session finishes in Settings.
            var settings = controller.settings
            settings.notifyFinished = rest != "off"
            controller.apply(settings)
        case "notifications":
            // notifications <channel> [mute | mac <level> | phone <level>], the same as picking that from the channel's
            // Notifications menu, which it prints after. The channel is named as `channel` names it.
            let words = rest.split(separator: " ").map(String.init)
            let kitten = Demo.kittens.first { $0.name.lowercased().hasPrefix(words.first?.lowercased() ?? "-") }
            let channel: ChannelID? = words.first == "general" ? .general : words.first == "shades" ? .shades : kitten.map(ChannelID.of)
            guard let channel else { return print("no channel [\(rest)]") }
            let book = controller.waiting
            let current = book.notifications[channel.settingsKey] ?? ChannelNotifications()
            var items = NotificationsMenu().items(current, phone: book.phone)
            if words.count > 1 {
                let section = words[1] == "phone" ? CatWords.notifyOn(.phone) : CatWords.notifyOn(.mac)
                let level = words.count > 2 ? NotifyLevel(rawValue: words[2]) : nil
                let picked = words[1] == "mute" ? items.first : items.drop { $0.title != section }.first { $0.title == level.map(CatWords.notifyLevel) }
                guard let picks = picked?.representedObject as? ChannelNotifications else { return print("no item [\(rest)]") }
                controller.messagesAction(.notifications(channel, picks))
                items = NotificationsMenu().items(picks, phone: book.phone)
            }
            for item in items {
                print(item.isSeparatorItem ? "notifications ---" : "notifications \(item.state == .on ? "*" : " ") \(item.title)")
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
        case "themes":
            // What Theme in Messages offers, in the order it does.
            for item in stage.themeMenu.items(controller.installedThemes(), current: controller.theme) {
                print(item.isSeparatorItem ? "theme ---" : "theme \(item.state == .on ? "*" : " ") \(item.title)\(item.isEnabled ? "" : " (a note)")")
                for theme in item.submenu?.items ?? [] {
                    print("theme   \(theme.state == .on ? "*" : " ") \(theme.title) \((theme.representedObject as? URL)?.path ?? "")")
                }
            }
        case "fonts":
            // What Font in Settings offers: the system's faces, then how many families All fonts has.
            for item in FontMenu().items(current: controller.settings.messagesFont, families: NSFontManager.shared.availableFontFamilies) {
                let more = item.submenu.map { " (\($0.items.count) families)" } ?? ""
                print(item.isSeparatorItem ? "font ---" : "font \(item.state == .on ? "*" : " ") \(item.title)\(more)\(item.isEnabled ? "" : " (not on this Mac)")")
            }
        case "font":
            // The same as picking that font from Settings' Font menu, by its name, or `font` alone for the system's.
            let items = FontMenu().items(current: controller.settings.messagesFont, families: NSFontManager.shared.availableFontFamilies)
            let picked = (items + items.compactMap(\.submenu).flatMap(\.items)).first { $0.title == (rest.isEmpty ? MessagesInk.systemFaces[0].name : rest) && $0.isEnabled }
            guard let picked else { return print("no font [\(rest)]") }
            var settings = controller.settings
            settings.messagesFont = picked.representedObject as? String
            controller.settingsEdited(settings)
            print("font \(settings.messagesFont ?? "system")")
        case "colors":
            // The same as picking a theme from that menu, by its app and name such as "Cursor/Opal Horizon", or
            // dropping a theme file onto Messages.
            let listed = controller.installedThemes().first { "\($0.app)/\($0.theme.name)" == rest }
            controller.themeChosen(rest == "shades" ? .plain : .file(listed?.file ?? URL(fileURLWithPath: (rest as NSString).expandingTildeInPath)))
            print("colors \(controller.theme.map { "\($0.name) paper=\(ColorTheme.hex($0.paper)) text=\(ColorTheme.hex($0.text)) accent=\(ColorTheme.hex($0.accent)) yours=\(ColorTheme.hex($0.yours))" } ?? CatWords.plainTheme)")
        case "picture":
            // As if you'd given it a picture with --picture, with a drawn stand-in, and shown at once.
            MessagesInk.picture = rest == "off" ? nil : DemoPicture.jpeg
            stage.channels.view.restyle()
            print("picture \(MessagesInk.picture == nil ? "off" : "on")")
        case "highlight":
            highlight(rest)
        case "link":
            pressLink(rest)
        case "webpicture":
            pressPicture(rest)
        case "recent":
            pickRecent(rest)
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
        case "voiceover":
            // voiceover [window] lists what VoiceOver finds. voiceover press|menu [label] is VO-Space or VO-Shift-M on the first it calls that.
            let action = rest.split(separator: " ", maxSplits: 1).map(String.init)
            guard let verb = action.first, verb == "press" || verb == "menu" else {
                for (window, view) in voiceOverElements where rest.isEmpty || window == rest {
                    let value = view.accessibilityValue().map { " value=\(String(describing: $0).prefix(80))" } ?? ""
                    let help = view.accessibilityHelp().map { " help=[\($0)]" } ?? ""
                    print("voiceover \(window) \(view.accessibilityRole()?.rawValue ?? "?") [\(view.accessibilityLabel() ?? "")]\(value)\(help)")
                }
                break
            }
            let label = action.count > 1 ? action[1] : ""
            guard let view = voiceOverElements.first(where: { $0.view.accessibilityLabel()?.hasPrefix(label) == true })?.view else {
                print("voiceover finds nothing called [\(label)]")
                break
            }
            let done = verb == "press" ? view.accessibilityPerformPress() : view.accessibilityPerformShowMenu()
            print("voiceover \(verb) [\(view.accessibilityLabel() ?? "")] \(done ? "done" : "refused")")
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
        case "bubble":
            // The same as clicking the bubble's button with these words.
            let button = stage.bubble.view.subviews.compactMap { $0 as? QuietButton }.first { $0.accessibilityLabel() == rest }
            print(button == nil ? "no bubble button [\(rest)]" : "pressed \(rest)")
            button?.onPress?()
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
        case "menuitems":
            // What the cat's menu and the menu bar show, with a check by what's on.
            for item in stage.menuBar.shownItems where !item.isSeparatorItem {
                print("menu \(item.state == .on ? "✓" : "-") \(item.title)")
            }
        case "menupress":
            // The same as choosing that item from the menu.
            let item = stage.menuBar.shownItems.first { $0.title == rest }
            print(item == nil ? "no menu item [\(rest)]" : "chose \(rest)")
            if let item, let action = item.action { NSApp.sendAction(action, to: item.target, from: item) }
        case "header":
            // The same as pressing a button at the top of the open thread's pane, such as Show on phone.
            let header = stage.channels.view.threadPane.subviews.compactMap { $0 as? ChannelHeader }.first
            let button = header?.subviews.compactMap { $0 as? QuietButton }.first { $0.accessibilityLabel() == rest }
            print(button == nil ? "no header button [\(rest)]" : "pressed \(rest)")
            button?.onPress?()
        case "sidebar":
            // The same as pressing a button at the foot of Messages' sidebar.
            let button = stage.channels.view.sidebar.subviews.compactMap { $0 as? QuietButton }.first { !$0.isHidden && $0.accessibilityLabel() == rest }
            print(button == nil ? "no sidebar button [\(rest)]" : "pressed \(rest)")
            button?.onPress?()
        case "dnd":
            // Where Do Not Disturb stands: the switch, the cat, and what's waiting to be caught up on.
            print("dnd \(controller.settings.doNotDisturb ? "on" : "off") cat=\(stage.cat.brain.state) away=\(controller.away.count)")
        case "cover":
            // A window standing in for your work, over Messages as clicking back into another app leaves it, or beside it.
            // Borderless, since AppKit pulls a titled window back over Messages when beside it would go off the screen.
            let window = cover ?? NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
            let frame = stage.channels.panel.frame
            window.isReleasedWhenClosed = false
            window.setFrame(rest == "beside" ? frame.offsetBy(dx: -frame.width - 1, dy: 0) : frame, display: false)
            window.orderFrontRegardless()
            cover = window
            print("cover \(NSStringFromRect(window.frame))")
        case "front":
            print("front \(front)")
        case "quit":
            NSApp.terminate(nil)
        default:
            break
        }
        fflush(stdout)
    }
}
