@testable import ShadesContext
import ShadesCore
import XCTest

final class CaptureStoreTests: XCTestCase {
    private var directory: URL!
    private var store: CaptureStore { CaptureStore(directory: directory) }

    override func setUp() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("shades-store-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func permissions(_ path: String) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        return (attributes[.posixPermissions] as! NSNumber).intValue
    }

    private func age(_ path: String, days: Double) throws {
        let date = Date().addingTimeInterval(-days * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: path)
    }

    func testOnlyYouCanReadWhatGetsSaved() throws {
        let path = try store.save(Data([1, 2, 3]))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), Data([1, 2, 3]))
        XCTAssertEqual(try permissions(path), 0o600)
        XCTAssertEqual(try permissions(directory.path), 0o700)
        XCTAssertTrue(path.hasPrefix(directory.path))
        XCTAssertTrue(path.hasSuffix(".jpg"))
    }

    func testTightensADirectoryThatAlreadyExists() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        _ = try store.save(Data([1]))
        XCTAssertEqual(try permissions(directory.path), 0o700)
    }

    func testTwoSavesInTheSameSecondDontCollide() throws {
        let now = Date()
        let first = try store.save(Data([1]), now: now)
        let second = try store.save(Data([2]), now: now)
        XCTAssertNotEqual(first, second)
    }

    func testDeletesCapturesOlderThanADayAndNothingElse() throws {
        let old = try store.save(Data([1]))
        let recent = try store.save(Data([2]))
        try age(old, days: 2)
        let notOurs = directory.appendingPathComponent("keep-me.jpg")
        try Data([3]).write(to: notOurs)
        try age(notOurs.path, days: 30)

        _ = try store.save(Data([4]))

        XCTAssertFalse(FileManager.default.fileExists(atPath: old))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recent))
        XCTAssertTrue(FileManager.default.fileExists(atPath: notOurs.path))
    }

    func testAnOldCaptureDoesntWaitForTheNextOneToBeCleanedUp() throws {
        let old = try store.save(Data([1]))
        try age(old, days: 2)
        store.removeOld()
        XCTAssertFalse(FileManager.default.fileExists(atPath: old))
    }

    func testTheRealStoreLivesInTheSettingsDirectory() {
        XCTAssertEqual(
            CaptureStore().directory.path,
            Settings.directory.appendingPathComponent("captures").path
        )
    }

    func testSavingGoesThroughTheProvider() throws {
        let provider = ScreenContextProvider(sources: FakeSources(), store: store, defaults: .standard)
        let path = try XCTUnwrap(provider.saveScreenshot(of: ScreenSnapshot(screenshotJPEG: Data([9]))))
        XCTAssertEqual(try permissions(path), 0o600)
    }
}
