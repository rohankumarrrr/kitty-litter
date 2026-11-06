import AppKit
import Foundation
import ShadesContext
import ShadesCore
import ShadesT3

/// Runs a flow from the command line, so it can be tried without touching the mouse or
/// keyboard. With `--image`, the agent sees that picture instead of your real screen, as if it
/// filled the main display, so an answer that points there sends the cat to the same spot.
///
///     shades --ask "What's on my screen?" --image page.jpg
///     shades --hand-off "Which of my projects is the budget app?" --image page.jpg
///     shades --fix "The total is wrong" --image page.jpg
///     shades --ask "Summarize this." --drop syllabus.pdf   # a file or link dropped onto the cat, with no look at the screen
///     shades --ask "Research this" --then "And that part?" --image page.jpg   # waits for the agents first
///     shades --ask "Make this friendlier" --selection "Send it by Friday." --image page.jpg   # as if that were selected
///
/// `--ask` prints where the cat pointed once the answer's in, or that it didn't.
///
/// And for the Channels window, none of which sends anything:
///
///     shades --channels                     # opens Messages at launch, with --demo or for real
///     shades --demo --channels-image out    # draws it to PNGs from canned data, then quits
///     shades --channels-check               # reads real T3 once, prints only counts, then signs out
///
/// And for driving the demo from a file of its commands, one a line, such as `wait 2` or `draw out`:
///
///     shades --demo --no-script --commands steps.txt
@MainActor
enum DevFlags {
    static var wantsFlow: Bool { ["--ask", "--hand-off", "--fix"].contains { value(after: $0) != nil } }
    static var wantsChannels: Bool { CommandLine.arguments.contains("--channels") }
    static var wantsChannelsCheck: Bool { CommandLine.arguments.contains("--channels-check") }
    static var channelsImageFolder: String? { value(after: "--channels-image") }
    static var commandsFile: String? { value(after: "--commands") }

    static func run(on controller: AppController) {
        if let question = value(after: "--ask") {
            controller.ask(question, capture: look(controller))
            Task {
                while controller.reply?.done == false { try? await Task.sleep(nanoseconds: 200_000_000) }
                // Where the cat went and nothing of what was said, so a run can check an answer pointed right.
                print(controller.pointingAt.map { "pointed at \(NSStringFromRect($0))" } ?? "didn't point")
                fflush(stdout)
            }
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
        let asks = all.filter { $0.kind == .ask }
        let askIDs = Set(asks.map(\.exchangeID))
        let unasked = all.filter { $0.kind == .reply && !askIDs.contains($0.exchangeID) }
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
            "done: \(book.issues.reduce(0) { $0 + $1.done.count })",
            "milliseconds: \(milliseconds)",
        ].joined(separator: "\n")
    }

    private static func look(_ controller: AppController, focusRegion: CGRect? = nil) -> Task<AppController.Capture, Never> {
        if let dropped = value(after: "--drop") {
            let drop = dropped.hasPrefix("http") ? URL(string: dropped).map(Drop.link) : .file(URL(fileURLWithPath: dropped))
            return Task.detached { AppController.Capture(snapshot: drop?.snapshot(), error: nil) }
        }
        guard let path = value(after: "--image") else {
            return controller.startLook(CaptureOptions(focusRegion: focusRegion))
        }
        let picture = try? Data(contentsOf: URL(fileURLWithPath: path))
        let snapshot = ScreenSnapshot(
            appName: "Test picture",
            selectedText: value(after: "--selection"),
            screenshotJPEG: picture,
            focusRegion: focusRegion,
            screenshotArea: NSScreen.screens.first?.frame
        )
        return Task { AppController.Capture(snapshot: snapshot, error: nil) }
    }

    private static func value(after flag: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
