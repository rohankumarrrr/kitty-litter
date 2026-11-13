import AppKit
import Carbon.HIToolbox

/// Global shortcuts through Carbon, which is still the one way that needs no permissions. Each is claimed for Shades
/// alone, so a shortcut another app already has fails here and the cat says so, instead of both quietly firing.
@MainActor
final class Hotkeys {
    static let shared = Hotkeys()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var installed = false

    private static let signature: OSType = 0x5348_4453 // SHDS
    /// A shared claim on a shortcut another app holds still succeeds, and then only one of them gets the key.
    /// Only an exclusive claim is refused, which is how Shades can tell you instead.
    static let options = OptionBits(kEventHotKeyExclusive)
    /// Off in a demo or a copy trying a flow out. Those press their keys through the controller, and a claim of theirs
    /// would take the shortcuts from the installed app whenever it starts while they run.
    var claimsKeys = true

    @discardableResult
    func register(keyCode: Int, modifiers: Int, handler: @escaping () -> Void) -> UInt32? {
        let id = nextID
        nextID += 1
        guard claimsKeys else { return id }
        installIfNeeded()
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(),
            Self.options,
            &ref
        )
        guard status == noErr, let ref else { return nil }
        refs[id] = ref
        handlers[id] = handler
        return id
    }

    func unregister(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        handlers.removeValue(forKey: id)
    }

    private func installIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &id
            )
            guard status == noErr, id.signature == Hotkeys.signature else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated { Hotkeys.shared.handlers[id.id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

/// The app's fixed shortcuts, as Carbon claims them and as a menu shows them.
struct Shortcut: Equatable {
    let keyCode: Int
    let modifiers: Int
    let key: String
    let keyModifiers: NSEvent.ModifierFlags
    let label: String

    static let ask = Shortcut(keyCode: kVK_Space, modifiers: optionKey, key: " ", keyModifiers: .option, label: "⌥Space")
    static let fix = Shortcut(keyCode: kVK_ANSI_F, modifiers: controlKey | optionKey, key: "f", keyModifiers: [.control, .option], label: "⌃⌥F")
    /// ⌃⌘ like the shortcuts people often give their apps, on a letter they rarely take. M is often Messages.
    static let messages = Shortcut(keyCode: kVK_ANSI_B, modifiers: controlKey | cmdKey, key: "b", keyModifiers: [.control, .command], label: "⌃⌘B")
}
