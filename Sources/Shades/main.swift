import AppKit
import ShadesCore

// The one place that decides what's real.
//
// Integrator: replace the body of `realDependencies()` with the real modules, such as
// `T3Client()` from ShadesT3, the context provider from ShadesContext, and the voice
// engine, text inserter and key monitor from ShadesVoice. Nothing else needs to change.
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
