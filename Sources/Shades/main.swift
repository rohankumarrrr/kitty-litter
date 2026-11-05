import AppKit
import ShadesContext
import ShadesCore
import ShadesT3
import ShadesVoice

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let wantsDemo = CommandLine.arguments.contains("--demo")
    let stage = AppStage()
    let controller: AppController
    var driver: DemoDriver?

    if wantsDemo {
        let parts = Demo.make()
        controller = AppController(dependencies: parts.dependencies, stage: stage)
        driver = DemoDriver(parts: parts, controller: controller, stage: stage)
    } else {
        let backend = T3Backend()
        let context = ScreenContextProvider()
        let voice = ParakeetVoiceEngine()
        let keys = KeyHoldMonitor()
        let real = AppController(
            dependencies: AppDependencies(
                backend: backend,
                context: context,
                voice: voice,
                inserter: TextInserter(),
                keys: keys,
                settings: Settings.load(),
                saveSettings: { try? $0.save() },
                screenTip: { context.takeJavaScriptTip() },
                kittens: { Kittens.load() },
                systemFacts: { SystemHealth.facts() },
                fileExists: { FileManager.default.fileExists(atPath: $0) },
                reportHealth: { findings in
                    let version = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
                    let report = HealthCheck.report(findings, pid: getpid(), version: version, at: Date())
                    SystemHealth.write(report, to: Settings.directory.appendingPathComponent("health.json"))
                }
            ),
            stage: stage
        )
        controller = real
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
            MenuBar.Extra(title: "Permissions...", action: Setup.openSettingsForWhatsMissing),
            MenuBar.Extra(title: "Keyboard Settings...", action: KeyHoldMonitor.openKeyboardSettings),
            MenuBar.Extra(title: "Restart", action: Setup.restart),
        ]
    }

    stage.controller = controller
    stage.start()
    controller.start()
    driver?.start(script: !CommandLine.arguments.contains("--no-script"))
    if !wantsDemo {
        if DevFlags.wantsFlow {
            DevFlags.run(on: controller)
        } else {
            controller.startHealthChecks()
            Setup.runOnFirstLaunch {
                let globeIsFree = controller.settings.dictateKey != .fn || KeyHoldMonitor.globeAction == .doNothing
                controller.say(globeIsFree ? CatWords.setUp : "\(CatWords.setUp) \(CatWords.globeTip)", seconds: 20)
            }
        }
    }

    // The run loop never returns, so these stay alive for the life of the app.
    withExtendedLifetime((stage, controller, driver)) {
        app.run()
    }
}
