import AppKit
import CoreGraphics
import Foundation
import ShadesCore

public final class KeyHoldMonitor: KeyHoldMonitoring {
    public var onPress: ((HoldKey) -> Void)?
    public var onRelease: ((HoldKey) -> Void)?
    public var onCancel: ((HoldKey) -> Void)?

    public static var hasPermission: Bool { CGPreflightListenEventAccess() }

    @discardableResult
    public static func requestPermission() -> Bool { CGRequestListenEventAccess() }

    private var gesture = HoldGesture()
    private var keys: Set<HoldKey> = []
    private var tap: CFMachPort?
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private let threadReady = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var watchdog: DispatchSourceTimer?
    private var stateIsReliable = false

    public init() {}

    deinit { stop() }

    public func start(keys: [HoldKey]) throws {
        stop()
        let wanted = Set(keys.filter { $0 != .off })
        guard !wanted.isEmpty else { return }
        lock.withLock {
            self.keys = wanted
            gesture.reset()
        }

        var events: CGEventMask = 0
        for type in [CGEventType.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown] {
            events |= CGEventMask(1) << type.rawValue
        }
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<KeyHoldMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: events,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw VoiceError.inputMonitoringNeeded
        }
        self.tap = tap

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        let thread = Thread { [weak self] in
            let loop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            self?.runLoop = loop
            self?.threadReady.signal()
            CFRunLoopRun()
        }
        thread.qualityOfService = .userInteractive
        thread.name = "shades.voice.keys"
        self.thread = thread
        thread.start()
        threadReady.wait()
    }

    public func stop() {
        stopWatchdog()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoop { CFRunLoopStop(runLoop) }
        tap = nil
        runLoop = nil
        thread = nil
        lock.withLock { gesture.reset() }
    }

    func setKeysForTesting(_ keys: Set<HoldKey>) {
        lock.withLock { self.keys = keys }
    }

    func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged:
            handleFlags(event)
        case .keyDown:
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return }
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let output = lock.withLock { code == KeyCodes.escape ? gesture.escapePressed() : gesture.otherKeyPressed(at: event.seconds) }
            deliver(output)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            deliver(lock.withLock { gesture.otherKeyPressed(at: event.seconds) })
        default:
            break
        }
    }

    private func handleFlags(_ event: CGEvent) {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let time = event.seconds

        guard let key = KeyCodes.key(for: code), lock.withLock({ keys.contains(key) }) else {
            guard code != KeyCodes.capsLock, isModifierGoingDown(code: code, flags: flags) else { return }
            deliver(lock.withLock { gesture.otherKeyPressed(at: time) })
            return
        }

        let isDown = KeyCodes.isDown(key, flags: flags)
        let others = KeyCodes.otherModifiersDown(besides: key, flags: flags)
        deliver(lock.withLock { gesture.keyChanged(key, isDown: isDown, otherModifiers: others, at: time) })
    }

    private func isModifierGoingDown(code: Int64, flags: CGEventFlags) -> Bool {
        switch code {
        case KeyCodes.leftShift, KeyCodes.rightShift: return flags.contains(.maskShift)
        case KeyCodes.leftCommand, KeyCodes.rightCommand: return flags.contains(.maskCommand)
        case KeyCodes.leftOption, KeyCodes.rightOption: return flags.contains(.maskAlternate)
        case KeyCodes.leftControl, KeyCodes.rightControl: return flags.contains(.maskControl)
        case KeyCodes.function: return flags.contains(.maskSecondaryFn)
        default: return false
        }
    }

    private func deliver(_ output: HoldGesture.Output?) {
        guard let output else { return }
        switch output {
        case .press(let key):
            startWatchdog(for: key)
            DispatchQueue.main.async { [weak self] in self?.onPress?(key) }
        case .release(let key):
            stopWatchdog()
            DispatchQueue.main.async { [weak self] in self?.onRelease?(key) }
        case .cancel(let key):
            stopWatchdog()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let onCancel = self.onCancel { onCancel(key) } else { self.onRelease?(key) }
            }
        }
    }

    // Outside the repo: Secure Keyboard Entry hides events from the tap, so a key's release can go unseen.
    private func startWatchdog(for key: HoldKey) {
        stopWatchdog()
        stateIsReliable = Self.isPhysicallyDown(key)
        guard stateIsReliable else { return }
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        timer.schedule(deadline: .now() + 0.25, repeating: 0.25)
        var misses = 0
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            misses = Self.isPhysicallyDown(key) ? 0 : misses + 1
            guard misses >= 2 else { return }
            self.deliver(self.lock.withLock { self.gesture.releaseWasMissed() })
            self.stopWatchdog()
        }
        lock.withLock { watchdog = timer }
        timer.resume()
    }

    private func stopWatchdog() {
        lock.withLock {
            watchdog?.cancel()
            watchdog = nil
        }
    }

    private static func isPhysicallyDown(_ key: HoldKey) -> Bool {
        if key == .fn {
            return CGEventSource.flagsState(.hidSystemState).contains(.maskSecondaryFn)
        }
        guard let code = KeyCodes.code(for: key) else { return false }
        return CGEventSource.keyState(.hidSystemState, key: CGKeyCode(code))
    }

    public enum GlobeAction: Int {
        case doNothing = 0, changeInputSource = 1, showEmoji = 2, startDictation = 3
    }

    public static var globeAction: GlobeAction? {
        CFPreferencesAppSynchronize("com.apple.HIToolbox" as CFString)
        let value = CFPreferencesCopyAppValue("AppleFnUsageType" as CFString, "com.apple.HIToolbox" as CFString)
        return (value as? Int).flatMap(GlobeAction.init(rawValue:))
    }

    public static func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

extension CGEvent {
    fileprivate var seconds: TimeInterval { TimeInterval(timestamp) / 1_000_000_000 }
}
