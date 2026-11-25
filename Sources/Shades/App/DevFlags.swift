import AppKit
import Foundation
import ShadesContext
import ShadesCore
import ShadesT3

@MainActor
enum DevFlags {
    static var wantsFlow: Bool { ["--ask", "--hand-off", "--fix"].contains { value(after: $0) != nil } }

    static func signInService(bundlePath: String = Bundle.main.bundlePath, isTryingAFlow: Bool? = nil) -> String {
        isInstalledApp(bundlePath: bundlePath, isTryingAFlow: isTryingAFlow) ? KeychainCredentialStore.defaultService : KeychainCredentialStore.defaultService + ".trial"
    }

    static func isInstalledApp(bundlePath: String = Bundle.main.bundlePath, isTryingAFlow: Bool? = nil) -> Bool {
        URL(fileURLWithPath: bundlePath).standardizedFileURL.path == "/Applications/Shades.app" && !(isTryingAFlow ?? wantsFlow)
    }
    static var wantsChannels: Bool { CommandLine.arguments.contains("--channels") }
    static var wantsChannelsCheck: Bool { CommandLine.arguments.contains("--channels-check") }
    static var channelsImageFolder: String? { value(after: "--channels-image") }
    static var commandsFile: String? { value(after: "--commands") }
    static var pictureFile: String? { value(after: "--picture") }
    static var reducesMotion: Bool { CommandLine.arguments.contains("--reduce-motion") }
    static var lockdownKitten: String? { value(after: "--lockdown") }

    static func savePicture(from path: String) -> Never {
        do {
            try YourPicture.save(from: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
            print("Saved your picture. It shows from the app's next start.")
            exit(0)
        } catch {
            print("Couldn't use that as your picture. Try a photo or picture file.")
            exit(1)
        }
    }

    static func run(on controller: AppController) {
        if let question = value(after: "--ask") {
            let asked = Date()
            controller.ask(question, capture: look(controller))
            Task {
                while controller.dispatchers.isEmpty { try? await Task.sleep(nanoseconds: 5_000_000) }
                print("in a thread after \(Int(Date().timeIntervalSince(asked) * 1000)) ms")
                fflush(stdout)
            }
            Task {
                while controller.reply?.done == false { try? await Task.sleep(nanoseconds: 200_000_000) }
                print(controller.reply?.pointingAt.map { "pointed at \(NSStringFromRect($0))" } ?? "didn't point")
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

    static func checkChannels() -> Never {
        let backend = T3Backend(credentials: MemoryCredentialStore(), label: "Shades channels check", sessionTTL: "1h", renewBefore: 0)
        let feed = ChannelFeed(backend: backend, kittens: { Kittens.load() })
        let router = Settings.directory.appendingPathComponent("router", isDirectory: true).standardizedFileURL.path
        feed.isWithShades = { $0.projectPath.map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL.path } == router }
        let inbox = (try? Data(contentsOf: Settings.directory.appendingPathComponent("inbox.json"))).flatMap { try? JSONDecoder().decode(Inbox.self, from: $0) }
        feed.messagesThreads = { inbox?.messagesThreads ?? [:] }
        feed.isCatsWork = { AppController.isCatsWork($0, kept: inbox?.catsWork ?? [:]) }
        feed.alsoSent = { Set(inbox?.alsoSent.keys ?? [:].keys) }
        Task { @MainActor in
            func milliseconds(since start: Date) -> Int { Int(Date().timeIntervalSince(start) * 1000) }
            @MainActor func until(_ done: (ChannelBook) -> Bool) async -> ChannelBook {
                while true {
                    let book = feed.open(threads: [])
                    if done(book) || book.cantReachT3 { return book }
                    try? await Task.sleep(for: .milliseconds(5))
                }
            }
            let started = Date()
            _ = await until { !$0.threads.isEmpty }
            let firstWords = milliseconds(since: started)
            let book = await until { !$0.isReading }
            let cold = milliseconds(since: started)
            let held = feed.threadsHeld
            feed.close()
            try? await Task.sleep(for: .seconds(1))
            let passes = feed.passes
            let reopened = Date()
            _ = await until { !$0.isReading }
            let shown = milliseconds(since: reopened)
            _ = await until { _ in feed.passes > passes }
            let caughtUp = milliseconds(since: reopened)
            feed.close()
            print(checkLine(book, threadsRead: held, milliseconds: cold))
            print("first words: \(firstWords) ms\nreopened and shown: \(shown) ms\nreopened and caught up: \(caughtUp) ms")
            await backend.signOut()
            await backend.disconnect()
            exit(book.cantReachT3 ? 1 : 0)
        }
        dispatchMain()
    }

    static func checkLine(_ book: ChannelBook, threadsRead: Int, milliseconds: Int) -> String {
        let threads = Array(book.threads.values)
        let all = threads.flatMap(\.messages)
        let asks = all.filter { $0.kind == .ask }
        let askIDs = Set(asks.map(\.exchangeID))
        let unasked = all.filter { $0.kind == .reply && !askIDs.contains($0.exchangeID) }
        func asked(by matches: (Speaker) -> Bool) -> Int { asks.filter { matches($0.speaker) }.count }
        return [
            "reached T3: \(!book.cantReachT3)",
            "threads read: \(threadsRead)",
            "unreadable: \(book.unreadable)",
            "channels with threads: \(book.channels.filter { !$0.posts.isEmpty }.count)",
            "threads: \(threads.count)",
            "replies: \(threads.reduce(0) { $0 + $1.replies.count })",
            "messages: \(all.count)",
            "asked by you: \(asked { $0 == .you })",
            "asked by a kitten: \(asked { if case .kitten = $0 { return true } else { return false } })",
            "asked by someone else: \(asked { $0 == .someoneElse })",
            "replies with no ask: \(unasked.count)",
            "issues: \(book.issueCount)",
            "posts with the cat: \(book.channel(.shades)?.posts.count ?? 0)",
            "the cat's own work with it: \(threads.filter { $0.home == .shades && !book.talks.contains($0.id) }.count)",
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
