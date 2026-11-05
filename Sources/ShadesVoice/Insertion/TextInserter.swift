import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation
import ShadesCore

/// Types dictated text wherever the cursor is.
///
/// Native text fields take it directly through Accessibility, which leaves the clipboard alone, and the
/// result is read back to prove it landed. Everything else gets a paste, with your clipboard put back after.
public final class TextInserter: TextInserting {
    public enum Method: String, Sendable {
        case accessibility, paste, nothing
    }

    /// How the last insert got there.
    public private(set) var lastMethod = Method.nothing
    public private(set) var lastSeconds: TimeInterval = 0

    /// Web views, terminals and Electron apps, where Accessibility tends to report success without typing
    /// anything, or breaks undo. The read-back would catch most of that, but paste just works there.
    public static let pasteOnlyPrefixes = [
        "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "org.mozilla.firefox", "company.thebrowser",
        "com.apple.Safari", "com.apple.Terminal", "com.googlecode.iterm2", "net.kovidgoyal.kitty", "com.mitchellh.ghostty",
        "dev.warp", "co.zeit.hyper", "com.tinyspeck.slackmacgap", "com.microsoft.VSCode", "com.todesktop", "com.cursor",
        "com.linear", "notion.id", "md.obsidian", "com.hnc.Discord", "com.figma", "com.apple.dt.Xcode",
    ]

    /// How long apps get to read the clipboard before it's put back. Slow Electron apps need most of this.
    public var clipboardHold: TimeInterval = 0.6
    /// Always paste, for trying that path in a native app.
    public var pasteOnly = false

    private var pendingRestore: Task<Void, Never>?

    public init() {}

    /// Whether the system lets this app read fields and send keystrokes. Doesn't prompt.
    public static var hasPermission: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt for Accessibility.
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
        // Secure input with no readable field is most likely a password box on a web page. With a
        // plain text field in front it's probably left over from another app, and shouldn't block you.
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

    static func isPasteOnly(_ bundleID: String?) -> Bool {
        // No bundle ID means something unusual, and paste is the choice that always works.
        guard let bundleID else { return true }
        return pasteOnlyPrefixes.contains(where: bundleID.hasPrefix)
    }

    // MARK: - Paste

    private func paste(_ text: String) async throws {
        // A paste still waiting to restore has to finish, or its text would be saved as yours.
        await pendingRestore?.value

        let pasteboard = NSPasteboard.general
        let saved = PasteboardSnapshot(pasteboard)
        let ours = PasteboardSnapshot.write(text, to: pasteboard)

        // Keystrokes are read off the current keyboard layout, so this has to run on the main thread.
        let posted = await MainActor.run { Self.postPaste() }
        guard posted else {
            saved.restore(to: pasteboard)
            throw VoiceError.accessibilityNeeded
        }

        // There's no signal for when an app has read the clipboard, so this just waits long enough.
        let hold = clipboardHold
        pendingRestore = Task {
            try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))
            // If it changed, you copied something new, and that's the one to keep.
            if pasteboard.changeCount == ours {
                saved.restore(to: pasteboard)
            }
        }
    }

    /// Waits until the clipboard is back to how it was.
    public func finishRestoring() async {
        await pendingRestore?.value
    }

    private static func postPaste() -> Bool {
        // A private source, so a modifier you happen to be holding can't turn this into Command-Shift-V.
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

    /// Which physical key types `character` on the current layout. On Dvorak, V isn't where it is on QWERTY.
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

/// A copy of everything on the clipboard, every type of every item.
struct PasteboardSnapshot {
    private let items: [[(NSPasteboard.PasteboardType, Data)]]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }

    static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    static let autoGenerated = NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType")

    /// Puts dictated text on the clipboard, marked so clipboard managers leave it out of their history.
    /// Returns the change count, for telling later whether anything else has written since.
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
            // Putting it back isn't a new copy, so histories shouldn't list it twice.
            item.setData(Data(), forType: Self.transient)
            return item
        }
        pasteboard.writeObjects(restored)
    }
}

/// The text field with the cursor, as Accessibility sees it.
struct FocusedField {
    let element: AXUIElement
    let bundleID: String?
    let isSecure: Bool
    let isTextField: Bool
    let canSetSelection: Bool
    let textBefore: String?
    let textAfter: String?

    private static let editableRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    static func current() -> FocusedField? {
        // The system-wide element is the direct way, but it can refuse, so the front app is asked next.
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
        // swiftlint:disable:next force_cast
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
        } else {
            textBefore = nil
            textAfter = nil
        }
    }

    /// Sets the selected text, then checks it actually happened. Some apps report success and do nothing.
    func insert(_ text: String) -> Bool {
        guard let before = Self.valueAndSelection(element) else { return false }
        let status = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
        guard status == .success else { return false }

        let inserted = (text as NSString).length
        let expected = before.value.length - before.selection.length + inserted
        // Native fields update at once, and a blink of patience covers the slower ones.
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
        // swiftlint:disable:next force_cast
        guard AXValueGetValue(selection as! AXValue, .cfRange, &range) else { return nil }
        return (text as NSString, NSRange(location: range.location, length: range.length))
    }
}
