import AppKit
import ShadesCore

/// `perf` in the demo: times what you'd feel in Messages, from inside the app, with no clicks, keys or screen capture.
/// Each step is the same call the window makes, then the window lays out and draws before the clock stops. Run it
/// after `busy` for a load like a real one.
@MainActor
enum DemoBench {
    private static let rounds = 5
    private static let scrollStep: CGFloat = 40

    static func run(controller: AppController, stage: AppStage) async {
        let window = stage.channels
        let view = window.view
        let pane = view.pane
        if !stage.isChannelsVisible {
            report("open", [time(window) { controller.channelsPressed() }])
        }
        await finishReading(controller)
        guard let steve = Demo.kittens.first, let clawde = Demo.kittens.first(where: { $0.name == "Clawde" }) else { return }
        view.select(.channel(.of(steve)))
        var reopens: [Double] = []
        for _ in 0..<rounds {
            stage.hideChannels()
            settle(window)
            reopens.append(time(window) { controller.channelsPressed() })
        }
        // What a reopen shows straight away: the conversation, or a note that it's still reading.
        report("reopen", reopens, "reading=\(controller.channels.open(threads: []).isReading) rows=\(pane.shown.count)")
        await finishReading(controller)
        let places: [(String, ChannelSelection)] = [
            ("kitten", .channel(.of(steve))),
            ("general", .channel(.general)),
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
        let thread = view.threadPane
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

        view.select(.channel(.of(steve)))
        view.open(thread: DemoBusy.longThread)
        settle(window)
        var scrolls: [Double] = []
        // Read back each time, since rows laid out above as you go up move where you are.
        while thread.scrollOffset > 0 {
            let next = max(thread.scrollOffset - scrollStep, 0)
            scrolls.append(time(window) { thread.scrollOffset = next })
        }
        report("scroll", scrolls, "steps=\(scrolls.count) over8ms=\(scrolls.filter { $0 > 8.3 }.count) over16ms=\(scrolls.filter { $0 > 16.7 }.count)")
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

        let frame = window.panel.frame
        var resizes: [Double] = []
        for step in 1...10 {
            var wider = frame
            wider.size.width += CGFloat(step * 8)
            resizes.append(time(window) { window.panel.setFrame(wider, display: false) })
        }
        window.panel.setFrame(frame, display: true)
        report("resize", resizes)

        let opal = controller.installedThemes().first { $0.theme.name == "Opal Horizon" }
        var themes: [Double] = []
        for _ in 0..<rounds {
            if let opal { themes.append(time(window) { controller.themeChosen(.file(opal.file)) }) }
            themes.append(time(window) { controller.themeChosen(.plain) })
        }
        report("theme", themes)

        let book = controller.channels.open(threads: [])
        var phones: [Double] = []
        for _ in 0..<rounds * 2 {
            phones.append(measure { _ = PhoneView(PhonePlace(PhonePlace.key(.channel(.of(steve))), in: book), in: book, now: Date()) })
        }
        let phoneView = PhoneView(PhonePlace(PhonePlace.key(.channel(.of(steve))), in: book), in: book, now: Date())
        report("phone-view", phones, "rows=\(phoneView.rows.count) bytes=\((try? JSONEncoder().encode(phoneView))?.count ?? 0)")
        print("perf done")
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

    private static func settle(_ window: ChannelsWindow) {
        window.panel.contentView?.layoutSubtreeIfNeeded()
        window.panel.displayIfNeeded()
        CATransaction.flush()
    }

    private static func measure(_ work: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        work()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    private static func time(_ window: ChannelsWindow, _ work: () -> Void) -> Double {
        measure {
            work()
            settle(window)
        }
    }

    private static func report(_ name: String, _ times: [Double], _ extra: String = "") {
        let sorted = times.sorted()
        guard !sorted.isEmpty else { return }
        let median = sorted[sorted.count / 2]
        let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        print(String(format: "perf %@ median=%.1fms p95=%.1fms max=%.1fms n=%d %@", name, median, p95, sorted.last ?? 0, sorted.count, extra))
        fflush(stdout)
    }
}
