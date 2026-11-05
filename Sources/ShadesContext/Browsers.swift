import Foundation

/// A browser we can script. The event codes come from each app's own dictionary (`sdef`).
struct Browser: Equatable, Sendable {
    enum Family: Sendable { case chromium, safari }

    let bundleID: String
    let name: String
    let family: Family
    var windowClass = "cwin"
    /// Where to find the setting that lets us read pages with JavaScript.
    var javaScriptSetting = "View > Developer > Allow JavaScript from Apple Events"

    static let known: [Browser] = [
        Browser(bundleID: "net.imput.helium", name: "Helium", family: .chromium),
        Browser(bundleID: "com.google.Chrome", name: "Chrome", family: .chromium),
        Browser(bundleID: "company.thebrowser.Browser", name: "Arc", family: .chromium, windowClass: "WiND"),
        Browser(
            bundleID: "com.apple.Safari",
            name: "Safari",
            family: .safari,
            javaScriptSetting: "Settings > Developer > Allow JavaScript from Apple Events"
        ),
        // These share Chrome's dictionary, so incognito windows stay hidden in them too.
        Browser(bundleID: "com.brave.Browser", name: "Brave", family: .chromium),
        Browser(bundleID: "com.microsoft.edgemac", name: "Edge", family: .chromium),
        Browser(bundleID: "com.vivaldi.Vivaldi", name: "Vivaldi", family: .chromium),
    ]

    init(bundleID: String, name: String, family: Family, windowClass: String = "cwin", javaScriptSetting: String? = nil) {
        self.bundleID = bundleID
        self.name = name
        self.family = family
        self.windowClass = windowClass
        if let javaScriptSetting { self.javaScriptSetting = javaScriptSetting }
    }

    init?(bundleID: String) {
        guard let browser = Self.known.first(where: { $0.bundleID == bundleID }) else { return nil }
        self = browser
    }

    var tip: String {
        "To let me read pages in \(name), turn on \(javaScriptSetting)."
    }
}

/// What the browser says about its front window, before anything is read from it.
struct BrowserLocation: Equatable, Sendable {
    var isPrivateWindow = false
    var url: URL?
    var failure: AppleEvents.Failure?
}

/// What a page gave up, and what went wrong if it didn't.
struct PageRead: Equatable, Sendable {
    var text: String?
    var selection: String?
    var url: URL?
    var failure: AppleEvents.Failure?
}

enum BrowserReader {
    static let locationTimeout: TimeInterval = 0.3
    static let pageTimeout: TimeInterval = 0.8

    static func location(of browser: Browser, pid: pid_t) -> BrowserLocation {
        if let failure = AppleEvents.permissionFailure(pid: pid) { return BrowserLocation(failure: failure) }

        var isPrivate = false
        if browser.family == .chromium {
            let window = AppleEvents.frontWindow(classCode: browser.windowClass)
            switch AppleEvents.get(AppleEvents.property("mode", of: window), pid: pid, timeout: locationTimeout) {
            case .success(let mode):
                isPrivate = mode == "incognito"
            case .failure(let failure):
                return BrowserLocation(isPrivateWindow: staysHidden(after: failure), failure: failure)
            }
        }

        switch AppleEvents.get(urlSpecifier(of: browser), pid: pid, timeout: locationTimeout) {
        case .success(let url):
            return BrowserLocation(isPrivateWindow: isPrivate, url: url.flatMap(URL.init(string:)))
        case .failure(let failure):
            return BrowserLocation(isPrivateWindow: isPrivate, failure: failure)
        }
    }

    /// If a browser won't say whether a window is private because it's stuck, assume it is.
    /// Being denied is different: that's lasting, and hiding every browser would make the cat useless.
    static func staysHidden(after failure: AppleEvents.Failure) -> Bool {
        failure == .timedOut
    }

    /// Reads the page through JavaScript, which has no side effects on the browser.
    static func page(of browser: Browser, pid: pid_t, wantsText: Bool) -> PageRead {
        let script = pageScript(wantsText: wantsText)
        let event: NSAppleEventDescriptor
        switch browser.family {
        case .chromium:
            event = AppleEvents.make("CrSu", "ExJa", pid: pid)
            event.setParam(activeTab(of: browser), forKeyword: AppleEvents.code("----"))
            event.setParam(NSAppleEventDescriptor(string: script), forKeyword: AppleEvents.code("JvSc"))
        case .safari:
            event = AppleEvents.make("sfri", "dojs", pid: pid)
            event.setParam(NSAppleEventDescriptor(string: script), forKeyword: AppleEvents.code("----"))
            event.setParam(activeTab(of: browser), forKeyword: AppleEvents.code("dcnm"))
        }
        switch AppleEvents.send(event, timeout: pageTimeout) {
        case .success(let reply):
            return parsePage(reply)
        case .failure(let failure):
            return PageRead(failure: failure)
        }
    }

    /// `innerText` leaves out what's typed into fields, so no password can come through it,
    /// and a focused password field is the one place a selection could reveal one.
    static func pageScript(wantsText: Bool) -> String {
        let text = wantsText ? "document.body ? document.body.innerText.slice(0, \(ScreenText.pageLimit)) : ''" : "''"
        return """
        (function () {
          var active = document.activeElement;
          var secret = active && active.tagName === 'INPUT' && active.type === 'password';
          return JSON.stringify({ text: \(text), selection: secret ? '' : String(getSelection()) });
        })()
        """
    }

    static func parsePage(_ reply: String?) -> PageRead {
        struct Reply: Decodable {
            var text: String
            var selection: String
        }
        guard let data = reply?.data(using: .utf8), let page = try? JSONDecoder().decode(Reply.self, from: data)
        else { return PageRead() }
        return PageRead(text: page.text, selection: page.selection)
    }

    private static func activeTab(of browser: Browser) -> NSAppleEventDescriptor {
        let window = AppleEvents.frontWindow(classCode: browser.windowClass)
        return AppleEvents.property(browser.family == .safari ? "cTab" : "acTa", of: window)
    }

    private static func urlSpecifier(of browser: Browser) -> NSAppleEventDescriptor {
        AppleEvents.property(browser.family == .safari ? "pURL" : "URL ", of: activeTab(of: browser))
    }
}

/// Private windows that only show themselves in their title, for browsers with no way to ask.
enum PrivateWindows {
    private static let titleOnly = ["com.apple.Safari", "org.mozilla.firefox"]

    static func looksPrivate(bundleID: String?, title: String?) -> Bool {
        guard let bundleID, let title, titleOnly.contains(bundleID) else { return false }
        return title == "Private Browsing" || title.hasSuffix(" Private Browsing")
    }
}
