import AppKit
import ShadesCore

// The one place that decides what's real. To wire in the real modules, import them here
// and replace the body of this function with:
//
//     let voice = ParakeetVoiceEngine()
//     return AppDependencies(
//         backend: T3Backend(),                 // ShadesT3
//         context: ScreenContextProvider(),     // ShadesContext
//         voice: voice,                         // ShadesVoice, as are the next two
//         inserter: TextInserter(),
//         keys: KeyHoldMonitor(),
//         settings: Settings.load(),
//         saveSettings: { try? $0.save() }
//     )
//
// Nothing else needs to change. `--demo` keeps working either way.
@MainActor
func realDependencies() -> AppDependencies? {
    nil
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let wantsDemo = CommandLine.arguments.contains("--demo")
    let stage = AppStage()
    let controller: AppController
    var driver: DemoDriver?

    if !wantsDemo, let real = realDependencies() {
        controller = AppController(dependencies: real, stage: stage)
    } else {
        if !wantsDemo { print("The real modules aren't wired in yet, so this is the demo.") }
        let parts = Demo.make()
        controller = AppController(dependencies: parts.dependencies, stage: stage)
        driver = DemoDriver(parts: parts, controller: controller, stage: stage)
    }

    stage.controller = controller
    stage.start()
    controller.start()
    driver?.start(script: !CommandLine.arguments.contains("--no-script"))

    // The run loop never returns, so these stay alive for the life of the app.
    withExtendedLifetime((stage, controller, driver)) {
        app.run()
    }
}
