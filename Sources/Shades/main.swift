import AppKit
import ShadesContext
import ShadesCore
import ShadesT3
import ShadesVoice

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.appearance = NSAppearance(named: .darkAqua)

    let wantsDemo = CommandLine.arguments.contains("--demo")
    if DevFlags.wantsChannelsCheck { DevFlags.checkChannels() }
    if let picture = DevFlags.pictureFile { DevFlags.savePicture(from: picture) }
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
        controller.readPriorities = DemoChannels.priorities
    } else {
        let keepsToItself = !DevFlags.isInstalledApp()
        let signIn = DevFlags.signInService()
        let backend = T3Backend(credentials: KeychainCredentialStore(service: signIn), label: keepsToItself ? "Shades trial" : "Shades", revokesWhatItCantRead: !keepsToItself)
        let context = ScreenContextProvider()
        let voice = ParakeetVoiceEngine()
        let keys = KeyHoldMonitor()
        let inboxFile = Settings.directory.appendingPathComponent("inbox.json")
        let notifications = keepsToItself ? nil : NeedsYouNotifications()
        if !keepsToItself { Settings.rewriteInTodaysForm() }
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
                saveSettings: { if !DevFlags.wantsFlow { try? $0.save() } },
                screenTip: { context.takeJavaScriptTip() },
                kittens: { Kittens.load() },
                systemFacts: { SystemHealth.facts() },
                fileExists: { FileManager.default.fileExists(atPath: $0) },
                screenBlockGaps: { ScreenBlock.gaps(in: FileManager.default.contents(atPath: $0 + "/.claude/settings.json")) },
                routerFolder: { try? RouterBlock.prepare(Settings.directory.appendingPathComponent("router", isDirectory: true)) },
                reportHealth: { findings, lockdown in
                    guard !keepsToItself else { return }
                    let version = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
                    let report = HealthCheck.report(findings, pid: getpid(), version: version, at: Date(), lockdown: lockdown)
                    SystemHealth.write(report, to: Settings.directory.appendingPathComponent("health.json"))
                },
                inbox: keepsToItself ? Inbox(since: .distantFuture) : Inbox.load(from: inboxFile, now: Date()),
                saveInbox: { inbox in
                    if !keepsToItself { try inbox.save(to: inboxFile) }
                },
                hidesTestThreads: !DevFlags.wantsFlow,
                notify: { notifications?.post($0) },
                withdrawNotifications: { notifications?.withdraw($0) },
                clearNotifications: { notifications?.clear() },
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
        real.readPriorities = { Priorities.read(for: $0) }
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

    withExtendedLifetime((stage, controller, driver)) {
        app.run()
    }
}
