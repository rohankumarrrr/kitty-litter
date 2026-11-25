import XCTest

final class LaunchMarkTests: XCTestCase {
    func testTheLaunchIsTimedFromTheFirstLineOfMain() throws {
        let code = try Repo.read("Sources/Shades/main.swift")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("import ") }
        XCTAssertEqual(Array(code.prefix(2)), ["MainActor.assumeIsolated {", "Launch.began = .now()"], """
        Sources/Shades/main.swift has to start by marking the launch, so `perf launch` times everything the app does \
        before its cat is up. Keep `Launch.began = .now()` as the first line inside `MainActor.assumeIsolated {`, and \
        put anything new after it.
        """)
    }

    func testTheCatIsOnScreenBeforeTheWindowsNobodySeesAtLaunchAreBuilt() throws {
        let stage = try Repo.read("Sources/Shades/main.swift")
            .split(separator: "\n")
            .filter { $0.contains("AppStage(") }
        XCTAssertEqual(stage.map { $0.trimmingCharacters(in: .whitespaces) }, ["let stage = AppStage(cat: Launch.putOnScreen(CatController()))"], """
        Sources/Shades/main.swift has to build the stage on a cat that's already on screen, with \
        `AppStage(cat: Launch.putOnScreen(CatController()))`. The stage builds the bubble, the Ask box and The Kitty \
        Litter's window, which nobody sees at launch, and on a cold launch, with macOS reading AppKit back in, they held \
        the cat back by 300 ms or more.
        """)
    }
}
