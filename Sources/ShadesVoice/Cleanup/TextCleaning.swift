import Foundation

public protocol TextCleaning: AnyObject {
    func clean(_ raw: String) async -> String?
}
