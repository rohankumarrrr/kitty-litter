import AppKit
import ShadesContext
import ShadesCore
import ShadesT3

// The one place that decides what's real. `--demo` swaps all of it for fakes.
@MainActor
func realDependencies() -> AppDependencies {
    let context = ScreenContextProvider()
    let voice = Demo.make()
    return AppDependencies(
        backend: T3Backend(),
        context: context,
        voice: voice.voice,
        inserter: voice.inserter,
        keys: voice.keys,
        settings: Settings.load(),
        saveSettings: { try? $0.save() },
        screenTip: { context.takeJavaScriptTip() }
    )
}

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
        controller = AppController(dependencies: realDependencies(), stage: stage)
        stage.menuBar.extras = [MenuBar.Extra(title: "Permissions...", action: Setup.openSettingsForWhatsMissing)]
    }

    stage.controller = controller
    stage.start()
    controller.start()
    driver?.start(script: !CommandLine.arguments.contains("--no-script"))
    if !wantsDemo {
        if DevFlags.wantsFlow {
            DevFlags.run(on: controller)
        } else {
            Setup.runOnFirstLaunch()
        }
    }

    // The run loop never returns, so these stay alive for the life of the app.
    withExtendedLifetime((stage, controller, driver)) {
        app.run()
    }
}
