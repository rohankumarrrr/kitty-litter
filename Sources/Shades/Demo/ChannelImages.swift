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
            isUnread: { $0.id == "demo-steve-yesterday" }
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
        var shots = [Shot(name: "needs-you", selection: .needsYou, book: full), Shot(name: "everyone", selection: .channel(.everyone), book: full)]
        for status in full.statuses {
            shots.append(Shot(name: "dm-\(slug(status.kitten.name))", selection: .channel(.direct(status.kitten)), book: full))
        }
        for channel in full.between {
            shots.append(Shot(name: "between-\(slug(full.title(of: channel.id)))", selection: .channel(channel.id), book: full))
        }

        let steve = ChannelSelection.channel(.direct(Demo.kittens[0]))
        shots += [
            Shot(name: "dm-expanded", selection: steve, book: full, expandsLongMessage: true),
            Shot(name: "dm-hover", selection: steve, book: full, hoversLastMessage: true),
            Shot(name: "crowded", selection: .needsYou, book: crowded(), height: ChannelsWindow.minimumSize.height),
            Shot(name: "narrow-dm", selection: steve, book: full, width: ChannelsWindow.minimumSize.width, height: ChannelsWindow.minimumSize.height),
            Shot(name: "narrow-needs-you", selection: .needsYou, book: full, width: ChannelsWindow.minimumSize.width, height: ChannelsWindow.minimumSize.height),
            Shot(name: "reading", selection: steve, book: book(threads: [], transcripts: [:], isReading: true)),
            Shot(name: "reading-needs-you", selection: .needsYou, book: book(threads: [], transcripts: [:], isReading: true)),
            Shot(name: "cant-reach", selection: steve, book: book(threads: [], transcripts: [:], isReading: true, cantReachT3: true)),
            Shot(name: "cant-reach-needs-you", selection: .needsYou, book: book(threads: [], transcripts: [:], isReading: true, cantReachT3: true)),
            Shot(name: "cant-reach-with-words", selection: steve, book: book(cantReachT3: true)),
            Shot(name: "unreadable", selection: steve, book: book(unreadable: 2)),
            Shot(name: "nothing-said", selection: steve, book: book(threads: [], transcripts: [:])),
            Shot(name: "nothing-open", selection: .needsYou, book: book(threads: [], transcripts: [:])),
        ]
        return shots
    }

    private static func render(_ shot: Shot, appearance: NSAppearance?) -> Data? {
        let scale: CGFloat = 2
        // Drawn from the window's own frame, so the window's buttons are in the picture. It's never ordered in.
        let panel = ChannelsPanel()
        let view = ChannelsView(frame: .zero)
        panel.contentView = view
        panel.setContentSize(NSSize(width: shot.width, height: shot.height))
        panel.appearance = appearance
        view.show(shot.book)
        view.select(shot.selection)
        if shot.expandsLongMessage { view.pane.longMessageRow?.pressShowMore() }
        if shot.hoversLastMessage { view.pane.shownMessageRows.last?.hovering = true }
        hideScrollers(in: view)
        let frame = view.superview ?? view

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(shot.width * scale),
            pixelsHigh: Int(shot.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = frame.bounds.size
        frame.layoutSubtreeIfNeeded()
        frame.cacheDisplay(in: frame.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    private static func hideScrollers(in view: NSView) {
        if view is NSScroller { view.isHidden = true }
        view.subviews.forEach(hideScrollers)
    }
}
