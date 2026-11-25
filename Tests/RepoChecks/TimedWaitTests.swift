import XCTest

final class TimedWaitTests: XCTestCase {
    static let timedWaits = ["Task.sleep", "Thread.sleep", "usleep(", "RunLoop.main.run(until", "RunLoop.current.run(until", "Task.yield()", ".asyncAfter("]
    static let waitingHelpers = "Tests/TestSupport/"

    static let timedWaitsLeft: [String: Int] = [
        "Tests/ShadesCoreTests/ChangeRequestAttackTests.swift": 3,
        "Tests/ShadesCoreTests/InstallLockTests.swift": 1,
        "Tests/ShadesT3Tests/T3AuthTests.swift": 1,
        "Tests/ShadesTests/AskFlowTests.swift": 5,
        "Tests/ShadesTests/AttachmentsTests.swift": 4,
        "Tests/ShadesTests/CatWindowsTests.swift": 1,
        "Tests/ShadesTests/ChangeRequestFlowTests.swift": 8,
        "Tests/ShadesTests/ChannelFeedTests.swift": 3,
        "Tests/ShadesTests/ChannelNotificationsTests.swift": 1,
        "Tests/ShadesTests/ChannelsWindowTests.swift": 1,
        "Tests/ShadesTests/DemoRecorderTests.swift": 1,
        "Tests/ShadesTests/DoNotDisturbTests.swift": 1,
        "Tests/ShadesTests/Fakes.swift": 1,
        "Tests/ShadesTests/FlowTests.swift": 95,
        "Tests/ShadesTests/LockdownEdgeTests.swift": 2,
        "Tests/ShadesTests/LockdownTests.swift": 1,
        "Tests/ShadesTests/MessageSearchTests.swift": 1,
        "Tests/ShadesTests/MessagesShortcutsTests.swift": 1,
        "Tests/ShadesTests/MessagesVoiceTests.swift": 1,
        "Tests/ShadesTests/PhoneServerTests.swift": 14,
        "Tests/ShadesTests/PressPhoneTests.swift": 4,
        "Tests/ShadesTests/PressWindowsTests.swift": 1,
        "Tests/ShadesTests/ScreenBoundaryTests.swift": 2,
        "Tests/ShadesTests/SettingsTests.swift": 1,
        "Tests/ShadesTests/ShadesConversationTests.swift": 1,
        "Tests/ShadesVoiceTests/EngineTests.swift": 7,
        "Tests/ShadesVoiceTests/HoldGestureTests.swift": 3,
        "Tests/ShadesVoiceTests/VocabularyQueueTests.swift": 1,
    ]

    func testATestWaitsOnTheThingItselfNeverASetTimeOrACountOfYields() throws {
        let files = try Repo.files(under: ["Tests"], endingIn: [".swift"]).filter { !$0.hasPrefix(Self.waitingHelpers) }
        for file in files {
            let count = Self.timedWaits(in: try Repo.read(file))
            let allowed = Self.timedWaitsLeft[file, default: 0]
            if count > allowed {
                XCTFail("""
                \(file) waits a set time or a count of yields \(count) times, where \(allowed) are allowed. GitHub's \
                runner can stall for a second or two, so wait on the thing itself, with `await until { condition }` or \
                `runMainLoop(until: { condition })` from Tests/TestSupport/Waiting.swift. To hold a fake back, have it \
                await something the test lets go of.
                """)
            } else if count < allowed {
                XCTFail("\(file) waits a set time \(count) times now, fewer than TimedWaitTests.timedWaitsLeft allows. Lower it to \(count), so they can't come back.")
            }
        }
        for file in Self.timedWaitsLeft.keys where !files.contains(file) {
            XCTFail("\(file) is gone, so take it out of TimedWaitTests.timedWaitsLeft.")
        }
    }

    static func timedWaits(in source: String) -> Int {
        SwiftLexer(source).pieces.reduce(0) { total, piece in
            guard case .code(let code) = piece else { return total }
            return total + timedWaits.reduce(0) { $0 + code.components(separatedBy: $1).count - 1 }
        }
    }
}
