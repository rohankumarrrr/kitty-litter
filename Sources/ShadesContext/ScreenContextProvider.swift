import Foundation
import ShadesCore

/// Sees what's on your screen, and only when asked.
///
/// `pickRegion()` returns global points in AppKit's coordinates, with the origin at the bottom left
/// of the primary display, the same as `NSWindow` frames. `CaptureOptions.focusRegion` takes the same.
public final class ScreenContextProvider: ScreenContextProviding, @unchecked Sendable {
    private let sources: ContextSources
    private let store: CaptureStore
    private let defaults: UserDefaults
    private let lock = NSLock()
    private var report = CaptureReport()
    /// The browser whose page text just went missing for want of JavaScript, if any.
    private var browserNeedingTip: Browser?

    private static let tipsKey = "shades.javaScriptTipsShown"

    public convenience init() {
        self.init(sources: LiveSources(), store: CaptureStore(), defaults: .standard)
    }

    init(sources: ContextSources, store: CaptureStore, defaults: UserDefaults) {
        self.sources = sources
        self.store = store
        self.defaults = defaults
    }

    /// How the latest snapshot went, for the UI to offer a permission or a tip.
    public var lastReport: CaptureReport {
        lock.withLock { report }
    }

    /// Takes nothing but the app's identity until it's sure the window isn't private, then
    /// reads the slower parts side by side. Missing permissions mean missing fields, never a prompt.
    public func snapshot(_ options: CaptureOptions) async throws -> ScreenSnapshot {
        let clock = ContinuousClock()
        let started = clock.now
        let hasScreenRecording = sources.hasScreenRecording
        var report = CaptureReport()
        report.screenRecording = hasScreenRecording
        report.accessibility = sources.hasAccessibility
        var needingTip: Browser?
        defer {
            report.timings.total = Self.milliseconds(clock.now - started)
            lock.withLock {
                self.report = report
                browserNeedingTip = needingTip
            }
        }

        guard let app = sources.frontApp() else { return ScreenSnapshot() }
        let privateApps = sources.privateApps()
        if let id = app.bundleID, privateApps.contains(where: { $0.caseInsensitiveCompare(id) == .orderedSame }) {
            report.wasPrivate = true
            return ScreenSnapshot(isPrivate: true)
        }

        let frontBrowser = app.bundleID.flatMap(Browser.init(bundleID:))
        let sources = sources
        async let timedFocus = Self.timed { await sources.focus(pid: app.pid) }
        async let timedLocation = Self.timed { await Self.location(of: frontBrowser, pid: app.pid, from: sources) }
        let (focus, focusTime) = await timedFocus
        let (location, locationTime) = await timedLocation
        report.timings.focus = focusTime
        report.timings.browserLocation = frontBrowser == nil ? nil : locationTime

        if location?.isPrivateWindow == true || PrivateWindows.looksPrivate(bundleID: app.bundleID, title: focus.windowTitle) {
            report.wasPrivate = true
            return ScreenSnapshot(isPrivate: true)
        }

        let wantsScreenshot = options.includeScreenshot && hasScreenRecording
        let request = ScreenCapture.Request(
            focusRegion: options.focusRegion,
            frontmostPID: app.pid,
            hiddenBundleIDs: privateApps
        )
        async let timedPage = Self.timed {
            await Self.page(of: frontBrowser, location: location, pid: app.pid, wantsText: options.includePageText, from: sources)
        }
        async let timedShot = Self.timed { wantsScreenshot ? await sources.screenshot(request) : nil }
        let (page, pageTime) = await timedPage
        let (shot, shotTime) = await timedShot

        report.browser = Self.status(browser: frontBrowser, location: location, page: page)
        report.timings.page = frontBrowser == nil ? nil : pageTime
        let pageText = options.includePageText ? ScreenText.clean(page?.text) : nil
        // Safari still gives up its text through Accessibility, so there it wouldn't help.
        if report.browser == .javaScriptOff, options.includePageText, pageText == nil { needingTip = frontBrowser }
        if wantsScreenshot {
            report.timings.screenshot = shotTime
            report.timings.screenshotList = shot.map { $0.listSeconds * 1000 }
            report.timings.screenshotGrab = shot.map { $0.grabSeconds * 1000 }
            report.timings.screenshotEncode = shot.map { $0.encodeSeconds * 1000 }
        }

        return ScreenSnapshot(
            appName: app.name,
            bundleID: app.bundleID,
            windowTitle: ScreenText.clean(focus.windowTitle),
            url: location?.url ?? page?.url,
            selectedText: ScreenText.clean(focus.selectedText ?? page?.selection),
            pageText: pageText,
            screenshotJPEG: shot?.jpeg,
            focusRegion: shot?.focusRegion,
            isPrivate: false
        )
    }

    public func pickRegion() async -> CGRect? {
        await RegionPicker.shared.pick()
    }

    public func saveScreenshot(of snapshot: ScreenSnapshot) throws -> String? {
        guard !snapshot.isPrivate, let jpeg = snapshot.screenshotJPEG else { return nil }
        return try store.save(jpeg)
    }

    /// The tip for turning on JavaScript, the first time a browser couldn't give up its page
    /// without it, and then never again. `nil` when the latest snapshot has nothing to suggest.
    public func takeJavaScriptTip() -> String? {
        lock.withLock {
            guard let browser = browserNeedingTip else { return nil }
            var shown = defaults.stringArray(forKey: Self.tipsKey) ?? []
            guard !shown.contains(browser.bundleID) else { return nil }
            shown.append(browser.bundleID)
            defaults.set(shown, forKey: Self.tipsKey)
            return browser.tip
        }
    }

    private static func location(of browser: Browser?, pid: pid_t, from sources: ContextSources) async -> BrowserLocation? {
        guard let browser else { return nil }
        return await sources.location(of: browser, pid: pid)
    }

    private static func page(
        of browser: Browser?,
        location: BrowserLocation?,
        pid: pid_t,
        wantsText: Bool,
        from sources: ContextSources
    ) async -> PageRead? {
        guard let browser, let location else { return nil }
        return await sources.page(of: browser, pid: pid, location: location, wantsText: wantsText)
    }

    private static func status(browser: Browser?, location: BrowserLocation?, page: PageRead?) -> BrowserStatus {
        guard browser != nil else { return .notABrowser }
        switch location?.failure ?? page?.failure {
        case .notAllowed: return .automationDenied
        case .notAsked: return .automationNotAsked
        case .javaScriptOff: return .javaScriptOff
        case .timedOut: return .timedOut
        default: return .ok
        }
    }

    private static func timed<T>(_ work: () async -> T) async -> (T, Double) {
        let clock = ContinuousClock()
        let started = clock.now
        let value = await work()
        return (value, milliseconds(clock.now - started))
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }
}
