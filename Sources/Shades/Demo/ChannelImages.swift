import AppKit
import ShadesCore

/// `--demo --channels-image`: draws every selection to PNGs, in light and dark, from canned data
/// and with no window on the screen. It stays in Demo so real messages can't reach an image.
@MainActor
enum ChannelImages {
    private struct Shot {
        var name: String
        var selection: ChannelSelection
        var book: ChannelBook
        var width = ChannelsWindow.size.width
        var height = ChannelsWindow.size.height
        var expandsLongMessage = false
        var hoversLastMessage = false
        var hoversLastReply = false
        /// A message by its ID, in whichever pane shows it.
        var hovers: String?
    }

    static func draw(to folder: String) {
        let url = URL(fileURLWithPath: folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for shot in shots() {
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                guard let png = render(shot, appearance: NSAppearance(named: appearance)) else { continue }
                try? png.write(to: url.appendingPathComponent("\(shot.name)-\(name).png"))
            }
        }
    }

    private static func book(
        threads: [AgentThread]? = nil,
        transcripts: [String: [Exchange]] = DemoChannels.transcripts,
        isReading: Bool = false,
        unreadable: Int = 0,
        cantReachT3: Bool = false
    ) -> ChannelBook {
        let live = [
            AgentThread(id: "demo-tidy", title: "Steve Pawsniak: Tidy up the pricing page", projectTitle: "site", status: .running, model: "claude-opus-5-5", updatedAt: Date()),
        ]
        return ChannelBook.build(
            kittens: Demo.kittens,
            threads: threads ?? live + DemoChannels.threads,
            transcripts: transcripts,
            isReading: isReading,
            unreadable: unreadable,
            cantReachT3: cantReachT3,
            waiting: DemoChannels.waiting,
            sent: [
                SentMessage(channel: .of(Demo.kittens[0]), message: DemoChannels.alsoSentEcho, alsoSent: true),
                SentMessage(channel: .general, message: ChannelMessage(exchangeID: "demo-general", kind: .ask, speaker: .you, text: "What day is the launch?", at: Date().addingTimeInterval(-300), threadID: "", threadTitle: "")),
                SentMessage(channel: .general, message: ChannelMessage(exchangeID: "demo-general-cat", kind: .reply, speaker: .cat, text: "Thursday, the 12th.", at: Date().addingTimeInterval(-290), threadID: "", threadTitle: "")),
            ],
            isUnread: { $0.id == "demo-steve-yesterday" || $0.id == "demo-steve-copy" },
            // As if you'd asked for the plan names in #general, which gave them to Pepper.
            inGeneral: ["demo-pepper-plans": Date().addingTimeInterval(-1_300)],
            withShades: DemoChannels.talks,
            reactions: ["copy-2:reply": [.thumbsUp, .check]]
        )
    }

    private static func crowded() -> ChannelBook {
        let kittens = (1...16).map { number in
            Kitten(name: "Kitten number \(number) with quite a long name", role: "Helper", covers: "", folder: "/demo/kitten-\(number)")
        }
        let threads = kittens.map { kitten in
            AgentThread(id: kitten.id, title: "A rather long title for what this kitten is working on right now, which won't fit on one line", projectTitle: kitten.name, status: .running, model: "m", updatedAt: Date(), pullRequest: ThreadPullRequest(number: 1_234, state: "open"), projectPath: kitten.folder)
        }
        return ChannelBook.build(kittens: kittens, threads: threads, transcripts: [:], isReading: false, unreadable: 0, cantReachT3: false)
    }

    private static func slug(_ text: String) -> String {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: "-")
    }

    private static func shots() -> [Shot] {
        let full = book()
        let steve = ChannelID.of(Demo.kittens[0])
        var shots = [
            Shot(name: "activity", selection: .activity, book: full),
            Shot(name: "threads", selection: .threads, book: full),
            Shot(name: "general", selection: .channel(.general), book: full),
            Shot(name: "shades", selection: .channel(.shades), book: full),
            Shot(name: "shades-thread", selection: .thread("demo-shades-plans", in: .channel(.shades)), book: full),
        ]
        for status in full.statuses {
            shots.append(Shot(name: "channel-\(slug(status.kitten.name))", selection: .channel(.of(status.kitten)), book: full))
        }

        // Each crowded kitten's thread has the kitten's own ID.
        let longNamed = crowded().statuses[0].kitten
        let thread = ChannelSelection.thread("demo-steve-copy", in: .channel(steve))
        shots += [
            Shot(name: "thread", selection: thread, book: full),
            Shot(name: "thread-from-threads", selection: .thread("demo-steve-copy", in: .threads), book: full),
            Shot(name: "thread-waiting", selection: .thread("demo-pepper-plans", in: .channel(.general)), book: full),
            Shot(name: "narrow-thread", selection: thread, book: full, width: ChannelsWindow.minimumSize.width, height: ChannelsWindow.minimumSize.height),
            Shot(name: "narrow-thread-hover", selection: thread, book: full, width: ChannelsWindow.minimumSize.width, height: ChannelsWindow.minimumSize.height, hoversLastReply: true),
            Shot(name: "channel-expanded", selection: thread, book: full, expandsLongMessage: true),
            Shot(name: "channel-hover", selection: .channel(steve), book: full, hoversLastMessage: true),
            Shot(name: "channel-hover-replies", selection: .channel(steve), book: full, hovers: "labels-1:ask"),
            Shot(name: "channel-hover-yours", selection: .channel(steve), book: full, hovers: "copy-1:ask"),
            Shot(name: "thread-hover-reactions", selection: thread, book: full, hovers: "copy-2:reply"),
            Shot(name: "narrow-thread-hover-reactions", selection: thread, book: full, width: ChannelsWindow.minimumSize.width, height: ChannelsWindow.minimumSize.height, hovers: "copy-2:reply"),
            Shot(name: "crowded", selection: .activity, book: crowded(), height: ChannelsWindow.minimumSize.height),
            Shot(name: "crowded-thread", selection: .thread(longNamed.id, in: .channel(.of(longNamed))), book: crowded(), width: ChannelsWindow.minimumSize.width, height: ChannelsWindow.minimumSize.height),
            Shot(name: "narrow-channel", selection: .channel(steve), book: full, width: ChannelsWindow.minimumSize.width, height: ChannelsWindow.minimumSize.height),
            Shot(name: "narrow-activity", selection: .activity, book: full, width: ChannelsWindow.minimumSize.width, height: ChannelsWindow.minimumSize.height),
            Shot(name: "reading", selection: .channel(steve), book: book(threads: [], transcripts: [:], isReading: true)),
            Shot(name: "reading-activity", selection: .activity, book: book(threads: [], transcripts: [:], isReading: true)),
            Shot(name: "cant-reach", selection: .channel(steve), book: book(threads: [], transcripts: [:], isReading: true, cantReachT3: true)),
            Shot(name: "cant-reach-activity", selection: .activity, book: book(threads: [], transcripts: [:], isReading: true, cantReachT3: true)),
            Shot(name: "cant-reach-with-words", selection: .channel(steve), book: book(cantReachT3: true)),
            Shot(name: "unreadable", selection: .channel(steve), book: book(unreadable: 2)),
            Shot(name: "nothing-said", selection: .channel(steve), book: book(threads: [], transcripts: [:])),
            Shot(name: "nothing-open", selection: .activity, book: book(threads: [], transcripts: [:])),
            Shot(name: "no-threads", selection: .threads, book: book(threads: [], transcripts: [:])),
        ]
        return shots
    }

    private static func render(_ shot: Shot, appearance: NSAppearance?) -> Data? {
        // Drawn from the window's own frame, so the window's buttons are in the picture. It's never ordered in.
        let panel = ChannelsPanel()
        let view = ChannelsView(frame: .zero)
        panel.contentView = view
        panel.setContentSize(NSSize(width: shot.width, height: shot.height))
        panel.appearance = appearance
        view.show(shot.book)
        view.select(shot.selection)
        if shot.expandsLongMessage { (view.threadPane.longMessageRow ?? view.pane.longMessageRow)?.pressShowMore() }
        if shot.hoversLastMessage { view.pane.shownMessageRows.last?.hovering = true }
        if shot.hoversLastReply { view.threadPane.shownMessageRows.last { !$0.isYours }?.hovering = true }
        if let id = shot.hovers { (view.pane.shownMessageRows + view.threadPane.shownMessageRows).first { $0.message.id == id }?.hovering = true }
        hideScrollers(in: view)
        return png(of: view.superview ?? view)
    }

    /// The view as it draws itself, which reads nothing from the screen.
    static func png(of view: NSView, scale: CGFloat = 2) -> Data? {
        bitmap(of: view, scale: scale)?.representation(using: .png, properties: [:])
    }

    static func bitmap(of view: NSView, scale: CGFloat) -> NSBitmapImageRep? {
        view.layoutSubtreeIfNeeded()
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(view.bounds.width * scale),
            pixelsHigh: Int(view.bounds.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    private static func hideScrollers(in view: NSView) {
        if view is NSScroller { view.isHidden = true }
        view.subviews.forEach(hideScrollers)
    }
}
