import AppKit

@MainActor
enum Offstage {
    static var isOn = false {
        didSet {
            guard isOn != oldValue else { return }
            _ = standInsSwapped
            if let awake { ProcessInfo.processInfo.endActivity(awake) }
            awake = isOn ? ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "A run with nothing on the screen keeps its timing") : nil
        }
    }

    static func alpha(of window: NSWindow) -> CGFloat {
        objc_getAssociatedObject(window, &alphaKey) as? CGFloat ?? window.alphaValue
    }

    static func takesClicks(_ window: NSWindow) -> Bool {
        !(objc_getAssociatedObject(window, &clicksKey) as? Bool ?? window.ignoresMouseEvents)
    }

    static func isSeen(_ window: NSWindow) -> Bool {
        CATransaction.flush()
        let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        let drawn = windows.first { $0[kCGWindowNumber as String] as? Int == window.windowNumber }
        return window.isVisible && (drawn?[kCGWindowAlpha as String] as? Double ?? 0) > 0
    }

    fileprivate static weak var keyWindow: NSWindow?
    private static var awake: NSObjectProtocol?
    fileprivate static var alphaKey = 0
    fileprivate static var clicksKey = 0

    fileprivate static func give(keyboardTo window: NSWindow?) {
        guard keyWindow !== window else { return }
        let old = keyWindow
        keyWindow = window
        old.map { NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: $0) }
        window.map { NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: $0) }
    }

    private static let standInsSwapped: Void = {
        swap(NSWindow.self, #selector(setter: NSWindow.alphaValue), #selector(NSWindow.offstageSetAlpha(_:)))
        swap(NSWindow.self, #selector(setter: NSWindow.ignoresMouseEvents), #selector(NSWindow.offstageSetIgnoresMouseEvents(_:)))
        swap(NSWindow.self, #selector(NSWindow.order(_:relativeTo:)), #selector(NSWindow.offstageOrderWindow(_:relativeTo:)))
        swap(NSWindow.self, #selector(NSWindow.orderFrontRegardless), #selector(NSWindow.offstageOrderFrontRegardless))
        swap(NSWindow.self, #selector(NSWindow.makeKey), #selector(NSWindow.offstageMakeKey))
        swap(NSWindow.self, #selector(NSWindow.makeKeyAndOrderFront(_:)), #selector(NSWindow.offstageMakeKeyAndOrderFront(_:)))
        swap(NSWindow.self, #selector(getter: NSWindow.isKeyWindow), #selector(getter: NSWindow.offstageIsKeyWindow))
        swap(NSApplication.self, #selector(getter: NSApplication.keyWindow), #selector(getter: NSApplication.offstageKeyWindow))
        swap(NSMenu.self, #selector(NSMenu.popUp(positioning:at:in:)), #selector(NSMenu.offstagePopUp(positioning:at:in:)))
    }()

    private static func swap(_ type: AnyClass, _ original: Selector, _ standIn: Selector) {
        guard let real = class_getInstanceMethod(type, original), let stand = class_getInstanceMethod(type, standIn) else {
            fatalError("Offstage can't stand in for \(original) on \(type), so a run trying The Kitty Litter out could show on the screen.")
        }
        method_exchangeImplementations(real, stand)
    }
}

extension NSWindow {
    // Outside the repo: once Offstage swaps the methods, each offstage name below runs AppKit's own.
    @objc fileprivate func offstageSetAlpha(_ alpha: CGFloat) {
        guard Offstage.isOn else { return offstageSetAlpha(alpha) }
        objc_setAssociatedObject(self, &Offstage.alphaKey, alpha, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        offstageSetAlpha(0)
    }

    @objc fileprivate func offstageSetIgnoresMouseEvents(_ ignores: Bool) {
        guard Offstage.isOn else { return offstageSetIgnoresMouseEvents(ignores) }
        objc_setAssociatedObject(self, &Offstage.clicksKey, ignores, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        offstageSetIgnoresMouseEvents(true)
    }

    private func goOffstage() {
        if objc_getAssociatedObject(self, &Offstage.alphaKey) == nil { alphaValue = alphaValue }
        if objc_getAssociatedObject(self, &Offstage.clicksKey) == nil { ignoresMouseEvents = ignoresMouseEvents }
    }

    @objc fileprivate func offstageOrderWindow(_ place: NSWindow.OrderingMode, relativeTo other: Int) {
        guard Offstage.isOn else { return offstageOrderWindow(place, relativeTo: other) }
        if place == .out, Offstage.keyWindow === self { Offstage.give(keyboardTo: nil) }
        if place != .out { goOffstage() }
        offstageOrderWindow(place, relativeTo: other)
    }

    @objc fileprivate func offstageOrderFrontRegardless() {
        if Offstage.isOn { goOffstage() }
        offstageOrderFrontRegardless()
    }

    @objc fileprivate func offstageMakeKey() {
        guard Offstage.isOn else { return offstageMakeKey() }
        if canBecomeKey { Offstage.give(keyboardTo: self) }
    }

    @objc fileprivate func offstageMakeKeyAndOrderFront(_ sender: Any?) {
        guard Offstage.isOn else { return offstageMakeKeyAndOrderFront(sender) }
        orderFrontRegardless()
        makeKey()
    }

    @objc fileprivate var offstageIsKeyWindow: Bool {
        guard Offstage.isOn else { return self.offstageIsKeyWindow }
        return Offstage.keyWindow === self && isVisible
    }
}

extension NSApplication {
    @objc fileprivate var offstageKeyWindow: NSWindow? {
        guard Offstage.isOn else { return self.offstageKeyWindow }
        return Offstage.keyWindow.flatMap { $0.isVisible ? $0 : nil }
    }
}

extension NSMenu {
    @MainActor @objc fileprivate func offstagePopUp(positioning item: NSMenuItem?, at location: NSPoint, in view: NSView?) -> Bool {
        guard Offstage.isOn else { return offstagePopUp(positioning: item, at: location, in: view) }
        return false
    }
}
