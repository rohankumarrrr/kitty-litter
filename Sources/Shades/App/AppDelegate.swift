import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller: AppController
    private let menuBar: MenuBar
    private(set) var opensWhenActivated = true

    init(controller: AppController, menuBar: MenuBar) {
        self.controller = controller
        self.menuBar = menuBar
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        launched(by: NSAppleEventManager.shared().currentAppleEvent)
    }

    func launched(by event: NSAppleEventDescriptor?) {
        guard Self.isLoginLaunch(event) else { return }
        opensWhenActivated = false
        if NSApp.isActive { NSApp.hide(nil) }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if opensWhenActivated, !controller.stage.isChannelsOpen { controller.channelsPressed() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller.channelsPressed()
        return false
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        menuBar.dockMenu()
    }

    nonisolated static func isLoginLaunch(_ event: NSAppleEventDescriptor?) -> Bool {
        guard let event, event.eventID == AEEventID(kAEOpenApplication) else { return false }
        return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }
}
