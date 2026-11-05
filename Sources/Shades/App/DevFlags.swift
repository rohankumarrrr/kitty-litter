import CoreGraphics
import Foundation
import ShadesCore
import ShadesT3

/// Runs a flow from the command line, so it can be tried without touching the mouse or
/// keyboard. With `--image`, the agent sees that picture instead of your real screen.
///
///     shades --ask "What's on my screen?" --image page.jpg
///     shades --hand-off "Which of my projects is the budget app?" --image page.jpg
///     shades --fix "The total is wrong" --image page.jpg
///     shades --ask "Research this" --then "And that part?" --image page.jpg   # waits for the agents first
///
/// And for the Channels window, none of which sends anything:
///
///     shades --channels                     # opens it at launch, with --demo or for real
///     shades --demo --channels-image out    # draws it to PNGs from canned data, then quits
///     shades --channels-check               # reads real T3 once, prints only counts, then signs out
@MainActor
enum DevFlags {
    static var wantsFlow: Bool { ["--ask", "--hand-off", "--fix"].contains { value(after: $0) != nil } }
    static var wantsChannels: Bool { CommandLine.arguments.contains("--channels") }
    static var wantsChannelsCheck: Bool { CommandLine.arguments.contains("--channels-check") }
    static var channelsImageFolder: String? { value(after: "--channels-image") }

    static func run(on controller: AppController) {
        if let question = value(after: "--ask") {
            controller.ask(question, capture: look(controller))
            if let next = value(after: "--then") {
                Task {
                    repeat {
                        try? await Task.sleep(nanoseconds: 15_000_000_000)
                    } while controller.watch.isBusy || controller.reply?.done == false
                    controller.ask(next, capture: look(controller))
                }
            }
        } else if let request = value(after: "--hand-off") {
            Task {
                let snapshot = await look(controller).value.snapshot
                let path = controller.saveScreenshot(of: snapshot)
                controller.startFrontier(
                    title: request,
                    text: Prompts.frontier(request: request, snapshot: snapshot, screenshotPath: path),
                    snapshot: snapshot
                )
            }
        } else if let description = value(after: "--fix") {
            Task {
                let region = CGRect(x: 200, y: 200, width: 400, height: 200)
                let capture = await look(controller, focusRegion: region).value
                controller.sendFix(description, snapshot: capture.snapshot ?? ScreenSnapshot(focusRegion: region))
            }
        }
    }

    /// One real pass over what's been said. It never prints a name, a title or a word of text.
    static func checkChannels() -> Never {
        let backend = T3Backend(credentials: MemoryCredentialStore(), label: "Shades channels check", sessionTTL: "1h", renewBefore: 0)
        let feed = ChannelFeed(backend: backend, kittens: { Kittens.load() })
        let started = Date()
        feed.onChange = { book in
            guard !book.isReading || book.cantReachT3 else { return }
            let held = feed.threadsHeld
            feed.close()
            print(checkLine(book, threadsRead: held, milliseconds: Int(Date().timeIntervalSince(started) * 1000)))
            Task {
                await backend.signOut()
                await backend.disconnect()
                exit(book.cantReachT3 ? 1 : 0)
            }
        }
        _ = feed.open(threads: [])
        dispatchMain()
    }

    static func checkLine(_ book: ChannelBook, threadsRead: Int, milliseconds: Int) -> String {
        let all = (book.directs + book.between).flatMap(\.messages)
        let asks = all.filter { $0.id.hasSuffix(":ask") }
        let askIDs = Set(asks.map { $0.id.dropLast(":ask".count) })
        let unasked = all.filter { $0.id.hasSuffix(":reply") && !askIDs.contains($0.id.dropLast(":reply".count)) }
        func asked(by matches: (Speaker) -> Bool) -> Int { asks.filter { matches($0.speaker) }.count }
        return [
            "reached T3: \(!book.cantReachT3)",
            "threads read: \(threadsRead)",
            "unreadable: \(book.unreadable)",
            "DMs with messages: \(book.directs.filter { !$0.messages.isEmpty }.count)",
            "between channels: \(book.between.count)",
            "messages: \(all.count)",
            "asked by you: \(asked { $0 == .you })",
            "asked by a kitten: \(asked { if case .kitten = $0 { return true } else { return false } })",
            "asked by someone else: \(asked { $0 == .someoneElse })",
            "replies with no ask: \(unasked.count)",
            "issues: \(book.issueCount)",
            "milliseconds: \(milliseconds)",
        ].joined(separator: "\n")
    }

    private static func look(_ controller: AppController, focusRegion: CGRect? = nil) -> Task<AppController.Capture, Never> {
        guard let path = value(after: "--image") else {
            return controller.startLook(CaptureOptions(focusRegion: focusRegion))
        }
        let picture = try? Data(contentsOf: URL(fileURLWithPath: path))
        let snapshot = ScreenSnapshot(
            appName: "Test picture",
            screenshotJPEG: picture,
            focusRegion: focusRegion
        )
        return Task { AppController.Capture(snapshot: snapshot, error: nil) }
    }

    private static func value(after flag: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
