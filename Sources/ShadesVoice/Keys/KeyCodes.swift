import CoreGraphics
import ShadesCore

/// The physical keys behind `HoldKey`. Left and right share a modifier flag and differ by key code and device bit.
enum KeyCodes {
    static let rightCommand: Int64 = 54
    static let leftCommand: Int64 = 55
    static let leftShift: Int64 = 56
    static let capsLock: Int64 = 57
    static let leftOption: Int64 = 58
    static let leftControl: Int64 = 59
    static let rightShift: Int64 = 60
    static let rightOption: Int64 = 61
    static let rightControl: Int64 = 62
    static let function: Int64 = 63
    static let escape: Int64 = 53

    static func key(for code: Int64) -> HoldKey? {
        switch code {
        case function: return .fn
        case rightOption: return .rightOption
        case rightCommand: return .rightCommand
        case rightControl: return .rightControl
        default: return nil
        }
    }

    static func code(for key: HoldKey) -> Int64? {
        switch key {
        case .fn: return function
        case .rightOption: return rightOption
        case .rightCommand: return rightCommand
        case .rightControl: return rightControl
        case .off: return nil
        }
    }

    // These device bits come from IOKit's NX_DEVICE* masks. Left Option and right Option both set the
    // same `.maskAlternate`, so only these can tell which one moved when both are down.
    private static let deviceRightOption: UInt64 = 0x40
    private static let deviceLeftOption: UInt64 = 0x20
    private static let deviceRightCommand: UInt64 = 0x10
    private static let deviceLeftCommand: UInt64 = 0x08
    private static let deviceRightControl: UInt64 = 0x2000
    private static let deviceLeftControl: UInt64 = 0x01
    private static let deviceRightShift: UInt64 = 0x04
    private static let deviceLeftShift: UInt64 = 0x02

    /// Whether a hold key is down, given the flags from its own flagsChanged event.
    static func isDown(_ key: HoldKey, flags: CGEventFlags) -> Bool {
        switch key {
        case .fn: return flags.contains(.maskSecondaryFn)
        case .rightOption: return flags.rawValue & deviceRightOption != 0
        case .rightCommand: return flags.rawValue & deviceRightCommand != 0
        case .rightControl: return flags.rawValue & deviceRightControl != 0
        case .off: return false
        }
    }

    /// Whether any modifier other than `key` is being held.
    static func otherModifiersDown(besides key: HoldKey, flags: CGEventFlags) -> Bool {
        var others: UInt64 = deviceLeftOption | deviceLeftCommand | deviceLeftControl | deviceLeftShift | deviceRightShift
        if key != .rightOption { others |= deviceRightOption }
        if key != .rightCommand { others |= deviceRightCommand }
        if key != .rightControl { others |= deviceRightControl }
        if flags.rawValue & others != 0 { return true }
        return key != .fn && flags.contains(.maskSecondaryFn)
    }
}
