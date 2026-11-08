import Foundation
import ShadesContext
import ShadesCore

/// Your picture beside your messages, as each kitten has its cat. It's a small copy in the app's folder, made from any
/// picture you give it, and it's only ever drawn: in Messages and on your paired phone, never sent to T3.
enum YourPicture {
    /// Its longest side in pixels, enough for a 32 point circle on a 3x phone.
    static let side: CGFloat = 128

    static var file: URL { Settings.directory.appendingPathComponent("picture.jpg") }

    /// `nil` with none, which keeps your messages as they were. A picture put there by hand is made small too.
    static func load(from file: URL = file) -> Data? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return Drop.file(file).thumbnail(side: side)
    }

    /// Keeps a small copy of `picture`, so the original can move or go.
    static func save(from picture: URL, to file: URL = file) throws {
        guard let small = Drop.file(picture).thumbnail(side: side) else { throw CocoaError(.fileReadCorruptFile) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try small.write(to: file, options: .atomic)
    }
}
