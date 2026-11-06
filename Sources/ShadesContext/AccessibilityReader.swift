import ApplicationServices
import Foundation
import ShadesCore

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
    private static let visitLimit = 2000
    private static let elementLimit = 150
    private static let labelLimit = 80
    /// What's worth pointing at. Groups and other containers only matter for what's inside them.
    private static let pointableRoles: Set<String> = [
        "AXButton", "AXMenuButton", "AXPopUpButton", "AXCheckBox", "AXRadioButton", "AXLink", "AXTextField",
        "AXTextArea", "AXComboBox", "AXSlider", "AXIncrementor", "AXDisclosureTriangle", "AXMenuBarItem",
        "AXStaticText", "AXImage",
    ]
    private static let fieldRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox"]

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

    /// What the cat could point at: the menus in the menu bar, then the labelled things in the front
    /// window, in AppKit global points. It stops at the deadline with what it has, nearest the window first.
    /// What's typed into a field is never read, only its label or placeholder.
    static func elements(pid: pid_t, primaryHeight: CGFloat, until deadline: Date) -> [ScreenElement] {
        let app = AXUIElementCreateApplication(pid)
        let menus = element(app, kAXMenuBarAttribute).map(children) ?? []
        var found = menus.compactMap { pointable(read($0), $0) }
        if let window = frontWindow(of: app), let bounds = read(window).frame {
            var queue: [(element: AXUIElement, parentLabel: String?)] = [(window, nil)]
            var next = 0
            while next < queue.count, next < visitLimit, found.count < elementLimit, Date() < deadline {
                let (candidate, parentLabel) = queue[next]
                next += 1
                let node = read(candidate)
                if isPasswordField(role: node.role, subrole: node.subrole) { continue }
                // Scrolled out of sight, so nothing inside can be pointed at either.
                if let frame = node.frame, !frame.isEmpty, !frame.intersects(bounds) { continue }
                let item = pointable(node, candidate)
                // A link's text repeats the link, and saying it twice only crowds the list.
                if let item, item.label != parentLabel, bounds.contains(CGPoint(x: item.frame.midX, y: item.frame.midY)) {
                    found.append(item)
                }
                queue += node.children.map { ($0, item?.label) }
            }
        }
        return found.map {
            ScreenElement(role: $0.role, label: $0.label, frame: ScreenGeometry.flipped($0.frame, primaryHeight: primaryHeight))
        }
    }

    private struct Node {
        var role: String?
        var subrole: String?
        var roleDescription: String?
        var title: String?
        var description: String?
        /// In Quartz points.
        var frame: CGRect?
        var children: [AXUIElement] = []
    }

    /// One round trip per element, since a page can have thousands of them.
    private static func read(_ element: AXUIElement) -> Node {
        let names = [
            kAXRoleAttribute, kAXSubroleAttribute, kAXRoleDescriptionAttribute, kAXTitleAttribute,
            kAXDescriptionAttribute, kAXPositionAttribute, kAXSizeAttribute, kAXChildrenAttribute,
        ]
        AXUIElementSetMessagingTimeout(element, messageTimeout)
        var result: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, names as CFArray, [], &result) == .success,
              let values = result as? [AnyObject], values.count == names.count
        else { return Node() }
        // A missing attribute comes back as an error in its place.
        let present = values.map { value -> AnyObject? in
            guard CFGetTypeID(value) == AXValueGetTypeID() else { return value }
            return AXValueGetType(value as! AXValue) == .axError ? nil : value
        }
        var origin = CGPoint.zero
        var size = CGSize.zero
        var frame: CGRect?
        if let position = present[5], CFGetTypeID(position) == AXValueGetTypeID(), AXValueGetValue(position as! AXValue, .cgPoint, &origin),
           let extent = present[6], CFGetTypeID(extent) == AXValueGetTypeID(), AXValueGetValue(extent as! AXValue, .cgSize, &size) {
            frame = CGRect(origin: origin, size: size)
        }
        return Node(
            role: present[0] as? String,
            subrole: present[1] as? String,
            roleDescription: present[2] as? String,
            title: present[3] as? String,
            description: present[4] as? String,
            frame: frame,
            children: present[7] as? [AXUIElement] ?? []
        )
    }

    /// In Quartz points, like the node.
    private static func pointable(_ node: Node, _ element: AXUIElement) -> ScreenElement? {
        guard let role = node.role, pointableRoles.contains(role), let frame = node.frame, frame.width >= 2, frame.height >= 2 else { return nil }
        var text = label(node.title) ?? label(node.description)
        if text == nil, role == "AXStaticText" { text = label(string(element, kAXValueAttribute)) }
        if text == nil, fieldRoles.contains(role) { text = label(string(element, kAXPlaceholderValueAttribute)) }
        guard let text else { return nil }
        return ScreenElement(role: label(node.roleDescription) ?? String(role.dropFirst(2)).lowercased(), label: text, frame: frame)
    }

    /// One line, so a label can't pass for another item in the list.
    private static func label(_ text: String?) -> String? {
        ScreenText.clean(text?.split(whereSeparator: \.isWhitespace).joined(separator: " "), limit: labelLimit)
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
