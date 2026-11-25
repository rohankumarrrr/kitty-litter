import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation
import ShadesCore

public final class TextInserter: TextInserting {
    public enum Method: String, Sendable {
        case accessibility, paste, nothing
    }

    public private(set) var lastMethod = Method.nothing
    public private(set) var lastSeconds: TimeInterval = 0

    // Outside the repo: in web views, terminals and Electron apps, Accessibility can report success without typing anything, or break undo.
    public static let pasteOnlyPrefixes = [
        "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "org.mozilla.firefox", "company.thebrowser",
        "com.apple.Safari", "com.apple.Terminal", "com.googlecode.iterm2", "net.kovidgoyal.kitty", "com.mitchellh.ghostty",
        "dev.warp", "co.zeit.hyper", "com.tinyspeck.slackmacgap", "com.microsoft.VSCode", "com.todesktop", "com.cursor",
        "com.linear", "notion.id", "md.obsidian", "com.hnc.Discord", "com.figma", "com.apple.dt.Xcode",
    ]

    public var clipboardHold: TimeInterval = 0.6
    public var pasteOnly = false

    private var pendingRestore: Task<Void, Never>?

    public init() {}

    public static var hasPermission: Bool { AXIsProcessTrusted() }

    public static func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    public func insert(_ text: String) async throws {
        guard !text.isEmpty else { return }
        guard AXIsProcessTrusted() else { throw VoiceError.accessibilityNeeded }
        let started = Date()

        let target = FocusedField.current()
        if target?.isSecure == true { throw VoiceError.passwordField }
        // Outside the repo: another app can leave secure input on, so it only means a password box when no plain text field is in front.
        if IsSecureEventInputEnabled(), target?.isTextField != true { throw VoiceError.passwordField }

        let fitted = TextFit.fit(text, before: target?.textBefore, after: target?.textAfter)

        if !pasteOnly, let target, target.canSetSelection, !Self.isPasteOnly(target.bundleID), target.insert(fitted) {
            lastMethod = .accessibility
        } else {
            try await paste(fitted)
            lastMethod = .paste
        }
        lastSeconds = Date().timeIntervalSince(started)
    }

    public func replaceSelection(_ original: String, in bundleID: String?, with text: String) async -> Bool {
        guard AXIsProcessTrusted(), let target = FocusedField.current(), target.bundleID == bundleID,
              !target.isSecure, target.canSetSelection, !Self.isPasteOnly(bundleID), target.selectedText == original
        else { return false }
        return target.insert(TextFit.inPlace(of: original, text))
    }

    static func isPasteOnly(_ bundleID: String?) -> Bool {
        guard let bundleID else { return true }
        return pasteOnlyPrefixes.contains(where: bundleID.hasPrefix)
    }

    private func paste(_ text: String) async throws {
        await pendingRestore?.value

        let pasteboard = NSPasteboard.general
        let saved = PasteboardSnapshot(pasteboard)
        let ours = PasteboardSnapshot.write(text, to: pasteboard)

        let posted = await MainActor.run { Self.postPaste() }
        guard posted else {
            saved.restore(to: pasteboard)
            throw VoiceError.accessibilityNeeded
        }

        // Outside the repo: macOS gives no signal for when an app has read the clipboard.
        let hold = clipboardHold
        pendingRestore = Task {
            try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))
            if pasteboard.changeCount == ours {
                saved.restore(to: pasteboard)
            }
        }
    }

    public func finishRestoring() async {
        await pendingRestore?.value
    }

    private static func postPaste() -> Bool {
        guard let source = CGEventSource(stateID: .privateState) else { return false }
        let key = keyCode(for: "v") ?? CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
        return true
    }

    private static func keyCode(for character: Character) -> CGKeyCode? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> CGKeyCode? in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return nil }
            for code in 0..<UInt16(128) {
                var state: UInt32 = 0
                var length = 0
                var buffer = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout, code, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysBit), &state, buffer.count, &length, &buffer
                )
                if status == noErr, length == 1, String(utf16CodeUnits: buffer, count: 1) == String(character) {
                    return CGKeyCode(code)
                }
            }
            return nil
        }
    }
}

struct PasteboardSnapshot {
    private let items: [[(NSPasteboard.PasteboardType, Data)]]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }

    static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    static let autoGenerated = NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType")

    @discardableResult
    static func write(_ text: String, to pasteboard: NSPasteboard) -> Int {
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: transient)
        item.setData(Data(), forType: autoGenerated)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        return pasteboard.changeCount
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restored = items.map { pairs -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in pairs { item.setData(data, forType: type) }
            item.setData(Data(), forType: Self.transient)
            return item
        }
        pasteboard.writeObjects(restored)
    }
}

struct FocusedField {
    let element: AXUIElement
    let bundleID: String?
    let isSecure: Bool
    let isTextField: Bool
    let canSetSelection: Bool
    let textBefore: String?
    let textAfter: String?
    let selectedText: String?

    private static let editableRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    static func current() -> FocusedField? {
        if let element = focusedElement(in: AXUIElementCreateSystemWide()) { return FocusedField(element: element) }
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let element = focusedElement(in: AXUIElementCreateApplication(pid))
        else { return nil }
        return FocusedField(element: element)
    }

    private static func focusedElement(in parent: AXUIElement) -> AXUIElement? {
        AXUIElementSetMessagingTimeout(parent, 0.1)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        return (focused as! AXUIElement)
    }

    init(element: AXUIElement) {
        self.element = element
        AXUIElementSetMessagingTimeout(element, 0.1)

        var pid = pid_t(0)
        AXUIElementGetPid(element, &pid)
        bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier

        let role = Self.string(element, kAXRoleAttribute) ?? ""
        let subrole = Self.string(element, kAXSubroleAttribute) ?? ""
        isSecure = subrole == "AXSecureTextField" || role == "AXSecureTextField"

        isTextField = Self.editableRoles.contains(role)

        var settable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable)
        canSetSelection = settable.boolValue && isTextField

        if let (value, range) = Self.valueAndSelection(element) {
            let start = max(0, min(range.location, value.length))
            let end = max(start, min(range.location + range.length, value.length))
            let contextLength = 200
            textBefore = value.substring(with: NSRange(location: max(0, start - contextLength), length: start - max(0, start - contextLength)))
            textAfter = value.substring(with: NSRange(location: end, length: min(contextLength, value.length - end)))
            selectedText = value.substring(with: NSRange(location: start, length: end - start))
        } else {
            textBefore = nil
            textAfter = nil
            selectedText = nil
        }
    }

    func insert(_ text: String) -> Bool {
        guard let before = Self.valueAndSelection(element) else { return false }
        let status = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
        guard status == .success else { return false }

        let inserted = (text as NSString).length
        let expected = before.value.length - before.selection.length + inserted
        for attempt in 0..<4 {
            if attempt > 0 { usleep(8_000) }
            if let after = Self.valueAndSelection(element), after.value.length == expected {
                let landed = NSRange(location: before.selection.location, length: inserted)
                if landed.location + landed.length <= after.value.length, after.value.substring(with: landed) == text {
                    return true
                }
            }
        }
        return false
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func valueAndSelection(_ element: AXUIElement) -> (value: NSString, selection: NSRange)? {
        var value: CFTypeRef?
        var selection: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selection) == .success,
              let text = value as? String, let selection, CFGetTypeID(selection) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue(selection as! AXValue, .cfRange, &range) else { return nil }
        return (text as NSString, NSRange(location: range.location, length: range.length))
    }
}
