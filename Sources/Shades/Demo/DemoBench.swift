import AppKit
import ShadesCore

/// `perf` in the demo: times what you'd feel in Messages, the cat's bubble, the Ask box and the phone page, from inside
/// the app, with no clicks, keys or screen capture. Each step is the same call the window makes, then the window lays
/// out and draws before the clock stops. Run it after `busy` for a load like a real one. `perf messages`, `perf cat`
/// and `perf phone` run one part, and `perf idle <seconds>` says what sitting still costs instead.
@MainActor
enum DemoBench {
    private static let rounds = 5
    private static let scrollStep: CGFloat = 40
    private static let cycles = 10

    static func run(_ argument: String, controller: AppController, stage: AppStage) async {
        let started = Date()
        // The person's own clicks go on around the demo, and mustn't close the bubble being timed.
        ClickAway.isPaused = true
        // Nor does it print all VoiceOver would read of the long answer, each time it comes up.
        let announce = BubbleController.onAnnounce
        BubbleController.onAnnounce = nil
        defer {
            ClickAway.isPaused = false
            BubbleController.onAnnounce = announce
        }
        let words = argument.split(separator: " ").map(String.init)
        switch words.first {
        case "idle": await idle(seconds: words.dropFirst().first.flatMap { Double($0) } ?? 20, controller: controller, stage: stage)
        case "messages": await messages(controller: controller, stage: stage)
        case "cat": await cat(stage: stage)
        case "phone": await phone(controller: controller)
        default:
            await messages(controller: controller, stage: stage)
            await cat(stage: stage)
            await phone(controller: controller)
        }
        print(String(format: "perf done in %.0fs", Date().timeIntervalSince(started)))
        fflush(stdout)
    }

    private static func messages(controller: AppController, stage: AppStage) async {
        let window = stage.channels.panel
        let view = stage.channels.view
        let pane = view.pane
        let thread = view.threadPane
        let start = footprint()
        if !stage.isChannelsVisible {
            report("open", [time(window) { controller.channelsPressed() }])
        }
        await finishReading(controller)
        guard let steve = Demo.kittens.first, let clawde = Demo.kittens.first(where: { $0.name == "Clawde" }) else { return }
        view.select(.channel(.of(steve)))
        await react(controller: controller, view: view)
        var reopens: [Double] = []
        for _ in 0..<rounds {
            stage.hideChannels()
            settle(window)
            reopens.append(time(window) { controller.channelsPressed() })
        }
        // What a reopen shows straight away: the conversation, or a note that it's still reading.
        report("reopen", reopens, "reading=\(controller.channels.open(threads: []).isReading) rows=\(pane.shown.count)")
        print(String(format: "perf memory-open before=%.1fMB after=%.1fMB", start, footprint()))
        await finishReading(controller)

        // Messages opening again where you left it, on the long thread, to its first full draw.
        view.open(thread: DemoBusy.longThread)
        settle(window)
        var longOpens: [Double] = []
        for _ in 0..<rounds {
            stage.hideChannels()
            settle(window)
            longOpens.append(time(window) { controller.channelsPressed() })
        }
        report("reopen-long", longOpens, "rows=\(thread.shown.count) inWindow=\(rowViews(in: thread))")
        view.closeThread()

        let places: [(String, ChannelSelection)] = [
            ("kitten", .channel(.of(steve))),
            ("shades", .channel(.shades)),
            ("threads", .threads),
            ("activity", .activity),
            ("kitten2", .channel(.of(clawde))),
        ]
        for (name, selection) in places {
            var times: [Double] = []
            for _ in 0..<rounds {
                view.select(.activity)
                settle(window)
                times.append(time(window) { view.select(selection) })
            }
            report("switch-\(name)", times, "rows=\(pane.shown.count) inWindow=\(rowViews(in: pane))")
        }

        // Opening a thread beside its channel, as clicking its reply bar does, then closing it with ✕, then going from
        // one thread to the next.
        var opens: [Double] = []
        var closes: [Double] = []
        var nexts: [Double] = []
        let others = controller.channels.open(threads: []).threads(in: .of(steve)).filter { $0 != DemoBusy.longThread }.suffix(rounds)
        for other in others {
            view.select(.channel(.of(steve)))
            settle(window)
            opens.append(time(window) { view.open(thread: DemoBusy.longThread) })
            nexts.append(time(window) { view.open(thread: other) })
            closes.append(time(window) { view.closeThread() })
        }
        view.open(thread: DemoBusy.longThread)
        settle(window)
        report("open-thread", opens, "rows=\(thread.shown.count) inWindow=\(rowViews(in: thread))")
        report("switch-thread", nexts)
        report("close-thread", closes)

        // The shortcuts, each the same call its key makes once Messages has the keyboard: up a channel's threads from
        // the newest, down and up the sidebar, back and forward, and jumping to a kitten by name.
        view.closeThread()
        view.select(.channel(.of(steve)))
        settle(window)
        var threadKeys: [Double] = []
        for _ in 0..<rounds * 2 { threadKeys.append(time(window) { view.perform(.previousThread) }) }
        report("key-thread", threadKeys, "rows=\(thread.shown.count)")
        view.closeThread()
        settle(window)
        var placeKeys: [Double] = []
        for index in 0..<rounds * 2 { placeKeys.append(time(window) { view.perform(index % 2 == 0 ? .nextPlace : .previousPlace) }) }
        report("key-place", placeKeys)
        var historyKeys: [Double] = []
        for index in 0..<rounds * 2 { historyKeys.append(time(window) { view.perform(index % 2 == 0 ? .back : .forward) }) }
        report("key-back", historyKeys)
        var jumps: [Double] = []
        var filters: [Double] = []
        for _ in 0..<rounds {
            jumps.append(time(window) { view.perform(.jump) })
            filters.append(time(window) { view.jumpBox.query = "steve" })
            jumps.append(time(window) { view.jumpBox.open() })
        }
        report("key-jump", jumps, "found=\(view.jumpBox.items.count)")
        report("jump-filter", filters)

        // The long thread end to end, a wheel's notch at a time, reading back each step, since rows laid out above as
        // you go up move where you are.
        view.select(.channel(.of(steve)))
        view.open(thread: DemoBusy.longThread)
        settle(window)
        var ups: [Double] = []
        while thread.scrollOffset > 0, ups.count < 10_000 {
            let next = max(thread.scrollOffset - scrollStep, 0)
            ups.append(time(window) { thread.scrollOffset = next })
        }
        reportFrames("scroll-up", ups)
        var downs: [Double] = []
        while thread.distanceFromBottom > 0, downs.count < 10_000 {
            let next = thread.scrollOffset + min(scrollStep, thread.distanceFromBottom)
            downs.append(time(window) { thread.scrollOffset = next })
        }
        reportFrames("scroll-down", downs)

        // Down a column of messages and off each again, as the pointer goes. The first time makes each one's buttons.
        for name in ["hover-first", "hover"] {
            var hovers: [Double] = []
            for row in thread.shownMessageRows where row.superview != nil && !row.visibleRect.isEmpty {
                hovers.append(time(window) { row.hovering = true })
                hovers.append(time(window) { row.hovering = false })
            }
            report(name, hovers, "rows=\(hovers.count / 2)")
        }

        let threadText = thread.composer.textView
        var threadKeysTyped: [Double] = []
        for letter in "the quick brown fox jumps over the lazy dog" {
            threadKeysTyped.append(time(window) { threadText.insertText(String(letter), replacementRange: threadText.selectedRange()) })
        }
        report("type-thread", threadKeysTyped, "rows=\(thread.shown.count)")
        threadText.string = ""
        thread.arrange(force: true)
        view.closeThread()

        view.select(.channel(.of(steve)))
        pane.scrollOffset = pane.scrollOffset + pane.distanceFromBottom
        settle(window)
        var arrivals: [Double] = []
        for index in 0..<rounds * 2 {
            let message = ChannelMessage(exchangeID: "bench-\(index)-\(UUID().uuidString)", kind: .ask, speaker: .you, text: "Bench message \(index)", at: Date(), threadID: "", threadTitle: "")
            arrivals.append(time(window) { controller.channels.sent(message, in: .of(steve)) })
        }
        report("arrive", arrivals)
        var refreshes: [Double] = []
        for _ in 0..<rounds * 2 {
            refreshes.append(time(window) { controller.channels.refresh() })
        }
        report("refresh-unchanged", refreshes)

        let text = pane.composer.textView
        var keys: [Double] = []
        for letter in "the quick brown fox jumps over the lazy dog" {
            keys.append(time(window) { text.insertText(String(letter), replacementRange: text.selectedRange()) })
        }
        report("type", keys)
        var lines: [Double] = []
        for _ in 0..<4 {
            lines.append(time(window) { text.insertText("\n", replacementRange: text.selectedRange()) })
        }
        report("type-newline", lines)
        text.string = ""
        pane.arrange(force: true)

        let frame = window.frame
        var resizes: [Double] = []
        for step in 1...10 {
            var wider = frame
            wider.size.width += CGFloat(step * 8)
            resizes.append(time(window) { window.setFrame(wider, display: false) })
        }
        window.setFrame(frame, display: true)
        report("resize", resizes)

        // Narrower, since the narrowest window has no room for a wider sidebar.
        var drags: [Double] = []
        for step in 1...10 {
            drags.append(time(window) { view.dragSidebarEdge(to: ChannelSidebar.width - CGFloat(step * 4)) })
        }
        view.chosenSidebarWidth = nil
        report("drag-sidebar", drags)
        var hides: [Double] = []
        for _ in 0..<rounds * 2 {
            hides.append(time(window) { view.perform(.toggleSidebar) })
        }
        report("key-sidebar", hides)

        // Opening and closing Messages over and over, on the long thread with each row hovered, keeps no more than it
        // needs: what it holds settles, and the rows and buttons of a thread you've left go.
        let left = NSHashTable<NSView>.weakObjects()
        var footprints: [Double] = []
        for cycle in 0..<cycles {
            stage.hideChannels()
            settle(window)
            controller.channelsPressed()
            view.select(.channel(.of(steve)))
            view.open(thread: DemoBusy.longThread)
            settle(window)
            for row in thread.shownMessageRows where row.superview != nil {
                row.hovering = true
                settle(window)
                row.hovering = false
                if cycle == 0 { ([row] + row.subviews).forEach(left.add) }
            }
            view.closeThread()
            view.select(.activity)
            settle(window)
            try? await Task.sleep(nanoseconds: 100_000_000)
            footprints.append(footprint())
        }
        let kept = left.allObjects.count
        var heap = malloc_statistics_t()
        malloc_zone_statistics(nil, &heap)
        print(String(format: "perf memory first=%.1fMB last=%.1fMB perCycle=%.2fMB cycles=%d kept=%d heap=%.1fMB graphics=%.1fMB", footprints.first ?? 0, footprints.last ?? 0, ((footprints.last ?? 0) - (footprints.first ?? 0)) / Double(max(cycles - 1, 1)), cycles, kept, Double(heap.size_in_use) / 1_048_576, graphics()))
        // What the drawn cards and tiles hold while the long thread is open, then once Messages closes.
        view.select(.channel(.of(steve)))
        view.open(thread: DemoBusy.longThread)
        settle(window)
        let open = Double(Opal.keptBytes) / 1_048_576
        stage.hideChannels()
        print(String(format: "perf memory-cache open=%.1fMB closed=%.1fMB limit=%.0fMB", open, Double(Opal.keptBytes) / 1_048_576, Double(Opal.keptLimit) / 1_048_576))
        controller.channelsPressed()

        let book = controller.channels.open(threads: [])
        var phones: [Double] = []
        for _ in 0..<rounds * 2 {
            phones.append(measure { _ = PhoneView(PhonePlace(PhonePlace.key(.channel(.of(steve))), in: book), in: book, now: Date()) })
        }
        let phoneView = PhoneView(PhonePlace(PhonePlace.key(.channel(.of(steve))), in: book), in: book, now: Date())
        report("phone-view", phones, "rows=\(phoneView.rows.count) bytes=\((try? JSONEncoder().encode(phoneView))?.count ?? 0)")
        let longView = PhoneView(PhonePlace(PhonePlace.key(.thread(DemoBusy.longThread, in: .channel(.of(steve)))), in: book), in: book, now: Date())
        print("perf phone-view-long rows=\(longView.rows.count) bytes=\((try? JSONEncoder().encode(longView))?.count ?? 0)")
        stage.hideChannels()
    }

    /// Reactions on every third message of the long thread, as you'd leave them.
    private static func react(controller: AppController, view: ChannelsView) async {
        view.open(thread: DemoBusy.longThread)
        await finishReading(controller)
        let messages = controller.channels.messages(in: DemoBusy.longThread)
        for (index, message) in messages.enumerated() where index % 3 == 1 && message.reactions?.isEmpty == true {
            controller.inbox.react(Reaction.allCases[index % Reaction.allCases.count], to: message.id, at: Date())
        }
        controller.channels.refresh()
        view.closeThread()
    }

    /// The cat's bubble coming up with a long answer, then the same answer coming in a few words at a time, and the
    /// Ask box opening.
    private static func cat(stage: AppStage) async {
        let bubble = stage.bubble.panel
        let answer = longAnswer
        var shows: [Double] = []
        for _ in 0..<rounds {
            stage.showBubble(nil)
            try? await Task.sleep(nanoseconds: 300_000_000)
            shows.append(time(bubble) { stage.showBubble(.reply(text: answer, done: true, threadID: nil, note: nil)) })
        }
        report("bubble-long", shows, "size=\(Int(bubble.frame.width))x\(Int(bubble.frame.height))")
        stage.showBubble(nil)
        try? await Task.sleep(nanoseconds: 300_000_000)
        let words = answer.split(separator: " ")
        var streams: [Double] = []
        for count in stride(from: 6, through: words.count, by: 6) {
            streams.append(time(bubble) { stage.showBubble(.reply(text: words.prefix(count).joined(separator: " "), done: false, threadID: nil, note: nil)) })
        }
        report("bubble-stream", streams)
        stage.showBubble(nil)
        try? await Task.sleep(nanoseconds: 300_000_000)

        let box = stage.input.panel
        var boxes: [Double] = []
        for _ in 0..<rounds {
            boxes.append(time(box) { stage.showInput(InputRequest(placeholder: CatWords.askPlaceholder, allowsEmpty: false, onSubmit: { _ in }, onCancel: {})) })
            stage.hideInput()
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        report("ask-box", boxes)
    }

    static let longAnswer = (0..<14).map { index in
        [
            "The pricing page has three plans, and the middle one is the one most people pick.",
            "**Free** covers one project. **Pro** adds sharing, and the button under it says `Start a trial`.",
            "- The table compares eleven things\n- Four of them say the same thing in different words\n- The footer repeats the plans",
            "```\nplans = [\"Free\", \"Pro\", \"Team\"]\nprint(plans)\n```",
        ][index % 4]
    }.joined(separator: "\n\n")

    /// The phone page on a long thread: what it sends, how long its first draw takes, and what drawing it again and
    /// scrolling it cost in the page, where its CSS is painted.
    private static func phone(controller: AppController) async {
        guard let steve = Demo.kittens.first else { return }
        var settings = controller.settings
        settings.phone = true
        controller.apply(settings)
        await controller.phoneTask?.value
        // As long as `phone on` and `phone pair` are given in a journey, which is what a page needs to pair.
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        controller.pairPhone()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        for _ in 0..<100 where controller.phoneAddress == nil || controller.phone?.door.pairing == nil {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard let address = controller.phoneAddress, let code = controller.phone?.door.pairing?.code else { return print("perf phone off") }
        let key = PhonePlace.key(.thread(DemoBusy.longThread, in: .channel(.of(steve))))
        let phone = DemoPhone()
        defer { phone.close() }
        phone.open(URL(string: "\(address)/?key=\(PhonePlace.key(.channel(.of(steve))).addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")#pair=\(code)")!)
        guard await until(phone, "document.querySelectorAll('#rows > *').length > 0") else { return print("perf phone didn't open") }
        _ = await phone.run("go(\(DemoPhone.quoted(key)))")
        guard await until(phone, "document.querySelectorAll('#rows .bubble').length > 50") else { return print("perf phone didn't show the thread") }
        // Off every screen the page is hidden and gets no frames, so drawing the thread is timed to its layout in the
        // page, and painting it, gradients, masks and all, to a picture of each screenful down it.
        print("perf phone-" + (await phone.run("""
            (() => {
                const builds = [];
                const shown = view;
                for (let round = 0; round < 5; round++) {
                    view = null;
                    $('rows').replaceChildren();
                    document.body.offsetHeight;
                    const start = performance.now();
                    show(shown);
                    document.body.offsetHeight;
                    builds.push(performance.now() - start);
                }
                builds.sort((a, b) => a - b);
                return `build median=${builds[2].toFixed(1)}ms max=${builds[4].toFixed(1)}ms n=5 bubbles=${document.querySelectorAll('#rows .bubble').length}`;
            })()
            """)))
        var pings: [Double] = []
        for _ in 0..<20 {
            let start = DispatchTime.now().uptimeNanoseconds
            _ = await phone.run("1")
            pings.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
        report("phone-ping", pings)
        var paints: [Double] = []
        let height = Double(await phone.run("document.scrollingElement.scrollHeight - innerHeight")) ?? 0
        var top = 0.0
        while top <= height, paints.count < 200 {
            _ = await phone.run("document.scrollingElement.scrollTop = \(top)")
            let start = DispatchTime.now().uptimeNanoseconds
            _ = try? await phone.view.takeSnapshot(configuration: nil)
            paints.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            top += DemoPhone.size.height * 0.8
        }
        report("phone-paint", paints, String(format: "total=%.0fms", paints.reduce(0, +)))
        print("perf phone-" + (await phone.run("""
            (() => {
                const entries = [...performance.getEntriesByType('navigation'), ...performance.getEntriesByType('resource')];
                const bytes = (name) => entries.filter((entry) => entry.name.includes(name)).reduce((sum, entry) => sum + entry.decodedBodySize, 0);
                return `bytes page=${bytes('/?key')} css=${bytes('/app.css')} js=${bytes('/app.js')} all=${entries.reduce((sum, entry) => sum + entry.decodedBodySize, 0)}`;
            })()
            """)))
        settings.phone = false
        controller.apply(settings)
    }

    /// Nothing changing for `seconds` at a time: Messages open on the long thread, then closed, then the cat's bubble up
    /// with a long answer, each with Reduce Motion off and then on. Anything that keeps drawing shows as time and
    /// wakeups.
    private static func idle(seconds: Double, controller: AppController, stage: AppStage) async {
        guard let steve = Demo.kittens.first else { return }
        let window = stage.channels.panel
        let states: [(name: String, setUp: () -> Void)] = [
            ("messages", {
                controller.channelsPressed()
                stage.channels.view.select(.channel(.of(steve)))
                stage.channels.view.open(thread: DemoBusy.longThread)
            }),
            ("closed", { stage.hideChannels() }),
            ("bubble", { stage.showBubble(.reply(text: longAnswer, done: true, threadID: nil, note: nil)) }),
        ]
        await finishReading(controller)
        for state in states {
            state.setUp()
            settle(window)
            for reduced in [false, true] {
                Motion.forced = reduced
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let before = usage()
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                let after = usage()
                let elapsed = after.at - before.at
                print(String(format: "perf idle-%@ reduceMotion=%@ cpu=%.2f%% wakeups=%.1f/s seconds=%.0f visible=%@", state.name, reduced ? "on" : "off", (after.cpu - before.cpu) / elapsed * 100, Double(after.wakeups - before.wakeups) / elapsed, elapsed, window.occlusionState.contains(.visible) ? "yes" : "no"))
                fflush(stdout)
            }
        }
        Motion.forced = DevFlags.reducesMotion ? true : nil
        stage.showBubble(nil)
    }

    /// Whether the page comes to say yes to `check` within 20 seconds.
    private static func until(_ phone: DemoPhone, _ check: String) async -> Bool {
        for _ in 0..<400 {
            if await phone.run(check) == "1" { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    private static func finishReading(_ controller: AppController) async {
        let started = Date()
        while controller.channels.open(threads: []).isReading, Date().timeIntervalSince(started) < 10 {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// Rows that are views in the window, rather than only in the list.
    private static func rowViews(in view: NSView) -> Int {
        view.subviews.reduce(0) { $0 + ($1 is ChannelRowView ? 1 : 0) + rowViews(in: $1) }
    }

    private static func settle(_ window: NSWindow) {
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        CATransaction.flush()
    }

    private static func measure(_ work: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        work()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    private static func time(_ window: NSWindow, _ work: () -> Void) -> Double {
        measure {
            work()
            settle(window)
        }
    }

    /// The app's CPU time so far, and how often it's been woken, as Activity Monitor counts them.
    private static func usage() -> (at: Double, cpu: Double, wakeups: UInt64) {
        var times = rusage()
        getrusage(RUSAGE_SELF, &times)
        let cpu = Double(times.ru_utime.tv_sec + times.ru_stime.tv_sec) + Double(times.ru_utime.tv_usec + times.ru_stime.tv_usec) / 1_000_000
        var power = task_power_info()
        var count = mach_msg_type_number_t(MemoryLayout<task_power_info>.size / MemoryLayout<natural_t>.size)
        _ = withUnsafeMutablePointer(to: &power) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_POWER_INFO), $0, &count) }
        }
        return (Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000, cpu, power.task_interrupt_wakeups)
    }

    /// What the app holds in memory, as Activity Monitor's Memory column counts it.
    private static func footprint() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    /// What of that is pictures the window server shows, such as each view's drawing.
    private static func graphics() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Double(info.ledger_tag_graphics_footprint) / 1_048_576 : 0
    }

    private static func report(_ name: String, _ times: [Double], _ extra: String = "") {
        let sorted = times.sorted()
        guard !sorted.isEmpty else { return }
        let median = sorted[sorted.count / 2]
        let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        print(String(format: "perf %@ median=%.1fms p95=%.1fms max=%.1fms n=%d %@", name, median, p95, sorted.last ?? 0, sorted.count, extra))
        fflush(stdout)
    }

    /// A scroll's steps, with the whole of it and how many missed a frame at 120 and 60 a second.
    private static func reportFrames(_ name: String, _ times: [Double]) {
        report(name, times, String(format: "total=%.0fms over8ms=%d over16ms=%d", times.reduce(0, +), times.filter { $0 > 8.3 }.count, times.filter { $0 > 16.7 }.count))
    }
}
