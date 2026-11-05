import ApplicationServices
import Foundation

/// The window title and selected text, read from the app through Accessibility.
struct FocusedContext: Equatable, Sendable {
    var windowTitle: String?
    var selectedText: String?
}

/// Everything here blocks on the other app, so it stays off the main thread.
enum AccessibilityReader {
    /// A hung app would otherwise hold each of these calls for six seconds.
    private static let messageTimeout: Float = 0.2
    private static let searchLimit = 400

    private static let webArea = "AXWebArea"
    private static let secureField = "AXSecureTextField"

    static func focusedContext(pid: pid_t) -> FocusedContext {
        let app = AXUIElementCreateApplication(pid)
        let title = frontWindow(of: app).flatMap { string($0, kAXTitleAttribute) }
        return FocusedContext(windowTitle: title, selectedText: selectedText(in: app))
    }

    /// Password fields never get asked for anything.
    static func isPasswordField(role: String?, subrole: String?) -> Bool {
        role == secureField || subrole == secureField
    }

    private static func selectedText(in app: AXUIElement) -> String? {
        guard let focused = element(app, kAXFocusedUIElementAttribute) else { return nil }
        let role = string(focused, kAXRoleAttribute)
        let subrole = string(focused, kAXSubroleAttribute)
        guard !isPasswordField(role: role, subrole: subrole) else { return nil }
        return string(focused, kAXSelectedTextAttribute)
    }

    /// Reads a browser page without JavaScript, if the page is exposed at all. WebKit always does.
    /// Chromium only builds its web tree for assistive tools, through `AXEnhancedUserInterface`,
    /// and we leave that alone: the tree takes about two seconds to appear and goes the moment
    /// the flag does, so it would mean keeping a browser in that slower mode all the time.
    static func page(pid: pid_t, wantsText: Bool) -> PageRead {
        let app = AXUIElementCreateApplication(pid)
        guard let window = frontWindow(of: app) else { return PageRead() }

        var read = PageRead(url: string(window, "AXDocument").flatMap(URL.init(string:)))
        guard let area = largestWebArea(in: window) else { return read }

        if read.url == nil { read.url = value(area, "AXURL") as? URL }
        read.selection = selectedText(in: app)
        if wantsText { read.text = fullText(of: area) }
        return read
    }

    /// One call through text markers, far cheaper than walking the page. Browsers mask password
    /// fields in what this returns.
    private static func fullText(of area: AXUIElement) -> String? {
        var range: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            area, "AXTextMarkerRangeForUIElement" as CFString, area, &range
        ) == .success, let range else { return nil }
        var text: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            area, "AXStringForTextMarkerRange" as CFString, range, &text
        ) == .success else { return nil }
        return text as? String
    }

    /// The biggest one, so docked developer tools don't get read in place of the page.
    private static func largestWebArea(in window: AXUIElement) -> AXUIElement? {
        var queue = [window]
        var next = 0
        var best: (area: AXUIElement, size: CGFloat)?
        while next < queue.count, next < searchLimit {
            let candidate = queue[next]
            next += 1
            if string(candidate, kAXRoleAttribute) == webArea {
                let size = pointSize(of: candidate)
                if size >= (best?.size ?? 0) { best = (candidate, size) }
                continue
            }
            queue += children(of: candidate)
        }
        return best?.area
    }

    private static func frontWindow(of app: AXUIElement) -> AXUIElement? {
        element(app, kAXFocusedWindowAttribute) ?? element(app, kAXMainWindowAttribute)
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    private static func pointSize(of element: AXUIElement) -> CGFloat {
        guard let raw = value(element, kAXSizeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return 0 }
        var size = CGSize.zero
        AXValueGetValue(raw as! AXValue, .cgSize, &size)
        return size.width * size.height
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(element, messageTimeout)
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    private static func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let raw = value(parent, attribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return (raw as! AXUIElement)
    }
}
