import AppKit
import ShadesContext
import ShadesCore

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
            .init(title: "Try Talking") { [weak self] in self?.hold(.talk) },
            .init(title: "Try Dictating") { [weak self] in self?.hold(.dictate) },
            .init(title: "Ask for Permission") { [weak self] in self?.parts.backend.requestApproval() },
            .init(title: "Ask a Question") { [weak self] in self?.parts.backend.askQuestion(threadID: "demo-research") },
            .init(title: "Finish All the Work") { [weak self] in self?.parts.backend.stopEverything() },
        ]
        BubbleController.onAnnounce = { words, priority in
            print("voiceover says\(priority == .high ? " at once" : ""): \(words.replacingOccurrences(of: "\n", with: " / "))")
            fflush(stdout)
        }
        if let steve = Demo.kittens.first { controller.channels.sent(DemoChannels.alsoSentEcho, in: .of(steve), alsoSent: true) }
        DemoBench.markLaunch()
        readCommands()
        print(Offstage.isOn ? "Demo mode, out of sight. Type a command. Try: help" : "Demo mode. Type a command, or use the menu bar item. Try: help")
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
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        if DemoBench.missedABudget { exit(1) }
                        NSApp.terminate(nil)
                    }
                }
            }
        }
    }

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
            let code = controller.phone?.door.pairing.map { "#pair=\($0.code)" } ?? ""
            let phone = self.phone ?? DemoPhone()
            self.phone = phone
            phone.open(URL(string: "\(address)/?key=\(key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")\(code)")!)
        case "go":
            runOnPhone("go(\(DemoPhone.quoted(phoneKey(rest))))")
        case "js":
            runOnPhone(rest)
        case "attach":
            guard let phone else { return print("The page isn't open. Try: phone open") }
            Task {
                print("[phone] \(await phone.runAsync(DemoPhone.attachPicture(named: rest.isEmpty ? "keyboard" : rest)))")
                fflush(stdout)
            }
        case "send":
            runOnPhone("$('words').value = \(DemoPhone.quoted(rest)); $('box').requestSubmit(); 'sent'")
        case "press":
            runOnPhone("(() => { const b = [...document.querySelectorAll('button')].find((b) => !b.disabled && !b.closest('[hidden]') && b.textContent.trim() === \(DemoPhone.quoted(rest))); if (!b) return 'no button'; b.click(); return 'pressed' })()")
        case "search":
            runOnPhone("(() => { if ($('search').hidden) $('find').click(); $('query').value = \(DemoPhone.quoted(rest)); $('query').dispatchEvent(new Event('input')); return 'typed' })()")
        case "answer":
            runOnPhone("(() => { const i = document.querySelector('.card input'); if (!i) return 'no box'; i.value = \(DemoPhone.quoted(rest)); i.dispatchEvent(new Event('input')); return 'typed' })()")
        case "subscribe":
            guard let phone else { return print("The page isn't open. Try: phone open") }
            let subscription = String(decoding: (try? JSONEncoder().encode(Demo.phoneSubscription)) ?? Data(), as: UTF8.self)
            Task {
                print("[phone] subscribed: \(await phone.runAsync("const r = await post('/push', \(subscription)); return r ? String(r.status) : 'unreachable'"))")
                fflush(stdout)
            }
        case "text":
            runOnPhone("document.body.innerText.split('\\n').filter((l) => l.trim()).join(' | ')")
        case "select":
            runOnPhone("(() => { const words = \(DemoPhone.quoted(rest)); const walk = document.createTreeWalker($('rows'), NodeFilter.SHOW_TEXT); for (let node = walk.nextNode(); node; node = walk.nextNode()) { const at = node.data.indexOf(words); if (at < 0) continue; const range = document.createRange(); range.setStart(node, at); range.setEnd(node, at + words.length); getSelection().removeAllRanges(); getSelection().addRange(range); return 'selected [' + getSelection().toString() + ']'; } return 'no such words' })()")
        case "link":
            runOnPhone("(() => { const a = [...$('rows').querySelectorAll('[role=link]')].find((a) => a.textContent.includes(\(DemoPhone.quoted(rest)))); if (!a) return 'no link'; a.click(); return $('linktitle').textContent + ' ' + $('linkaddress').textContent })()")
        case "unselect":
            runOnPhone("getSelection().removeAllRanges(); 'unselected'")
        case "close":
            phone?.close()
            phone = nil
        default:
            print("phone on | off | pair | open [place] | go [place] | attach [name] | send [words] | press [button] | search [words] | answer [words] | subscribe | text | select [words] | link [words] | unselect | close")
        }
    }

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
                    // Outside the repo: AppKit's drawn copy of a view smooths a layer's pixel art.
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
        ClickAway.isPaused = true
        let screen = NSScreen.screens.first?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        stage.pointer = { CGPoint(x: screen.minX + screen.width * 0.55, y: screen.minY + screen.height * 0.3) }
        recorder.start()
    }

    private func highlight(_ words: String) {
        let panel = stage.channels.window
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

    private func pressLink(_ words: String) {
        for view in allSubviews(of: stage.channels.window.contentView) {
            guard let text = view as? ChannelTextView, let storage = text.textStorage else { continue }
            let range = (text.string as NSString).range(of: words)
            guard range.location != NSNotFound, let link = storage.attribute(.link, at: range.location, effectiveRange: nil) as? URL else { continue }
            text.tryToPerform(#selector(ChannelPane.ask(toOpen:)), with: link)
            let bars = allSubviews(of: stage.channels.window.contentView).compactMap { $0 as? LinkBar }.filter { !$0.isHidden }
            return print("link bar shows \(bars.map { $0.link?.absoluteString ?? "" })")
        }
        print("no link shows [\(words)]")
    }

    private func setting(_ words: String) {
        let controls = allSubviews(of: stage.settingsPanel.panel.contentView).filter { $0 is NSControl || $0 is QuietButton || $0 is SettingsControl }
        func names(_ view: NSView) -> [String] {
            [view.accessibilityIdentifier(), (view as? QuietButton)?.accessibilityLabel() ?? "", (view as? QuietSwitch)?.title ?? ""].filter { !$0.isEmpty }
        }
        let found = controls.flatMap { view in names(view).map { (view, $0) } }
            .filter { words.lowercased().hasPrefix($0.1.lowercased()) }
            .max { $0.1.count < $1.1.count }
        guard let (control, label) = found else { return print("no setting [\(words)]") }
        let choice = String(words.dropFirst(label.count)).trimmingCharacters(in: .whitespaces)
        switch control {
        case let toggle as QuietSwitch:
            toggle.toggle()
        case let segments as QuietSegments:
            guard segments.titles.contains(choice) else { return print("no choice [\(choice)] in \(label)") }
            segments.pick(choice)
        case let tab as SettingsTab:
            tab.onPress?()
        case let field as NSTextField:
            stage.settingsPanel.panel.makeFirstResponder(field)
            field.stringValue = choice
            field.sendAction(field.action, to: field.target)
        case let button as QuietButton where button.accessibilityRole() == .popUpButton:
            guard let menu = button.menu else { return print("\(label) opens a menu: use notifications or font") }
            guard let index = menu.items.firstIndex(where: { $0.title == choice }) else { return print("no choice [\(choice)] in \(label)") }
            menu.performActionForItem(at: index)
        case let button as QuietButton:
            button.onPress?()
        default:
            break
        }
        print("set \(label)")
        settingsShown()
    }

    private func pressKey(_ characters: String, keyCode: UInt16? = nil, control: Bool = false) {
        guard let (name, window) = windows.first(where: { $0.1.isKeyWindow }) else { return print("no window has the keyboard") }
        if characters == " ", let button = window.firstResponder as? QuietButton, button.accessibilityRole() == .popUpButton {
            return print("space on \(button.accessibilityLabel() ?? "") would open its menu: use setting")
        }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: characters == "\u{19}" ? .shift : control ? .control : [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: keyCode ?? (characters == " " ? 49 : 48)
            )
            event.map(window.sendEvent)
        }
        let responder = window.firstResponder
        let view = (responder as? NSTextView).flatMap { $0.isFieldEditor ? $0.delegate as? NSView : nil } ?? responder as? NSView
        let label = view?.accessibilityLabel() ?? ""
        print("focus \(name) \(label.isEmpty ? responder.map { String(describing: type(of: $0)) } ?? "nothing" : label) key=\(window.isKeyWindow) front=\(front)")
    }

    private func settingsShown() {
        let panel = stage.settingsPanel
        print("settings page=\(panel.page.title) visible=\(panel.isVisible)")
        for view in allSubviews(of: panel.panel.contentView) {
            let id = view.accessibilityIdentifier()
            switch view {
            case let field as NSTextField where field.isEditable: print("  \(id): \(field.stringValue)")
            case let toggle as QuietSwitch: print("  [\(toggle.isOn ? "x" : " ")] \(toggle.title)")
            case let segments as QuietSegments: print("  \(id): \(segments.titles[segments.selected])")
            case let button as QuietButton where !id.isEmpty: print("  \(id): \(button.accessibilityValue() as? String ?? "")")
            default: break
            }
        }
    }

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

    private func phoneKey(_ place: String) -> String {
        if ["activity", "threads", "shades", "home"].contains(place) { return place }
        let parts = place.split(separator: "/", maxSplits: 1).map(String.init)
        if parts.count == 2, let kitten = Demo.kittens.first(where: { $0.name.lowercased().hasPrefix(parts[0].lowercased()) }) {
            return PhonePlace.key(.thread(parts[1], in: .channel(.of(kitten))))
        }
        if let kitten = Demo.kittens.first(where: { $0.name.lowercased().hasPrefix(place.lowercased()) }) {
            return PhonePlace.key(.channel(.of(kitten)))
        }
        return place
    }

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

    private static let shortcuts: [String: MessagesShortcut] = {
        var named: [String: MessagesShortcut] = [
            "previous-thread": .previousThread, "next-thread": .nextThread,
            "previous-place": .previousPlace, "next-place": .nextPlace,
            "previous-unread": .previousUnread, "next-unread": .nextUnread, "mark-all-read": .markAllRead,
            "back": .back, "forward": .forward, "jump": .jump, "search": .search, "esc": .escape,
            "threads": .threads, "activity": .activity, "new": .compose, "close": .close, "shortcuts": .cheatsheet, "sidebar": .toggleSidebar,
        ]
        for number in 1...9 { named["\(number)"] = .place(number) }
        return named
    }()

    private static func subviews(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(subviews)
    }

    static func front(_ app: NSRunningApplication?) -> String {
        guard let app else { return "nothing" }
        return app.processIdentifier == NSRunningApplication.current.processIdentifier ? CatWords.appName : "another app"
    }

    private var front: String { Self.front(NSWorkspace.shared.frontmostApplication) }

    private var whereMessagesIs: String {
        let view = stage.channels.view
        let place: String
        switch view.selection.place {
        case .activity: place = "activity"
        case .threads: place = "threads"
        case .channel(let id): place = view.book?.name(of: id) ?? "?"
        }
        return "place=\(place) thread=\(view.selection.thread ?? "none")"
    }

    private var windows: [(String, NSWindow)] {
        [
            ("cat", stage.cat.panel),
            ("bubble", stage.bubble.panel),
            ("input", stage.input.panel),
            ("kittens", stage.kittens.panel),
            ("channels", stage.channels.window),
            ("pairing", stage.pairing.panel),
            ("settings", stage.settingsPanel.panel),
            ("pill", stage.pill.panel),
        ]
    }

    private var voiceOverElements: [(window: String, view: NSView)] {
        let roots: [(String, NSView?)] = [
            ("cat", stage.cat.view),
            ("bubble", stage.bubble.view),
            ("kittens", stage.kittens.panel.contentView),
            ("sidebar", stage.channels.view.sidebar),
            ("input", stage.input.panel.contentView),
            ("box", stage.channels.view.pane.composer),
            ("threadbox", stage.channels.view.threadPane.composer),
            ("pairing", stage.pairing.panel.contentView),
        ]
        func elements(in view: NSView) -> [NSView] {
            guard !view.isHidden else { return [] }
            return (view.isAccessibilityElement() ? [view] : []) + view.subviews.flatMap(elements)
        }
        return roots.flatMap { name, root -> [(window: String, view: NSView)] in
            guard let root, root.window?.isVisible == true, !root.isHiddenOrHasHiddenAncestor else { return [] }
            return elements(in: root).map { (name, $0) }
        }
    }

    private func handle(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let word = trimmed.split(separator: " ").first.map(String.init) ?? ""
        let rest = String(trimmed.dropFirst(word.count)).trimmingCharacters(in: .whitespaces)
        switch word {
        case "help":
            print("busy | perf [messages|cat|phone|launch|idle seconds] | ask [question] | drop pdf|[path]|[link] | select [text] | replace | fix | kittens | channels | messages | channel activity|threads|shades|[kitten] | thread [reply] [words] | back | also on|off | attach pdf|picture|[path] | recent [n] | webpicture [show] | key [shortcut] | keyboard on|off | tab [back|control] | arrow up|down | space | jump [words] | search [words] | jump-down | jump-up | jump-open | scroll [points] | unread [words] | read [place|words] | places | toolbar [button] | new [jump] | send [words] | draft [words] | retry | react [reaction] | pose [frame] | submit [text] | esc | talk | dictate | settings [page] | setting [row] [choice] | phone on|off|pair|open|go|send|press|search|answer|subscribe|text|select|link|unselect|close | type [words] | record [file.gif] [windows]|stop | allow | deny | session | handoff yes|no | approval [kind] [summary] | report decision|shipped|note|long|asks|ask|change|plain [waiting] | inbox [reply|done|clear] | card [button] | notification [thread] | notify-finished on|off | notifications [channel] [mute|mac [level]|phone [level]] | finish [thread] | quiet | pet | run x y | home | fonts | font [name] | picture on|off | highlight [words] | link [words] | more | copy | private on|off | t3 on|off|stuck | check | team on|off | screen on|off | ears on|off|denied | menu | menuclose | menuitems | menupress [item] | header [button] | sidebar [button] | dnd | voiceover [window]|press [label]|menu [label] | windows | cover [beside] | draw [folder] | opal [folder] [jacket...] | wait [seconds] | buttons | bubble [button] | words | typed | front | quit")
        case "ask":
            if rest.isEmpty {
                controller.askPressed()
            } else {
                controller.ask(rest, snapshot: ScreenSnapshot(appName: "Safari", windowTitle: "Pricing", selectedText: parts.inserter.selection))
            }
        case "select":
            parts.inserter.selection = rest.isEmpty ? nil : rest
        case "replace":
            if case .reply(let text, true, _, _, true)? = stage.bubble.content { controller.bubbleAction(.replace(text)) }
        case "drop":
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
            stage.escapePressed()
        case "clickaway":
            controller.bubbleDismissed(byClick: true)
        case "talk":
            hold(.talk)
        case "dictate":
            hold(.dictate)
        case "busy":
            parts.backend.makeBusy()
        case "perf":
            Task { await DemoBench.run(rest, controller: controller, stage: stage) }
        case "kittens":
            controller.kittensPressed()
        case "channels":
            controller.channelsPressed()
        case "messages":
            controller.messagesHotkeyPressed()
        case "channel":
            let kitten = Demo.kittens.first { $0.name.lowercased().hasPrefix(rest.lowercased()) }
            switch rest {
            case "activity": stage.channels.view.select(.activity)
            case "threads": stage.channels.view.select(.threads)
            case "shades": stage.channels.view.select(.channel(.shades))
            default: if let kitten, !rest.isEmpty { stage.channels.view.select(.channel(.of(kitten))) }
            }
        case "thread":
            let typing = rest == "reply" || rest.hasPrefix("reply ")
            let words = typing ? String(rest.dropFirst(5)).trimmingCharacters(in: .whitespaces) : rest
            let chosen = words.isEmpty ? shownThreads.last : shownThreads.last { $0.words.localizedCaseInsensitiveContains(words) }
            if let chosen {
                stage.channels.view.open(thread: chosen.id, typing: typing)
                print("thread \(chosen.id)")
            } else {
                print("no thread shows [\(rest)]")
            }
        case "back":
            stage.channels.view.closeThread()
        case "key":
            guard let shortcut = Self.shortcuts[rest] else {
                return print("key \(Self.shortcuts.keys.sorted().joined(separator: " | "))")
            }
            let panel = stage.channels.window
            panel.makeKey()
            let handled = panel.handle(shortcut)
            print("key \(rest) handled=\(handled) \(whereMessagesIs) key=\(panel.isKeyWindow) front=\(front)")
        case "keyboard":
            QuietFocus.fullKeyboardAccess = { rest != "off" }
            print("keyboard navigation \(rest == "off" ? "off" : "on")")
        case "tab", "space":
            pressKey(word == "space" ? " " : rest == "back" ? "\u{19}" : "\t", control: rest == "control")
        case "arrow":
            let up = rest == "up"
            pressKey(String(Character(UnicodeScalar(up ? NSUpArrowFunctionKey : NSDownArrowFunctionKey)!)), keyCode: up ? 126 : 125)
        case "jump":
            let view = stage.channels.view
            if view.jumpBox.isHidden {
                stage.channels.window.makeKey()
                stage.channels.window.handle(.jump)
            }
            view.jumpBox.query = rest
            print("jump [\(rest)] \(view.jumpBox.items.map(\.title).joined(separator: ", "))")
        case "search":
            let view = stage.channels.view
            if view.jumpBox.isHidden || view.jumpBox.mode != .search {
                stage.channels.window.makeKey()
                stage.channels.window.handle(.search)
            }
            if view.jumpBox.query != rest { view.jumpBox.query = rest }
            print("search [\(rest)] \(view.jumpBox.items.map { "\($0.title): \($0.found?.snippet ?? "")" }.joined(separator: " | "))")
        case "jump-down", "jump-up":
            stage.channels.view.jumpBox.move(by: word == "jump-down" ? 1 : -1)
            print("\(word) \(stage.channels.view.jumpBox.highlighted)")
        case "jump-open":
            stage.channels.view.jumpBox.open()
            print("jump-open \(whereMessagesIs)")
            let view = stage.channels.view
            let found = (view.threadPane.isHidden ? view.pane : view.threadPane).shownMessageRows.first(where: \.isFound)
            if let found { print("found \(found.message.id) [\((found.message.text ?? "").prefix(60))]") }
        case "also":
            let composer = stage.channels.view.threadPane.composer
            composer.alsoSends = rest == "on"
            print("also \(composer.alsoSend.isHidden ? "isn't offered" : "\(composer.alsoSend.title) \(composer.alsoSends ? "on" : "off")")")
        case "more":
            let view = stage.channels.view
            let pane = view.threadPane.isHidden ? view.pane : view.threadPane
            if let row = pane.longMessageRow { row.pressShowMore() } else { print("no message is cut") }
        case "toolbar":
            let view = stage.channels.view
            let pane = view.threadPane.isHidden ? view.pane : view.threadPane
            guard let row = pane.shownMessageRows.last else { return print("no message shows") }
            row.hovering = true
            guard let button = row.toolbar?.button(rest) else { return print("no [\(rest)] in its bar") }
            let panel = stage.channels.window
            let shown = button.isHidden ? row.toolbar?.more : button
            guard let shown, let frame = panel.contentView?.superview else { return }
            let centre = shown.convert(NSPoint(x: shown.bounds.midX, y: shown.bounds.midY), to: nil)
            let hit = frame.hitTest(frame.convert(centre, from: nil))
            print("toolbar [\(rest)] \(button.isHidden ? "is under More, " : "")lands on \(hit === shown ? "it" : hit.map { String(describing: type(of: $0)) } ?? "nothing")")
            if button.isHidden, let menu = row.menu(for: NSEvent()) {
                return menu.performActionForItem(at: menu.indexOfItem(withTitle: rest))
            }
            guard let hit else { return }
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                guard let event = NSEvent.mouseEvent(with: type, location: centre, modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { return }
                type == .leftMouseDown ? hit.mouseDown(with: event) : hit.mouseUp(with: event)
            }
        case "unread":
            let view = stage.channels.view
            let pane = view.threadPane.isHidden ? view.pane : view.threadPane
            let row = pane.shownMessageRows.last { $0.onMarkUnread != nil && ($0.accessibilityLabel() ?? "").localizedCaseInsensitiveContains(rest) }
            print(row == nil ? "no message to mark unread shows [\(rest)]" : "marked unread [\(rest)]")
            row?.onMarkUnread?()
        case "read":
            let view = stage.channels.view
            let sidebar = view.sidebar.rows.filter { $0.item.title.localizedCaseInsensitiveCompare(rest) == .orderedSame }
            let pane = view.threadPane.isHidden ? view.pane : view.threadPane
            let threads: [ChannelRowView] = pane.shownMessageRows + Self.subviews(of: pane).compactMap { $0 as? ThreadDigestRowView }
            let row = sidebar.first ?? threads.last { ($0.accessibilityLabel() ?? "").localizedCaseInsensitiveContains(rest) && $0.actions.contains { $0.name == CatWords.markRead } }
            guard let action = row?.actions.first(where: { $0.name == CatWords.markRead }) else { return print("nothing to mark read [\(rest)]") }
            action.run()
            print("marked read [\(rest)]")
        case "places":
            for row in stage.channels.view.sidebar.rows {
                print("place \(row.item.title) bold=\(row.item.isUnread || row.item.badge > 0) badge=\(row.item.badge) unread=\(row.item.unread) menu=\(row.actions.map(\.name).joined(separator: "/"))")
            }
        case "new":
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
            let pane = stage.channels.view.pane
            if let points = Double(rest) { pane.scrollOffset = min(max(pane.scrollOffset + points, 0), pane.scrollOffset + pane.distanceFromBottom) }
        case "send":
            let view = stage.channels.view
            (view.selection.thread == nil ? view.pane : view.threadPane).composer.send(rest)
        case "retry":
            let view = stage.channels.view
            let row = (view.pane.shownMessageRows + view.threadPane.shownMessageRows).last { $0.onTryAgain != nil }
            print(row == nil ? "nothing to try again" : "tried again")
            row?.onTryAgain?()
        case "draft":
            let view = stage.channels.view
            let text = (view.selection.thread == nil ? view.pane : view.threadPane).composer.textView
            text.insertText(rest, replacementRange: NSRange(location: (text.string as NSString).length, length: 0))
        case "react":
            let view = stage.channels.view
            let row = (view.pane.shownMessageRows + view.threadPane.shownMessageRows).last { $0.onReact != nil }
            guard let reaction = Reaction(rawValue: rest) else { return print("react " + Reaction.allCases.map(\.rawValue).joined(separator: " | ")) }
            print(row.map { "reacted \(reaction.emoji) to [\(($0.accessibilityLabel() ?? "").prefix(70))]" } ?? "nothing takes a reaction")
            row?.onReact?(reaction)
        case "attach":
            let view = stage.channels.view
            let drop: Drop? = switch rest {
            case "pdf": Demo.samplePDF().map(Drop.file)
            case "picture": Demo.samplePicture().map(Drop.picture)
            default: rest.isEmpty ? nil : .file(URL(fileURLWithPath: rest))
            }
            let taken = drop.map { (view.selection.thread == nil ? view.pane : view.threadPane).composer.attach([$0]) } ?? false
            print("attached \(drop?.name ?? rest), taken: \(taken)")
        case "settings":
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
            let first = controller.inboxEntries.first { $0.questionID == nil }
            switch rest {
            case "reply":
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
            let cards = allSubviews(of: stage.channels.view.pane).compactMap { $0 as? CardRowView }
            let button = cards.lazy.flatMap(\.buttons).first { $0.accessibilityLabel() == rest }
            guard let button else { return print("no card button [\(rest)]") }
            print(button.accessibilityPerformPress() ? "pressed \(rest)" : "didn't press \(rest)")
        case "notification":
            controller.showInMessages(rest.isEmpty ? "demo-tidy" : rest)
        case "notify-finished":
            var settings = controller.settings
            settings.notifyFinished = rest != "off"
            controller.apply(settings)
        case "notifications":
            let words = rest.split(separator: " ").map(String.init)
            let kitten = Demo.kittens.first { $0.name.lowercased().hasPrefix(words.first?.lowercased() ?? "-") }
            let channel: ChannelID? = words.first == "shades" ? .shades : kitten.map(ChannelID.of)
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
            let words = rest.split(separator: " ").map(String.init)
            stage.cat.hold(words.first.flatMap(CatFrame.init(rawValue:)).map { CatPose(frame: $0, flip: words.count > 1) })
        case "run":
            let values = rest.split(separator: " ").compactMap { Double($0) }
            if values.count == 2 { stage.cat.run(to: CGPoint(x: values[0], y: values[1])) }
        case "home":
            stage.catGoHome()
        case "fonts":
            for item in FontMenu().items(current: controller.settings.messagesFont, families: NSFontManager.shared.availableFontFamilies) {
                let more = item.submenu.map { " (\($0.items.count) families)" } ?? ""
                print(item.isSeparatorItem ? "font ---" : "font \(item.state == .on ? "*" : " ") \(item.title)\(more)\(item.isEnabled ? "" : " (not on this Mac)")")
            }
        case "font":
            let items = FontMenu().items(current: controller.settings.messagesFont, families: NSFontManager.shared.availableFontFamilies)
            let picked = (items + items.compactMap(\.submenu).flatMap(\.items)).first { $0.title == (rest.isEmpty ? MessagesInk.systemFaces[0].name : rest) && $0.isEnabled }
            guard let picked else { return print("no font [\(rest)]") }
            var settings = controller.settings
            settings.messagesFont = picked.representedObject as? String
            controller.settingsEdited(settings)
            print("font \(settings.messagesFont ?? "system")")
        case "picture":
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
            let target = NSApp.target(forAction: #selector(NSText.copy(_:)), to: nil, from: stage.channels.window)
            let words = (target as? NSTextView).map { ($0.string as NSString).substring(with: $0.selectedRange()) }
            print("copy goes to \(target.map { String(describing: type(of: $0)) } ?? "nothing") with [\(words ?? "")] types=\((target as? NSTextView)?.writablePasteboardTypes.map(\.rawValue) ?? [])")
        case "private":
            parts.context.isPrivate = rest == "on"
        case "t3":
            parts.backend.connectFails = rest == "off"
            parts.backend.stuck = rest == "stuck"
        case "check":
            controller.checkMyselfPressed()
        case "team":
            parts.facts.found.isSignedByTeam = rest != "off"
        case "kittens-check":
            let (hours, misses) = (rest.prefix { $0 != " " }, rest.drop { $0 != " " })
            parts.facts.kittensCheck = Double(hours).map { DemoFacts.kittensCheck(hoursAgo: $0, misses: String(misses)) } ?? Data(rest.utf8)
        case "screen":
            parts.context.fails = rest == "off"
        case "ears":
            parts.voice.downloading = rest == "off"
            parts.voice.denied = rest == "denied"
        case "voiceover":
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
                print("window \(name) id=\(window.windowNumber) visible=\(window.isVisible) key=\(window.isKeyWindow) frame=\(NSStringFromRect(window.frame)) clicks=\(Offstage.takesClicks(window)) alpha=\(String(format: "%.2f", Offstage.alpha(of: window))) seen=\(Offstage.isSeen(window) ? "yes" : "no")")
            }
            print("state \(stage.cat.brain.state) pose=\(stage.cat.brain.pose.frame.rawValue) active=\(NSApp.isActive)")
        case "opal":
            let parts = rest.split(separator: " ").map(String.init)
            let jackets = parts.dropFirst().compactMap { UInt32($0.replacingOccurrences(of: "#", with: ""), radix: 16) }
            let file = OpalSheet.draw(to: parts.first ?? ".verify/shades/opal", jackets: jackets)
            print(file.map { "drew opal \($0.path)" } ?? "couldn't draw opal")
        case "draw":
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
            let button = stage.bubble.view.subviews.compactMap { $0 as? QuietButton }.first { $0.accessibilityLabel() == rest }
            print(button == nil ? "no bubble button [\(rest)]" : "pressed \(rest)")
            button?.onPress?()
        case "words":
            let bubble = stage.bubble
            guard bubble.isVisible, bubble.view.textView.needsPanelToBecomeKey else { return print("no words to click into") }
            bubble.panel.makeKey()
            bubble.panel.makeFirstResponder(bubble.view.textView)
            print("words key=\(bubble.panel.isKeyWindow) front=\(front)")
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
            for item in stage.menuBar.shownItems {
                guard !item.isSeparatorItem else {
                    print("menu ---")
                    continue
                }
                let key = [Shortcut.ask, .fix, .messages].first { $0.key == item.keyEquivalent && $0.keyModifiers == item.keyEquivalentModifierMask }
                let extras = [key.map { "key=\($0.label)" }, item.badge?.stringValue.map { "badge=[\($0)]" }, item.toolTip.map { "tip=[\($0)]" }]
                print((["menu \(item.state == .on ? "✓" : "-") \(item.title)"] + extras.compactMap { $0 }).joined(separator: "  "))
                for sub in item.submenu?.items ?? [] {
                    print(sub.isSeparatorItem ? "menu   ---" : "menu   \(sub.state == .on ? "✓" : "-") \(sub.title)")
                }
            }
        case "menupress":
            let path = rest.components(separatedBy: " > ")
            let item = path.dropFirst().reduce(stage.menuBar.shownItems.first { $0.title == path[0] }) { parent, title in
                parent?.submenu?.items.first { $0.title == title }
            }
            print(item == nil ? "no menu item [\(rest)]" : "chose \(rest)")
            if let item, let action = item.action { NSApp.sendAction(action, to: item.target, from: item) }
        case "header":
            let view = stage.channels.view
            let header = (view.threadPane.isHidden ? view.pane : view.threadPane).subviews.compactMap { $0 as? ChannelHeader }.first
            let button = header?.subviews.compactMap { $0 as? QuietButton }.first { $0.accessibilityLabel() == rest }
            print(button == nil ? "no header button [\(rest)]" : "pressed \(rest)")
            button?.onPress?()
        case "sidebar":
            let button = stage.channels.view.sidebar.subviews.compactMap { $0 as? QuietButton }.first { !$0.isHidden && $0.accessibilityLabel() == rest }
            print(button == nil ? "no sidebar button [\(rest)]" : "pressed \(rest)")
            button?.onPress?()
        case "dnd":
            print("dnd \(controller.settings.doNotDisturb ? "on" : "off") cat=\(stage.cat.brain.state) away=\(controller.away.count)")
        case "cover":
            // Outside the repo: AppKit pulls a titled window back over Messages when beside it would go off the screen.
            let window = cover ?? NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
            let frame = stage.channels.window.frame
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
