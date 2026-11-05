import CoreGraphics
import Foundation
import ShadesCore

/// Runs a flow from the command line, so it can be tried without touching the mouse or
/// keyboard. With `--image`, the agent sees that picture instead of your real screen.
///
///     shades --ask "What's on my screen?" --image page.jpg
///     shades --hand-off "Which of my projects is the budget app?" --image page.jpg
///     shades --fix "The total is wrong" --image page.jpg
///     shades --ask "Research this" --then "And that part?" --image page.jpg   # waits for the agents first
@MainActor
enum DevFlags {
    static var wantsFlow: Bool { ["--ask", "--hand-off", "--fix"].contains { value(after: $0) != nil } }

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
