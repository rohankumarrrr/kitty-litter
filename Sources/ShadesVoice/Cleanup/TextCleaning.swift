import Foundation

/// Turns a raw transcript into written text.
public protocol TextCleaning: AnyObject {
    /// `nil` means this cleaner can't help right now, and the next one should try.
    func clean(_ raw: String) async -> String?
}
