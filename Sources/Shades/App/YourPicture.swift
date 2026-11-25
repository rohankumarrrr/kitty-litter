import Foundation
import ShadesContext
import ShadesCore

enum YourPicture {
    static let side: CGFloat = 128

    static var file: URL { Settings.directory.appendingPathComponent("picture.jpg") }

    static func load(from file: URL = file) -> Data? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return Drop.file(file).thumbnail(side: side)
    }

    static func save(from picture: URL, to file: URL = file) throws {
        guard let small = Drop.file(picture).thumbnail(side: side) else { throw CocoaError(.fileReadCorruptFile) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try small.write(to: file, options: .atomic)
    }
}
