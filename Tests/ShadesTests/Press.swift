import AppKit
import XCTest

@MainActor
enum Press {
    // Outside the repo: from macOS 27, Tab moves on only in the app's key window, which a window that's never shown can't be.
    nonisolated(unsafe) static weak var keyWindow: NSWindow? {
        didSet { _ = reportsKeyWindow }
    }

    nonisolated private static let reportsKeyWindow: Void = {
        guard let real = class_getInstanceMethod(NSApplication.self, #selector(getter: NSApplication.keyWindow)),
              let standIn = class_getInstanceMethod(NSApplication.self, #selector(getter: NSApplication.pressKeyWindow))
        else { return }
        method_exchangeImplementations(real, standIn)
    }()
    static func hit(_ control: NSView, at point: NSPoint? = nil, file: StaticString = #filePath, line: UInt = #line) throws -> NSView {
        let window = try XCTUnwrap(control.window, "\(type(of: control)) is in a window", file: file, line: line)
        window.contentView?.layoutSubtreeIfNeeded()
        let root = try XCTUnwrap(window.contentView?.superview ?? window.contentView, file: file, line: line)
        let centre = control.convert(point ?? NSPoint(x: control.bounds.midX, y: control.bounds.midY), to: nil)
        return try XCTUnwrap(root.hitTest(root.convert(centre, from: nil)), "something is under the pointer", file: file, line: line)
    }

    @discardableResult
    static func click(_ control: NSView, at point: NSPoint? = nil, file: StaticString = #filePath, line: UInt = #line) throws -> NSView {
        let target = try hit(control, at: point, file: file, line: line)
        let window = try XCTUnwrap(control.window, file: file, line: line)
        let centre = control.convert(point ?? NSPoint(x: control.bounds.midX, y: control.bounds.midY), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: centre, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1), file: file, line: line)
            type == .leftMouseDown ? target.mouseDown(with: event) : target.mouseUp(with: event)
        }
        return target
    }

    static func key(_ characters: String, keyCode: UInt16 = 0, modifiers: NSEvent.ModifierFlags = [], on view: NSView, file: StaticString = #filePath, line: UInt = #line) throws {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: view.window?.windowNumber ?? 0, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode), file: file, line: line)
            type == .keyDown ? view.keyDown(with: event) : view.keyUp(with: event)
        }
    }
}

extension NSApplication {
    // Outside the repo: once the methods are exchanged, this call runs NSApplication's own keyWindow.
    @objc fileprivate var pressKeyWindow: NSWindow? { Press.keyWindow ?? self.pressKeyWindow }
}
