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
}
