import AppKit
import ShadesContext
import ShadesCore
import ShadesT3
import ShadesVoice

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    // Opal is dark only, menus and scrollers included.
    app.appearance = NSAppearance(named: .darkAqua)

    let wantsDemo = CommandLine.arguments.contains("--demo")
    if DevFlags.wantsChannelsCheck { DevFlags.checkChannels() }
    if let picture = DevFlags.pictureFile { DevFlags.savePicture(from: picture) }
    // Only with --demo, so real messages can't reach an image.
    if wantsDemo, let folder = DevFlags.channelsImageFolder {
        ChannelImages.draw(to: folder)
        exit(0)
    }
    let stage = AppStage()
    let controller: AppController
    var driver: DemoDriver?

    if wantsDemo {
        let parts = Demo.make()
        controller = AppController(dependencies: parts.dependencies, stage: stage)
        driver = DemoDriver(parts: parts, controller: controller, stage: stage)
        stage.channels.view.readPriorities = DemoChannels.priorities
    } else {
        // Any copy but the installed app, built from source, bundled elsewhere or trying a flow out, keeps to itself:
        // its own sign-in, and none of the app's inbox, notifications, phone keys or phone page.
        let keepsToItself = !DevFlags.isInstalledApp()
        let signIn = DevFlags.signInService()
        // Copies that aren't installed share one service and can run at once, so one can't tell another's sign-in
        // from a stale one.
        let backend = T3Backend(credentials: KeychainCredentialStore(service: signIn), label: keepsToItself ? "Shades trial" : "Shades", revokesWhatItCantRead: !keepsToItself)
        let context = ScreenContextProvider()
        let voice = ParakeetVoiceEngine()
        let keys = KeyHoldMonitor()
        let inboxFile = Settings.directory.appendingPathComponent("inbox.json")
        // Such a copy sees your real threads too, and the real app already says.
        let notifications = keepsToItself ? nil : NeedsYouNotifications()
        var settings = Settings.load()
        MessagesInk.picture = YourPicture.load()
        if keepsToItself { settings.phone = false }
        if let name = DevFlags.lockdownKitten, let kitten = Kittens.load().first(where: { $0.name == name }) {
            settings.lockdown = Lockdown(kitten: kitten.id)
        }
        let tailscale = keepsToItself ? nil : TailscaleServe(port: PhoneLink.port)
        let real = AppController(
            dependencies: AppDependencies(
                backend: backend,
                context: context,
                voice: voice,
                inserter: TextInserter(),
                keys: keys,
                settings: settings,
                // A copy trying a flow out can be set up for it, as with --lockdown, and that's never kept.
                saveSettings: { if !DevFlags.wantsFlow { try? $0.save() } },
                screenTip: { context.takeJavaScriptTip() },
                kittens: { Kittens.load() },
                systemFacts: { SystemHealth.facts() },
                fileExists: { FileManager.default.fileExists(atPath: $0) },
                screenBlockGaps: { ScreenBlock.gaps(in: FileManager.default.contents(atPath: $0 + "/.claude/settings.json")) },
                routerFolder: { try? RouterBlock.prepare(Settings.directory.appendingPathComponent("router", isDirectory: true)) },
                // The installed app's report is what the install waits for, so no other copy writes one.
                reportHealth: { findings, lockdown in
                    guard !keepsToItself else { return }
                    let version = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
                    let report = HealthCheck.report(findings, pid: getpid(), version: version, at: Date(), lockdown: lockdown)
                    SystemHealth.write(report, to: Settings.directory.appendingPathComponent("health.json"))
                },
                // It has no business filing anything, or touching the real file.
                inbox: keepsToItself ? Inbox(since: .distantFuture) : Inbox.load(from: inboxFile, now: Date()),
                saveInbox: { inbox in
                    if !keepsToItself { try inbox.save(to: inboxFile) }
                },
                hidesTestThreads: !DevFlags.wantsFlow,
                notify: { notifications?.post($0) },
                withdrawNotifications: { notifications?.withdraw($0) },
                clearNotifications: { notifications?.clear() },
                // Phone keys in memory, so it can never replace the app's own.
                phoneKeys: keepsToItself ? MemoryPhoneKeys() : KeychainPhoneKeys(),
                servePhone: { port in
                    guard let tailscale else { throw TailscaleServe.Problem(errorDescription: "Only the installed copy of me goes on your tailnet.") }
                    return try await tailscale.serve(to: port)
                },
                stopServingPhone: { await tailscale?.stop() },
                sendPush: { request in
                    (try? await URLSession(configuration: .ephemeral).data(for: request)).flatMap { ($0.1 as? HTTPURLResponse)?.statusCode }
                },
                recentFiles: { RecentFiles.find() },
                webPicture: { await WebPicture.fetch($0) }
            ),
            stage: stage
        )
        controller = real
        stage.channels.view.readPriorities = { Priorities.read(for: $0) }
        notifications?.onClick = { [weak real] in real?.showInMessages($0) }
        keys.onCancel = { [weak real] _ in
            MainActor.assumeIsolated { real?.cancelListening() }
        }
        voice.onSetupProgress = { [weak real] progress in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { real?.fetchingEars(progress.stage == .ready ? nil : progress.fraction) }
            }
        }
        Task { [weak real] in
            let projects = (try? await backend.projects()) ?? []
            real?.projectNames = projects.map(\.title).filter { $0 != "No project" }
        }
        stage.menuBar.extras = [
            MenuBar.Extra(title: "Check Myself") { real.checkMyselfPressed() },
            MenuBar.Extra(title: "Permissions…", action: Setup.openSettingsForWhatsMissing),
            MenuBar.Extra(title: "Keyboard Settings…", action: KeyHoldMonitor.openKeyboardSettings),
            MenuBar.Extra(title: "Restart", action: Setup.restart),
        ]
    }

    stage.controller = controller
    Hotkeys.shared.claimsKeys = !wantsDemo && !DevFlags.wantsFlow
    stage.start()
    controller.start()
    driver?.start(script: !CommandLine.arguments.contains("--no-script"))
    if DevFlags.wantsChannels { controller.channelsPressed() }
    if !wantsDemo {
        if DevFlags.wantsFlow {
            DevFlags.run(on: controller)
        } else {
            controller.startHealthChecks()
            Setup.runOnFirstLaunch {
                let globeIsFree = controller.settings.dictateKey != .fn || KeyHoldMonitor.globeAction == .doNothing
                controller.say(globeIsFree ? CatWords.setUp : "\(CatWords.setUp) \(CatWords.globeTip)")
            }
        }
    }

    // The run loop never returns, so these stay alive for the life of the app.
    withExtendedLifetime((stage, controller, driver)) {
        app.run()
    }
}
